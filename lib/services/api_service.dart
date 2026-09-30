import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' show Random;
import 'package:http/http.dart' as http;
import '../models/library_item.dart';
import 'app_logger.dart';
import '../models/member.dart';
import '../models/loan.dart';
import '../models/fine.dart';
import '../models/reservation.dart';
import '../models/chat_message.dart';
import '../models/report.dart';
import '../models/user_account.dart';
import '../config/network_config.dart';
import 'repository.dart';
import 'api_contract.dart';

/// Classification of a pre-flight reachability probe (NET-01) so the UI can
/// distinguish an outage from a wrong port, an auth-locked server, or an
/// unrelated HTTP listener that is not the app.
enum ConnectStatus {
  online, // our server answered /db-version with its payload
  needsAuth, // a server is there but requires a bearer token (pair/login)
  notAHost, // something answered 200 but not with our payload
  httpError, // a server replied with an unexpected status
  unreachable, // connection refused / host lookup failed / socket error
  timeout, // no response within the probe budget
}

class ConnectivityResult {
  const ConnectivityResult(
    this.status, {
    this.statusCode,
    this.latencyMs,
    this.message,
  });

  final ConnectStatus status;
  final int? statusCode;
  final int? latencyMs;
  final String? message;

  /// Something listening on the port answered (even if it rejected us).
  bool get isReachable =>
      status != ConnectStatus.unreachable && status != ConnectStatus.timeout;

  /// A usable connection to THIS app's server is established (no auth gate).
  bool get isUsableHost => status == ConnectStatus.online;

  @override
  String toString() =>
      'ConnectivityResult($status'
      '${statusCode != null ? ', $statusCode' : ''}'
      '${message != null ? ', $message' : ''})';
}

class ApiService implements LibraryRepository {
  final String hostIp;
  final int port;
  final http.Client _client;
  final Duration _timeout;

  /// Source of per-operation idempotency keys (REL-03 / 6.2). Secure-random so
  /// two distinct logical mutations essentially never collide on a key.
  final Random _rand = Random.secure();

  /// Bearer token obtained during LAN pairing (or a password login). Attached
  /// to every request once the host enables authentication (SEC-01/NET-01).
  /// When null/empty the client behaves as before (works against a host that
  /// has not configured a credential yet).
  String? authToken;

  /// The identity/role the current [authToken] was minted for (Phase 10.1),
  /// learned from the login response. Defaults to the LEAST privileged role so
  /// a client that restored a persisted token without a role simply hides write
  /// affordances until it signs in -- the server enforces regardless.
  UserRole sessionRole = UserRole.viewer;
  String? sessionUsername;

  /// API protocol version the host advertised on the most recent
  /// `/db-version` poll (null until one succeeds). Lets a client detect a
  /// partial upgrade -- a stale exe against a newer host, or the reverse --
  /// instead of silently mis-parsing the contract (DEP-02).
  int? serverApiVersion;

  /// Whether the last-seen host speaks this build's API protocol.
  bool get isServerProtocolCompatible =>
      isApiVersionCompatible(serverApiVersion);

  ApiService({
    required this.hostIp,
    this.port = NetworkConfig.defaultHttpPort,
    this.authToken,
    http.Client? client,
    Duration timeout = const Duration(seconds: 3),
  }) : _client = client ?? http.Client(),
       _timeout = timeout;

  String get _baseUrl => 'http://$hostIp:$port';

  /// Percent-encode ONE dynamic path segment (FB-04). An item `code`, scanned
  /// `barcode`, code-definition `prefix` or member `memberId` may contain `/`,
  /// `#`, `?`, spaces or non-ASCII (legacy / hand-entered ids). Interpolated raw
  /// into `Uri.parse`, such a value breaks out of its segment -- a code `A/B`
  /// becomes path `/items/A/B` and hits the wrong route (or 404s). Encoding it
  /// keeps it a single segment that the server's `<param>` route URL-decodes
  /// back to the original value.
  String _seg(String value) => Uri.encodeComponent(value);

  /// Merges an optional `Authorization: Bearer` header into request headers.
  Map<String, String> _withAuth([Map<String, String>? extra]) {
    final headers = <String, String>{...?extra};
    // Always advertise the protocol this client speaks (DEP-02).
    headers[apiVersionHeader] = '$kApiProtocolVersion';
    final token = authToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// A fresh, opaque idempotency key for one logical mutation. Generated once
  /// per user-initiated operation (OUTSIDE `_retry`) and therefore reused
  /// across every network retry of that operation, letting the server replay
  /// the original outcome instead of re-executing a duplicate write
  /// (REL-03 / TX-05 / 6.2).
  String _newIdempotencyKey() => List.generate(
    16,
    (_) => _rand.nextInt(256),
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Builds a typed [ApiException] from a non-2xx [response], surfacing the
  /// server's structured `{"error","message"}` body (BE-02) instead of
  /// collapsing every failure to a generic message. Falls back to the raw body
  /// or [fallback] when the body is absent or not the expected JSON shape.
  ApiException _apiError(
    http.Response response, [
    String fallback = 'Request failed',
  ]) {
    var message = fallback;
    String? code;
    final body = response.body;
    if (body.isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          message = (decoded['message'] ?? decoded['error'] ?? fallback)
              .toString();
          code = decoded['error']?.toString();
        } else {
          message = body;
        }
      } catch (_) {
        message = body;
      }
    }
    return ApiException(response.statusCode, message, error: code);
  }

  bool _isRetryable(Object e) {
    return e is http.ClientException ||
        e is SocketException ||
        e is TimeoutException;
  }

  Future<T> _retry<T>(Future<T> Function() action, {int maxRetries = 1}) async {
    var retries = 0;
    while (true) {
      try {
        return await action();
      } catch (e) {
        retries++;
        if (retries > maxRetries || !_isRetryable(e)) {
          rethrow;
        }
        final delay = Duration(milliseconds: 500 * retries);
        await Future.delayed(delay);
      }
    }
  }

  Future<http.Response> _get(Uri uri) =>
      _client.get(uri, headers: _withAuth()).timeout(_timeout);
  Future<http.Response> _post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) => _client
      .post(uri, headers: _withAuth(headers), body: body)
      .timeout(_timeout);
  Future<http.Response> _put(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) => _client
      .put(uri, headers: _withAuth(headers), body: body)
      .timeout(_timeout);
  Future<http.Response> _delete(Uri uri) =>
      _client.delete(uri, headers: _withAuth()).timeout(_timeout);

  void close() {
    _client.close();
  }

  /// Exchanges credentials for a bearer token (`POST /auth/login`). Used by
  /// manual-IP client connections that do not go through the pairing code, and
  /// by the per-user client login (Phase 10.1). Returns the token PLUS the
  /// identity/role the host granted, and stores them on this client; returns
  /// `null` on rejection or lockout. Never sends the password for ordinary
  /// data requests.
  Future<LoginSession?> login(String username, String password) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final session = LoginSession.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
        if (session.isValid) {
          authToken = session.token;
          sessionRole = session.role;
          sessionUsername = session.username;
          return session;
        }
      }
    } catch (e) {
      appLog.warn('net', 'Auth login failed', e);
    }
    return null;
  }

  /// Asks the host who the current bearer token belongs to (`GET
  /// /auth/session`), so a client that restored a persisted token can recover
  /// its role without a password. Null when there is no token / no session.
  Future<LoginSession?> currentSession() async {
    final token = authToken;
    if (token == null || token.isEmpty) return null;
    try {
      final response = await _get(Uri.parse('$_baseUrl/auth/session'));
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body);
      if (json is! Map) return null;
      // No token comes back from this endpoint; keep the one we hold.
      return LoginSession(
        token: token,
        username: (json['username'] ?? '').toString(),
        role: UserRole.tryParse(json['role']) ?? UserRole.viewer,
      );
    } catch (e) {
      appLog.warn('net', 'Auth session lookup failed', e);
      return null;
    }
  }

  // ==========================================================================
  // User administration (Phase 10.1) -- CLIENT SIDE of the /users surface.
  // These are deliberately NOT part of [LibraryRepository]: accounts are not
  // library data, and the host serves them from AuthService rather than the
  // repository. Both are ADMIN-only on the server; a client without the right
  // role gets a 403 which [ApiException] carries through verbatim.
  // ==========================================================================

  Future<List<UserRecord>> fetchUsers() async {
    return _retry(() async {
      final response = await _get(Uri.parse('$_baseUrl/users'));
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to load accounts');
      }
      final body = jsonDecode(response.body);
      final list = body is Map ? (body['users'] ?? const []) : body;
      return [
        for (final u in List<dynamic>.from(list as Iterable)) _userFrom(u),
      ];
    });
  }

  UserRecord _userFrom(Object? raw) {
    final m = Map<String, dynamic>.from(raw as Map);
    return UserRecord(
      username: (m['username'] ?? '').toString(),
      role: UserRole.tryParse(m['role']) ?? UserRole.viewer,
      createdAt: m['created_at']?.toString(),
    );
  }

  Future<UserRecord> createUser({
    required String username,
    required String password,
    required UserRole role,
  }) async {
    final idemKey = _newIdempotencyKey();
    return _retry(() async {
      final response = await _post(
        Uri.parse('$_baseUrl/users'),
        headers: {
          'Content-Type': 'application/json',
          'Idempotency-Key': idemKey,
        },
        body: jsonEncode({
          'username': username,
          'password': password,
          'role': role.storage,
        }),
      );
      if (response.statusCode != 201) {
        throw _apiError(response, 'Failed to create account');
      }
      return _userFrom(jsonDecode(response.body));
    });
  }

  Future<void> setUserRole(String username, UserRole role) async {
    await _retry(() async {
      final response = await _put(
        Uri.parse('$_baseUrl/users/${_seg(username)}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'role': role.storage}),
      );
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to change role');
      }
    });
  }

  Future<void> setUserPassword(String username, String password) async {
    await _retry(() async {
      final response = await _put(
        Uri.parse('$_baseUrl/users/${_seg(username)}/password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'password': password}),
      );
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to change password');
      }
    });
  }

  Future<void> deleteUser(String username) async {
    await _retry(() async {
      final response = await _delete(
        Uri.parse('$_baseUrl/users/${_seg(username)}'),
      );
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to remove account');
      }
    });
  }

  /// Lightweight pre-flight reachability probe (NET-01). Hits a cheap endpoint
  /// and CLASSIFIES the outcome instead of throwing, so the caller can tell a
  /// dead host from a wrong port, an auth-locked server, or a healthy one --
  /// rather than a single red dot. Never retries (fail fast); always returns a
  /// [ConnectivityResult].
  Future<ConnectivityResult> checkConnectivity({Duration? timeout}) async {
    final dur = timeout ?? _timeout;
    final sw = Stopwatch()..start();
    try {
      final res = await _client
          .get(Uri.parse('$_baseUrl/db-version'), headers: _withAuth())
          .timeout(dur);
      sw.stop();
      final latency = sw.elapsedMilliseconds;
      if (res.statusCode == 200) {
        final host = _looksLikeHost(res.body);
        if (host) _captureServerApi(res.body);
        return ConnectivityResult(
          host ? ConnectStatus.online : ConnectStatus.notAHost,
          statusCode: res.statusCode,
          latencyMs: latency,
        );
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        // A server is present and enforcing auth; pairing/login is required.
        return ConnectivityResult(
          ConnectStatus.needsAuth,
          statusCode: res.statusCode,
          latencyMs: latency,
        );
      }
      return ConnectivityResult(
        ConnectStatus.httpError,
        statusCode: res.statusCode,
        latencyMs: latency,
        message: 'Server replied ${res.statusCode}',
      );
    } on TimeoutException {
      sw.stop();
      return ConnectivityResult(
        ConnectStatus.timeout,
        latencyMs: sw.elapsedMilliseconds,
        message: 'No response within ${dur.inMilliseconds}ms',
      );
    } on SocketException catch (e) {
      return ConnectivityResult(
        ConnectStatus.unreachable,
        message: e.osError?.message ?? e.message,
      );
    } on http.ClientException catch (e) {
      // package:http funnels refused connections / failed host lookups here.
      return ConnectivityResult(ConnectStatus.unreachable, message: e.message);
    } catch (e) {
      return ConnectivityResult(ConnectStatus.unreachable, message: '$e');
    }
  }

  /// A 200 from our server always carries a `{"version": ...}` object; anything
  /// else means some unrelated HTTP listener answered on this port.
  bool _looksLikeHost(String body) {
    try {
      final j = jsonDecode(body);
      return j is Map && j.containsKey('version');
    } catch (_) {
      return false;
    }
  }

  /// Records the host's advertised API protocol from a `/db-version` body so
  /// [isServerProtocolCompatible] reflects the newest known server version.
  void _captureServerApi(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        serverApiVersion = (decoded[apiVersionBodyKey] as num?)?.toInt();
      }
    } catch (_) {
      // Leave the last-known version untouched on a malformed body.
    }
  }

  @override
  Future<List<LibraryItem>> getItems({
    int limit = 1000,
    int offset = 0,
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) async {
    return _retry(() async {
      final response = await _get(
        _itemsUri(
          '/items',
          limit: limit,
          offset: offset,
          search: search,
          status: status,
          codeType: codeType,
          sort: sort,
          ascending: ascending,
        ),
      );
      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList.map((map) => LibraryItem.fromMap(map)).toList();
      } else {
        throw _apiError(response, 'Failed to load items');
      }
    });
  }

  @override
  Future<int> countItems({
    String? search,
    String? status,
    String? codeType,
  }) async {
    return _retry(() async {
      final response = await _get(
        _itemsUri(
          '/items/count',
          search: search,
          status: status,
          codeType: codeType,
        ),
      );
      if (response.statusCode == 200) {
        return (jsonDecode(response.body)['count'] as num).toInt();
      }
      throw _apiError(response, 'Failed to count items');
    });
  }

  /// Builds a `$_baseUrl<path>` with URL-encoded query parameters; null / empty
  /// filters are omitted so the server applies no constraint for them.
  Uri _itemsUri(
    String path, {
    int? limit,
    int? offset,
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool? ascending,
  }) {
    final params = <String, String>{
      if (limit != null) 'limit': '$limit',
      if (offset != null) 'offset': '$offset',
      if (search != null && search.trim().isNotEmpty) 'search': search,
      if (status != null && status.isNotEmpty) 'status': status,
      if (codeType != null && codeType.isNotEmpty) 'codeType': codeType,
      if (sort != null && sort.isNotEmpty) 'sort': sort,
      if (sort != null && sort.isNotEmpty)
        'order': (ascending ?? true) ? 'asc' : 'desc',
    };
    return Uri.parse(
      '$_baseUrl$path',
    ).replace(queryParameters: params.isEmpty ? null : params);
  }

  // NOTE (TX-01/5.2): the mutating methods below accept an optional `audit`
  // entry to satisfy the LibraryRepository seam, but a remote client must NOT
  // author its own audit row. The server builds the authoritative entry (real
  // client IP + server clock) and writes it atomically with the mutation, so
  // the client-side `audit` here is intentionally ignored.
  @override
  Future<void> addItem(LibraryItem item, {Map<String, dynamic>? audit}) async {
    final idemKey = _newIdempotencyKey();
    await _retry(() async {
      final response = await _post(
        Uri.parse('$_baseUrl/items'),
        headers: {
          'Content-Type': 'application/json',
          'Idempotency-Key': idemKey,
        },
        body: jsonEncode(item.toMap()),
      );
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to add item');
      }
    });
  }

  @override
  Future<void> updateItem(
    LibraryItem item, {
    Map<String, dynamic>? audit,
    int? expectedVersion,
  }) async {
    await _retry(() async {
      final response = await _put(
        Uri.parse('$_baseUrl/items'),
        headers: {
          'Content-Type': 'application/json',
          // TX-06: ask the server to reject (409) the write if the row changed
          // since we read [expectedVersion]. Absent => unconditional write.
          if (expectedVersion != null) 'X-Expected-Version': '$expectedVersion',
        },
        body: jsonEncode(item.toMap()),
      );
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to update item');
      }
    });
  }

  @override
  Future<void> deleteItem(String code, {Map<String, dynamic>? audit}) async {
    await _retry(() async {
      final response = await _delete(
        Uri.parse('$_baseUrl/items/${_seg(code)}'),
      );
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to delete item');
      }
    });
  }

  @override
  Future<List<Map<String, dynamic>>> getHistory({
    int limit = 20,
    int offset = 0,
    String? subject,
  }) async {
    return _retry(() async {
      // Pass 5: a subject string narrows the audit query to rows mentioning
      // it (server-side LIKE). Omit the param entirely for backward compat
      // with older hosts that don't recognise it.
      final uri = Uri.parse('$_baseUrl/history').replace(
        queryParameters: {
          'limit': '$limit',
          'offset': '$offset',
          if (subject != null && subject.isNotEmpty) 'subject': subject,
        },
      );
      final response = await _get(uri);
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body));
      } else {
        throw _apiError(response, 'Failed to load history');
      }
    });
  }

  @override
  Future<void> addHistoryEntry(Map<String, dynamic> entry) async {
    final idemKey = _newIdempotencyKey();
    await _retry(() async {
      final response = await _post(
        Uri.parse('$_baseUrl/history'),
        headers: {
          'Content-Type': 'application/json',
          'Idempotency-Key': idemKey,
        },
        body: jsonEncode(entry),
      );
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to log history');
      }
    });
  }

  @override
  Future<LibraryItem?> getItemByBarcode(String barcode) async {
    try {
      final response = await _get(
        Uri.parse('$_baseUrl/barcode/${_seg(barcode)}'),
      );
      if (response.statusCode == 200) {
        return LibraryItem.fromMap(jsonDecode(response.body));
      }
    } catch (e) {
      appLog.warn('net', 'Error fetching item by barcode', e);
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>> getStats() async {
    return _retry(() async {
      final response = await _get(Uri.parse('$_baseUrl/stats'));
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      } else {
        throw _apiError(response, 'Failed to load stats');
      }
    });
  }

  @override
  Future<String> generateMemberID() async {
    // The host assigns the real member id inside POST /members (it ignores an
    // 'AUTO' placeholder), so the client never needs to generate one itself.
    return 'AUTO';
  }

  @override
  Future<String> getDbVersion({int maxRetries = 0}) async {
    return _retry(() async {
      final response = await _get(Uri.parse('$_baseUrl/db-version'));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          serverApiVersion = (decoded[apiVersionBodyKey] as num?)?.toInt();
          return (decoded['version'] ?? '0').toString();
        }
        return '0';
      }
      throw _apiError(response, 'Failed to load DB version');
    }, maxRetries: maxRetries);
  }

  @override
  Future<List<Map<String, dynamic>>> getCodeDefinitions() async {
    return _retry(() async {
      final response = await _get(Uri.parse('$_baseUrl/code-definitions'));
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body));
      } else {
        throw _apiError(response, 'Failed to load code definitions');
      }
    });
  }

  // Definition mutations carry an optional `audit` row for seam parity, but a
  // remote client never authors its own audit: the embedded server records it
  // from the request (real client IP + clock), so [audit] is intentionally
  // ignored here (BE-05 / BE-09).
  @override
  Future<void> addCodeDefinition(
    String prefix,
    String label, {
    Map<String, dynamic>? audit,
  }) async {
    final idemKey = _newIdempotencyKey();
    await _retry(() async {
      final response = await _post(
        Uri.parse('$_baseUrl/code-definitions'),
        headers: {
          'Content-Type': 'application/json',
          'Idempotency-Key': idemKey,
        },
        body: jsonEncode({'prefix': prefix, 'label': label}),
      );
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to add code definition');
      }
    });
  }

  @override
  Future<void> updateCodeDefinition(
    String oldPrefix,
    String newPrefix,
    String label, {
    Map<String, dynamic>? audit,
  }) async {
    await _retry(() async {
      final response = await _put(
        Uri.parse('$_baseUrl/code-definitions/${_seg(oldPrefix)}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prefix': newPrefix, 'label': label}),
      );
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to update code definition');
      }
    });
  }

  @override
  Future<void> deleteCodeDefinition(
    String prefix, {
    Map<String, dynamic>? audit,
  }) async {
    await _retry(() async {
      final response = await _delete(
        Uri.parse('$_baseUrl/code-definitions/${_seg(prefix)}'),
      );
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to delete code definition');
      }
    });
  }

  @override
  Future<List<Map<String, dynamic>>> getAttributeDefinitions(
    String? type,
  ) async {
    return _retry(() async {
      // FB-04: build the query via Uri so a `type` with specials is encoded
      // (the server reads it back through queryParameters, already decoded).
      final base = Uri.parse('$_baseUrl/attribute-definitions');
      final uri = (type != null && type.isNotEmpty)
          ? base.replace(queryParameters: {'type': type})
          : base;
      final response = await _get(uri);
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body));
      } else {
        throw _apiError(response, 'Failed to load attribute definitions');
      }
    });
  }

  @override
  Future<void> addAttributeDefinition(
    String type,
    String value, {
    Map<String, dynamic>? audit,
  }) async {
    final idemKey = _newIdempotencyKey();
    await _retry(() async {
      final response = await _post(
        Uri.parse('$_baseUrl/attribute-definitions'),
        headers: {
          'Content-Type': 'application/json',
          'Idempotency-Key': idemKey,
        },
        body: jsonEncode({'type': type, 'value': value}),
      );
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to add attribute definition');
      }
    });
  }

  @override
  Future<void> deleteAttributeDefinition(
    int id, {
    Map<String, dynamic>? audit,
  }) async {
    await _retry(() async {
      final response = await _delete(
        Uri.parse('$_baseUrl/attribute-definitions/${_seg('$id')}'),
      );
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to delete attribute definition');
      }
    });
  }

  // Members (Client implementation)
  @override
  Future<List<Member>> getMembers() async {
    return _retry(() async {
      final response = await _get(Uri.parse('$_baseUrl/members'));
      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList.map((map) => Member.fromMap(map)).toList();
      } else {
        throw _apiError(response, 'Failed to load members');
      }
    });
  }

  @override
  Future<void> addMember(Member member, {Map<String, dynamic>? audit}) async {
    final idemKey = _newIdempotencyKey();
    await _retry(() async {
      final response = await _post(
        Uri.parse('$_baseUrl/members'),
        headers: {
          'Content-Type': 'application/json',
          'Idempotency-Key': idemKey,
        },
        body: jsonEncode(member.toMap()),
      );
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to add member');
      }
    });
  }

  @override
  Future<void> updateMember(
    Member member, {
    Map<String, dynamic>? audit,
    int? expectedVersion,
  }) async {
    await _retry(() async {
      final response = await _put(
        Uri.parse('$_baseUrl/members'),
        headers: {
          'Content-Type': 'application/json',
          // TX-06: ask the server to reject (409) the write if the member row
          // changed since we read [expectedVersion]. Absent => unconditional.
          if (expectedVersion != null) 'X-Expected-Version': '$expectedVersion',
        },
        body: jsonEncode(member.toMap()),
      );
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to update member');
      }
    });
  }

  @override
  Future<void> deleteMember(
    String memberId, {
    Map<String, dynamic>? audit,
  }) async {
    await _retry(() async {
      final response = await _delete(
        Uri.parse('$_baseUrl/members/${_seg(memberId)}'),
      );
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to delete member');
      }
    });
  }

  // Loans (Client implementation)
  @override
  Future<List<Loan>> getLoans({bool activeOnly = false}) async {
    return _retry(() async {
      final url = activeOnly
          ? '$_baseUrl/loans?activeOnly=true'
          : '$_baseUrl/loans';
      final response = await _get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList.map((map) => Loan.fromMap(map)).toList();
      } else {
        throw _apiError(response, 'Failed to load loans');
      }
    });
  }

  @override
  Future<void> addLoan(Loan loan, {Map<String, dynamic>? audit}) async {
    final idemKey = _newIdempotencyKey();
    await _retry(() async {
      final response = await _post(
        Uri.parse('$_baseUrl/loans'),
        headers: {
          'Content-Type': 'application/json',
          'Idempotency-Key': idemKey,
        },
        body: jsonEncode(loan.toMap()),
      );
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to add loan');
      }
    });
  }

  @override
  Future<void> updateLoan(Loan loan, {Map<String, dynamic>? audit}) async {
    await _retry(() async {
      final response = await _put(
        Uri.parse('$_baseUrl/loans'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(loan.toMap()),
      );
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to update loan');
      }
    });
  }

  @override
  Future<Loan?> findActiveLoanByScan(String scanned) async {
    // The server owns scan resolution (BL-03); a miss returns 404 -> null.
    try {
      final code = Uri.encodeComponent(scanned.trim());
      final response = await _get(
        Uri.parse('$_baseUrl/loans/resolve-scan?code=$code'),
      );
      if (response.statusCode == 200) {
        return Loan.fromMap(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      appLog.warn('net', 'Scan resolution failed', e);
      return null;
    }
  }

  // ==========================================================================
  // Fines & payments (Phase 10.2) -- CLIENT SIDE. The host owns the money
  // rules: accrual happens in its return transaction and pay/waive record the
  // AUTHENTICATED principal (from the bearer token) as `resolved_by`, so a
  // client never authors its own audit or supplies its own operator name. The
  // [audit] / [operatorName] seam parameters are intentionally ignored here.
  // Role gates are enforced server-side (403 is surfaced via [ApiException]).
  // ==========================================================================

  @override
  Future<FineSettings> getFineSettings() async {
    return _retry(() async {
      final response = await _get(Uri.parse('$_baseUrl/settings/fines'));
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to load fine settings');
      }
      return FineSettings.fromMap(jsonDecode(response.body) as Map);
    });
  }

  @override
  Future<void> setFineSettings(
    FineSettings settings, {
    Map<String, dynamic>? audit,
  }) async {
    await _retry(() async {
      final response = await _put(
        Uri.parse('$_baseUrl/settings/fines'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(settings.toMap()),
      );
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to save fine settings');
      }
    });
  }

  @override
  Future<List<Fine>> getFines({String? memberId, FineStatus? status}) async {
    return _retry(() async {
      final params = <String, String>{
        if (memberId != null && memberId.isNotEmpty) 'member_id': memberId,
        if (status != null) 'status': status.storage,
      };
      final base = Uri.parse('$_baseUrl/fines');
      final response = await _get(
        base.replace(queryParameters: params.isEmpty ? null : params),
      );
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to load fines');
      }
      final List<dynamic> jsonList = jsonDecode(response.body);
      return jsonList
          .map((m) => Fine.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    });
  }

  @override
  Future<double> outstandingBalance(String memberId) async {
    return _retry(() async {
      final base = Uri.parse('$_baseUrl/fines/balance');
      final response = await _get(
        base.replace(queryParameters: {'member_id': memberId}),
      );
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to load balance');
      }
      final decoded = jsonDecode(response.body);
      final balance = decoded is Map ? decoded['balance'] : null;
      return (balance as num?)?.toDouble() ?? 0.0;
    });
  }

  @override
  Future<void> payFine(
    int id, {
    String? operatorName,
    Map<String, dynamic>? audit,
  }) => _resolveFineRemote(id, 'pay');

  @override
  Future<void> waiveFine(
    int id, {
    String? operatorName,
    Map<String, dynamic>? audit,
  }) => _resolveFineRemote(id, 'waive');

  Future<void> _resolveFineRemote(int id, String verb) async {
    final idemKey = _newIdempotencyKey();
    await _retry(() async {
      final response = await _post(
        Uri.parse('$_baseUrl/fines/$id/$verb'),
        headers: {'Idempotency-Key': idemKey},
      );
      if (response.statusCode != 200) {
        // A 409 here (already resolved / unknown fine) carries the server's
        // concrete message; surface it verbatim so money is never double-taken.
        throw _apiError(response, 'Failed to record fine payment');
      }
    });
  }

  // ==========================================================================
  // Reservations / hold queue (Phase 10.3) -- CLIENT SIDE. The host owns the
  // queue and the copy claims: this client only asks to join/leave a line and
  // reads what the server decided. It never supplies an operator name or
  // authors its own audit (both are the server's bearer-derived truth), and it
  // never mutates a copy -- a walk-up that would cut a holder is refused
  // server-side (409) regardless of what this client renders.
  // ==========================================================================

  @override
  Future<HoldSettings> getHoldSettings() async {
    return _retry(() async {
      final response = await _get(Uri.parse('$_baseUrl/settings/holds'));
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to load hold settings');
      }
      return HoldSettings.fromMap(jsonDecode(response.body) as Map);
    });
  }

  @override
  Future<void> setHoldSettings(
    HoldSettings settings, {
    Map<String, dynamic>? audit,
  }) async {
    await _retry(() async {
      final response = await _put(
        Uri.parse('$_baseUrl/settings/holds'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(settings.toMap()),
      );
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to save hold settings');
      }
    });
  }

  @override
  Future<Reservation> placeReservation(
    String itemCode,
    String memberId, {
    Map<String, dynamic>? audit,
  }) async {
    final idemKey = _newIdempotencyKey();
    return _retry(() async {
      final response = await _post(
        Uri.parse('$_baseUrl/reservations'),
        headers: {
          'Content-Type': 'application/json',
          'Idempotency-Key': idemKey,
        },
        body: jsonEncode({'item_code': itemCode, 'member_id': memberId}),
      );
      // The server enforces every rule (unknown item/member, a duplicate
      // live hold, a full queue) as a typed 409/404 whose message is the
      // concrete refusal -- carried through verbatim below.
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw _apiError(response, 'Failed to place hold');
      }
      return Reservation.fromMap(
        Map<String, dynamic>.from(jsonDecode(response.body) as Map),
      );
    });
  }

  @override
  Future<List<Reservation>> getReservations({
    String? itemCode,
    String? memberId,
    ReservationStatus? status,
    bool liveOnly = false,
  }) async {
    return _retry(() async {
      final params = <String, String>{
        if (itemCode != null && itemCode.isNotEmpty) 'item_code': itemCode,
        if (memberId != null && memberId.isNotEmpty) 'member_id': memberId,
        if (status != null) 'status': status.storage,
        if (liveOnly) 'live': '1',
      };
      final base = Uri.parse('$_baseUrl/reservations');
      final response = await _get(
        base.replace(queryParameters: params.isEmpty ? null : params),
      );
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to load holds');
      }
      final List<dynamic> jsonList = jsonDecode(response.body);
      return jsonList
          .map((m) => Reservation.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    });
  }

  @override
  Future<List<Reservation>> readyForPickup() async {
    return _retry(() async {
      final response = await _get(Uri.parse('$_baseUrl/reservations/ready'));
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to load ready holds');
      }
      final List<dynamic> jsonList = jsonDecode(response.body);
      return jsonList
          .map((m) => Reservation.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    });
  }

  @override
  Future<void> cancelReservation(int id, {Map<String, dynamic>? audit}) async {
    final idemKey = _newIdempotencyKey();
    await _retry(() async {
      final response = await _post(
        Uri.parse('$_baseUrl/reservations/$id/cancel'),
        headers: {'Idempotency-Key': idemKey},
      );
      if (response.statusCode != 200) {
        // 409 (unknown / already terminal) carries the server's reason.
        throw _apiError(response, 'Failed to cancel hold');
      }
    });
  }

  /// Pass 6: ask the server to swap hold [id] with its queued neighbour.
  /// Idempotency-keyed like every other mutation so a retry after a
  /// transient network blip cannot bubble the row twice.
  @override
  Future<void> moveReservation(
    int id, {
    required bool up,
    Map<String, dynamic>? audit,
  }) async {
    final idemKey = _newIdempotencyKey();
    await _retry(() async {
      final response = await _post(
        Uri.parse('$_baseUrl/reservations/$id/move'),
        headers: {
          'Content-Type': 'application/json',
          'Idempotency-Key': idemKey,
        },
        body: jsonEncode({'direction': up ? 'up' : 'down'}),
      );
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to reorder hold');
      }
    });
  }

  // --------------------------------------------------------------------------
  // Reports (Phase 10.4). Read-only and computed by the HOST: the client simply
  // asks for a kind over an optional window and renders exactly what the server
  // returns. A malformed kind/date the UI somehow sent is a 400 (surfaced as an
  // ApiException); a role the server refuses is a 403 -- never a client-side
  // re-computation, so a remote operator can never see different totals.
  // --------------------------------------------------------------------------
  @override
  Future<Report> generateReport(
    ReportKind kind, {
    String? from,
    String? to,
  }) async {
    return _retry(() async {
      final params = <String, String>{
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
      };
      final base = Uri.parse('$_baseUrl/reports/${kind.storage}');
      final response = await _get(
        base.replace(queryParameters: params.isEmpty ? null : params),
      );
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to build report');
      }
      return Report.fromMap(
        Map<String, dynamic>.from(jsonDecode(response.body) as Map),
      );
    });
  }

  /// Phase 19: send a LAN-chat message to the host (`POST /chat`). A fresh
  /// idempotency key per logical send means an internal transport retry can
  /// never double-post the message, while distinct sends stay distinct. Throws
  /// an [ApiException] carrying the host's reason on any non-201, so the UI
  /// cannot report a message as sent when the host refused it.
  Future<void> sendChat(String text) async {
    final idemKey = _newIdempotencyKey();
    await _retry(() async {
      final response = await _post(
        Uri.parse('$_baseUrl/chat'),
        headers: {
          'Content-Type': 'application/json',
          'Idempotency-Key': idemKey,
        },
        body: jsonEncode({'text': text}),
      );
      if (response.statusCode != 201) {
        throw _apiError(response, 'Failed to send message');
      }
    });
  }

  /// Phase 19: fetch chat messages newer than [since] (`GET /chat?since=`),
  /// returning them plus the host's current high-water id so the caller can
  /// advance its poll cursor and never re-request delivered rows.
  Future<({List<ChatMessage> messages, int latest})> fetchChat(
    int since,
  ) async {
    return _retry(() async {
      final response = await _get(Uri.parse('$_baseUrl/chat?since=$since'));
      if (response.statusCode != 200) {
        throw _apiError(response, 'Failed to load messages');
      }
      final m = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (m['messages'] as List<dynamic>)
          .map((e) => ChatMessage.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      return (messages: list, latest: (m['latest'] as num?)?.toInt() ?? since);
    });
  }
}

/// A failed LAN API call that carries the server's HTTP status and the
/// structured error message it returned, so callers can distinguish (e.g.) a
/// 409 delete-conflict from a transport failure and surface the real reason
/// (BE-02).
class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.error});
  final int statusCode;
  final String message;
  final String? error;

  /// True for the BL-04 "cannot delete, still on loan" conflict.
  bool get isConflict => statusCode == 409;

  @override
  String toString() =>
      'ApiException($statusCode, ${error ?? 'error'}: $message)';
}

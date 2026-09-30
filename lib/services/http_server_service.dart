import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import '../models/library_item.dart';
import '../models/member.dart';
import '../models/loan.dart';
import '../models/fine.dart';
import '../models/reservation.dart';
import '../models/chat_message.dart';
import '../models/report.dart';
import '../domain/report_query.dart';
import '../models/user_account.dart';
import '../config/network_config.dart';
import 'database_service.dart';
import 'repository.dart';
import 'auth_service.dart';
import 'auth_middleware.dart';
import 'idempotency_store.dart';
import 'api_contract.dart';
import 'rate_limit.dart';
import 'app_logger.dart';

class HttpServerService {
  late Handler _handler;
  final LibraryRepository _db;
  final AuthService? _auth;
  final IdempotencyStore _idempotency;
  final RateLimiter _rateLimit;
  HttpServer? _server;

  // Restore / wipe quiesce (DB-04). While [_maintenance] is set the server
  // answers 503 to NEW requests, and [_inFlight] tracks requests actively being
  // handled so the caller can drain them before swapping / wiping the shared
  // database -- so no LAN client observes a half-replaced DB or a
  // "database is closed" 500.
  bool _maintenance = false;
  int _inFlight = 0;

  // ARC-06: monotonic per-request id minted in the outermost middleware so a
  // trace (timeout, 5xx, and any downstream appLog line carrying the same
  // request) can be followed across a single exchange. Process-local counter.
  int _reqSeq = 0;

  // Phase 19: an in-memory LAN-staff-chat buffer. Chat is ephemeral
  // coordination between the host and its paired staff clients, so it is
  // deliberately NOT persisted to the shared database (it must survive no
  // restore and disclose nothing at rest). A bounded ring keeps memory fixed
  // under a chatty LAN.
  static const int _chatRetention = 200;
  static const int _chatMaxTextChars = 1000;
  final List<ChatMessage> _chat = [];
  int _chatSeq = 0;

  /// Maximum accepted request-body size in bytes (NET-04). A declared
  /// Content-Length over this is rejected up front; a chunked / mis-declared
  /// body is cut off mid-stream once the running total exceeds it.
  final int maxRequestBodyBytes;

  /// Upper bound on how long a single request may be handled before the server
  /// answers 504, so a stuck dependency can't hold a connection open forever
  /// (NET-04).
  final Duration requestTimeout;

  /// [repository] defaults to the [DatabaseService] host singleton; it is
  /// injectable so the full server (router + auth middleware) can be exercised
  /// against an in-memory repository in tests. [auth] is only supplied on the
  /// host; when present, requests are guarded once an admin credential exists.
  /// [idempotencyStore] backs safe replay of retried POSTs (REL-03); it is
  /// injectable for tests and defaults to a fresh in-memory store per server.
  /// [maxRequestBodyBytes] / [requestTimeout] tune the request guards and are
  /// injectable so tests can trigger 413 / 504 without huge or slow payloads.
  HttpServerService({
    LibraryRepository? repository,
    AuthService? auth,
    IdempotencyStore? idempotencyStore,
    RateLimiter? rateLimiter,
    this.maxRequestBodyBytes = 5 * 1024 * 1024,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _db = repository ?? DatabaseService(),
       _auth = auth,
       _rateLimit = rateLimiter ?? RateLimiter(),
       _idempotency = idempotencyStore ?? IdempotencyStore();

  bool get isRunning => _server != null;

  /// The port the server is actually bound to (useful when starting on 0).
  int get port => _server?.port ?? 0;

  /// Requests currently mid-handling (exposed for quiesce + tests).
  int get inFlightRequests => _inFlight;

  /// Whether the server is refusing new work for a maintenance window.
  bool get isMaintenance => _maintenance;

  /// Begin a maintenance window: new requests get 503 until [exitMaintenance].
  void enterMaintenance() => _maintenance = true;

  /// Resume accepting requests after [enterMaintenance].
  void exitMaintenance() => _maintenance = false;

  /// Phase 19: host-local chat post used by the host's OWN UI (paired clients
  /// post over HTTP to the `/chat` route, which funnels here too). Returns the
  /// stored message so the caller can reflect it immediately. Throws on an
  /// empty or over-long message so the UI cannot report a false send.
  ChatMessage postChatLocal(String sender, String role, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Message is empty');
    }
    if (trimmed.length > _chatMaxTextChars) {
      throw FormatException('Message exceeds $_chatMaxTextChars characters');
    }
    final msg = ChatMessage(
      id: ++_chatSeq,
      sender: sender,
      role: role,
      sentAt: DateTime.now(),
      text: trimmed,
    );
    _chat.add(msg);
    if (_chat.length > _chatRetention) {
      _chat.removeRange(0, _chat.length - _chatRetention);
    }
    return msg;
  }

  /// Phase 19: host-local read of chat messages with id greater than [since],
  /// plus the current high-water id (the cursor a poller sends next time).
  ({List<ChatMessage> messages, int latest}) chatSinceLocal(int since) {
    final newer = _chat.where((m) => m.id > since).toList(growable: false);
    return (messages: newer, latest: _chatSeq);
  }

  /// Wait until no request is mid-handling, so the caller can safely swap or
  /// wipe the database. Returns true if drained within [timeout]; false if it
  /// gave up with requests still active (best-effort; the caller still proceeds,
  /// because new work is already being refused).
  Future<bool> drainInFlight({
    Duration timeout = const Duration(seconds: 5),
    Duration poll = const Duration(milliseconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (_inFlight > 0 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(poll);
    }
    return _inFlight == 0;
  }

  /// Runs a destructive [op] (restore / wipe) inside a quiesced window: refuse
  /// new requests, drain in-flight handlers, run [op], then ALWAYS resume.
  Future<T> withMaintenance<T>(Future<T> Function() op) async {
    enterMaintenance();
    try {
      await drainInFlight();
      return await op();
    } finally {
      exitMaintenance();
    }
  }

  /// Outermost middleware: turns any uncaught exception from downstream
  /// handlers (auth, idempotency, the router) into a structured
  /// `{"error","message"}` JSON response with an appropriate status code, so a
  /// failure is diagnosable by clients instead of surfacing as a bare 500 or a
  /// dropped connection (BE-02). Maps a domain delete-conflict to 409 and a
  /// malformed request body to 400.
  Middleware _errorMiddleware() {
    return (Handler inner) {
      return (Request request) async {
        // ARC-06: mint a per-request id and thread it through the shelf context
        // so a downstream timeout/5xx and any handler log line can be tied to
        // one exchange when reading the diagnostics bundle.
        final reqId = 'r${++_reqSeq}';
        final traced = request.change(context: {'reqId': reqId});
        try {
          return await inner(traced);
        } on ActiveLoanConflictException catch (e) {
          return _json(409, {'error': 'conflict', 'message': e.message});
        } on MemberIdConflictException catch (e) {
          // DB-01: a member_id rename colliding with another member -- surface
          // the reason as a 409, exactly like the delete conflicts.
          return _json(409, {'error': 'conflict', 'message': e.message});
        } on ItemCodeConflictException catch (e) {
          // BE-07 / BE-08: a duplicate item code (incl. two concurrent adds
          // that picked the same generated number) is a conflict, not a 500.
          return _json(409, {'error': 'conflict', 'message': e.message});
        } on BarcodeConflictException catch (e) {
          // DB-01: a non-empty barcode already held by another title violates
          // the partial UNIQUE index; surface 409 with the reason, not a 500.
          return _json(409, {'error': 'conflict', 'message': e.message});
        } on AttributeConflictException catch (e) {
          // DB-01: a duplicate (type, value) attribute definition violates
          // uq_attr_type_value; a conflict (409), not a 500.
          return _json(409, {'error': 'conflict', 'message': e.message});
        } on ConcurrentUpdateConflictException catch (e) {
          // TX-06: a stale whole-row write was refused because the row changed
          // since the caller read its version. 409 so the client reloads the
          // current row instead of silently clobbering another edit.
          return _json(409, {'error': 'conflict', 'message': e.message});
        } on MalformedRequestException catch (e) {
          // PROTO-01: a body that IS valid JSON but is unusable (wrong shape /
          // missing or wrongly-typed field) is a client error, not a 500.
          return _json(400, {'error': 'bad_request', 'message': e.message});
        } on InvalidStatusException catch (e) {
          // BL-05: a title status outside the copy-derived vocabulary is an
          // invalid input VALUE (400), not a state conflict -- the message is
          // server-authored and names no secret.
          return _json(400, {'error': 'bad_request', 'message': e.message});
        } on UserAdminException catch (e) {
          // Phase 10.1: user-administration refusals. Input-format problems
          // are 400; state conflicts (duplicate/unknown account, last-admin
          // guard) are 409. Messages are server-authored and carry no secrets.
          final m = e.message;
          final badRequest =
              m.contains('characters') ||
              m.contains('starting with') ||
              m.contains('Password must not');
          return _json(badRequest ? 400 : 409, {
            'error': badRequest ? 'bad_request' : 'conflict',
            'message': m,
          });
        } on StateError catch (e) {
          // Phase 10.2: a fine settle refused because the ledger row is unknown
          // or ALREADY resolved (the compare-and-swap on the pending state).
          // This is a real conflict, never a 500 -- so a double-click or a
          // racing client cannot double-collect and instead gets a clean, typed
          // refusal carrying the server's concrete reason.
          return _json(409, {'error': 'conflict', 'message': e.message});
        } on FormatException {
          return _json(400, {
            'error': 'bad_request',
            'message': 'Invalid JSON body',
          });
        } on _BodyTooLargeException {
          return _json(413, {
            'error': 'payload_too_large',
            'message': 'Request body exceeds $maxRequestBodyBytes bytes',
          });
        } catch (e, st) {
          // Persist before responding: a release-mode 500 that only debugPrints
          // leaves no trace on a user's machine (REL/logging).
          appLog.error(
            'http',
            '[$reqId] Unhandled error on ${request.method} ${request.url}',
            e,
            st,
          );
          return _json(500, {
            'error': 'internal_error',
            'message': kReleaseMode ? 'Internal server error' : '$e',
          });
        }
      };
    };
  }

  /// Rejects a request whose `X-Api-Version` header advertises a protocol this
  /// host does not speak (426 Upgrade Required), so a stale-vs-new client cannot
  /// silently mis-parse a response. A request with NO header (a peer predating
  /// versioning, curl, a health probe) is passed through untouched, so adding
  /// this check never breaks an already-deployed client (DEP-02).
  Middleware _versionNegotiation() {
    return (Handler inner) {
      return (Request request) async {
        final raw = request.headers[apiVersionHeader.toLowerCase()];
        if (raw != null && !isApiVersionCompatible(int.tryParse(raw.trim()))) {
          return _json(426, {
            'error': 'upgrade_required',
            'message':
                'Client API version $raw is incompatible with server $kApiProtocolVersion',
          });
        }
        return inner(request);
      };
    };
  }

  /// Refuses new requests with 503 during a maintenance window and otherwise
  /// brackets each request with an in-flight counter, so [drainInFlight] can
  /// wait for active handlers before a restore swaps or a wipe clears the
  /// shared database (DB-04).
  Middleware _maintenanceGate() {
    return (Handler inner) {
      return (Request request) async {
        if (_maintenance) {
          return _json(503, {
            'error': 'maintenance',
            'message':
                'Server is restoring or resetting the database, retry shortly',
          });
        }
        _inFlight++;
        try {
          return await inner(request);
        } finally {
          _inFlight--;
        }
      };
    };
  }

  /// Rejects a declared body over [maxRequestBodyBytes] up front (413), caps
  /// the actual byte stream so a chunked / lying client can't exhaust memory
  /// (the read throws mid-flight -> 413 via the error middleware), and bounds
  /// total handling time with [requestTimeout] (504). Installed just inside
  /// the error middleware so a size/timeout failure is reported as structured
  /// JSON rather than a dropped connection (NET-04).
  Middleware _requestGuards() {
    return (Handler inner) {
      return (Request request) async {
        if ((request.contentLength ?? 0) > maxRequestBodyBytes) {
          return _json(413, {
            'error': 'payload_too_large',
            'message': 'Request body exceeds $maxRequestBodyBytes bytes',
          });
        }
        final guarded = request.change(
          body: _capStream(request.read(), maxRequestBodyBytes),
        );
        return await Future.value(inner(guarded)).timeout(
          requestTimeout,
          onTimeout: () {
            appLog.warn(
              'http',
              '[${request.context['reqId'] ?? '-'}] Request timed out after '
                  '$requestTimeout: ${request.method} ${request.url}',
            );
            return _json(504, {
              'error': 'gateway_timeout',
              'message': 'Request processing timed out',
            });
          },
        );
      };
    };
  }

  /// Passes chunks through until the running byte total exceeds [maxBytes], at
  /// which point the returned stream errors with [_BodyTooLargeException].
  Stream<List<int>> _capStream(Stream<List<int>> source, int maxBytes) async* {
    var total = 0;
    await for (final chunk in source) {
      total += chunk.length;
      if (total > maxBytes) throw const _BodyTooLargeException();
      yield chunk;
    }
  }

  /// Throttles *state-changing* requests per source IP with a token bucket
  /// (NET-13 / PROTO-04): once a caller spends the burst it is capped to the
  /// sustained rate, and further writes get 429 + Retry-After instead of reaching
  /// the shared database. Read methods (GET/HEAD) are exempt so the clients'
  /// 1-2s `/db-version` sync poll is never throttled. Installed innermost (after
  /// auth and idempotent replay) so unauthorized floods and cache-served retried
  /// POSTs never consume a write token.
  Middleware _writeRateLimit() {
    const writes = {'POST', 'PUT', 'PATCH', 'DELETE'};
    return (Handler inner) {
      return (Request request) async {
        if (!writes.contains(request.method.toUpperCase())) {
          return inner(request);
        }
        final retryAfter = _rateLimit.tryAcquire(_clientIp(request));
        if (retryAfter != null) {
          return _json(429, {
            'error': 'rate_limited',
            'message':
                'Too many write requests; retry after '
                '${retryAfter.inSeconds}s',
            'retry_after_seconds': retryAfter.inSeconds,
          });
        }
        return inner(request);
      };
    };
  }

  Future<void> stopServer() async {
    final server = _server;
    if (server == null) return;
    _server = null;
    try {
      await server.close(force: true);
    } catch (e) {
      // RC-07: a failed shutdown was previously swallowed to debugPrint only;
      // surface it so a leaked listener / stuck socket is diagnosable.
      appLog.warn('http', 'Error stopping LAN server', e);
    }
  }

  Future<void> startServer({
    Function(String ip)? onActivity,
    String host = '0.0.0.0',
    int port = NetworkConfig.defaultHttpPort,
  }) async {
    if (_server != null) return;
    final router = Router();

    // Authentication: exchange admin credentials for a bearer token. Always
    // available (never itself guarded); throttled per source IP by AuthService.
    if (_auth != null) {
      router.post('/auth/login', (Request request) async {
        final body = await request.readAsString();
        Map<String, dynamic> map;
        try {
          map = jsonDecode(body) as Map<String, dynamic>;
        } catch (_) {
          return _json(400, {
            'error': 'bad_request',
            'message': 'Invalid JSON body',
          });
        }
        final username = (map['username'] ?? '').toString();
        final password = (map['password'] ?? '').toString();
        final result = await _auth.login(
          username,
          password,
          sourceKey: _clientIp(request),
        );
        switch (result.status) {
          case AuthStatus.ok:
            // Echo the winner's identity+role (Phase 10.1) so the client can
            // label its session and gate WRITE affordances locally; the
            // SERVER remains the enforcement authority regardless.
            return _json(200, {
              'token': result.token,
              if (result.principal != null)
                'username': result.principal!.username,
              if (result.principal != null)
                'role': result.principal!.role.storage,
            });
          case AuthStatus.locked:
            return _json(429, {
              'error': 'too_many_attempts',
              'retry_after_seconds': result.retryAfter?.inSeconds ?? 0,
            });
          case AuthStatus.invalidCredentials:
            return _json(401, {'error': 'invalid_credentials'});
        }
      });

      // The client's own identity, re-derivable from a bearer token alone.
      // Lets a restarting client recover the role it previously logged in with
      // (the persisted token grants those rights anyway -- this only tells the
      // UI which affordances to offer). Guarded by the bearer middleware, so an
      // unpaired caller learns nothing.
      router.get('/auth/session', (Request request) async {
        final p = principalOf(request);
        return _json(200, {
          'username': p?.username ?? '',
          'role': (p?.role ?? UserRole.viewer).storage,
          'named': p?.isNamed ?? false,
        });
      });

      // ------------------------------------------------------------------
      // Users & roles (Phase 10.1). Mounted ONLY when auth is configured --
      // a bootstrap-open server (no credential yet) has no user store to
      // administer, and a client cannot BECOME admin over HTTP: accounts are
      // created exclusively by an already-authenticated admin principal, so
      // this surface can never escalate an unpaired caller.
      // ------------------------------------------------------------------
      router.get('/users', (Request request) async {
        final denied = _forbiddenUnless(request, UserRole.admin);
        if (denied != null) return denied;
        final list = await _auth.users();
        return _json(200, {
          'users': [for (final u in list) u.toPublicMap()],
        });
      });

      router.post('/users', (Request request) async {
        final denied = _forbiddenUnless(request, UserRole.admin);
        if (denied != null) return denied;
        final map = await readJsonObject(request);
        final username = requireNonEmpty(map, 'username');
        final password = requireNonEmpty(map, 'password');
        final role = _requireRole(map['role']);
        final created = await _auth.addUser(username, password, role);
        return _json(201, created.toPublicMap());
      });

      router.put('/users/<username>', (Request request, String username) async {
        final denied = _forbiddenUnless(request, UserRole.admin);
        if (denied != null) return denied;
        final map = await readJsonObject(request);
        final role = _requireRole(map['role']);
        await _auth.changeUserRole(Uri.decodeComponent(username), role);
        return _json(200, {'ok': true});
      });

      router.put('/users/<username>/password', (
        Request request,
        String username,
      ) async {
        final denied = _forbiddenUnless(request, UserRole.admin);
        if (denied != null) return denied;
        final map = await readJsonObject(request);
        final password = requireNonEmpty(map, 'password');
        await _auth.setUserPassword(Uri.decodeComponent(username), password);
        return _json(200, {'ok': true});
      });

      router.delete('/users/<username>', (
        Request request,
        String username,
      ) async {
        final denied = _forbiddenUnless(request, UserRole.admin);
        if (denied != null) return denied;
        await _auth.removeUser(Uri.decodeComponent(username));
        return _json(200, {'ok': true});
      });

      // ------------------------------------------------------------------
      // LAN staff chat (Phase 19). Ephemeral, host-held, STAFF-ONLY: a
      // viewer/kiosk client can neither read nor post (a read-only surface
      // would only ever show an empty panel). Mounted only when auth is
      // configured, like the other internals. The buffer is in-process
      // ([postChatLocal]) -- nothing reaches the shared database.
      // ------------------------------------------------------------------
      router.post('/chat', (Request request) async {
        final denied = _forbiddenUnless(request, UserRole.staff);
        if (denied != null) return denied;
        final map = await readJsonObject(request);
        final raw = map['text'];
        final text = (raw is String ? raw : '').trim();
        if (text.isEmpty) {
          return _json(400, {
            'error': 'bad_request',
            'message': 'Empty message',
          });
        }
        if (text.length > _chatMaxTextChars) {
          return _json(400, {
            'error': 'bad_request',
            'message': 'Message exceeds $_chatMaxTextChars characters',
          });
        }
        final p = principalOf(request);
        final msg = postChatLocal(
          p?.username ?? 'staff',
          (p?.role ?? UserRole.staff).storage,
          text,
        );
        return _json(201, msg.toMap());
      });

      router.get('/chat', (Request request) async {
        final denied = _forbiddenUnless(request, UserRole.staff);
        if (denied != null) return denied;
        final since =
            int.tryParse(request.url.queryParameters['since'] ?? '0') ?? 0;
        final res = chatSinceLocal(since);
        return _json(200, {
          'messages': res.messages.map((m) => m.toMap()).toList(),
          'latest': res.latest,
        });
      });
    }

    // GET /items
    router.get('/items', (Request request) async {
      final q = request.url.queryParameters;
      final limit = int.tryParse(q['limit'] ?? '1000') ?? 1000;
      final offset = int.tryParse(q['offset'] ?? '0') ?? 0;

      // Search / filter / pagination happen in the database, not over a cached
      // page (FE-05 / FE2-05 / Phase 7).
      final items = await _db.getItems(
        limit: limit,
        offset: offset,
        search: q['search'],
        status: q['status'],
        codeType: q['codeType'],
        sort: q['sort'],
        ascending: (q['order'] ?? 'asc').toLowerCase() != 'desc',
      );
      final jsonList = items.map((item) => item.toMap()).toList();
      return Response.ok(
        jsonEncode(jsonList),
        headers: {'content-type': 'application/json'},
      );
    });

    // GET /items/count — total rows matching the same filters, so clients can
    // paginate correctly against the whole catalogue.
    router.get('/items/count', (Request request) async {
      final q = request.url.queryParameters;
      final count = await _db.countItems(
        search: q['search'],
        status: q['status'],
        codeType: q['codeType'],
      );
      return _json(200, {'count': count});
    });

    // POST /items
    router.post('/items', (Request request) async {
      final denied = _forbiddenUnless(request, UserRole.staff);
      if (denied != null) return denied;
      final map = await readJsonObject(request);
      requireNonEmpty(map, 'code');
      requireNonEmpty(map, 'designation');
      final item = parseModel(map, LibraryItem.fromMap, 'Item');
      // BE-08: reject a negative quantity/price as a 400 (never persisted).
      if (item.quantite < 0 || item.taux < 0) {
        throw MalformedRequestException(
          'quantite and taux must not be negative',
        );
      }
      // Audit is written atomically with the mutation (TX-01 / 5.2).
      await _db.addItem(
        item,
        audit: {
          'timestamp': DateTime.now().toIso8601String(),
          'operation': 'ADD',
          'details': 'Item ajouté: ${item.fullCode}',
          'user': _clientIp(request),
        },
      );
      return Response.ok('Item added');
    });

    // PUT /items
    router.put('/items', (Request request) async {
      final denied = _forbiddenUnless(request, UserRole.staff);
      if (denied != null) return denied;
      final map = await readJsonObject(request);
      requireNonEmpty(map, 'code');
      requireNonEmpty(map, 'designation');
      final item = parseModel(map, LibraryItem.fromMap, 'Item');
      // BE-08: reject a negative quantity/price as a 400 (never persisted).
      if (item.quantite < 0 || item.taux < 0) {
        throw MalformedRequestException(
          'quantite and taux must not be negative',
        );
      }
      // TX-06: honour an optimistic-concurrency check when the client sends the
      // version it read. Absent (or non-numeric) => unconditional write, so the
      // route stays backward-compatible with legacy/host callers.
      final verHeader = request.headers['x-expected-version'];
      final expectedVersion = verHeader == null
          ? null
          : int.tryParse(verHeader.trim());
      await _db.updateItem(
        item,
        audit: {
          'timestamp': DateTime.now().toIso8601String(),
          'operation': 'UPDATE',
          'details': 'Item modifié: ${item.fullCode}',
          'user': _clientIp(request),
        },
        expectedVersion: expectedVersion,
      );
      return Response.ok('Item updated');
    });

    // DELETE /items/<code.>
    router.delete('/items/<code>', (Request request, String code) async {
      final denied = _forbiddenUnless(request, UserRole.staff);
      if (denied != null) return denied;
      // FB-04: the client percent-encodes the code so specials survive as one
      // segment; DB keys are the raw value, so decode before use.
      final itemCode = Uri.decodeComponent(code);
      try {
        await _db.deleteItem(
          itemCode,
          audit: {
            'timestamp': DateTime.now().toIso8601String(),
            'operation': 'DELETE',
            'details': 'Item supprimé: $itemCode',
            'user': _clientIp(request),
          },
        );
      } on ActiveLoanConflictException catch (e) {
        // BL-04: refuse to delete a title that is on loan (409, not 500).
        return _json(409, {'error': 'conflict', 'message': e.message});
      }
      return Response.ok('Item deleted');
    });

    // GET /history
    router.get('/history', (Request request) async {
      final queryParams = request.url.queryParameters;
      final limit = int.tryParse(queryParams['limit'] ?? '20') ?? 20;
      final offset = int.tryParse(queryParams['offset'] ?? '0') ?? 0;
      // Pass 5: an optional `subject` query param narrows the response to
      // audit rows whose `details` mention it (used by Item Detail and
      // Member Detail history timelines). Absent = unfiltered, matching
      // older client behaviour.
      final subject = queryParams['subject'];

      final stats = await _db.getHistory(
        limit: limit,
        offset: offset,
        subject: subject,
      );
      return Response.ok(
        jsonEncode(stats),
        headers: {'content-type': 'application/json'},
      );
    });

    // POST /history -- DB-05: a client may append an audit line, but ONLY with
    // a server-assigned id, server receive-time and the authenticated source.
    // The raw body is never inserted: a client-supplied `id` (which can collide
    // with the AUTOINCREMENT sequence -> ConstraintError/500), a backdated
    // timestamp, a spoofed `user`, or an unknown column (no-such-column -> 500)
    // are all dropped -- the route builds a whitelisted entry from validated
    // fields and records the caller's own IP as the source.
    router.post('/history', (Request request) async {
      final denied = _forbiddenUnless(request, UserRole.staff);
      if (denied != null) return denied;
      final map = await readJsonObject(request);
      final entry = <String, dynamic>{
        'timestamp': DateTime.now().toIso8601String(),
        'operation': requireNonEmpty(map, 'operation'),
        'details': requireNonEmpty(map, 'details'),
        'user': _clientIp(request),
      };
      await _db.addHistoryEntry(entry);
      return Response.ok('History logged');
    });

    // GET /stats
    router.get('/stats', (Request request) async {
      final stats = await _db.getStats();
      return Response.ok(
        jsonEncode(stats),
        headers: {'content-type': 'application/json'},
      );
    });

    router.get('/barcode/<barcode>', (Request request, String barcode) async {
      final scanned = Uri.decodeComponent(barcode); // FB-04
      final item = await _db.getItemByBarcode(scanned);
      if (item == null) {
        return Response.notFound(jsonEncode({'error': 'Item not found'}));
      }
      return Response.ok(
        jsonEncode(item.toMap()),
        headers: {'content-type': 'application/json'},
      );
    });

    // GET /db-version -- also advertises the host's API protocol so a client
    // learns compatibility on its very first poll (DEP-02).
    router.get('/db-version', (Request request) async {
      final version = await _db.getDbVersion();
      return Response.ok(
        jsonEncode({
          'version': version,
          apiVersionBodyKey: kApiProtocolVersion,
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    // Code Definitions CRUD
    router.get('/code-definitions', (Request request) async {
      final defs = await _db.getCodeDefinitions();
      return Response.ok(
        jsonEncode(defs),
        headers: {'content-type': 'application/json'},
      );
    });

    router.post('/code-definitions', (Request request) async {
      final denied = _forbiddenUnless(request, UserRole.admin);
      if (denied != null) return denied;
      final map = await readJsonObject(request);
      final newPrefix = requireNonEmpty(map, 'prefix');
      final label = requireNonEmpty(map, 'label');
      await _db.addCodeDefinition(
        newPrefix,
        label,
        audit: {
          'timestamp': DateTime.now().toIso8601String(),
          'operation': 'ADD_VAR',
          'details': 'Code definition added: $newPrefix ($label)',
          'user': _clientIp(request),
        },
      );
      return Response.ok('Definition added');
    });

    router.put('/code-definitions/<prefix>', (
      Request request,
      String prefix,
    ) async {
      final denied = _forbiddenUnless(request, UserRole.admin);
      if (denied != null) return denied;
      final oldPrefix = Uri.decodeComponent(prefix); // FB-04
      final map = await readJsonObject(request);
      final replacementPrefix = requireNonEmpty(map, 'prefix');
      final label = requireNonEmpty(map, 'label');
      await _db.updateCodeDefinition(
        oldPrefix,
        replacementPrefix,
        label,
        audit: {
          'timestamp': DateTime.now().toIso8601String(),
          'operation': 'UPDATE_VAR',
          'details':
              'Code definition updated: $oldPrefix -> $replacementPrefix ($label)',
          'user': _clientIp(request),
        },
      );
      return Response.ok('Definition updated');
    });

    router.delete('/code-definitions/<prefix>', (
      Request request,
      String prefix,
    ) async {
      final denied = _forbiddenUnless(request, UserRole.admin);
      if (denied != null) return denied;
      final target = Uri.decodeComponent(prefix); // FB-04
      await _db.deleteCodeDefinition(
        target,
        audit: {
          'timestamp': DateTime.now().toIso8601String(),
          'operation': 'DELETE_VAR',
          'details': 'Code definition deleted: $target',
          'user': _clientIp(request),
        },
      );
      return Response.ok('Definition deleted');
    });

    // Attribute Definitions Enum/Lists
    router.get('/attribute-definitions', (Request request) async {
      final type = request.url.queryParameters['type'];
      final defs = await _db.getAttributeDefinitions(type);
      return Response.ok(
        jsonEncode(defs),
        headers: {'content-type': 'application/json'},
      );
    });

    router.post('/attribute-definitions', (Request request) async {
      final denied = _forbiddenUnless(request, UserRole.admin);
      if (denied != null) return denied;
      final map = await readJsonObject(request);
      final type = requireNonEmpty(map, 'type');
      final value = requireNonEmpty(map, 'value');
      await _db.addAttributeDefinition(
        type,
        value,
        audit: {
          'timestamp': DateTime.now().toIso8601String(),
          'operation': 'ADD_ATTR',
          'details': 'Attribute definition added ($type): $value',
          'user': _clientIp(request),
        },
      );
      return Response.ok('Attribute added');
    });

    router.delete('/attribute-definitions/<id>', (
      Request request,
      String id,
    ) async {
      final denied = _forbiddenUnless(request, UserRole.admin);
      if (denied != null) return denied;
      final intId = int.tryParse(id);
      if (intId != null) {
        await _db.deleteAttributeDefinition(
          intId,
          audit: {
            'timestamp': DateTime.now().toIso8601String(),
            'operation': 'DELETE_ATTR',
            'details': 'Attribute definition deleted (ID: $intId)',
            'user': _clientIp(request),
          },
        );
      }
      return Response.ok('Attribute deleted');
    });

    // Members CRUD
    router.get('/members', (Request request) async {
      final members = await _db.getMembers();
      final jsonList = members.map((m) => m.toMap()).toList();
      return Response.ok(
        jsonEncode(jsonList),
        headers: {'content-type': 'application/json'},
      );
    });

    router.post('/members', (Request request) async {
      final denied = _forbiddenUnless(request, UserRole.staff);
      if (denied != null) return denied;
      final map = await readJsonObject(request);
      requireMemberName(map);
      final member = parseModel(map, Member.fromMap, 'Member');
      Member finalMember = member;
      final memberId = member.memberId.trim();
      if (memberId.isEmpty || memberId == 'AUTO') {
        final generated = await _db.generateMemberID();
        finalMember = Member(
          id: member.id,
          firstName: member.firstName,
          lastName: member.lastName,
          email: member.email,
          phone: member.phone,
          memberId: generated,
          registeredAt: member.registeredAt,
        );
      }
      await _db.addMember(
        finalMember,
        audit: {
          'timestamp': DateTime.now().toIso8601String(),
          'operation': 'ADD_MEMBER',
          'details': 'Member added: ${finalMember.fullName}',
          'user': _clientIp(request),
        },
      );

      return Response.ok(
        jsonEncode(finalMember.toMap()),
        headers: {'content-type': 'application/json'},
      );
    });

    router.put('/members', (Request request) async {
      final denied = _forbiddenUnless(request, UserRole.staff);
      if (denied != null) return denied;
      final map = await readJsonObject(request);
      requireMemberName(map);
      if (map['id'] == null) {
        throw MalformedRequestException(
          'Field "id" is required to update a member',
        );
      }
      final member = parseModel(map, Member.fromMap, 'Member');
      // TX-06: honour an optimistic-concurrency check when the client sends the
      // version it read. Absent (or non-numeric) => unconditional write, so the
      // route stays backward-compatible with legacy/host callers.
      final verHeader = request.headers['x-expected-version'];
      final expectedVersion = verHeader == null
          ? null
          : int.tryParse(verHeader.trim());
      await _db.updateMember(
        member,
        audit: {
          'timestamp': DateTime.now().toIso8601String(),
          'operation': 'UPDATE_MEMBER',
          'details': 'Member updated: ${member.fullName}',
          'user': _clientIp(request),
        },
        expectedVersion: expectedVersion,
      );

      return Response.ok('Member updated');
    });

    router.delete('/members/<memberId>', (
      Request request,
      String memberId,
    ) async {
      final denied = _forbiddenUnless(request, UserRole.staff);
      if (denied != null) return denied;
      final id = Uri.decodeComponent(memberId); // FB-04
      try {
        await _db.deleteMember(
          id,
          audit: {
            'timestamp': DateTime.now().toIso8601String(),
            'operation': 'DELETE_MEMBER',
            'details': 'Member deleted: $id',
            'user': _clientIp(request),
          },
        );
      } on ActiveLoanConflictException catch (e) {
        // BL-04: refuse to delete a member with items still out (409, not 500).
        return _json(409, {'error': 'conflict', 'message': e.message});
      }

      return Response.ok('Member deleted');
    });

    // Loans CRUD
    router.get('/loans', (Request request) async {
      final queryParams = request.url.queryParameters;
      final activeOnly = queryParams['activeOnly'] == 'true';
      final loans = await _db.getLoans(activeOnly: activeOnly);
      final jsonList = loans.map((l) => l.toMap()).toList();
      return Response.ok(
        jsonEncode(jsonList),
        headers: {'content-type': 'application/json'},
      );
    });

    // Scan-to-return resolution (BL-03): maps a copied/scanned value to the
    // specific active loan. 404 when nothing matches (client treats as null).
    router.get('/loans/resolve-scan', (Request request) async {
      final code = request.url.queryParameters['code'] ?? '';
      final loan = await _db.findActiveLoanByScan(code);
      if (loan == null) {
        return _json(404, {'error': 'no_active_loan', 'code': code});
      }
      return Response.ok(
        jsonEncode(loan.toMap()),
        headers: {'content-type': 'application/json'},
      );
    });

    router.post('/loans', (Request request) async {
      final denied = _forbiddenUnless(request, UserRole.staff);
      if (denied != null) return denied;
      final map = await readJsonObject(request);
      final loan = parseModel(map, Loan.fromMap, 'Loan');
      await _db.addLoan(
        loan,
        audit: {
          'timestamp': DateTime.now().toIso8601String(),
          'operation': 'LOAN_OUT',
          'details': 'Loan created: ${loan.itemCode} to ${loan.memberName}',
          'user': _clientIp(request),
        },
      );

      return Response.ok('Loan added');
    });

    router.put('/loans', (Request request) async {
      final denied = _forbiddenUnless(request, UserRole.staff);
      if (denied != null) return denied;
      final map = await readJsonObject(request);
      final loan = parseModel(map, Loan.fromMap, 'Loan');
      await _db.updateLoan(
        loan,
        audit: {
          'timestamp': DateTime.now().toIso8601String(),
          'operation': loan.status == LoanStatus.returned.storage
              ? 'LOAN_RETURN'
              : 'LOAN_UPDATE',
          'details': 'Loan updated: ${loan.itemCode}',
          'user': _clientIp(request),
        },
      );

      return Response.ok('Loan updated');
    });

    // ------------------------------------------------------------------
    // Fines & payments (Phase 10.2). Server-authoritative money rules:
    // accrual already happened inside PUT /loans; these routes READ the
    // ledger and RESOLVE (pay / waive) an open fine. Reads require STAFF
    // (a fine is patron-financial data, not a public catalogue); settling
    // one records the AUTHENTICATED bearer as `resolved_by`, so a client
    // can never attribute a collection to someone else. The fine POLICY
    // (rate / currency) is administrator-only to author. A settle of an
    // unknown/already-resolved fine throws StateError -> 409 (see the
    // error middleware), which is what makes pay/waive idempotency-safe.
    // ------------------------------------------------------------------
    router.get('/settings/fines', (Request request) async {
      final denied = _forbiddenUnless(request, UserRole.staff);
      if (denied != null) return denied;
      final s = await _db.getFineSettings();
      return _json(200, s.toMap());
    });

    router.put('/settings/fines', (Request request) async {
      final denied = _forbiddenUnless(request, UserRole.admin);
      if (denied != null) return denied;
      final map = await readJsonObject(request);
      final rate = map['rate_per_day'];
      if (rate is! num || !rate.isFinite || rate < 0) {
        throw MalformedRequestException(
          'rate_per_day must be a non-negative number',
        );
      }
      final currencyRaw = map['currency'];
      final currency = (currencyRaw is String && currencyRaw.trim().isNotEmpty)
          ? currencyRaw.trim()
          : FineSettings.defaultCurrency;
      await _db.setFineSettings(
        FineSettings(ratePerDay: rate.toDouble(), currency: currency),
        audit: {
          'timestamp': DateTime.now().toIso8601String(),
          'operation': 'FINE_SETTINGS',
          'details': 'Fine rate set to ${rate.toDouble()} $currency per day',
          'user': _clientIp(request),
        },
      );
      return _json(200, {'ok': true});
    });

    router.get('/fines', (Request request) async {
      final denied = _forbiddenUnless(request, UserRole.staff);
      if (denied != null) return denied;
      final q = request.url.queryParameters;
      final memberId = q['member_id'];
      final statusRaw = q['status'];
      FineStatus? status;
      if (statusRaw != null && statusRaw.isNotEmpty) {
        status = FineStatus.tryParse(statusRaw);
        if (status == null) {
          throw MalformedRequestException(
            'status must be one of: pending, paid, waived',
          );
        }
      }
      final fines = await _db.getFines(memberId: memberId, status: status);
      return Response.ok(
        jsonEncode(fines.map((f) => f.toMap()).toList()),
        headers: {'content-type': 'application/json'},
      );
    });

    router.get('/fines/balance', (Request request) async {
      final denied = _forbiddenUnless(request, UserRole.staff);
      if (denied != null) return denied;
      final memberId = (request.url.queryParameters['member_id'] ?? '').trim();
      if (memberId.isEmpty) {
        throw MalformedRequestException('member_id is required');
      }
      final balance = await _db.outstandingBalance(memberId);
      return _json(200, {'member_id': memberId, 'balance': balance});
    });

    router.post('/fines/<id>/pay', (Request request, String id) async {
      final denied = _forbiddenUnless(request, UserRole.staff);
      if (denied != null) return denied;
      final fineId = int.tryParse(id);
      if (fineId == null) {
        throw MalformedRequestException('fine id must be an integer');
      }
      await _db.payFine(
        fineId,
        operatorName: principalOf(request)?.username,
        audit: {
          'timestamp': DateTime.now().toIso8601String(),
          'operation': 'FINE_PAY',
          'details': 'Fine #$fineId marked paid',
          'user': _clientIp(request),
        },
      );
      return _json(200, {'ok': true});
    });

    router.post('/fines/<id>/waive', (Request request, String id) async {
      final denied = _forbiddenUnless(request, UserRole.staff);
      if (denied != null) return denied;
      final fineId = int.tryParse(id);
      if (fineId == null) {
        throw MalformedRequestException('fine id must be an integer');
      }
      await _db.waiveFine(
        fineId,
        operatorName: principalOf(request)?.username,
        audit: {
          'timestamp': DateTime.now().toIso8601String(),
          'operation': 'FINE_WAIVE',
          'details': 'Fine #$fineId waived',
          'user': _clientIp(request),
        },
      );
      return _json(200, {'ok': true});
    });

    // ------------------------------------------------------------------
    // Reservations / hold queue (Phase 10.3). Server-authoritative: the host
    // owns the queue and every copy claim, so a client can only ask to JOIN or
    // LEAVE a line and read what the server decided. Reads and hold moves
    // require STAFF (a hold names a patron); the hold POLICY (pickup window /
    // queue cap) is administrator-only to author. Placing a hold for an unknown
    // item/member, a duplicate live hold, or a full queue, and cancelling an
    // unknown/already-closed hold, all throw StateError -> 409 (see the error
    // middleware). A borrow that would cut a promoted holder in line is refused
    // inside PUT/POST /loans regardless of anything these routes accept.
    // ------------------------------------------------------------------
    router.get('/settings/holds', (Request request) async {
      final denied = _forbiddenUnless(request, UserRole.staff);
      if (denied != null) return denied;
      final s = await _db.getHoldSettings();
      return _json(200, s.toMap());
    });

    router.put('/settings/holds', (Request request) async {
      final denied = _forbiddenUnless(request, UserRole.admin);
      if (denied != null) return denied;
      final map = await readJsonObject(request);
      final pickup = map['pickup_days'];
      if (pickup is! num || !pickup.isFinite || pickup < 1 || pickup > 90) {
        throw MalformedRequestException(
          'pickup_days must be a whole number between 1 and 90',
        );
      }
      final cap = map['queue_max_per_item'];
      if (cap is! num || !cap.isFinite || cap < 1 || cap > 500) {
        throw MalformedRequestException(
          'queue_max_per_item must be a whole number between 1 and 500',
        );
      }
      await _db.setHoldSettings(
        // Persist the SANITISED integers, never the raw client number.
        HoldSettings(pickupDays: pickup.toInt(), queueMaxPerItem: cap.toInt()),
        audit: {
          'timestamp': DateTime.now().toIso8601String(),
          'operation': 'HOLD_SETTINGS',
          'details':
              'Hold policy set: pickup ${pickup.toInt()}d, queue cap ${cap.toInt()}',
          'user': _clientIp(request),
        },
      );
      return _json(200, {'ok': true});
    });

    router.post('/reservations', (Request request) async {
      final denied = _forbiddenUnless(request, UserRole.staff);
      if (denied != null) return denied;
      final map = await readJsonObject(request);
      final itemCode = requireNonEmpty(map, 'item_code');
      final memberId = requireNonEmpty(map, 'member_id');
      final res = await _db.placeReservation(
        itemCode,
        memberId,
        audit: {
          'timestamp': DateTime.now().toIso8601String(),
          'operation': 'HOLD_PLACE',
          'details': 'Hold placed: $memberId for $itemCode',
          'user': _clientIp(request),
        },
      );
      return _json(201, res.toMap());
    });

    router.get('/reservations', (Request request) async {
      final denied = _forbiddenUnless(request, UserRole.staff);
      if (denied != null) return denied;
      final q = request.url.queryParameters;
      ReservationStatus? status;
      final statusRaw = q['status'];
      if (statusRaw != null && statusRaw.isNotEmpty) {
        status = ReservationStatus.tryParse(statusRaw);
        if (status == null) {
          throw MalformedRequestException(
            'status must be one of: queued, available, fulfilled, cancelled, expired',
          );
        }
      }
      final liveOnly = q['live'] == '1';
      final holds = await _db.getReservations(
        itemCode: q['item_code'],
        memberId: q['member_id'],
        status: status,
        liveOnly: liveOnly,
      );
      return Response.ok(
        jsonEncode(holds.map((r) => r.toMap()).toList()),
        headers: {'content-type': 'application/json'},
      );
    });

    router.get('/reservations/ready', (Request request) async {
      final denied = _forbiddenUnless(request, UserRole.staff);
      if (denied != null) return denied;
      final holds = await _db.readyForPickup();
      return Response.ok(
        jsonEncode(holds.map((r) => r.toMap()).toList()),
        headers: {'content-type': 'application/json'},
      );
    });

    router.post('/reservations/<id>/cancel', (
      Request request,
      String id,
    ) async {
      final denied = _forbiddenUnless(request, UserRole.staff);
      if (denied != null) return denied;
      final holdId = int.tryParse(id);
      if (holdId == null) {
        throw MalformedRequestException('reservation id must be an integer');
      }
      await _db.cancelReservation(
        holdId,
        audit: {
          'timestamp': DateTime.now().toIso8601String(),
          'operation': 'HOLD_CANCEL',
          'details': 'Hold #$holdId cancelled',
          'user': _clientIp(request),
        },
      );
      return _json(200, {'ok': true});
    });

    // Pass 6: reorder a queued hold within its item's line. Body is
    // `{"direction": "up" | "down"}`. A malformed direction or a
    // non-integer id returns 400 BEFORE any write; a hold that does not
    // exist or is not in `queued` surfaces as a StateError from the
    // repository and is mapped by the shared error middleware. Server owns
    // the audit row (real client IP + clock), matching the sibling cancel
    // route above.
    router.post('/reservations/<id>/move', (Request request, String id) async {
      final denied = _forbiddenUnless(request, UserRole.staff);
      if (denied != null) return denied;
      final holdId = int.tryParse(id);
      if (holdId == null) {
        throw MalformedRequestException('reservation id must be an integer');
      }
      final map = await readJsonObject(request);
      final dir = map['direction']?.toString();
      if (dir != 'up' && dir != 'down') {
        throw MalformedRequestException("direction must be 'up' or 'down'");
      }
      final up = dir == 'up';
      await _db.moveReservation(
        holdId,
        up: up,
        audit: {
          'timestamp': DateTime.now().toIso8601String(),
          'operation': up ? 'HOLD_MOVE_UP' : 'HOLD_MOVE_DOWN',
          'details': 'Hold #$holdId moved $dir',
          'user': _clientIp(request),
        },
      );
      return _json(200, {'ok': true});
    });

    // ------------------------------------------------------------------
    // Reports (Phase 10.4). READ-ONLY, SERVER-AUTHORITATIVE aggregates.
    // Staff-gated (a report surfaces patron + financial data); the HOST
    // computes every figure so a remote operator sees identical numbers.
    // An unknown kind, or a malformed / reversed / oversized date window,
    // is rejected with a 400 BEFORE any query runs (never a 500, and never
    // a partially-considered default).
    // ------------------------------------------------------------------
    router.get('/reports/<kind>', (Request request, String kind) async {
      final denied = _forbiddenUnless(request, UserRole.staff);
      if (denied != null) return denied;
      final rk = ReportKind.tryParse(kind);
      if (rk == null) {
        throw MalformedRequestException(
          'Unknown report kind. Use one of: '
          '${ReportKind.values.map((k) => k.storage).join(', ')}',
        );
      }
      final q = request.url.queryParameters;
      final from = q['from'];
      final to = q['to'];
      try {
        // Validate + apply defaults here so a bad request is a clean 400;
        // the engine re-derives the SAME window from the same inputs.
        ReportQuery.window(rk, from: from, to: to);
      } on FormatException catch (e) {
        throw MalformedRequestException(e.message);
      }
      final report = await _db.generateReport(rk, from: from, to: to);
      return Response.ok(
        jsonEncode(report.toMap()),
        headers: {'content-type': 'application/json'},
      );
    });

    var pipeline = Pipeline()
        // Error handling is outermost so it also catches anything thrown by the
        // logging, activity, auth and idempotency layers below it (BE-02).
        .addMiddleware(_errorMiddleware())
        // Reject a client that advertises an incompatible API protocol before it
        // can consume work or mis-read a response (DEP-02). Requests that omit
        // the header (legacy peers) are allowed through unchanged.
        .addMiddleware(_versionNegotiation())
        // Refuse new work + count in-flight handlers during a restore/wipe so
        // the shared database can be swapped safely (DB-04).
        .addMiddleware(_maintenanceGate())
        // Size + timeout guards wrap the real handlers (and are themselves
        // wrapped by the error middleware) so abusive requests are rejected
        // with 413/504 before they can consume unbounded memory or hang a
        // connection (NET-04).
        .addMiddleware(_requestGuards())
        .addMiddleware(kReleaseMode ? (Handler inner) => inner : logRequests())
        .addMiddleware((innerHandler) {
          return (request) async {
            final ip = _clientIp(request);
            if (ip != 'unknown' && onActivity != null) {
              onActivity(ip);
            }
            return await innerHandler(request);
          };
        });

    // Guard every route once a credential exists (bootstrap-open otherwise).
    // Installed innermost so it runs immediately before the router; the login
    // route stays reachable.
    if (_auth != null) {
      pipeline = pipeline.addMiddleware(
        requireAuthIfConfigured(_auth, openPaths: {'/auth/login'}),
      );
    }

    // Idempotent replay of retried POSTs (REL-03/TX-05). Added innermost so it
    // runs *after* auth — an unauthorized request never consults or pollutes
    // the cache — and immediately before the router. Opt-in: only POSTs that
    // carry an `Idempotency-Key` header are affected.
    pipeline = pipeline.addMiddleware(idempotencyMiddleware(_idempotency));

    // Write-rate limiting is added innermost (closest to the router) so it runs
    // after auth -- unauthorized floods never reach it -- and after idempotent
    // replay -- a cache-hit retried POST does not consume a write token
    // (NET-13 / PROTO-04).
    pipeline = pipeline.addMiddleware(_writeRateLimit());

    _handler = pipeline.addHandler(router.call);

    // Listen on all interfaces (0.0.0.0) to allow LAN access.
    _server = await shelf_io.serve(_handler, host, port);
    appLog.info('http', 'LAN server listening on port ${_server!.port}');
  }

  Response _json(int status, Map<String, dynamic> body) => Response(
    status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json'},
  );

  /// Phase 10.1 role gate for route handlers. Returns a structured 403 when
  /// the authenticated bearer lacks [minimum]; null means "proceed".
  /// Bootstrap-open requests and legacy pre-10.1 tokens pass (see
  /// [authorizedFor]) so enabling roles never locks out an existing install.
  Response? _forbiddenUnless(Request request, UserRole minimum) {
    if (authorizedFor(request, minimum)) return null;
    final p = principalOf(request);
    final who = p?.username ?? '?';
    final role = p?.role.storage ?? '?';
    return _json(403, {
      'error': 'forbidden',
      'message':
          'The account "$who" (role $role) may not perform this action (requires ${minimum.storage}).',
    });
  }

  /// STRICT role parsing for the user-admin routes (Phase 10.1). A missing,
  /// misspelled or forged `role` value is a client error answered with 400 --
  /// NEVER a silently-guessed privilege. ([UserRole.parse]'s viewer fallback is
  /// for reading already-persisted rows only.)
  UserRole _requireRole(Object? raw) {
    final role = UserRole.tryParse(raw);
    if (role == null) {
      throw MalformedRequestException(
        'role must be one of: admin, staff, viewer.',
      );
    }
    return role;
  }

  String _clientIp(Request request) {
    final connectionInfo =
        request.context['shelf.io.connection_info'] as dynamic;
    if (connectionInfo != null) {
      try {
        return connectionInfo.remoteAddress.address as String;
      } catch (_) {}
    }
    return 'unknown';
  }
}

/// Thrown by the request size guard when a body exceeds [maxRequestBodyBytes]
/// mid-stream (chunked transfer or a Content-Length the client under-reported).
/// The outermost error middleware maps it to a 413 JSON response (NET-04).
class _BodyTooLargeException implements Exception {
  const _BodyTooLargeException();
}

/// Thrown when a request body decodes to JSON but is not usable for the route:
/// not an object, a missing required field, or a field of the wrong type. The
/// error middleware maps it to a clean 400 (PROTO-01) instead of letting a
/// model's cast/parse failure surface as a 500.
class MalformedRequestException implements Exception {
  MalformedRequestException(this.message);
  final String message;
  @override
  String toString() => 'MalformedRequestException: $message';
}

/// Reads + decodes the body guaranteeing a JSON OBJECT. Invalid JSON throws a
/// [FormatException] (already mapped to 400); a non-object (array / scalar)
/// throws [MalformedRequestException] (400).
Future<Map<String, dynamic>> readJsonObject(Request request) async {
  final decoded = jsonDecode(await request.readAsString());
  if (decoded is! Map<String, dynamic>) {
    throw MalformedRequestException('Request body must be a JSON object');
  }
  return decoded;
}

/// Returns the trimmed non-empty String at [field] or throws
/// [MalformedRequestException] (400), so a blank identity field is rejected
/// BEFORE it can be committed as a meaningless row.
String requireNonEmpty(Map<String, dynamic> map, String field) {
  final v = map[field];
  if (v is! String || v.trim().isEmpty) {
    throw MalformedRequestException(
      'Field "$field" must be a non-empty string',
    );
  }
  return v.trim();
}

/// A member is meaningless with neither name; require at least one non-empty.
void requireMemberName(Map<String, dynamic> map) {
  final first = map['first_name'];
  final last = map['last_name'];
  final hasFirst = first is String && first.trim().isNotEmpty;
  final hasLast = last is String && last.trim().isNotEmpty;
  if (!hasFirst && !hasLast) {
    throw MalformedRequestException('A member needs a first or last name');
  }
}

/// Builds a model from [map], converting any cast / parse error a `fromMap`
/// throws on a missing or wrongly-typed field into a 400 rather than a 500.
T parseModel<T>(
  Map<String, dynamic> map,
  T Function(Map<String, dynamic>) build,
  String label,
) {
  try {
    return build(map);
  } on MalformedRequestException {
    rethrow;
  } catch (_) {
    throw MalformedRequestException(
      '$label has a missing or wrongly-typed field',
    );
  }
}

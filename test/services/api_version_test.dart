import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:library_manager/services/api_contract.dart';
import 'package:library_manager/services/api_service.dart';
import 'package:library_manager/services/http_server_service.dart';
import 'package:library_manager/services/repository.dart';

/// Binding-free: the server half opens a real loopback socket, and the client
/// half uses an injected [http.BaseClient] (never a real `HttpClient`), so no
/// `TestWidgetsFlutterBinding` (whose interceptor would mask genuine sockets and
/// header propagation) is used anywhere in this file.

String? headerCaseInsensitive(Map<String, String>? h, String name) {
  if (h == null) return null;
  for (final e in h.entries) {
    if (e.key.toLowerCase() == name.toLowerCase()) return e.value;
  }
  return null;
}

class _CaptureClient extends http.BaseClient {
  _CaptureClient(this.status, this.body);
  final int status;
  final String body;
  Map<String, String>? lastHeaders;
  String? lastPath;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastHeaders = request.headers;
    lastPath = request.url.path;
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(<List<int>>[utf8.encode(body)]),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

/// Server repo: only `/db-version` is exercised, so a canned version is enough.
class _VersionRepo implements LibraryRepository {
  @override
  Future<String> getDbVersion() async => '123';
  @override
  dynamic noSuchMethod(Invocation inv) => null;
}

void main() {
  group('api_contract (pure, DEP-02)', () {
    test('only an exact version match is compatible; null is not', () {
      expect(isApiVersionCompatible(kApiProtocolVersion), isTrue);
      expect(isApiVersionCompatible(kApiProtocolVersion + 1), isFalse);
      expect(isApiVersionCompatible(null), isFalse,
          reason: 'a server that never advertised a version is untrusted');
    });
  });

  group('client advertises + learns the protocol (DEP-02)', () {
    ApiService apiWith(http.Client c) =>
        ApiService(hostIp: '127.0.0.1', port: 9, client: c);

    test('getDbVersion sends the X-Api-Version header and stores the reply',
        () async {
      final client = _CaptureClient(200, jsonEncode({'version': '42', 'api': 1}));
      final api = apiWith(client);

      final v = await api.getDbVersion();

      expect(v, '42');
      expect(headerCaseInsensitive(client.lastHeaders, apiVersionHeader),
          '$kApiProtocolVersion');
      expect(client.lastPath, '/db-version');
      expect(api.serverApiVersion, kApiProtocolVersion);
      expect(api.isServerProtocolCompatible, isTrue);
    });

    test('a pre-versioning server (no api field) is flagged incompatible',
        () async {
      final api = apiWith(_CaptureClient(200, jsonEncode({'version': '7'})));
      final v = await api.getDbVersion();
      expect(v, '7');
      expect(api.serverApiVersion, isNull);
      expect(api.isServerProtocolCompatible, isFalse);
    });

    test('a mismatched advertised version is incompatible', () async {
      final api = apiWith(_CaptureClient(
          200, jsonEncode({'version': '1', 'api': kApiProtocolVersion + 5})));
      await api.getDbVersion();
      expect(api.isServerProtocolCompatible, isFalse);
    });

    test('checkConnectivity also captures the advertised version on success',
        () async {
      final api = apiWith(_CaptureClient(
          200, jsonEncode({'version': '1', 'api': kApiProtocolVersion})));
      final r = await api.checkConnectivity();
      expect(r.status, ConnectStatus.online);
      expect(api.serverApiVersion, kApiProtocolVersion);
    });
  });

  group('server enforces + advertises the protocol (DEP-02)', () {
    late HttpServerService server;
    late http.Client client;
    late String base;

    setUp(() async {
      server = HttpServerService(repository: _VersionRepo());
      await server.startServer(host: '127.0.0.1', port: 0);
      base = 'http://127.0.0.1:${server.port}';
      client = http.Client();
    });

    tearDown(() async {
      client.close();
      await server.stopServer();
    });

    test('/db-version advertises the api version', () async {
      final res = await client.get(Uri.parse('$base/db-version'));
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['version'], '123');
      expect(body[apiVersionBodyKey], kApiProtocolVersion);
    });

    test('a matching header is served normally', () async {
      final res = await client.get(Uri.parse('$base/db-version'),
          headers: {apiVersionHeader: '$kApiProtocolVersion'});
      expect(res.statusCode, 200);
    });

    test('an incompatible header is refused with 426 Upgrade Required',
        () async {
      final res = await client.get(Uri.parse('$base/db-version'),
          headers: {apiVersionHeader: '${kApiProtocolVersion + 9}'});
      expect(res.statusCode, 426);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['error'], 'upgrade_required');
    });

    test('a request with NO header (legacy peer) is allowed through',
        () async {
      final res = await client.get(Uri.parse('$base/db-version'));
      expect(res.statusCode, 200);
    });
  });
}

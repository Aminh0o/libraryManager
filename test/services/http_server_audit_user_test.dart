import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:library_manager/services/http_server_service.dart';
import 'package:library_manager/services/repository.dart';

/// Captures the audit map a mutation route hands to the repository, so we can
/// assert the server-authored `user` field is the real client IP rather than a
/// `Instance of '_HttpConnectionInfo'` string (BE-03). Binding-free socket test
/// (no `TestWidgetsFlutterBinding`, whose HttpClient interceptor would prevent a
/// genuine loopback connection from carrying a real remote address).
class _CapturingRepo implements LibraryRepository {
  Map<String, dynamic>? lastAudit;

  @override
  Future<void> deleteItem(String code, {Map<String, dynamic>? audit}) async {
    lastAudit = audit;
  }

  @override
  dynamic noSuchMethod(Invocation inv) => null;
}

void main() {
  late HttpServerService server;
  late _CapturingRepo repo;
  late http.Client client;
  late String base;

  setUp(() async {
    repo = _CapturingRepo();
    server = HttpServerService(repository: repo);
    await server.startServer(host: '127.0.0.1', port: 0);
    base = 'http://127.0.0.1:${server.port}';
    client = http.Client();
  });

  tearDown(() async {
    client.close();
    await server.stopServer();
  });

  group('server-authored audit user (BE-03 / Phase 8.3)', () {
    test('a mutation logs the real client IP, not a connection-info object',
        () async {
      final res = await client.delete(Uri.parse('$base/items/ABC123'));
      expect(res.statusCode, 200);
      expect(repo.lastAudit, isNotNull,
          reason: 'route should hand an audit map to the repository');

      final user = repo.lastAudit!['user'] as String;
      expect(user, '127.0.0.1',
          reason: 'loopback client must be recorded by IP');
      expect(user, isNot(contains('Instance of')));
      expect(user, isNot('Client'));
      expect(user, isNot('unknown'));
    });
  });
}

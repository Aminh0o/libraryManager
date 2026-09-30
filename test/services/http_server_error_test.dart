import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/services/database_service.dart'
    show ActiveLoanConflictException;
import 'package:library_manager/services/http_server_service.dart';
import 'package:library_manager/services/repository.dart';

/// A repository whose reads/mutations throw, to prove the server's error
/// middleware turns uncaught exceptions into structured JSON responses instead
/// of a bare 500 / dropped connection (BE-02). Binding-free socket tests (no
/// `TestWidgetsFlutterBinding`, whose interceptor would force a 400).
class _ThrowingRepo implements LibraryRepository {
  // Typed overrides (not noSuchMethod) so the thrown error, not a return-type
  // cast failure, is what propagates out of the route.
  @override
  Future<List<LibraryItem>> getItems({
    int limit = 1000,
    int offset = 0,
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) => Future.error(Exception('db exploded'));

  @override
  Future<void> deleteMember(String memberId, {Map<String, dynamic>? audit}) =>
      Future.error(ActiveLoanConflictException('Membre a des prêts actifs'));

  @override
  dynamic noSuchMethod(Invocation inv) => null;
}

void main() {
  late HttpServerService server;
  late http.Client client;
  late String base;

  setUp(() async {
    server = HttpServerService(repository: _ThrowingRepo());
    await server.startServer(host: '127.0.0.1', port: 0);
    base = 'http://127.0.0.1:${server.port}';
    client = http.Client();
  });

  tearDown(() async {
    client.close();
    await server.stopServer();
  });

  group('server error middleware (BE-02 / Phase 8.2)', () {
    test('an uncaught route exception becomes a structured 500, not a dropped '
        'connection', () async {
      final res = await client.get(Uri.parse('$base/items'));
      expect(res.statusCode, 500);
      expect(res.headers['content-type'], contains('application/json'));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['error'], 'internal_error');
      expect((body['message'] as String), contains('db exploded'));
    });

    test('a malformed JSON body becomes a structured 400', () async {
      final res = await client.post(
        Uri.parse('$base/items'),
        headers: {'content-type': 'application/json'},
        body: '{ this is not valid json',
      );
      expect(res.statusCode, 400);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['error'], 'bad_request');
    });

    test('a domain conflict is reported as 409 carrying its message', () async {
      final res = await client.delete(Uri.parse('$base/members/M1'));
      expect(res.statusCode, 409);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['error'], 'conflict');
      expect(body['message'], 'Membre a des prêts actifs');
    });
  });
}

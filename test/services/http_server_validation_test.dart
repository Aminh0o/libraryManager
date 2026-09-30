import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/services/database_service.dart';
import 'package:library_manager/services/http_server_service.dart';
import 'package:library_manager/services/repository.dart';

/// PROTO-01: a request body that decodes to JSON but is unusable (not an
/// object, a missing required identity field, or a wrongly-typed value) must be
/// rejected with a clean 400 BEFORE any write happens — never surface as a 500
/// from a model's cast, and never silently commit a blank/garbage row.
///
/// This file deliberately avoids `TestWidgetsFlutterBinding`, whose interceptor
/// would force every `HttpClient` call to a 400 (see the repo's other socket
/// tests); the fake repository records whether a mutation ever reached it.
class _CountingRepo implements LibraryRepository {
  int addItems = 0;
  int updateItems = 0;
  int addMembers = 0;
  int updateMembers = 0;
  int addDefs = 0;
  LibraryItem? lastItem;
  int? lastUpdateExpectedVersion;
  Map<String, dynamic>? lastHistory;
  Map<String, dynamic>? lastDefAudit;

  @override
  dynamic noSuchMethod(Invocation inv) {
    switch (inv.memberName) {
      case #addItem:
        final it = inv.positionalArguments.first as LibraryItem;
        // Simulate the repository's duplicate-code conflict so the error
        // middleware's 409 mapping is exercised over a real socket (BE-07).
        if (it.code == 'DUP') {
          throw ItemCodeConflictException('Item code DUP already exists.');
        }
        // Simulate the duplicate-barcode conflict (DB-01) end-to-end over a
        // real socket so its 409 mapping is proven, not just the DB path.
        if (it.barcode == 'DUPBC') {
          throw BarcodeConflictException(
              'Barcode DUPBC is already used by item 0001.');
        }
        addItems++;
        lastItem = it;
        return Future.value();
      case #addMember:
        addMembers++;
        return Future.value();
      case #updateMember:
        updateMembers++;
        return Future.value();
      case #addCodeDefinition:
        addDefs++;
        lastDefAudit = inv.namedArguments[#audit] as Map<String, dynamic>?;
        return Future.value();
      case #addAttributeDefinition:
        // Simulate the duplicate (type,value) attribute conflict (DB-01) so
        // its 409 mapping is exercised over a real socket.
        if (inv.positionalArguments[1] == 'DUPATTR') {
          throw AttributeConflictException(
              'Attribute (STATUS, DUPATTR) already exists.');
        }
        return Future.value();
      case #addHistoryEntry:
        lastHistory = inv.positionalArguments.first as Map<String, dynamic>;
        return Future.value();
      case #updateItem:
        // Records the version the server parsed from X-Expected-Version so the
        // test can prove the header is forwarded into the repository (TX-06),
        // and simulates the stale-write refusal so the 409 mapping is exercised
        // over a real socket.
        final it = inv.positionalArguments.first as LibraryItem;
        updateItems++;
        lastItem = it;
        lastUpdateExpectedVersion =
            inv.namedArguments[#expectedVersion] as int?;
        if (it.code == 'STALE') {
          throw ConcurrentUpdateConflictException(
              'Item STALE was modified by another client (now version 2, '
              'expected 0).');
        }
        return Future.value();
    }
    return super.noSuchMethod(inv);
  }
}

void main() {
  late HttpServerService server;
  late _CountingRepo repo;
  late http.Client client;
  late String base;

  setUp(() async {
    repo = _CountingRepo();
    server = HttpServerService(repository: repo);
    await server.startServer(host: '127.0.0.1', port: 0);
    base = 'http://127.0.0.1:${server.port}';
    client = http.Client();
  });

  tearDown(() async {
    client.close();
    await server.stopServer();
  });

  Future<http.Response> postJson(String path, Object body) => client.post(
        Uri.parse('$base$path'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode(body),
      );

  Future<http.Response> putJson(String path, Object body) => client.put(
        Uri.parse('$base$path'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode(body),
      );

  Future<http.Response> putJsonWithVersion(
          String path, Object body, String version) =>
      client.put(
        Uri.parse('$base$path'),
        headers: {
          'content-type': 'application/json',
          'X-Expected-Version': version,
        },
        body: jsonEncode(body),
      );

  Map<String, dynamic> decode(http.Response r) =>
      jsonDecode(r.body) as Map<String, dynamic>;

  group('request validation (PROTO-01 / Phase 9.6)', () {
    test('POST /items with a non-object body is a 400, not a 500', () async {
      final res = await postJson('/items', [1, 2, 3]);
      expect(res.statusCode, 400);
      expect(decode(res)['error'], 'bad_request');
      expect(repo.addItems, 0);
    });

    test('POST /items missing required fields is a 400 and never writes',
        () async {
      final res = await postJson('/items', {});
      expect(res.statusCode, 400);
      expect(decode(res)['error'], 'bad_request');
      expect(repo.addItems, 0);
    });

    test('POST /items with a valid body still succeeds and writes once',
        () async {
      final res = await postJson('/items', {'code': '0700', 'designation': 'A book'});
      expect(res.statusCode, 200);
      expect(repo.addItems, 1);
      expect(repo.lastItem?.code, '0700');
    });

    test('POST /items with a wrongly-typed numeric is a 400, not a 500',
        () async {
      final res = await postJson('/items',
          {'code': '1', 'designation': 'x', 'quantite': 'not-a-number'});
      expect(res.statusCode, 400);
      expect(decode(res)['error'], 'bad_request');
      expect(repo.addItems, 0);
    });

    test('POST /members with blank names is a 400 and never writes', () async {
      final res =
          await postJson('/members', {'first_name': '', 'last_name': '   '});
      expect(res.statusCode, 400);
      expect(decode(res)['error'], 'bad_request');
      expect(repo.addMembers, 0);
    });

    test('POST /members with an unparseable date is a 400, not a 500',
        () async {
      final res = await postJson(
          '/members', {'first_name': 'A', 'registered_at': 'not-a-date'});
      expect(res.statusCode, 400);
      expect(decode(res)['error'], 'bad_request');
      expect(repo.addMembers, 0);
    });

    test('PUT /members without an id is a 400 and never writes', () async {
      final res = await putJson('/members', {'first_name': 'A'});
      expect(res.statusCode, 400);
      expect(decode(res)['error'], 'bad_request');
      expect(repo.updateMembers, 0);
    });

    test('POST /code-definitions with a blank prefix is a 400, not a write',
        () async {
      final res =
          await postJson('/code-definitions', {'prefix': '', 'label': 'Books'});
      expect(res.statusCode, 400);
      expect(decode(res)['error'], 'bad_request');
      expect(repo.addDefs, 0);
    });

    test('POST /history is recorded with the caller identity, not forged '
        'fields (DB-05)', () async {
      final res = await postJson('/history', {
        'id': 999999, // must be dropped (server assigns)
        'timestamp': '1999-01-01T00:00:00.000', // backdated -> server overrides
        'user': 'attacker', // spoofed -> server overrides with caller IP
        'evil': 'no-such-column', // unknown -> dropped
        'operation': 'FORGE',
        'details': 'attempt',
      });
      expect(res.statusCode, 200);
      final h = repo.lastHistory;
      expect(h, isNotNull);
      expect(h!['operation'], 'FORGE');
      expect(h['details'], 'attempt');
      expect(h.containsKey('id'), isFalse);
      expect(h.containsKey('evil'), isFalse);
      expect(h['user'], isNot('attacker'));
      expect((h['user'] as String), startsWith('127.'));
      expect(h['timestamp'], isNot('1999-01-01T00:00:00.000'));
    });

    test('POST /history with a blank operation is a 400 and never writes',
        () async {
      final res = await postJson('/history', {'operation': '', 'details': 'd'});
      expect(res.statusCode, 400);
      expect(decode(res)['error'], 'bad_request');
      expect(repo.lastHistory, isNull);
    });

    test('POST /items with a negative quantity is a 400, not a write (BE-08)',
        () async {
      final res = await postJson(
          '/items', {'code': '1', 'designation': 'x', 'quantite': -5});
      expect(res.statusCode, 400);
      expect(decode(res)['error'], 'bad_request');
      expect(repo.addItems, 0);
    });

    test('a duplicate item code becomes a 409 conflict, not a 500 (BE-07)',
        () async {
      final res =
          await postJson('/items', {'code': 'DUP', 'designation': 'x'});
      expect(res.statusCode, 409);
      expect(decode(res)['error'], 'conflict');
      expect(repo.addItems, 0);
    });

    test('a duplicate barcode becomes a 409 conflict, not a 500 (DB-01)',
        () async {
      final res = await postJson(
          '/items', {'code': '1', 'designation': 'x', 'barcode': 'DUPBC'});
      expect(res.statusCode, 409);
      expect(decode(res)['error'], 'conflict');
      expect(repo.addItems, 0);
    });

    test('a duplicate attribute definition becomes a 409, not a 500 (DB-01)',
        () async {
      final res = await postJson(
          '/attribute-definitions', {'type': 'STATUS', 'value': 'DUPATTR'});
      expect(res.statusCode, 409);
      expect(decode(res)['error'], 'conflict');
    });

    test('PUT /items forwards X-Expected-Version to the repository (TX-06)',
        () async {
      final res = await putJsonWithVersion(
          '/items', {'code': '0700', 'designation': 'x'}, '7');
      expect(res.statusCode, 200);
      expect(repo.updateItems, 1);
      expect(repo.lastUpdateExpectedVersion, 7,
          reason: 'server must parse the header and pass expectedVersion');
    });

    test('PUT /items without a version is an unconditional write, so the '
        'repository receives a null expectedVersion (backward-compat TX-06)',
        () async {
      final res =
          await putJson('/items', {'code': '0700', 'designation': 'x'});
      expect(res.statusCode, 200);
      expect(repo.updateItems, 1);
      expect(repo.lastUpdateExpectedVersion, isNull);
    });

    test('a stale optimistic update becomes a 409 conflict, not a 500 '
        '(TX-06)', () async {
      final res = await putJsonWithVersion(
          '/items', {'code': 'STALE', 'designation': 'x'}, '0');
      expect(res.statusCode, 409);
      expect(decode(res)['error'], 'conflict');
    });

    test('POST /code-definitions records a server-built audit with the caller '
        'IP, not a client-forged one (BE-05 / BE-09)', () async {
      final res = await postJson(
          '/code-definitions', {'prefix': 'BK', 'label': 'Books'});
      expect(res.statusCode, 200);
      expect(repo.addDefs, 1);
      final a = repo.lastDefAudit;
      expect(a, isNotNull, reason: 'route must pass an audit row to the repo');
      expect(a!['operation'], 'ADD_VAR');
      expect(a['timestamp'], isNotNull);
      // The identity is the caller's IP as seen by the server, never anything
      // a client could claim in the body.
      expect((a['user'] as String), startsWith('127.'));
    });
  });
}

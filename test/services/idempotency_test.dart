import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:library_manager/services/http_server_service.dart';
import 'package:library_manager/services/idempotency_store.dart';
import 'package:library_manager/services/repository.dart';

/// A [LibraryRepository] that counts how many times a mutation ran, so a test
/// can assert that an idempotent replay does **not** re-execute the handler.
/// `noSuchMethod` stands in for the ~25 unused interface members.
class _CountingRepo implements LibraryRepository {
  int addCalls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == const Symbol('addItem')) {
      addCalls++;
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  group('IdempotencyStore', () {
    test('round-trips a saved result', () {
      final s = IdempotencyStore();
      expect(s.lookup('k'), isNull);
      s.save('k', 200, 'ok');
      final r = s.lookup('k');
      expect(r, isNotNull);
      expect(r!.status, 200);
      expect(r.body, 'ok');
    });

    test('expires an entry once older than the ttl', () {
      var now = DateTime(2026, 1, 1, 12);
      final s = IdempotencyStore(
        ttl: const Duration(minutes: 5),
        clock: () => now,
      );
      s.save('k', 200, 'ok');
      now = now.add(const Duration(minutes: 6));
      expect(s.lookup('k'), isNull);
      expect(s.length, 0); // stale entry dropped on read
    });

    test('evicts the oldest entries beyond maxEntries', () {
      var t = DateTime(2026, 1, 1);
      final s = IdempotencyStore(
        ttl: const Duration(days: 1),
        maxEntries: 2,
        clock: () => t,
      );
      s.save('a', 200, 'A');
      t = t.add(const Duration(seconds: 1));
      s.save('b', 200, 'B');
      t = t.add(const Duration(seconds: 1));
      s.save('c', 200, 'C'); // pushes out oldest 'a'
      expect(s.length, 2);
      expect(s.lookup('a'), isNull);
      expect(s.lookup('b'), isNotNull);
      expect(s.lookup('c'), isNotNull);
    });
  });

  group('idempotencyMiddleware (unit)', () {
    Handler wrap(IdempotencyStore s, Handler inner) =>
        idempotencyMiddleware(s)(inner);

    Future<Response> post(Handler h, {String? key}) async =>
        await h(Request(
          'POST',
          Uri.parse('http://x/items'),
          headers: key == null ? {} : {'Idempotency-Key': key},
        ));

    test('caches and replays a POST carrying a key, without re-running inner',
        () async {
      final s = IdempotencyStore();
      var calls = 0;
      final h = wrap(s, (req) async {
        calls++;
        return Response.ok('{"n":$calls}');
      });

      final r1 = await post(h, key: 'k1');
      expect(r1.statusCode, 200);
      expect(await r1.readAsString(), '{"n":1}');
      expect(calls, 1);

      final r2 = await post(h, key: 'k1');
      expect(calls, 1); // handler NOT re-invoked
      expect(r2.headers['idempotency-replayed'], 'true');
      expect(await r2.readAsString(), '{"n":1}'); // original body replayed
    });

    test('distinct keys execute independently', () async {
      final s = IdempotencyStore();
      var calls = 0;
      final h = wrap(s, (req) async => Response.ok('c${++calls}'));
      await post(h, key: 'a');
      await post(h, key: 'b');
      expect(calls, 2);
    });

    test('a keyless POST always passes through (backward compatible)',
        () async {
      final s = IdempotencyStore();
      var calls = 0;
      final h = wrap(s, (req) async => Response.ok('c${++calls}'));
      await post(h);
      await post(h);
      expect(calls, 2);
      expect(s.length, 0);
    });

    test('non-POST requests are never cached', () async {
      final s = IdempotencyStore();
      var calls = 0;
      final h = wrap(s, (req) async => Response.ok('c${++calls}'));
      Future<void> del() async {
        await h(Request('DELETE', Uri.parse('http://x/items/1'),
            headers: {'Idempotency-Key': 'd1'}));
      }

      await del();
      await del();
      expect(calls, 2);
    });

    test('a 5xx outcome is NOT cached, so it stays retryable', () async {
      final s = IdempotencyStore();
      var calls = 0;
      final h = wrap(s, (req) async {
        calls++;
        return Response(503, body: 'down');
      });
      await post(h, key: 'k');
      await post(h, key: 'k');
      expect(calls, 2); // re-executed, not replayed
      expect(s.length, 0);
    });

    test('a deterministic 4xx (e.g. conflict) IS cached and replayed',
        () async {
      final s = IdempotencyStore();
      var calls = 0;
      final h = wrap(s, (req) async {
        calls++;
        return Response(409,
            body: '{"error":"conflict"}',
            headers: {'content-type': 'application/json'});
      });
      await post(h, key: 'k');
      final r2 = await post(h, key: 'k');
      expect(calls, 1);
      expect(r2.statusCode, 409);
      expect(jsonDecode(await r2.readAsString())['error'], 'conflict');
    });
  });

  group('idempotency over the real server pipeline', () {
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

    Future<http.Response> postItem({String? key}) => client.post(
          Uri.parse('$base/items'),
          headers: {
            'Content-Type': 'application/json',
            'Idempotency-Key': ?key,
          },
          body: jsonEncode({'code': '0700', 'designation': 'A book'}),
        );

    test('a retried POST with the same key mutates the repo only once',
        () async {
      final r1 = await postItem(key: 'op-1');
      expect(r1.statusCode, 200);
      expect(repo.addCalls, 1);

      final r2 = await postItem(key: 'op-1');
      expect(r2.statusCode, 200);
      expect(r2.headers['idempotency-replayed'], 'true');
      expect(repo.addCalls, 1); // no duplicate write
    });

    test('separate logical POSTs (different keys) both execute', () async {
      await postItem(key: 'op-a');
      await postItem(key: 'op-b');
      expect(repo.addCalls, 2);
    });

    test('legacy clients sending no key keep working (one call each)',
        () async {
      await postItem();
      await postItem();
      expect(repo.addCalls, 2);
    });
  });
}

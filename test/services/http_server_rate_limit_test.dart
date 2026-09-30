import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:library_manager/services/http_server_service.dart';
import 'package:library_manager/services/rate_limit.dart';
import 'package:library_manager/services/repository.dart';

/// PROTO-04 / NET-13 end-to-end over a real loopback socket: a source that
/// spends its write burst gets 429 (not a hang or a 500), READS (the `/db-version`
/// sync poll) are never throttled, and the bucket recovers as time passes. A
/// clock is injected so the refill assertions need no real sleeping.
///
/// Deliberately binding-free (no TestWidgetsFlutterBinding) so HttpClient talks
/// to the real shelf server (see the repo's other socket tests).
class _MiniRepo implements LibraryRepository {
  int addItems = 0;

  @override
  dynamic noSuchMethod(Invocation inv) {
    switch (inv.memberName) {
      case #addItem:
        addItems++;
        return Future.value();
      case #getDbVersion:
        return Future.value('1');
    }
    return super.noSuchMethod(inv);
  }
}

void main() {
  late HttpServerService server;
  late _MiniRepo repo;
  late http.Client client;
  late String base;
  late DateTime now;

  setUp(() async {
    now = DateTime(2026, 1, 1, 12);
    repo = _MiniRepo();
    server = HttpServerService(
      repository: repo,
      // 2-token burst, refills at 60/min (1/sec) -- enough that a minute's wait
      // restores a full bucket for the recovery assertion.
      rateLimiter: RateLimiter(
        capacity: 2,
        refillPerMinute: 60,
        clock: () => now,
      ),
    );
    await server.startServer(host: '127.0.0.1', port: 0);
    base = 'http://127.0.0.1:${server.port}';
    client = http.Client();
  });

  tearDown(() async {
    client.close();
    await server.stopServer();
  });

  Future<http.Response> postItem(String code) => client.post(
    Uri.parse('$base/items'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({'code': code, 'designation': 'x'}),
  );

  Map<String, dynamic> decode(http.Response r) =>
      jsonDecode(r.body) as Map<String, dynamic>;

  group('write rate limiting over the wire (PROTO-04)', () {
    test('a source that exceeds its write burst is refused with 429', () async {
      expect((await postItem('A1')).statusCode, 200);
      expect((await postItem('A2')).statusCode, 200);
      // Burst of 2 spent; the third write is throttled before touching the repo.
      final throttled = await postItem('A3');
      expect(throttled.statusCode, 429);
      expect(decode(throttled)['error'], 'rate_limited');
      expect(
        repo.addItems,
        2,
        reason: 'throttled writes must not reach the repo',
      );
    });

    test(
      'READS are exempt so the /db-version sync poll is never throttled',
      () async {
        // Exhaust the write bucket first.
        await postItem('B1');
        await postItem('B2');
        expect((await postItem('B3')).statusCode, 429);
        // A read still succeeds despite no write tokens remaining.
        final get = await client.get(Uri.parse('$base/db-version'));
        expect(get.statusCode, 200);
        expect(decode(get)['version'], '1');
      },
    );

    test('the bucket refills over time so a throttled source recovers', () async {
      await postItem('C1');
      await postItem('C2');
      expect((await postItem('C3')).statusCode, 429);
      // Advance the injected clock by a full minute -> bucket restored to burst.
      now = now.add(const Duration(minutes: 1));
      final after = await postItem('C4');
      expect(after.statusCode, 200);
    });
  });
}

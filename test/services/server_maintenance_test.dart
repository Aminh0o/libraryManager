import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:library_manager/services/http_server_service.dart';
import 'package:library_manager/services/repository.dart';

// A no-auth repository whose /db-version read blocks until [release] completes,
// so a test can hold a request genuinely in-flight and observe the quiesce
// gate counting + draining it (DB-04).
class _BlockingRepo implements LibraryRepository {
  final Completer<void> release = Completer<void>();
  @override
  Future<String> getDbVersion() async {
    await release.future;
    return '1';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// A repository that answers immediately.
class _QuickRepo implements LibraryRepository {
  @override
  Future<String> getDbVersion() async => '1';
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  // Binding-free: real loopback socket.
  Future<(HttpServerService, http.Client, Uri)> start(
    LibraryRepository repo,
  ) async {
    final server = HttpServerService(repository: repo);
    await server.startServer(host: '127.0.0.1', port: 0);
    final client = http.Client();
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    addTearDown(() async {
      client.close();
      await server.stopServer();
    });
    return (server, client, base);
  }

  Future<void> waitInFlight(HttpServerService server, int target) async {
    for (var i = 0; i < 200 && server.inFlightRequests < target; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  group('maintenance quiesce gate (DB-04)', () {
    test(
      'refuses new requests with 503 during maintenance, resumes after',
      () async {
        final (server, client, base) = await start(_QuickRepo());

        server.enterMaintenance();
        final refused = await client.get(base.replace(path: '/db-version'));
        expect(refused.statusCode, 503);
        expect(refused.body, contains('maintenance'));

        server.exitMaintenance();
        final ok = await client.get(base.replace(path: '/db-version'));
        expect(ok.statusCode, 200);
        expect(ok.body, contains('"1"'));
      },
    );

    test('withMaintenance drains an in-flight request, refuses new work, runs '
        'the op under maintenance, then resumes', () async {
      final repo = _BlockingRepo();
      final (server, client, base) = await start(repo);

      // Kick off a request that will block inside the handler.
      final inflight = client.get(base.replace(path: '/db-version'));
      await waitInFlight(server, 1);
      expect(server.inFlightRequests, 1);

      var ranUnderMaintenance = false;
      final maintenanceResult = server.withMaintenance(() async {
        ranUnderMaintenance = server.isMaintenance;
        return 'done';
      });

      // While draining, a fresh request is refused (never reaches the repo).
      final refused = await client.get(base.replace(path: '/db-version'));
      expect(refused.statusCode, 503);

      // Let the in-flight request finish; then the drain completes and op runs.
      repo.release.complete();
      final first = await inflight;
      expect(first.statusCode, 200);

      expect(await maintenanceResult, 'done');
      expect(
        ranUnderMaintenance,
        isTrue,
        reason: 'the op must run while new requests are still refused',
      );
      expect(server.isMaintenance, isFalse, reason: 'must resume');

      final after = await client.get(base.replace(path: '/db-version'));
      expect(after.statusCode, 200);
    });

    test('withMaintenance ALWAYS resumes, even if the op throws', () async {
      final (server, client, base) = await start(_QuickRepo());

      await expectLater(
        server.withMaintenance<int>(() async => throw StateError('boom')),
        throwsA(isA<StateError>()),
      );

      expect(server.isMaintenance, isFalse);
      final ok = await client.get(base.replace(path: '/db-version'));
      expect(ok.statusCode, 200);
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/services/http_server_service.dart';
import 'package:library_manager/services/repository.dart';

/// Minimal repository stand-in: the server/provider paths under test never
/// touch it, and passing one keeps `HttpServerService` from lazily binding to
/// the real `DatabaseService` singleton.
class _NullRepo implements LibraryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A server whose socket bind always fails (simulates port 8080 in use).
class _FailingServer extends HttpServerService {
  _FailingServer() : super(repository: _NullRepo());

  @override
  bool get isRunning => false;

  @override
  Future<void> startServer({
    Function(String ip)? onActivity,
    String host = '0.0.0.0',
    int port = 8080,
  }) async {
    throw const SocketException('address already in use');
  }
}

/// A server that is already listening.
class _RunningStub extends HttpServerService {
  _RunningStub() : super(repository: _NullRepo());

  @override
  bool get isRunning => true;

  @override
  Future<void> startServer({
    Function(String ip)? onActivity,
    String host = '0.0.0.0',
    int port = 8080,
  }) async {}
}

/// A server that only becomes "running" once `startServer` completes.
class _LazyStartStub extends HttpServerService {
  _LazyStartStub() : super(repository: _NullRepo());
  bool _up = false;

  @override
  bool get isRunning => _up;

  @override
  Future<void> startServer({
    Function(String ip)? onActivity,
    String host = '0.0.0.0',
    int port = 8080,
  }) async {
    _up = true;
  }
}

void main() {
  group('Provider reflects real LAN-server state (BE-01 / Phase 8.1)', () {
    test('a bind failure is NOT reported as connected and surfaces an error',
        () async {
      final provider = LibraryProvider.forTesting(repository: _NullRepo());
      provider.serverForTesting = _FailingServer();

      await provider.startHostServerForTesting();

      expect(provider.isConnected, isFalse);
      expect(provider.serverRunning, isFalse);
      expect(provider.serverError(), isNotNull);
      // P22: the failure kind is reported independently of any translation.
      expect(
          provider.serverErrorKind, LanServerErrorKind.startFailed);
    });

    test('an already-running server reports connected with no error', () async {
      final provider = LibraryProvider.forTesting(repository: _NullRepo());
      provider.serverForTesting = _RunningStub();

      await provider.startHostServerForTesting();

      expect(provider.isConnected, isTrue);
      expect(provider.serverRunning, isTrue);
      expect(provider.serverError(), isNull);
      expect(provider.serverErrorKind, isNull);
    });

    test('a successful start flips connected only after it is listening',
        () async {
      final provider = LibraryProvider.forTesting(repository: _NullRepo());
      final stub = _LazyStartStub();
      provider.serverForTesting = stub;
      expect(provider.serverRunning, isFalse);

      await provider.startHostServerForTesting();

      expect(provider.isConnected, isTrue);
      expect(provider.serverRunning, isTrue);
      expect(provider.serverError(), isNull);
    });
  });

  group('HttpServerService propagates a real bind conflict (BE-01)', () {
    test('startServer throws on an occupied port and stays not-running',
        () async {
      // Occupy an ephemeral port, then try to start the server on the same one.
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final takenPort = probe.port;
      final service = HttpServerService(repository: _NullRepo());

      expect(service.isRunning, isFalse);
      await expectLater(
        service.startServer(
            host: InternetAddress.loopbackIPv4.address, port: takenPort),
        throwsA(isA<SocketException>()),
      );
      // A failed bind must leave the service reporting it is NOT running.
      expect(service.isRunning, isFalse);

      await probe.close();
    });

    test('a successful bind makes isRunning true with a real port', () async {
      final service = HttpServerService(repository: _NullRepo());
      await service
          .startServer(host: InternetAddress.loopbackIPv4.address, port: 0);
      expect(service.isRunning, isTrue);
      expect(service.port, greaterThan(0));
      await service.stopServer();
      expect(service.isRunning, isFalse);
    });
  });
}

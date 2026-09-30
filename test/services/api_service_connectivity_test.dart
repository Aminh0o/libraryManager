import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:library_manager/services/api_service.dart';

/// Answers with a canned status/body (recording the request path) so the probe's
/// status classification can be asserted without a server.
class _CannedClient extends http.BaseClient {
  _CannedClient(this.status, this.body);
  final int status;
  final String body;
  String? lastPath;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastPath = request.url.path;
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(<List<int>>[utf8.encode(body)]),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

/// A client whose send throws [error] (models connection refused / DNS fail).
class _ThrowingClient extends http.BaseClient {
  _ThrowingClient(this.error);
  final Object error;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw error;
  }
}

/// A client whose send never answers within the probe budget (models a black
/// hole / stalled host). It completes long after the timeout with a harmless
/// 200, so the abandoned future never raises once the probe has moved on.
class _SlowClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return Future.delayed(const Duration(milliseconds: 400),
        () => http.StreamedResponse(Stream<List<int>>.empty(), 200));
  }
}

ApiService _api(http.Client client) =>
    ApiService(hostIp: '127.0.0.1', port: 9, client: client);

void main() {
  group('checkConnectivity (NET-01 / Phase 8.7)', () {
    test('a healthy host with our payload is online + usable', () async {
      final client = _CannedClient(200, jsonEncode({'version': 14}));
      final r = await _api(client).checkConnectivity();
      expect(r.status, ConnectStatus.online);
      expect(r.isReachable, isTrue);
      expect(r.isUsableHost, isTrue);
      expect(client.lastPath, '/db-version');
    });

    test('a 200 that is NOT our payload is a foreign listener (notAHost)',
        () async {
      final r = await _api(_CannedClient(200, '<html>router on this port</html>'))
          .checkConnectivity();
      expect(r.status, ConnectStatus.notAHost);
      expect(r.isReachable, isTrue);
      expect(r.isUsableHost, isFalse);
    });

    test('401/403 mean a server is present but locked (needsAuth)', () async {
      for (final code in [401, 403]) {
        final r = await _api(_CannedClient(code, '{"error":"unauthorized"}'))
            .checkConnectivity();
        expect(r.status, ConnectStatus.needsAuth, reason: 'status $code');
        expect(r.isReachable, isTrue);
        expect(r.statusCode, code);
      }
    });

    test('an unexpected status is httpError but still reachable', () async {
      final r = await _api(_CannedClient(500, '')).checkConnectivity();
      expect(r.status, ConnectStatus.httpError);
      expect(r.isReachable, isTrue);
    });

    test('a refused connection (SocketException) is unreachable', () async {
      final r = await _api(_ThrowingClient(SocketException('Connection refused')))
          .checkConnectivity();
      expect(r.status, ConnectStatus.unreachable);
      expect(r.isReachable, isFalse);
      expect(r.message, contains('refused'));
    });

    test('a failed host lookup (ClientException) is unreachable', () async {
      final r = await _api(
              _ThrowingClient(http.ClientException('Failed host lookup: bogus')))
          .checkConnectivity();
      expect(r.status, ConnectStatus.unreachable);
      expect(r.isReachable, isFalse);
    });

    test('a stalled host exceeds the budget as timeout', () async {
      final r = await _api(_SlowClient())
          .checkConnectivity(timeout: const Duration(milliseconds: 50));
      expect(r.status, ConnectStatus.timeout);
      expect(r.isReachable, isFalse);
    });

    test('checkConnectivity never throws, even on an unexpected error',
        () async {
      final r = await _api(_ThrowingClient(Exception('weird')))
          .checkConnectivity();
      expect(r.status, ConnectStatus.unreachable);
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/services/http_server_service.dart';
import 'package:library_manager/services/repository.dart';

/// A repository whose read blocks well past the test's request timeout, to
/// prove the server bounds handling time (NET-04).
class _SlowRepo implements LibraryRepository {
  @override
  Future<List<LibraryItem>> getItems({
    int limit = 1000,
    int offset = 0,
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation inv) => null;
}

void main() {
  group('request guards (NET-04 / Phase 8.4)', () {
    test('a declared body over the limit is rejected with 413 up front',
        () async {
      final server = HttpServerService(
          repository: _SlowRepo(), maxRequestBodyBytes: 32);
      await server.startServer(host: '127.0.0.1', port: 0);
      final client = http.Client();
      try {
        final res = await client.post(
          Uri.parse('http://127.0.0.1:${server.port}/items'),
          headers: {'content-type': 'application/json'},
          // Content-Length is set by the client and exceeds the 32-byte cap.
          body: '{"title": "${'x' * 200}"}',
        );
        expect(res.statusCode, 413);
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        expect(body['error'], 'payload_too_large');
      } finally {
        client.close();
        await server.stopServer();
      }
    });

    test('a chunked body (no Content-Length) is cut off mid-stream with 413',
        () async {
      final server = HttpServerService(
          repository: _SlowRepo(), maxRequestBodyBytes: 32);
      await server.startServer(host: '127.0.0.1', port: 0);
      final httpClient = HttpClient();
      try {
        final req = await httpClient
            .post('127.0.0.1', server.port, '/items');
        // -1 => transfer-encoding: chunked, so no Content-Length is sent; the
        // up-front check passes and the byte-counting stream must reject it.
        req.contentLength = -1;
        req.add(List.filled(24, 0x41));
        await req.addStream(Stream.value(List.filled(24, 0x42)));
        final resp = await req.close();
        expect(resp.statusCode, 413);
        final body =
            jsonDecode(await utf8.decodeStream(resp)) as Map<String, dynamic>;
        expect(body['error'], 'payload_too_large');
      } finally {
        httpClient.close(force: true);
        await server.stopServer();
      }
    });

    test('a handler that overruns the timeout is answered 504', () async {
      final server = HttpServerService(
        repository: _SlowRepo(),
        requestTimeout: const Duration(milliseconds: 50),
      );
      await server.startServer(host: '127.0.0.1', port: 0);
      final client = http.Client();
      try {
        final res = await client
            .get(Uri.parse('http://127.0.0.1:${server.port}/items'))
            .timeout(const Duration(seconds: 5));
        expect(res.statusCode, 504);
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        expect(body['error'], 'gateway_timeout');
      } finally {
        client.close();
        await server.stopServer();
      }
    });
  });
}

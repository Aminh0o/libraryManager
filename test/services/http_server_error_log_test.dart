import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:library_manager/services/app_logger.dart';
import 'package:library_manager/services/http_server_service.dart';
import 'package:library_manager/services/repository.dart';

/// REL/logging end-to-end over a real loopback socket: an UNEXPECTED repository
/// failure must (1) surface to the client as a 500 AND (2) be persisted to the
/// process logger, so a release build leaves a diagnosable trace instead of the
/// old debugPrint-only dead end. Binding-free so HttpClient reaches the server.
class _ThrowingRepo implements LibraryRepository {
  @override
  dynamic noSuchMethod(Invocation inv) {
    switch (inv.memberName) {
      case #addItem:
        return Future.error(Exception('simulated db failure'));
      case #getDbVersion:
        return Future.value('1');
    }
    return super.noSuchMethod(inv);
  }
}

void main() {
  late HttpServerService server;
  late http.Client client;
  late String base;
  late List<String> logged;
  late AppLogger original;

  setUp(() async {
    original = appLog;
    logged = <String>[];
    appLog = AppLogger(minLevel: LogLevel.debug, sink: logged.add);
    server = HttpServerService(repository: _ThrowingRepo());
    await server.startServer(host: '127.0.0.1', port: 0);
    base = 'http://127.0.0.1:${server.port}';
    client = http.Client();
  });

  tearDown(() async {
    client.close();
    await server.stopServer();
    appLog = original;
  });

  test('an unhandled repository error returns 500 AND is persisted', () async {
    final r = await client.post(
      Uri.parse('$base/items'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'code': 'X1', 'designation': 'boom'}),
    );
    expect(r.statusCode, 500);
    expect((jsonDecode(r.body) as Map)['error'], 'internal_error');

    final err = logged.where((l) => l.contains('ERROR [http]')).toList();
    expect(err, hasLength(1));
    expect(err.single, contains('Unhandled error on POST'));
    expect(err.single, contains('simulated db failure'));
  });

  test('a handled conflict (400) is NOT logged as an error', () async {
    // A malformed body (missing designation) is a 400 via MalformedRequest,
    // which the error middleware returns without the catch-all -- nothing to
    // persist at ERROR level.
    final r = await client.post(
      Uri.parse('$base/items'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'code': 'X2'}),
    );
    expect(r.statusCode, 400);
    expect(logged.any((l) => l.contains('ERROR [http]')), isFalse);
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/services/auth_middleware.dart';
import 'package:library_manager/services/auth_service.dart';
import 'package:library_manager/services/password_hasher.dart';
import 'package:shelf/shelf.dart';

Future<Response> _handle(Handler handler, Request request) async =>
    await handler(request);

void main() {
  late AuthService auth;
  late String validToken;

  setUp(() async {
    auth = AuthService(hasher: PasswordHasher(iterations: 1000));
    await auth.setPassword('pw');
    validToken = await auth.issueToken();
  });

  Response okHandler(Request _) => Response.ok('protected');

  test('rejects request with no Authorization header (401 JSON)', () async {
    final handler = const Pipeline()
        .addMiddleware(requireAuth(auth))
        .addHandler(okHandler);

    final res = await _handle(
        handler, Request('GET', Uri.parse('http://host/items')));
    expect(res.statusCode, 401);
    final body = jsonDecode(await res.readAsString());
    expect(body['error'], 'unauthorized');
  });

  test('rejects invalid token', () async {
    final handler = const Pipeline()
        .addMiddleware(requireAuth(auth))
        .addHandler(okHandler);
    final res = await _handle(handler, Request('GET',
        Uri.parse('http://host/items'),
        headers: {'authorization': 'Bearer not-a-real-token'}));
    expect(res.statusCode, 401);
  });

  test('accepts a valid bearer token', () async {
    final handler = const Pipeline()
        .addMiddleware(requireAuth(auth))
        .addHandler(okHandler);
    final res = await _handle(handler, Request('GET',
        Uri.parse('http://host/items'),
        headers: {'authorization': 'Bearer $validToken'}));
    expect(res.statusCode, 200);
    expect(await res.readAsString(), 'protected');
  });

  test('non-bearer schemes are rejected', () async {
    final handler = const Pipeline()
        .addMiddleware(requireAuth(auth))
        .addHandler(okHandler);
    final res = await _handle(handler, Request('GET',
        Uri.parse('http://host/items'),
        headers: {'authorization': 'Basic $validToken'}));
    expect(res.statusCode, 401);
  });

  test('open paths bypass authentication', () async {
    final handler = const Pipeline()
        .addMiddleware(requireAuth(auth, openPaths: {'/db-version'}))
        .addHandler(okHandler);
    final res = await _handle(
        handler, Request('GET', Uri.parse('http://host/db-version')));
    expect(res.statusCode, 200);
  });

  test('revoked token is rejected', () async {
    await auth.revokeToken(validToken);
    final handler = const Pipeline()
        .addMiddleware(requireAuth(auth))
        .addHandler(okHandler);
    final res = await _handle(handler, Request('GET',
        Uri.parse('http://host/items'),
        headers: {'authorization': 'Bearer $validToken'}));
    expect(res.statusCode, 401);
  });

  test('protected writes (POST) also require auth', () async {
    final handler = const Pipeline()
        .addMiddleware(requireAuth(auth))
        .addHandler((_) => Response.ok('written'));
    final res = await _handle(
        handler, Request('POST', Uri.parse('http://host/items'), body: '{}'));
    expect(res.statusCode, 401);
  });
}

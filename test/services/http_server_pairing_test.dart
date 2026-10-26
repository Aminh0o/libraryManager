import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:library_manager/services/http_server_service.dart';
import 'package:library_manager/services/auth_service.dart';
import 'package:library_manager/services/api_service.dart';
import 'package:library_manager/models/user_account.dart';
import 'package:library_manager/providers/library_provider.dart';

void main() {
  group('LibraryProvider.normalizeHostInput', () {
    test('normalizes bare IP', () {
      final res = LibraryProvider.normalizeHostInput('192.168.1.10');
      expect(res.ip, '192.168.1.10');
      expect(res.port, isNull);
    });

    test('extracts port from IP:port', () {
      final res = LibraryProvider.normalizeHostInput('192.168.1.10:8080');
      expect(res.ip, '192.168.1.10');
      expect(res.port, 8080);
    });

    test('strips http:// scheme and trailing slash', () {
      final res = LibraryProvider.normalizeHostInput('http://10.0.0.5:9000/');
      expect(res.ip, '10.0.0.5');
      expect(res.port, 9000);
    });

    test('strips https:// scheme and paths', () {
      final res = LibraryProvider.normalizeHostInput(
        'https://172.16.0.1:8080/api/v1',
      );
      expect(res.ip, '172.16.0.1');
      expect(res.port, 8080);
    });

    test('trims surrounding whitespace', () {
      final res = LibraryProvider.normalizeHostInput('   192.168.0.50:4567   ');
      expect(res.ip, '192.168.0.50');
      expect(res.port, 4567);
    });
  });

  group('HttpServerService direct pairing (POST /auth/pair)', () {
    late AuthService auth;
    late HttpServerService server;
    late int port;

    setUp(() async {
      auth = AuthService(store: InMemoryAuthStore());
      await auth.setPassword('admin-secret');
    });

    tearDown(() async {
      await server.stopServer();
    });

    test('rejects empty or malformed body with 400', () async {
      server = HttpServerService(
        auth: auth,
        pairingHandler: (code, ip) async => null,
      );
      await server.startServer(port: 0);
      port = server.port;

      final res = await http.post(
        Uri.parse('http://127.0.0.1:$port/auth/pair'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({}),
      );
      expect(res.statusCode, 400);
      final json = jsonDecode(res.body);
      expect(json['error'], 'bad_request');
    });

    test('returns 400 pairing_disabled when pairingHandler is null', () async {
      server = HttpServerService(auth: auth);
      await server.startServer(port: 0);
      port = server.port;

      final res = await http.post(
        Uri.parse('http://127.0.0.1:$port/auth/pair'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': '123456'}),
      );
      expect(res.statusCode, 400);
      final json = jsonDecode(res.body);
      expect(json['error'], 'pairing_disabled');
    });

    test(
      'returns 401 on invalid/expired code without token required',
      () async {
        server = HttpServerService(
          auth: auth,
          pairingHandler: (code, ip) async {
            if (code == '999999') {
              return {
                'status': 401,
                'error': 'invalid_code',
                'message': 'Code mismatch',
              };
            }
            return null;
          },
        );
        await server.startServer(port: 0);
        port = server.port;

        final res = await http.post(
          Uri.parse('http://127.0.0.1:$port/auth/pair'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'code': '999999'}),
        );
        expect(res.statusCode, 401);
        final json = jsonDecode(res.body);
        expect(json['error'], 'invalid_code');
      },
    );

    test('returns 200 with bearer token and allows ApiService to pair', () async {
      server = HttpServerService(
        auth: auth,
        pairingHandler: (code, ip) async {
          if (code == '654321') {
            final token = await auth.issueTokenFor(
              const TokenPrincipal(
                username: 'device-654321',
                role: UserRole.staff,
              ),
            );
            return {
              'status': 200,
              'token': token,
              'role': UserRole.staff.storage,
              'username': 'device-654321',
            };
          }
          return null;
        },
      );
      await server.startServer(port: 0);
      port = server.port;

      final client = ApiService(hostIp: '127.0.0.1', port: port);

      final session = await client.pairWithHost('654321');
      expect(session, isNotNull);
      expect(session!.isValid, isTrue);
      expect(session.role, UserRole.staff);
      expect(session.username, 'device-654321');
      expect(client.authToken, session.token);
      expect(client.sessionRole, UserRole.staff);

      // Now verify that the paired client can hit an auth-guarded endpoint (/auth/session)
      final sessionCheck = await client.currentSession();
      expect(sessionCheck, isNotNull);
      expect(sessionCheck!.role, UserRole.staff);
      expect(sessionCheck.username, 'device-654321');

      client.close();
    });
  });
}

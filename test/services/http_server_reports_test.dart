import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:library_manager/services/auth_service.dart';
import 'package:library_manager/services/http_server_service.dart';
import 'package:library_manager/services/password_hasher.dart';

import 'http_server_auth_test.dart' show FakeRepo;

/// Phase 10.4 -- the REPORT ROUTES over a real socket. Proves what a client
/// experiences directly: reports are staff-gated (a viewer is refused with a
/// clean 403 before any aggregate runs), an unknown report kind is a 400 (not a
/// 500 or a wrong report), a malformed / reversed date window is a 400 BEFORE
/// the engine is touched, and a valid kind + window round-trips intact. The
/// `FakeRepo` echoes the accepted kind and window back, so the assertions check
/// exactly what the routing + validation layer let through.
void main() {
  late HttpServerService server;
  late FakeRepo repo;
  late AuthService auth;
  late String base;
  late http.Client client;

  setUp(() async {
    auth = AuthService(
      hasher: PasswordHasher(iterations: 1000),
      store: InMemoryAuthStore(),
    );
    repo = FakeRepo();
    server = HttpServerService(repository: repo, auth: auth);
    await server.startServer(host: '127.0.0.1', port: 0);
    base = 'http://127.0.0.1:${server.port}';
    client = http.Client();
    await auth.setPassword('root-pw');
  });

  tearDown(() async {
    client.close();
    await server.stopServer();
  });

  Map<String, String> hdr(String? token) => {
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<http.Response> get(String path, {String? token}) =>
      client.get(Uri.parse('$base$path'), headers: hdr(token));

  Future<http.Response> postBody(String path, Map<String, dynamic> body,
          {String? token}) =>
      client.post(
        Uri.parse('$base$path'),
        headers: {'Content-Type': 'application/json', ...hdr(token)},
        body: jsonEncode(body),
      );

  Future<String> login(String u, String p) async {
    final res = await postBody('/auth/login', {'username': u, 'password': p});
    expect(res.statusCode, 200, reason: 'login failed for $u: ${res.body}');
    return jsonDecode(res.body)['token'] as String;
  }

  Future<String> adminToken() => login('admin', 'root-pw');

  Future<String> addAndLogin(String name, String pw, String role) async {
    final r = await postBody('/users',
        {'username': name, 'password': pw, 'role': role},
        token: await adminToken());
    expect(r.statusCode, 201, reason: 'seed $name: ${r.body}');
    return login(name, pw);
  }

  test('a viewer cannot run any report (403 before any aggregate)', () async {
    final viewer = await addAndLogin('kiosk', 'kiosk-pw-1', 'viewer');
    final res = await get('/reports/circulation', token: viewer);
    expect(res.statusCode, 403, reason: res.body);
    expect(jsonDecode(res.body)['error'], 'forbidden');
  });

  test('staff and admin can run a report and the kind + window round-trip',
      () async {
    final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
    final res = await get(
      '/reports/overdue',
      token: staff,
    );
    expect(res.statusCode, 200, reason: res.body);
    expect(jsonDecode(res.body)['kind'], 'overdue');

    final admin = await adminToken();
    final ranged = await get(
      '/reports/circulation?from=2026-09-01&to=2026-09-30',
      token: admin,
    );
    expect(ranged.statusCode, 200, reason: ranged.body);
    final body = jsonDecode(ranged.body);
    expect(body['kind'], 'circulation');
    expect(body['from'], '2026-09-01');
    expect(body['to'], '2026-09-30');
  });

  test('an unknown report kind is a 400, not a 500 or a wrong report', () async {
    final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
    final res = await get('/reports/secretsauce', token: staff);
    expect(res.statusCode, 400, reason: res.body);
    expect(jsonDecode(res.body)['error'], 'bad_request');
  });

  test('a malformed date bound is refused with a 400 before the engine runs',
      () async {
    final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
    final res = await get(
      '/reports/circulation?from=yesterday',
      token: staff,
    );
    expect(res.statusCode, 400, reason: res.body);
    expect(jsonDecode(res.body)['error'], 'bad_request');
  });

  test('a reversed date window is refused with a 400', () async {
    final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
    final res = await get(
      '/reports/fines?from=2026-09-30&to=2026-09-01',
      token: staff,
    );
    expect(res.statusCode, 400, reason: res.body);
  });

  test('a windowless kind ignores bogus bounds and still answers 200', () async {
    // overdue / inventory never parse from/to, so extra query params are inert.
    final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
    final res = await get(
      '/reports/inventory?from=garbage&to=nope',
      token: staff,
    );
    expect(res.statusCode, 200, reason: res.body);
    expect(jsonDecode(res.body)['kind'], 'inventory');
  });
}

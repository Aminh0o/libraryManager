import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:library_manager/models/fine.dart';
import 'package:library_manager/services/auth_service.dart';
import 'package:library_manager/services/http_server_service.dart';
import 'package:library_manager/services/password_hasher.dart';

import 'http_server_auth_test.dart' show FakeRepo;

/// Phase 10.2 -- the FINES ROUTES over a real socket. Proves the part a client
/// experiences directly: every fine surface refuses the wrong role with a clean
/// 403 BEFORE touching data, only an admin may author the policy, a double
/// settle is a 409 (never a silent second collection), the authenticated bearer
/// is recorded as resolved_by, and a malformed query/body is a 400 -- not a 500.
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
      client.post(Uri.parse('$base$path'),
          headers: {'Content-Type': 'application/json', ...hdr(token)},
          body: jsonEncode(body));

  Future<http.Response> postEmpty(String path, {String? token}) =>
      client.post(Uri.parse('$base$path'), headers: hdr(token));

  Future<http.Response> putBody(String path, Map<String, dynamic> body,
          {String? token}) =>
      client.put(Uri.parse('$base$path'),
          headers: {'Content-Type': 'application/json', ...hdr(token)},
          body: jsonEncode(body));

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

  void expectForbidden(http.Response res) {
    expect(res.statusCode, 403, reason: res.body);
    expect(jsonDecode(res.body)['error'], 'forbidden');
  }

  group('reads are staff-gated', () {
    test('a viewer cannot read the ledger', () async {
      final viewer = await addAndLogin('kiosk', 'kiosk-pw-1', 'viewer');
      expectForbidden(await get('/fines', token: viewer));
      expectForbidden(await get('/fines/balance?member_id=M1', token: viewer));
    });

    test('staff sees the ledger and the outstanding balance', () async {
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      final a = repo.seedFine('M1', 10);
      final b = repo.seedFine('M1', 5);
      repo.seedFine('M2', 7);

      final res = await get('/fines', token: staff);
      expect(res.statusCode, 200);
      expect((jsonDecode(res.body) as List), hasLength(3));
      expect(a, isNonNegative);
      expect(b, isNonNegative);

      final bal = await get('/fines/balance?member_id=M1', token: staff);
      expect(bal.statusCode, 200);
      expect(jsonDecode(bal.body)['balance'], 15);
    });

    test('a malformed status filter is a 400, not a 500', () async {
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      final res = await get('/fines?status=garbage', token: staff);
      expect(res.statusCode, 400);
      expect(jsonDecode(res.body)['error'], 'bad_request');
    });

    test('a status filter narrows the ledger', () async {
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      final id = repo.seedFine('M1', 3);
      repo.seedFine('M1', 4);
      await postEmpty('/fines/$id/pay', token: staff);

      final pending = await get('/fines?status=pending', token: staff);
      expect((jsonDecode(pending.body) as List), hasLength(1));
      final paid = await get('/fines?status=paid', token: staff);
      expect((jsonDecode(paid.body) as List), hasLength(1));
    });
  });

  group('settlement records the operator and is idempotency-safe', () {
    test('a staff pay marks the fine paid attributed to the bearer', () async {
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      final id = repo.seedFine('M1', 12);

      final res = await postEmpty('/fines/$id/pay', token: staff);
      expect(res.statusCode, 200, reason: res.body);

      final fines = await repo.getFines();
      final settled = fines.firstWhere((f) => f.id == id);
      expect(settled.status, FineStatus.paid);
      expect(settled.resolvedBy, 'libby');
      expect(settled.resolvedAt, isNotNull);
    });

    test('a waive resolves too', () async {
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      final id = repo.seedFine('M1', 8);
      final res = await postEmpty('/fines/$id/waive', token: staff);
      expect(res.statusCode, 200);
      expect((await repo.getFines()).single.status, FineStatus.waived);
    });

    test('double-settling is a 409 conflict, never a second collection',
        () async {
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      final id = repo.seedFine('M1', 5);
      expect((await postEmpty('/fines/$id/pay', token: staff)).statusCode, 200);

      final again = await postEmpty('/fines/$id/pay', token: staff);
      expect(again.statusCode, 409);
      expect(jsonDecode(again.body)['error'], 'conflict');
      expect((await repo.getFines()).single.status, FineStatus.paid);
    });

    test('settling an unknown fine is a 409', () async {
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      final res = await postEmpty('/fines/99999/pay', token: staff);
      expect(res.statusCode, 409);
    });

    test('a viewer cannot settle a fine', () async {
      final viewer = await addAndLogin('kiosk', 'kiosk-pw-1', 'viewer');
      final id = repo.seedFine('M1', 5);
      expectForbidden(await postEmpty('/fines/$id/pay', token: viewer));
      expect((await repo.getFines()).single.status, FineStatus.pending);
    });
  });

  group('the fine policy is admin-only to author', () {
    test('a staff member may read but not write the rate', () async {
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      expect((await get('/settings/fines', token: staff)).statusCode, 200);
      expectForbidden(
          await putBody('/settings/fines', {'rate_per_day': 3}, token: staff));
    });

    test('an admin sets the rate; a viewer may not even read it', () async {
      final viewer = await addAndLogin('kiosk', 'kiosk-pw-1', 'viewer');
      expectForbidden(await get('/settings/fines', token: viewer));

      final admin = await adminToken();
      final put = await putBody(
          '/settings/fines', {'rate_per_day': 2.5, 'currency': 'DZD'},
          token: admin);
      expect(put.statusCode, 200, reason: put.body);

      final read = jsonDecode((await get('/settings/fines', token: admin)).body);
      expect(read['rate_per_day'], 2.5);
      expect(read['currency'], 'DZD');
    });

    test('a negative rate is rejected with 400', () async {
      final admin = await adminToken();
      final res =
          await putBody('/settings/fines', {'rate_per_day': -1}, token: admin);
      expect(res.statusCode, 400);
    });
  });
}

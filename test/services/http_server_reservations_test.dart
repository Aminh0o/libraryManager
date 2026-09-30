import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:library_manager/models/reservation.dart';
import 'package:library_manager/services/auth_service.dart';
import 'package:library_manager/services/http_server_service.dart';
import 'package:library_manager/services/password_hasher.dart';

import 'http_server_auth_test.dart' show FakeRepo;

/// Phase 10.3 -- the RESERVATION ROUTES over a real socket. Proves the part a
/// client experiences directly: every hold surface refuses the wrong role with
/// a clean 403 before touching data, only an admin may author the hold policy,
/// a duplicate/live-full queue is a 409, a malformed status or id is a 400 (not
/// a 500), and a cancel of a closed hold is a 409.
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
    test('a viewer cannot read the queue, the ready shelf or the policy',
        () async {
      final viewer = await addAndLogin('kiosk', 'kiosk-pw-1', 'viewer');
      expectForbidden(await get('/reservations', token: viewer));
      expectForbidden(await get('/reservations/ready', token: viewer));
      expectForbidden(await get('/settings/holds', token: viewer));
    });

    test('staff sees the queue and the policy', () async {
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      repo.seedHold('0001', 'M1');
      repo.seedHold('0001', 'M2',
          status: ReservationStatus.available,
          availableUntil: DateTime.now()
              .add(const Duration(days: 7))
              .toIso8601String());

      final res = await get('/reservations', token: staff);
      expect(res.statusCode, 200);
      expect((jsonDecode(res.body) as List), hasLength(2));

      final ready = await get('/reservations/ready', token: staff);
      expect((jsonDecode(ready.body) as List), hasLength(1));

      final policy = await get('/settings/holds', token: staff);
      expect(jsonDecode(policy.body)['pickup_days'],
          HoldSettings.defaultPickupDays);
    });

    test('a malformed status filter is a 400, not a 500', () async {
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      final res = await get('/reservations?status=garbage', token: staff);
      expect(res.statusCode, 400);
      expect(jsonDecode(res.body)['error'], 'bad_request');
    });
  });

  group('placing a hold', () {
    test('a viewer cannot place a hold', () async {
      final viewer = await addAndLogin('kiosk', 'kiosk-pw-1', 'viewer');
      expectForbidden(
          await postBody('/reservations', {'item_code': '0001', 'member_id': 'M1'},
              token: viewer));
    });

    test('staff places a hold and gets 201 with the row', () async {
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      final res = await postBody(
          '/reservations', {'item_code': '0001', 'member_id': 'M1'},
          token: staff);
      expect(res.statusCode, 201, reason: res.body);
      final body = jsonDecode(res.body);
      expect(body['status'], 'queued');
      expect(body['item_code'], '0001');
      expect(body['member_id'], 'M1');
    });

    test('a missing field is a 400', () async {
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      final res = await postBody('/reservations', {'item_code': '0001'},
          token: staff);
      expect(res.statusCode, 400);
    });

    test('a duplicate live hold is a 409 conflict', () async {
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      expect(
          (await postBody('/reservations',
                  {'item_code': '0001', 'member_id': 'M1'}, token: staff))
              .statusCode,
          201);
      final again = await postBody(
          '/reservations', {'item_code': '0001', 'member_id': 'M1'},
          token: staff);
      expect(again.statusCode, 409);
      expect(jsonDecode(again.body)['error'], 'conflict');
    });

    test('a full queue is a 409', () async {
      final admin = await adminToken();
      await putBody('/settings/holds',
          {'pickup_days': 7, 'queue_max_per_item': 1}, token: admin);
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      await postBody('/reservations', {'item_code': '0001', 'member_id': 'M1'},
          token: staff);
      final res = await postBody(
          '/reservations', {'item_code': '0001', 'member_id': 'M2'},
          token: staff);
      expect(res.statusCode, 409);
    });
  });

  group('cancelling a hold', () {
    test('a malformed id is a 400', () async {
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      final res = await postEmpty('/reservations/abc/cancel', token: staff);
      expect(res.statusCode, 400);
    });

    test('cancelling an unknown hold is a 409', () async {
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      final res = await postEmpty('/reservations/99999/cancel', token: staff);
      expect(res.statusCode, 409);
    });

    test('staff cancels a live hold; a second cancel is a 409', () async {
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      final id = repo.seedHold('0001', 'M1');
      expect((await postEmpty('/reservations/$id/cancel', token: staff)).statusCode,
          200);
      expect((await repo.getReservations()).single.status,
          ReservationStatus.cancelled);
      final again = await postEmpty('/reservations/$id/cancel', token: staff);
      expect(again.statusCode, 409);
    });

    test('a viewer cannot cancel', () async {
      final viewer = await addAndLogin('kiosk', 'kiosk-pw-1', 'viewer');
      final id = repo.seedHold('0001', 'M1');
      expectForbidden(await postEmpty('/reservations/$id/cancel', token: viewer));
    });
  });

  group('the hold policy is admin-only to author', () {
    test('staff may read but not write the policy', () async {
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      expect((await get('/settings/holds', token: staff)).statusCode, 200);
      expectForbidden(await putBody(
          '/settings/holds', {'pickup_days': 3, 'queue_max_per_item': 5},
          token: staff));
    });

    test('an admin sets the policy and it reads back', () async {
      final admin = await adminToken();
      final put = await putBody(
          '/settings/holds', {'pickup_days': 4, 'queue_max_per_item': 9},
          token: admin);
      expect(put.statusCode, 200, reason: put.body);
      final read =
          jsonDecode((await get('/settings/holds', token: admin)).body);
      expect(read['pickup_days'], 4);
      expect(read['queue_max_per_item'], 9);
    });

    test('an out-of-range pickup window is rejected with 400', () async {
      final admin = await adminToken();
      final res = await putBody(
          '/settings/holds', {'pickup_days': 0, 'queue_max_per_item': 5},
          token: admin);
      expect(res.statusCode, 400);
    });

    test('a non-integer queue cap is rejected with 400', () async {
      final admin = await adminToken();
      final res = await putBody(
          '/settings/holds', {'pickup_days': 5, 'queue_max_per_item': 'lots'},
          token: admin);
      expect(res.statusCode, 400);
    });
  });
}

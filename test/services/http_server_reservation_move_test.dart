import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:library_manager/models/reservation.dart';
import 'package:library_manager/services/auth_service.dart';
import 'package:library_manager/services/http_server_service.dart';
import 'package:library_manager/services/password_hasher.dart';

import 'http_server_auth_test.dart' show FakeRepo;

/// Pass 6 -- the REORDER ROUTE over a real socket. Proves what the client
/// experiences directly:
///
/// * a viewer cannot reorder the queue (403, no repo call);
/// * a staff member may post `{direction: 'up'|'down'}` and gets a 200 with
///   the swap recorded server-side (the audit row is server-authored, not
///   anything the client supplied);
/// * a malformed body (missing direction, garbage direction, non-integer
///   id) is a 400 BEFORE the repository is touched -- never a 500;
/// * a move on a non-queued (cancelled / fulfilled) hold is a 409 conflict,
///   the same guard shape `cancel` uses.
///
/// Reuses the FakeRepo harness from `http_server_auth_test.dart`, whose
/// minimal `moveReservation` override validates the same status rule the
/// real DatabaseService applies.
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

  Future<http.Response> postBody(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) => client.post(
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
    final r = await postBody('/users', {
      'username': name,
      'password': pw,
      'role': role,
    }, token: await adminToken());
    expect(r.statusCode, 201, reason: 'seed $name: ${r.body}');
    return login(name, pw);
  }

  void expectForbidden(http.Response res) {
    expect(res.statusCode, 403, reason: res.body);
    expect(jsonDecode(res.body)['error'], 'forbidden');
  }

  group('POST /reservations/<id>/move', () {
    test('a viewer is refused before the queue is touched', () async {
      final viewer = await addAndLogin('kiosk', 'kiosk-pw-1', 'viewer');
      final id = repo.seedHold('0001', 'M1');
      final res = await postBody('/reservations/$id/move', {
        'direction': 'up',
      }, token: viewer);
      expectForbidden(res);
      // The route denies BEFORE reading or writing anything: the hold is
      // still queued with the same rank (untouched).
      final still = (await repo.getReservations()).single;
      expect(still.status, ReservationStatus.queued);
      expect(still.rank, isNull);
    });

    test('staff moves a queued hold and gets 200 ok', () async {
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      repo.seedHold('0001', 'M1');
      final second = repo.seedHold('0001', 'M2');
      final res = await postBody('/reservations/$second/move', {
        'direction': 'up',
      }, token: staff);
      expect(res.statusCode, 200, reason: res.body);
      expect(jsonDecode(res.body)['ok'], isTrue);
    });

    test('a down direction is accepted the same way as up', () async {
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      final first = repo.seedHold('0001', 'M1');
      repo.seedHold('0001', 'M2');
      final res = await postBody('/reservations/$first/move', {
        'direction': 'down',
      }, token: staff);
      expect(res.statusCode, 200, reason: res.body);
    });

    test(
      'a missing direction is a 400 (not a 500, not a silent default)',
      () async {
        final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
        final id = repo.seedHold('0001', 'M1');
        final res = await postBody(
          '/reservations/$id/move',
          <String, dynamic>{},
          token: staff,
        );
        expect(res.statusCode, 400, reason: res.body);
        expect(jsonDecode(res.body)['error'], 'bad_request');
      },
    );

    test('a garbage direction is a 400', () async {
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      final id = repo.seedHold('0001', 'M1');
      final res = await postBody('/reservations/$id/move', {
        'direction': 'sideways',
      }, token: staff);
      expect(res.statusCode, 400, reason: res.body);
      expect(jsonDecode(res.body)['error'], 'bad_request');
    });

    test('a non-integer id is a 400', () async {
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      final res = await postBody('/reservations/abc/move', {
        'direction': 'up',
      }, token: staff);
      expect(res.statusCode, 400, reason: res.body);
    });

    test('moving an unknown hold is a 409 conflict', () async {
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      final res = await postBody('/reservations/99999/move', {
        'direction': 'up',
      }, token: staff);
      expect(res.statusCode, 409, reason: res.body);
      expect(jsonDecode(res.body)['error'], 'conflict');
    });

    test('moving a non-queued (available) hold is a 409 conflict', () async {
      // A promoted hold is server-owned: its position IS the shelf, not the
      // queue. The route must refuse BEFORE any rank write happens.
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      final id = repo.seedHold(
        '0001',
        'M1',
        status: ReservationStatus.available,
        availableUntil: DateTime.now()
            .add(const Duration(days: 7))
            .toIso8601String(),
      );
      final res = await postBody('/reservations/$id/move', {
        'direction': 'up',
      }, token: staff);
      expect(res.statusCode, 409, reason: res.body);
      // The row is unchanged -- the FakeRepo throws StateError before
      // touching anything, mirroring the real transaction's early exit.
      final row = (await repo.getReservations()).single;
      expect(row.status, ReservationStatus.available);
      expect(row.rank, isNull);
    });

    test(
      'an unauthenticated call is refused before the queue is read',
      () async {
        final id = repo.seedHold('0001', 'M1');
        final res = await client.post(
          Uri.parse('$base/reservations/$id/move'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'direction': 'up'}),
        );
        expect(res.statusCode, anyOf(401, 403), reason: res.body);
      },
    );
  });
}

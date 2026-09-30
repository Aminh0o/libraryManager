import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:library_manager/models/user_account.dart';
import 'package:library_manager/services/auth_service.dart';
import 'package:library_manager/services/http_server_service.dart';
import 'package:library_manager/services/password_hasher.dart';

import 'http_server_auth_test.dart' show FakeRepo;

/// Phase 10.1 -- AUTHORIZATION ENFORCEMENT over a real socket.
///
/// Everything above the HTTP layer is covered by the service/store tests; this
/// file proves the part that actually matters to a client: that the ROUTES
/// refuse the wrong role, and refuse it *before* touching data. Each refused
/// write asserts a 403 (`forbidden`) rather than a 400/500 from deeper in the
/// handler -- which is exactly what it means for the gate to be first.
void main() {
  late HttpServerService server;
  late AuthService auth;
  late String base;
  late http.Client client;

  setUp(() async {
    auth = AuthService(
      hasher: PasswordHasher(iterations: 1000),
      store: InMemoryAuthStore(),
    );
    server = HttpServerService(repository: FakeRepo(), auth: auth);
    await server.startServer(host: '127.0.0.1', port: 0);
    base = 'http://127.0.0.1:${server.port}';
    client = http.Client();
    await auth.setPassword('root-pw');
  });

  tearDown(() async {
    client.close();
    await server.stopServer();
  });

  // Raw HTTP helpers are declared first because the login/seed wrappers below
  // close over them (Dart rejects a local function used before its declaration).
  Future<http.Response> get(String path, {String? token}) => client.get(
    Uri.parse('$base$path'),
    headers: token == null ? {} : {'Authorization': 'Bearer $token'},
  );

  Future<http.Response> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) => client.post(
    Uri.parse('$base$path'),
    headers: {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    },
    body: jsonEncode(body),
  );

  Future<http.Response> put(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) => client.put(
    Uri.parse('$base$path'),
    headers: {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    },
    body: jsonEncode(body),
  );

  Future<http.Response> del(String path, {String? token}) => client.delete(
    Uri.parse('$base$path'),
    headers: token == null ? {} : {'Authorization': 'Bearer $token'},
  );

  Future<String> tokenFor(String username, String password) async {
    final res = await post('/auth/login', {
      'username': username,
      'password': password,
    });
    expect(res.statusCode, 200, reason: 'login failed for $username');
    return jsonDecode(res.body)['token'] as String;
  }

  /// Legacy shared-admin login (the identity every existing install has).
  Future<String> adminToken() => tokenFor('admin', 'root-pw');

  Future<String> addAndLogin(String name, String pw, String role) async {
    final t = await adminToken();
    final r = await post('/users', {
      'username': name,
      'password': pw,
      'role': role,
    }, token: t);
    expect(r.statusCode, 201, reason: 'seed user $name failed: ${r.body}');
    return tokenFor(name, pw);
  }

  void expectForbidden(http.Response res, {String? containing}) {
    expect(res.statusCode, 403, reason: res.body);
    final body = jsonDecode(res.body);
    expect(body['error'], 'forbidden');
    if (containing != null) {
      expect(body['message'].toString(), contains(containing));
    }
  }

  group('least privilege is enforced per route', () {
    test('a viewer may read the catalogue', () async {
      final viewer = await addAndLogin('kiosk', 'kiosk-pw-1', 'viewer');
      expect((await get('/items', token: viewer)).statusCode, 200);
      expect((await get('/stats', token: viewer)).statusCode, 200);
      expect((await get('/members', token: viewer)).statusCode, 200);
    });

    test('a viewer may not write items', () async {
      final viewer = await addAndLogin('kiosk', 'kiosk-pw-1', 'viewer');
      expectForbidden(
        await post('/items', {'title': 'x'}, token: viewer),
        containing: 'viewer',
      );
    });

    test('a viewer may not write members, loans or history', () async {
      final viewer = await addAndLogin('kiosk', 'kiosk-pw-1', 'viewer');
      expectForbidden(await post('/members', {'name': 'x'}, token: viewer));
      expectForbidden(await post('/loans', {'itemCode': 'x'}, token: viewer));
      expectForbidden(await post('/history', {'a': 1}, token: viewer));
      expectForbidden(await del('/members/M1', token: viewer));
    });

    test('staff may write circulation data but not administration', () async {
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      // Guard passes -> the handler runs and rejects the placeholder body on
      // its own merits. A 403 here would mean the gate is mis-wired.
      final res = await post('/items', {'title': 'x'}, token: staff);
      expect(res.statusCode, isNot(403), reason: res.body);
      expect((await del('/items/0001', token: staff)).statusCode, isNot(403));

      expectForbidden(
        await post('/users', {
          'username': 'ghost',
          'password': 'ghost-pw-1',
          'role': 'viewer',
        }, token: staff),
        containing: 'staff',
      );
      expectForbidden(
        await post('/code-definitions', {'prefix': 'X'}, token: staff),
      );
    });

    test(
      'the code- and attribute-vocabulary surfaces are admin-only',
      () async {
        final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
        expectForbidden(
          await post('/code-definitions', {'prefix': 'X'}, token: staff),
        );
        expectForbidden(
          await put('/code-definitions/X', {'label': 'y'}, token: staff),
        );
        expectForbidden(await del('/code-definitions/X', token: staff));
        expectForbidden(
          await post('/attribute-definitions', {'value': 'y'}, token: staff),
        );
        expectForbidden(await del('/attribute-definitions/1', token: staff));
      },
    );

    test('reads of the user list are admin-only', () async {
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      final viewer = await addAndLogin('kiosk', 'kiosk-pw-1', 'viewer');
      expectForbidden(await get('/users', token: staff));
      expectForbidden(await get('/users', token: viewer));
      final body = jsonDecode(
        (await get('/users', token: await adminToken())).body,
      );
      expect((body['users'] as List), isNotEmpty);
    });
  });

  group('the user-admin surface cannot be escalated from outside', () {
    test('a viewer cannot create accounts (not even a viewer)', () async {
      final viewer = await addAndLogin('kiosk', 'kiosk-pw-1', 'viewer');
      expectForbidden(
        await post('/users', {
          'username': 'puppet',
          'password': 'puppet-pw',
          'role': 'viewer',
        }, token: viewer),
      );
      expect(
        (await get('/users', token: await adminToken())).body,
        isNot(contains('puppet')),
      );
    });

    test('a viewer cannot promote itself', () async {
      final viewer = await addAndLogin('kiosk', 'kiosk-pw-1', 'viewer');
      expectForbidden(
        await put('/users/kiosk', {'role': 'admin'}, token: viewer),
      );
      expectForbidden(
        await put('/users/admin', {'role': 'viewer'}, token: viewer),
      );
      // Still a viewer afterwards.
      expectForbidden(await post('/items', {'title': 'x'}, token: viewer));
    });

    test(
      'account creation over HTTP yields a token with the granted role',
      () async {
        final t = await adminToken();
        expect(
          (await post('/users', {
            'username': 'maria',
            'password': 'maria-pw-1',
            'role': 'staff',
          }, token: t)).statusCode,
          201,
        );
        final maria = await tokenFor('maria', 'maria-pw-1');
        expect(
          (await post('/items', {'title': 'x'}, token: maria)).statusCode,
          isNot(403),
        );
        expectForbidden(
          await post('/users', {
            'username': 'x1',
            'password': 'x1-pw-123',
            'role': 'staff',
          }, token: maria),
        );
      },
    );

    test('no unauthenticated caller can create an admin', () async {
      final res = await post('/users', {
        'username': 'intruder',
        'password': 'intruder-pw',
        'role': 'admin',
      });
      // The install has a credential, so the bearer guard answers first.
      expect(res.statusCode, 401);
      expect(
        (await get('/users', token: await adminToken())).body,
        isNot(contains('intruder')),
      );
    });
  });

  group('role changes bite immediately', () {
    test('a demotion applies to the session already in use', () async {
      final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
      expect(
        (await post('/items', {'title': 'x'}, token: staff)).statusCode,
        isNot(403),
      );
      expectForbidden(
        await post('/code-definitions', {'prefix': 'X'}, token: staff),
      );

      final t = await adminToken();
      expect(
        (await put('/users/libby', {'role': 'viewer'}, token: t)).statusCode,
        200,
      );
      expectForbidden(
        await post('/items', {'title': 'x'}, token: staff),
        containing: 'viewer',
      );
    });

    test('an admin password change kills that admin session', () async {
      final t = await adminToken();
      await auth.addUser('chief', 'chief-pw-1', UserRole.admin);
      final chief = await tokenFor('chief', 'chief-pw-1');
      expect((await get('/users', token: chief)).statusCode, 200);
      expect(
        (await put('/users/chief/password', {
          'password': 'chief-pw-2',
        }, token: t)).statusCode,
        200,
      );
      // Named-admin credential rotated -> its outstanding tokens are gone.
      expect((await get('/users', token: chief)).statusCode, 401);
      expect(
        (await get('/users', token: t)).statusCode,
        200,
        reason: 'the operator session is independent and survives',
      );
    });

    test('deleting an account ends its sessions', () async {
      final t = await adminToken();
      await auth.addUser('temp', 'temp-pw-1', UserRole.staff);
      final temp = await tokenFor('temp', 'temp-pw-1');
      expect(
        (await post('/items', {'title': 'x'}, token: temp)).statusCode,
        isNot(403),
      );
      expect((await del('/users/temp', token: t)).statusCode, 200);
      expect((await get('/items', token: temp)).statusCode, 401);
    });
  });

  group('malformed administration input is a 4xx, never a 500 or a guess', () {
    test('a missing or forged role is refused outright', () async {
      final t = await adminToken();
      await auth.addUser('libby', 'libby-pw-1', UserRole.staff);
      for (final bad in ['supervisor', 'ADMIN', '', 'root', 'owner']) {
        final res = await put('/users/libby', {'role': bad}, token: t);
        expect(
          res.statusCode,
          400,
          reason: '"$bad" must be a client error, not a guessed privilege',
        );
        expect(jsonDecode(res.body)['error'], 'bad_request');
      }
      final missing = await put('/users/libby', {
        'not_role': 'staff',
      }, token: t);
      expect(missing.statusCode, 400);
      // libby is untouched by every refusal above.
      expect((await get('/users', token: t)).body, contains('"staff"'));
    });

    test(
      'an invalid role on CREATE is refused before any row exists',
      () async {
        final t = await adminToken();
        final res = await post('/users', {
          'username': 'oops',
          'password': 'oops-pw-1',
          'role': 'everything',
        }, token: t);
        expect(res.statusCode, 400);
        expect((await get('/users', token: t)).body, isNot(contains('oops')));
      },
    );

    test(
      'duplicate, unknown-account and reserved-name admin ops are 409',
      () async {
        final t = await adminToken();
        await auth.addUser('libby', 'libby-pw-1', UserRole.staff);
        final dup = await post('/users', {
          'username': 'libby',
          'password': 'libby-pw-2',
          'role': 'staff',
        }, token: t);
        expect(dup.statusCode, 409, reason: dup.body);
        expect(
          (await put('/users/ghost', {'role': 'staff'}, token: t)).statusCode,
          409,
        );
        expect(
          (await post('/users', {
            'username': 'admin',
            'password': 'admin-pw-1',
            'role': 'admin',
          }, token: t)).statusCode,
          409,
        );
      },
    );

    test('a malformed username is a 400 and creates nothing', () async {
      final t = await adminToken();
      final res = await post('/users', {
        'username': 'has spaces',
        'password': 'whatever1',
        'role': 'viewer',
      }, token: t);
      expect(res.statusCode, 400, reason: res.body);
      expect((await get('/users', token: t)).body, isNot(contains('has')));
    });

    test('a non-JSON body to an admin route is a 400, not a crash', () async {
      final t = await adminToken();
      final res = await client.post(
        Uri.parse('$base/users'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $t',
        },
        body: '{not json',
      );
      expect(res.statusCode, 400);
    });
  });

  group(
    'backward compatibility: enabling roles does not strand an install',
    () {
      test('a legacy pairing token keeps full rights', () async {
        final legacy = await auth.issueToken();
        expect((await get('/items', token: legacy)).statusCode, 200);
        expect(
          (await post('/items', {'title': 'x'}, token: legacy)).statusCode,
          isNot(403),
        );
        expect((await get('/users', token: legacy)).statusCode, 200);
        expect(
          (await del('/items/0001', token: legacy)).statusCode,
          isNot(403),
        );
      });

      test(
        'the legacy admin login path keeps working alongside named accounts',
        () async {
          await auth.addUser('libby', 'libby-pw-1', UserRole.staff);
          final t = await adminToken();
          expect((await get('/users', token: t)).statusCode, 200);
        },
      );

      test(
        'while no credential exists the server stays bootstrap-open',
        () async {
          final open = AuthService(hasher: PasswordHasher(iterations: 1000));
          final s2 = HttpServerService(repository: FakeRepo(), auth: open);
          await s2.startServer(host: '127.0.0.1', port: 0);
          addTearDown(s2.stopServer);
          final res = await client.get(
            Uri.parse('http://127.0.0.1:${s2.port}/items'),
          );
          expect(res.statusCode, 200);
        },
      );
    },
  );
}

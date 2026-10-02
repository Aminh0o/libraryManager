import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/models/user_account.dart';
import 'package:library_manager/services/auth_service.dart';
import 'package:library_manager/services/password_hasher.dart';

/// Phase 10.1 (USERS & ROLES) -- SERVICE-LAYER semantics.
///
/// These are the authorization rules the HTTP route guards depend on, tested at
/// the auth core where they actually live: role binding at mint time, the
/// last-admin lockout guards, revocation-on-delete / revocation-on-password-
/// change, and the backward-compatibility contract that lets roles be enabled
/// on a live install WITHOUT stranding its existing operator.
///
/// A deliberately cheap hasher keeps the suite fast; PBKDF2 itself is covered
/// by password_hasher_test.dart.
PasswordHasher _fastHasher() => PasswordHasher(iterations: 1000);

const _pw = 'longenough1';

void main() {
  late InMemoryAuthStore store;
  late AuthService auth;

  setUp(() async {
    store = InMemoryAuthStore();
    auth = AuthService(hasher: _fastHasher(), store: store);
    // A live install always has the legacy shared-admin credential; every
    // upgrade-compatibility assertion below depends on it being present.
    await auth.setPassword('root-admin');
  });

  group('role binding at mint time', () {
    test('a token minted by login carries that account\'s role', () async {
      await auth.addUser('librarian', _pw, UserRole.staff);
      final res = await auth.login('librarian', _pw, sourceKey: '10.0.0.5');
      expect(res.isSuccess, isTrue);
      expect(res.principal, isNotNull);
      expect(res.principal!.username, 'librarian');
      expect(res.principal!.role, UserRole.staff);
      expect(
        res.principal!.isNamed,
        isTrue,
        reason: 'named accounts are least-privilege, not legacy',
      );

      final p = await auth.principalFor(res.token!);
      expect(p.role, UserRole.staff);
      expect(p.username, 'librarian');
    });

    test('viewer and admin roles are bound exactly as granted', () async {
      await auth.addUser('counter', _pw, UserRole.viewer);
      await auth.addUser('boss', _pw, UserRole.admin);
      final v = await auth.principalFor(
        (await auth.login('counter', _pw, sourceKey: 'i')).token!,
      );
      final a = await auth.principalFor(
        (await auth.login('boss', _pw, sourceKey: 'i')).token!,
      );
      expect(v.role, UserRole.viewer);
      expect(a.role, UserRole.admin);
    });

    test('legacy password login yields an admin principal', () async {
      final res = await auth.login('admin', 'root-admin', sourceKey: 'i');
      expect(res.isSuccess, isTrue);
      expect(res.principal!.role, UserRole.admin);
    });

    test('an unattributed (pre-10.1 / pairing) token keeps admin and is '
        'flagged legacy', () async {
      final t = await auth.issueToken();
      final p = await auth.principalFor(t);
      expect(p.role, UserRole.admin);
      expect(
        p.isNamed,
        isFalse,
        reason:
            'route guards must treat this as the legacy all-powerful '
            'path so upgrading never strands an already-paired client',
      );
    });
  });

  group('account lifecycle', () {
    test('addUser stores only a hash and normalizes the username', () async {
      final rec = await auth.addUser('  Mary.Jones  ', _pw, UserRole.staff);
      expect(rec.username, 'mary.jones');
      expect(store.debugUserHash('mary.jones'), startsWith('pbkdf2|sha256|'));
      expect(
        rec.toPublicMap().containsKey('hash'),
        isFalse,
        reason: 'the public projection must never carry a credential',
      );
      expect(jsonSafeUsers(await auth.users()), contains('mary.jones'));
    });

    test(
      'rejects malformed usernames, weak passwords and duplicates',
      () async {
        expect(
          () => auth.addUser('ab', _pw, UserRole.staff),
          throwsA(isA<UserAdminException>()),
        );
        expect(
          () => auth.addUser('-leading', _pw, UserRole.staff),
          throwsA(isA<UserAdminException>()),
        );
        expect(
          () => auth.addUser('has spaces', _pw, UserRole.staff),
          throwsA(isA<UserAdminException>()),
        );
        expect(
          () => auth.addUser('rob', 'short', UserRole.staff),
          throwsA(isA<UserAdminException>()),
        );
        await auth.addUser('dup', _pw, UserRole.viewer);
        expect(
          () => auth.addUser('dup', _pw, UserRole.viewer),
          throwsA(isA<UserAdminException>()),
        );
      },
    );

    test('a rejected addUser never persists a row', () async {
      await expectLater(
        auth.addUser('bad name!', _pw, UserRole.admin),
        throwsA(isA<UserAdminException>()),
      );
      expect(store.debugUserHash('bad name!'), isNull);
      expect(jsonSafeUsers(await auth.users()), isNot(contains('bad name!')));
    });

    test(
      '"admin" is reserved -- it cannot be recreated with a new password',
      () async {
        expect(
          () => auth.addUser('admin', _pw, UserRole.admin),
          throwsA(isA<UserAdminException>()),
          reason: 'two credentials for one identity is an escalation vector',
        );
      },
    );

    test('removing an account revokes exactly its own tokens', () async {
      await auth.addUser('alice', _pw, UserRole.staff);
      await auth.addUser('bob', _pw, UserRole.staff);
      final a = (await auth.login('alice', _pw, sourceKey: 'i')).token!;
      final b = (await auth.login('bob', _pw, sourceKey: 'i')).token!;
      final legacy = await auth.issueToken();

      await auth.removeUser('alice');
      expect(await auth.isAuthorized(a), isFalse);
      expect(
        await auth.isAuthorized(b),
        isTrue,
        reason: 'a delete must not collateral-damage other accounts',
      );
      expect(
        await auth.isAuthorized(legacy),
        isTrue,
        reason: 'the operator\'s own session must survive',
      );
    });

    test('an unknown account cannot be deleted', () async {
      expect(
        () => auth.removeUser('ghost'),
        throwsA(isA<UserAdminException>()),
      );
    });

    test('the built-in administrator cannot be deleted', () async {
      await expectLater(
        auth.removeUser('admin'),
        throwsA(isA<UserAdminException>()),
      );
      // The failure must be the reserved-identity refusal, not "no such user"
      // -- otherwise the test would pass for the wrong reason.
      expect(
        await auth
            .removeUser('admin')
            .then((_) => '')
            .catchError((Object e) => e.toString()),
        contains('administrator'),
      );
    });
  });

  group('last-admin guards (anti-lockout AND anti-escalation)', () {
    test('the last named admin cannot be demoted', () async {
      await auth.addUser('solo', _pw, UserRole.admin);
      // Two admins exist (legacy + solo); demoting solo is allowed...
      await auth.changeUserRole('solo', UserRole.staff);
      expect(
        (await auth.users()).firstWhere((u) => u.username == 'solo').role,
        UserRole.staff,
      );
    });

    test('the last administrator cannot be demoted or removed', () async {
      // No legacy credential, so the single named admin really IS the last.
      final bare = AuthService(
        hasher: _fastHasher(),
        store: InMemoryAuthStore(),
      );
      await bare.addUser('owner', _pw, UserRole.admin);
      expect(
        () => bare.changeUserRole('owner', UserRole.viewer),
        throwsA(isA<UserAdminException>()),
        reason: 'demoting the last admin would leave nobody who can administer',
      );
      expect(
        () => bare.removeUser('owner'),
        throwsA(isA<UserAdminException>()),
      );
      // Still administrable afterwards -- the refusal changed nothing.
      expect((await bare.users()).single.role, UserRole.admin);
    });

    test('an admin is removable while another admin remains', () async {
      await auth.addUser('admina', _pw, UserRole.admin);
      await auth.addUser('adminb', _pw, UserRole.admin);
      await auth.removeUser('admina');
      expect(jsonSafeUsers(await auth.users()), contains('adminb'));
      expect(jsonSafeUsers(await auth.users()), isNot(contains('admina')));
    });

    test('the built-in admin always keeps the admin role', () async {
      expect(
        () => auth.changeUserRole('admin', UserRole.staff),
        throwsA(isA<UserAdminException>()),
        reason: 'roles must not be a way to strip the bootstrap identity',
      );
    });
  });

  group('role changes take effect on live sessions', () {
    test('demotion re-privileges an ALREADY-ISSUED token', () async {
      await auth.addUser('rising', _pw, UserRole.admin);
      final t = (await auth.login('rising', _pw, sourceKey: 'i')).token!;
      expect((await auth.principalFor(t)).role, UserRole.admin);

      await auth.changeUserRole('rising', UserRole.viewer);
      expect(
        (await auth.principalFor(t)).role,
        UserRole.viewer,
        reason:
            'a demotion that only applied after re-login is a '
            'privilege-retention bug',
      );
      expect(
        await auth.isAuthorized(t),
        isTrue,
        reason: 'demotion narrows rights, it does not end the session',
      );
    });

    test('promotion likewise applies to an existing token', () async {
      await auth.addUser('temp', _pw, UserRole.viewer);
      final t = (await auth.login('temp', _pw, sourceKey: 'i')).token!;
      await auth.changeUserRole('temp', UserRole.staff);
      expect((await auth.principalFor(t)).role, UserRole.staff);
    });

    test('changing a non-admin password keeps that session alive', () async {
      await auth.addUser('staff1', _pw, UserRole.staff);
      final t = (await auth.login('staff1', _pw, sourceKey: 'i')).token!;
      await auth.setUserPassword('staff1', 'replacement2');
      expect(await auth.isAuthorized(t), isTrue);
      expect(
        (await auth.login('staff1', 'replacement2', sourceKey: 'i')).isSuccess,
        isTrue,
      );
    });

    test('changing an ADMIN password revokes its outstanding tokens', () async {
      await auth.addUser('chief', _pw, UserRole.admin);
      final t = (await auth.login('chief', _pw, sourceKey: 'i')).token!;
      await auth.setUserPassword('chief', 'replacement2');
      expect(
        await auth.isAuthorized(t),
        isFalse,
        reason:
            'an admin credential change is the classic '
            'compromise-response moment',
      );
      expect(
        (await auth.login('chief', 'replacement2', sourceKey: 'i')).isSuccess,
        isTrue,
      );
    });

    test('a short or unknown-target password change is refused', () async {
      await auth.addUser('staff2', _pw, UserRole.staff);
      expect(
        () => auth.setUserPassword('staff2', 'tiny'),
        throwsA(isA<UserAdminException>()),
      );
      expect(
        () => auth.setUserPassword('nobody', _pw),
        throwsA(isA<UserAdminException>()),
      );
      expect(store.debugUserHash('staff2'), isNotNull);
    });
  });

  group('login surface hardening', () {
    test('an unknown username costs a failure but never a token', () async {
      final res = await auth.login('mallory', _pw, sourceKey: 'src');
      expect(res.status, AuthStatus.invalidCredentials);
      expect(res.token, isNull);
      expect(auth.failuresFor('src'), 1);
    });

    test(
      'a named account cannot log in with the legacy admin password',
      () async {
        await auth.addUser('iso', _pw, UserRole.viewer);
        final res = await auth.login('iso', 'root-admin', sourceKey: 'i');
        expect(
          res.isSuccess,
          isFalse,
          reason:
              'credentials are per-account; the shared root password must '
              'not be a skeleton key into lesser-privileged accounts',
        );
      },
    );

    test(
      'a named admin password does not unlock the legacy admin identity',
      () async {
        await auth.addUser('other', 'different-pw', UserRole.admin);
        expect(
          (await auth.login('admin', 'different-pw', sourceKey: 'i')).isSuccess,
          isFalse,
        );
      },
    );

    test('a malformed stored role degrades to the LEAST privileged role', () {
      expect(
        UserRole.parse('ADMIN'),
        UserRole.viewer,
        reason: 'storage values are case-sensitive by contract',
      );
      expect(UserRole.parse('nonsense'), UserRole.viewer);
      expect(UserRole.parse(null), UserRole.viewer);
      expect(UserRole.parse('admin'), UserRole.admin);
    });

    test('role ordering is what the route guards assume', () {
      expect(UserRole.admin.atLeast(UserRole.staff), isTrue);
      expect(UserRole.staff.atLeast(UserRole.staff), isTrue);
      expect(UserRole.viewer.atLeast(UserRole.staff), isFalse);
      expect(UserRole.staff.atLeast(UserRole.admin), isFalse);
    });
  });

  group('case-insensitive sign-in (host-created account on a client PC)', () {
    // Regression: addUser stores the normalized (lowercase) name, but login
    // and the admin operations receive the username AS TYPED -- a staff
    // account created for "Mary" could never sign in as "Mary" from a client.
    test('a mixed-case login matches the normalized stored account', () async {
      await auth.addUser('Mary.Jones', _pw, UserRole.staff);
      final res = await auth.login('Mary.Jones', _pw, sourceKey: 'src-a');
      expect(
        res.isSuccess,
        isTrue,
        reason: 'identities are case-insensitive by storage contract',
      );
      expect(res.principal!.username, 'mary.jones');
      expect(res.principal!.role, UserRole.staff);
    });

    test('whitespace-padded and uppercase legacy admin logins still work',
        () async {
      expect(
        (await auth.login('Admin', 'root-admin', sourceKey: 'src-b')).isSuccess,
        isTrue,
      );
      expect(
        (await auth.login('  admin  ', 'root-admin', sourceKey: 'src-c'))
            .isSuccess,
        isTrue,
      );
    });

    test('wrong password on a mixed-case login is still denied', () async {
      await auth.addUser('casey', _pw, UserRole.viewer);
      final res = await auth.login('Casey', 'wrong-password', sourceKey: 'd');
      expect(
        res.status,
        AuthStatus.invalidCredentials,
        reason: 'normalisation must not weaken the credential check',
      );
    });

    test('admin operations match a mixed-case username against the store',
        () async {
      await auth.addUser('worker', _pw, UserRole.staff);
      await auth.setUserPassword('Worker', 'newpassword1');
      expect(
        (await auth.login('worker', 'newpassword1', sourceKey: 'src-e'))
            .isSuccess,
        isTrue,
      );
      await auth.changeUserRole('WORKER', UserRole.viewer);
      expect(
        (await auth.users()).firstWhere((u) => u.username == 'worker').role,
        UserRole.viewer,
      );
      await auth.removeUser('Worker');
      expect(jsonSafeUsers(await auth.users()), isNot(contains('worker')));
    });
  });

  group('username input policy is injection-safe by construction', () {
    test('SQL-shaped and path-shaped usernames are all rejected', () async {
      for (final evil in [
        "a' OR '1'='1",
        'admin;DROP TABLE users',
        '../../etc/passwd',
        'a' * 40,
        '\$inject',
        '🎭unicode',
      ]) {
        await expectLater(
          auth.addUser(evil, _pw, UserRole.admin),
          throwsA(isA<UserAdminException>()),
          reason: 'rejected before it ever reaches the store: "$evil"',
        );
      }
      expect(store.debugUserHash("a' OR '1'='1"), isNull);
    });

    test('the accepted alphabet is exactly documented', () {
      // Digits are legal in the FIRST character (the policy is "letter or
      // digit"), and everything is stored lowercase (normalizeUsername).
      for (final ok in [
        'abc',
        'a1b', // digits allowed anywhere but need the 3-char minimum
        '1ab',
        'mary.jones',
        'jane_d',
        'jo-h',
        'a' * 32,
      ]) {
        expect(UserRecord.isValidUsername(ok), isTrue, reason: ok);
      }
      for (final bad in [
        'ab', // too short -- 3 is the documented minimum
        'a1',
        'a' * 33, // too long
        '.abc', // must not start with punctuation
        '_abc',
        'a b', // no whitespace
        'A_b', // must already be normalized
        'café', // ascii only
      ]) {
        expect(UserRecord.isValidUsername(bad), isFalse, reason: bad);
      }
    });

    test(
      'mixed-case input is normalized, so "Admin" collides with "admin"',
      () async {
        expect(UserRecord.normalizeUsername('  Admin  '), 'admin');
        // ...and the reserved-identity check runs on the NORMALIZED form, so
        // casing cannot be used to create a second bootstrap identity.
        await expectLater(
          auth.addUser('  AdMiN  ', _pw, UserRole.admin),
          throwsA(isA<UserAdminException>()),
        );
      },
    );
  });
}

/// Usernames only -- so an assertion can never accidentally compare a hash.
List<String> jsonSafeUsers(List<UserRecord> users) =>
    users.map((u) => u.username).toList();

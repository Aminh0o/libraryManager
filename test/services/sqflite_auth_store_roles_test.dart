import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/models/user_account.dart';
import 'package:library_manager/services/auth_service.dart';
import 'package:library_manager/services/password_hasher.dart';
import 'package:library_manager/services/sqflite_auth_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Phase 10.1 -- named accounts and token attribution against a REAL SQLite
/// database (the `sqflite_common_ffi` factory), not the in-memory test double.
///
/// The service-level role rules are covered by auth_service_roles_test.dart.
/// This file only proves the things that can ONLY go wrong in a store: a role
/// or attribution that fails to persist, a hash leaking into a read-back, a
/// schema that breaks an upgrade, and the exact degradation a live install
/// depends on after a host restart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late SqfliteAuthStore store;
  late PasswordHasher hasher;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, v) => SqfliteAuthStore(() async => d).ensureSchema(d),
      ),
    );
    store = SqfliteAuthStore(() async => db);
    hasher = PasswordHasher(iterations: 1000);
  });

  tearDown(() async {
    await db.close();
  });

  AuthService service() => AuthService(hasher: hasher, store: store);

  group('users table', () {
    test('listUsers is empty on a fresh database', () async {
      expect(await store.listUsers(), isEmpty);
      expect(await store.userHash('nobody'), isNull);
    });

    test(
      'a row round-trips with its role and never exposes a hash read-side',
      () async {
        await store.upsertUser('libby', 'pbkdf2|sha256|x|y', UserRole.staff);
        final users = await store.listUsers();
        expect(users.containsKey('libby'), isTrue);
        expect(users['libby']!.role, UserRole.staff);
        expect(users['libby']!.createdAt, isNotNull);
        // The read-side record type has no hash field at all, so a projection
        // bug cannot even be written; prove the hash is only reachable via
        // userHash(), which the auth core uses and the API never serializes.
        expect(users['libby']!.toString(), isNot(contains('pbkdf2')));
        expect(await store.userHash('libby'), 'pbkdf2|sha256|x|y');
      },
    );

    test(
      'an upsert preserves created_at (audit trail is not rewritten)',
      () async {
        await store.upsertUser('libby', 'hash-one', UserRole.staff);
        final born = (await store.listUsers())['libby']!.createdAt;
        await store.upsertUser('libby', 'hash-two', UserRole.admin);
        final after = await store.listUsers();
        expect(after['libby']!.role, UserRole.admin, reason: 'role did update');
        expect(
          after['libby']!.createdAt,
          born,
          reason: 'a role/password change must not falsify the creation date',
        );
        expect(await store.userHash('libby'), 'hash-two');
      },
    );

    test('removeUserRow drops the account', () async {
      await store.upsertUser('gone', 'h', UserRole.viewer);
      await store.removeUserRow('gone');
      expect(await store.listUsers(), isEmpty);
      expect(await store.userHash('gone'), isNull);
    });

    test(
      'a corrupt/unknown stored role reads back as the LEAST privileged',
      () async {
        await store.upsertUser('weird', 'h', UserRole.admin);
        // Simulate a legacy writer / tampered row putting junk in `role`.
        await db.update(
          'users',
          {'role': 'supervisor'},
          where: 'username = ?',
          whereArgs: ['weird'],
        );
        expect(
          (await store.listUsers())['weird']!.role,
          UserRole.viewer,
          reason: 'a bad row must never escalate',
        );
      },
    );
  });

  group('token attribution', () {
    test(
      'a legacy token (NULL username) is NOT attributed -- stays admin',
      () async {
        await store.saveTokens({'legacy-token'});
        expect(await store.loadTokens(), contains('legacy-token'));
        expect(
          await store.loadTokenPrincipals(),
          isEmpty,
          reason: 'unattributed rows must not materialize as named principals',
        );
      },
    );

    test(
      'attribution persists and resolves its role through the users table',
      () async {
        await store.saveTokens({'tok-a'});
        await store.saveTokenPrincipals({
          'tok-a': (username: 'libby', role: UserRole.admin),
        });
        await store.upsertUser('libby', 'h', UserRole.staff);

        final p = await store.loadTokenPrincipals();
        expect(p['tok-a']!.username, 'libby');
        expect(
          p['tok-a']!.role,
          UserRole.staff,
          reason:
              'the users table is the live role source, so a demotion '
              'survives a restart without re-writing every token row',
        );
      },
    );

    test(
      'attributing an un-persisted token still survives (row is created)',
      () async {
        // AuthService saves principals for tokens that saveTokens has not yet
        // written (e.g. a role change touching an already-paired token). Losing
        // that attribution would degrade the owner to legacy ADMIN on restart.
        await store.saveTokenPrincipals({
          'early': (username: 'libby', role: UserRole.viewer),
        });
        await store.upsertUser('libby', 'h', UserRole.viewer);
        final p = await store.loadTokenPrincipals();
        expect(
          p['early'],
          isNotNull,
          reason: 'the attribution must be durable, not silently dropped',
        );
        expect(p['early']!.username, 'libby');
        expect(await store.loadTokens(), contains('early'));
      },
    );

    test(
      'clearing attribution for a departed token is a no-op on legacy rows',
      () async {
        await store.saveTokens({'legacy', 'owned'});
        await store.saveTokenPrincipals({
          'owned': (username: 'libby', role: UserRole.staff),
        });
        await store.upsertUser('libby', 'h', UserRole.staff);
        // libby leaves; principals now only holds the remaining owned token.
        await store.saveTokenPrincipals({});
        expect(
          await store.loadTokens(),
          equals({'legacy', 'owned'}),
          reason: 'revoking ATTRIBUTION is not revoking the token',
        );
        expect(await store.loadTokenPrincipals(), isEmpty);
      },
    );
  });

  group('AuthService + SQLite named accounts end-to-end', () {
    test('accounts, roles and sessions all survive a host restart', () async {
      final first = service();
      await first.setPassword('root-pw');
      await first.addUser('libby', 'libby-pw', UserRole.staff);
      final staffToken = (await first.login(
        'libby',
        'libby-pw',
        sourceKey: 'i',
      )).token!;
      final legacyToken = await first
          .login('admin', 'root-pw', sourceKey: 'i')
          .then((r) => r.token!);

      // Brand-new service over the same persisted database == app restart.
      final restarted = service();
      expect(jsonSafe(await restarted.users()), contains('libby'));
      expect((await restarted.principalFor(staffToken)).role, UserRole.staff);
      expect((await restarted.principalFor(staffToken)).username, 'libby');
      expect(await restarted.isAuthorized(staffToken), isTrue);
      expect(await restarted.isAuthorized(legacyToken), isTrue);
      expect((await restarted.principalFor(legacyToken)).role, UserRole.admin);
    });

    test(
      'a demotion taken on the live service is what the restart reports',
      () async {
        final first = service();
        await first.setPassword('root-pw');
        await first.addUser('libby', 'libby-pw', UserRole.staff);
        final t = (await first.login(
          'libby',
          'libby-pw',
          sourceKey: 'i',
        )).token!;
        await first.changeUserRole('libby', UserRole.viewer);

        expect((await service().principalFor(t)).role, UserRole.viewer);
      },
    );

    test(
      'deleting an account revokes its sessions across the restart',
      () async {
        final first = service();
        await first.setPassword('root-pw');
        await first.addUser('temp', 'temp-pw-1', UserRole.viewer);
        await first.addUser('boss', 'boss-pw-1', UserRole.admin);
        final gone = (await first.login(
          'temp',
          'temp-pw-1',
          sourceKey: 'i',
        )).token!;
        await first.removeUser('temp');

        final restarted = service();
        expect(await restarted.isAuthorized(gone), isFalse);
        expect(jsonSafe(await restarted.users()), isNot(contains('temp')));
      },
    );

    test(
      'the legacy shared credential still authenticates when users exist',
      () async {
        final auth = service();
        await auth.setPassword('root-pw');
        await auth.addUser('someone', 'someone-pw', UserRole.viewer);
        final r = await auth.login('admin', 'root-pw', sourceKey: 'i');
        expect(r.isSuccess, isTrue);
        expect(r.principal!.role, UserRole.admin);
      },
    );
  });
}

List<String> jsonSafe(List<UserRecord> users) =>
    users.map((u) => u.username).toList();

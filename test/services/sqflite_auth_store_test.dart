import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/services/auth_service.dart';
import 'package:library_manager/services/password_hasher.dart';
import 'package:library_manager/services/sqflite_auth_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late DatabaseFactory factory;

  setUp(() async {
    factory = databaseFactoryFfi;
    db = await factory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, v) => SqfliteAuthStore(() async => d).ensureSchema(d),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('SqfliteAuthStore', () {
    test('no credential until one is saved', () async {
      final store = SqfliteAuthStore(() async => db);
      expect(await store.loadCredential(), isNull);
    });

    test('credential round-trips and overwrites', () async {
      final store = SqfliteAuthStore(() async => db);
      await store.saveCredential('hash-1');
      expect(await store.loadCredential(), 'hash-1');
      await store.saveCredential('hash-2');
      expect(await store.loadCredential(), 'hash-2');
    });

    test('empty stored credential reads back as null', () async {
      final store = SqfliteAuthStore(() async => db);
      await store.saveCredential('x');
      await store.saveCredential('');
      expect(await store.loadCredential(), isNull);
    });

    test('token set round-trips, adds and removes', () async {
      final store = SqfliteAuthStore(() async => db);
      expect(await store.loadTokens(), isEmpty);

      await store.saveTokens({'a', 'b'});
      expect(await store.loadTokens(), equals({'a', 'b'}));

      // Replace: drop 'a', add 'c' -> {b, c}
      await store.saveTokens({'b', 'c'});
      expect(await store.loadTokens(), equals({'b', 'c'}));

      await store.saveTokens({});
      expect(await store.loadTokens(), isEmpty);
    });

    test('ensureSchema is idempotent', () async {
      final store = SqfliteAuthStore(() async => db);
      await store.ensureSchema(db);
      await store.ensureSchema(db);
      expect(await store.loadTokens(), isEmpty);
    });
  });

  group('AuthService + SQLite store end-to-end', () {
    test('tokens survive a service restart (same database)', () async {
      final hasher = PasswordHasher(iterations: 1000);
      final first = AuthService(
        hasher: hasher,
        store: SqfliteAuthStore(() async => db),
      );
      await first.setPassword('correct horse');
      final token = await first.issueToken();
      expect(await first.isAuthorized(token), isTrue);

      // Simulate app restart: brand-new service over the same persisted DB.
      final restarted = AuthService(
        hasher: hasher,
        store: SqfliteAuthStore(() async => db),
      );
      expect(await restarted.hasCredential(), isTrue);
      expect(await restarted.verifyPassword('correct horse'), isTrue);
      expect(
        await restarted.isAuthorized(token),
        isTrue,
        reason: 'issued token must persist across restart',
      );
    });

    test('revocation persists across restart', () async {
      final hasher = PasswordHasher(iterations: 1000);
      final store = SqfliteAuthStore(() async => db);
      final first = AuthService(hasher: hasher, store: store);
      final token = await first.issueToken();
      await first.revokeToken(token);

      final restarted = AuthService(hasher: hasher, store: store);
      expect(await restarted.isAuthorized(token), isFalse);
    });
  });
}

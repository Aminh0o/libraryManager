import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/services/auth_service.dart';
import 'package:library_manager/services/repository.dart';

// verifyAdminPassword never touches the repository, so an inert fake is enough.
class _FakeRepo implements LibraryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// FE2-11: the sensitive host actions (unlock settings / view history / erase /
/// reset) were gated by [LibraryProvider.checkPassword], whose empty local
/// SharedPreferences default returned `true` for ANY input — so anyone at the
/// host machine could reconfigure or wipe it without knowing the admin password.
/// The fix routes those gates through [LibraryProvider.verifyAdminPassword],
/// which checks the SERVER-side salted credential (the same one the LAN API
/// enforces), while preserving the documented bootstrap-open state until a
/// password is actually configured.
void main() {
  group('LibraryProvider.verifyAdminPassword (FE2-11)', () {
    test(
      'host with a configured password rejects wrong/blank, accepts real',
      () async {
        final auth = AuthService(store: InMemoryAuthStore());
        await auth.setPassword('s3cret');
        final provider = LibraryProvider.forTesting(
          repository: _FakeRepo(),
          isHost: true,
          authService: auth,
        );

        // The old hole is still demonstrably weak: with no LOCAL password stored,
        // checkPassword accepts everything...
        expect(provider.checkPassword(''), isTrue);
        expect(provider.checkPassword('guess'), isTrue);

        // ...but the authoritative gate now demands the real server credential.
        expect(await provider.verifyAdminPassword('wrong'), isFalse);
        expect(await provider.verifyAdminPassword(''), isFalse);
        expect(await provider.verifyAdminPassword('s3cret'), isTrue);
      },
    );

    test(
      'host with NO credential runs bootstrap-open (operator not locked out)',
      () async {
        final auth = AuthService(store: InMemoryAuthStore());
        final provider = LibraryProvider.forTesting(
          repository: _FakeRepo(),
          isHost: true,
          authService: auth,
        );

        // Nothing is protected until a password is set — matches the LAN server's
        // own enforcement-off default, so an unconfigured host is never bricked.
        expect(await provider.verifyAdminPassword('anything'), isTrue);
      },
    );

    test(
      'client delegates to the local gate and never consults the server',
      () async {
        // No authService injected: if the client path reached _hostAuthService it
        // would build a real DB-backed service and throw. Returning the local
        // result proves it stays client-side (server routes are token-guarded).
        final provider = LibraryProvider.forTesting(
          repository: _FakeRepo(),
          isHost: false,
        );
        expect(await provider.verifyAdminPassword('whatever'), isTrue);
      },
    );
  });

  // FE2-11 (change-password leg): the old-password step must be driven by the
  // AUTHORITATIVE enforcement state, not the blankable local prefs copy.
  group('LibraryProvider.passwordEnforcementActive (FE2-11)', () {
    test('host reports TRUE only once a server credential exists', () async {
      final auth = AuthService(store: InMemoryAuthStore());
      final provider = LibraryProvider.forTesting(
        repository: _FakeRepo(),
        isHost: true,
        authService: auth,
      );
      // Bootstrap: no credential yet -> first-time setup asks for no old pw.
      expect(await provider.passwordEnforcementActive(), isFalse);

      await auth.setPassword('s3cret');
      // Now enforced -> changing the password must prove the current one,
      // EVEN IF the local prefs copy is still empty (the old bypass).
      expect(provider.checkPassword(''), isTrue); // local gate still weak
      expect(await provider.passwordEnforcementActive(), isTrue);
    });

    test('client reflects the local gate and never touches the server', () async {
      // No authService injected: a client reaching _hostAuthService would build
      // a DB-backed service and throw. A clean false proves it stays local.
      final provider = LibraryProvider.forTesting(
        repository: _FakeRepo(),
        isHost: false,
      );
      expect(await provider.passwordEnforcementActive(), isFalse);
    });
  });
}

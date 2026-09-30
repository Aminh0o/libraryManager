import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/services/auth_service.dart';
import 'package:library_manager/services/password_hasher.dart';

// A deliberately cheap hasher so the suite stays fast; correctness of PBKDF2
// itself is covered by password_hasher_test.dart.
PasswordHasher _fastHasher() => PasswordHasher(iterations: 1000);

class _FakeClock {
  DateTime now;
  _FakeClock(this.now);
  void advance(Duration d) => now = now.add(d);
}

void main() {
  group('AuthService credential storage', () {
    test('setPassword stores a salted hash, never the raw password', () async {
      final store = InMemoryAuthStore();
      final auth = AuthService(hasher: _fastHasher(), store: store);
      await auth.setPassword('s3cr3t');

      final stored = await store.loadCredential();
      expect(stored, isNotNull);
      expect(stored, isNot('s3cr3t'));
      expect(stored, startsWith('pbkdf2|sha256|'));
      expect(await auth.hasCredential(), isTrue);
    });

    test('verifyPassword accepts correct and rejects wrong password', () async {
      final auth = AuthService(hasher: _fastHasher(), store: InMemoryAuthStore());
      await auth.setPassword('hunter2');
      expect(await auth.verifyPassword('hunter2'), isTrue);
      expect(await auth.verifyPassword('hunter3'), isFalse);
    });

    test('verifyPassword is false when no credential exists', () async {
      final auth = AuthService(hasher: _fastHasher(), store: InMemoryAuthStore());
      expect(await auth.verifyPassword('anything'), isFalse);
    });

    test('setPassword rejects empty password', () async {
      final auth = AuthService(hasher: _fastHasher(), store: InMemoryAuthStore());
      expect(() => auth.setPassword(''), throwsA(isA<ArgumentError>()));
    });

    test('reset clears credential and all tokens', () async {
      final auth = AuthService(hasher: _fastHasher(), store: InMemoryAuthStore());
      await auth.setPassword('abc123');
      final token = await auth.issueToken();
      expect(await auth.isAuthorized(token), isTrue);

      await auth.reset();
      expect(await auth.hasCredential(), isFalse);
      expect(await auth.isAuthorized(token), isFalse);
    });
  });

  group('AuthService tokens', () {
    test('successful login mints a usable bearer token', () async {
      final auth = AuthService(hasher: _fastHasher(), store: InMemoryAuthStore());
      await auth.setPassword('pw');
      final res = await auth.login('admin', 'pw', sourceKey: '10.0.0.2');
      expect(res.isSuccess, isTrue);
      expect(res.token, isNotNull);
      expect(await auth.isAuthorized(res.token), isTrue);
    });

    test('wrong username or password is denied without a token', () async {
      final auth = AuthService(hasher: _fastHasher(), store: InMemoryAuthStore());
      await auth.setPassword('pw');
      final bad = await auth.login('admin', 'nope', sourceKey: 'ip');
      expect(bad.status, AuthStatus.invalidCredentials);
      expect(bad.token, isNull);
      final otherUser = await auth.login('root', 'pw', sourceKey: 'ip');
      expect(otherUser.isSuccess, isFalse);
    });

    test('issued tokens are unique and unpredictable', () async {
      final auth = AuthService(hasher: _fastHasher(), store: InMemoryAuthStore());
      final a = await auth.issueToken();
      final b = await auth.issueToken();
      expect(a, isNot(b));
      expect(a.length, greaterThanOrEqualTo(32));
    });

    test('revokeToken removes authorization', () async {
      final auth = AuthService(hasher: _fastHasher(), store: InMemoryAuthStore());
      final t = await auth.issueToken();
      await auth.revokeToken(t);
      expect(await auth.isAuthorized(t), isFalse);
    });

    test('null/empty token is never authorized', () async {
      final auth = AuthService(hasher: _fastHasher(), store: InMemoryAuthStore());
      expect(await auth.isAuthorized(null), isFalse);
      expect(await auth.isAuthorized(''), isFalse);
    });

    test('tokens persist across service restart (shared store)', () async {
      final store = InMemoryAuthStore();
      final first = AuthService(hasher: _fastHasher(), store: store);
      final t = await first.issueToken();

      final second = AuthService(hasher: _fastHasher(), store: store);
      expect(await second.isAuthorized(t), isTrue);
    });
  });

  group('AuthService brute-force throttle', () {
    test('locks after maxFailedAttempts and refuses even correct password', () async {
      final clock = _FakeClock(DateTime(2026, 1, 1));
      final auth = AuthService(
        hasher: _fastHasher(),
        store: InMemoryAuthStore(),
        maxFailedAttempts: 3,
        lockoutWindow: const Duration(seconds: 60),
        now: () => clock.now,
      );
      await auth.setPassword('right');

      for (var i = 0; i < 3; i++) {
        final r = await auth.login('admin', 'wrong', sourceKey: 'attacker');
        expect(r.status, i == 2 ? AuthStatus.locked : AuthStatus.invalidCredentials);
      }

      // Locked: a correct password during the window is refused.
      final during = await auth.login('admin', 'right', sourceKey: 'attacker');
      expect(during.status, AuthStatus.locked);
      expect(during.retryAfter, isNotNull);

      // After the window elapses, the correct password works again.
      clock.advance(const Duration(seconds: 61));
      final after = await auth.login('admin', 'right', sourceKey: 'attacker');
      expect(after.isSuccess, isTrue);
    });

    test('lockout is per source key (no cross-IP DoS)', () async {
      final auth = AuthService(
        hasher: _fastHasher(),
        store: InMemoryAuthStore(),
        maxFailedAttempts: 2,
        lockoutWindow: const Duration(seconds: 60),
      );
      await auth.setPassword('pw');
      await auth.login('admin', 'x', sourceKey: 'bad-ip');
      await auth.login('admin', 'x', sourceKey: 'bad-ip'); // now locked for bad-ip
      final locked = await auth.login('admin', 'x', sourceKey: 'bad-ip');
      expect(locked.status, AuthStatus.locked);

      // A different source is unaffected.
      final other = await auth.login('admin', 'pw', sourceKey: 'good-ip');
      expect(other.isSuccess, isTrue);
    });

    test('successful login resets the failure counter', () async {
      final auth = AuthService(
        hasher: _fastHasher(),
        store: InMemoryAuthStore(),
        maxFailedAttempts: 3,
        lockoutWindow: const Duration(seconds: 60),
      );
      await auth.setPassword('pw');
      await auth.login('admin', 'wrong', sourceKey: 'ip');
      await auth.login('admin', 'wrong', sourceKey: 'ip');
      expect(auth.failuresFor('ip'), 2);
      await auth.login('admin', 'pw', sourceKey: 'ip');
      expect(auth.failuresFor('ip'), 0);
    });
  });
}

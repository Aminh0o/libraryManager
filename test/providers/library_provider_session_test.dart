import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:library_manager/models/user_account.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/services/api_service.dart';
import 'package:library_manager/services/repository.dart';

// Phase 10.1c: the DYNAMIC role surface the UI reads. These pin that a client
// mirrors the identity/role its ApiService holds, that signing out forgets the
// credential and demotes the device to read-only (so affordances disappear
// immediately), that the host is always administrator and cannot sign itself
// out, and that a non-admin is refused account management BEFORE a request is
// even attempted (the route guard stays the real enforcement point).

class _FakeRepo implements LibraryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

ApiService _client(
  UserRole role, {
  String? user = 'someone',
  String? token = 'tok',
}) => ApiService(hostIp: '127.0.0.1', port: 8080, authToken: token)
  ..sessionRole = role
  ..sessionUsername = user;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'clientToken': 'tok'}));

  group('client session getters', () {
    test('staff can write but cannot administer', () {
      final provider = LibraryProvider.forTesting(
        repository: _client(UserRole.staff),
        isHost: false,
      );
      expect(provider.canWrite, isTrue);
      expect(provider.canAdminister, isFalse);
      expect(provider.hasSession, isTrue);
      expect(provider.sessionRole, UserRole.staff);
    });

    test('viewer can neither write nor administer', () {
      final provider = LibraryProvider.forTesting(
        repository: _client(UserRole.viewer),
        isHost: false,
      );
      expect(provider.canWrite, isFalse);
      expect(provider.canAdminister, isFalse);
    });

    test('no session (no username) reads as signed-out', () {
      final provider = LibraryProvider.forTesting(
        repository: _client(UserRole.admin, user: null, token: null),
        isHost: false,
      );
      expect(provider.hasSession, isFalse);
    });

    test(
      'a restored token with an unknown role defaults to viewer, not admin',
      () {
        // Guards against a client forging more privileges than the host grants.
        final provider = LibraryProvider.forTesting(
          repository: _FakeRepo(),
          isHost: false,
        );
        expect(provider.sessionRole, UserRole.viewer);
        expect(provider.canAdminister, isFalse);
      },
    );
  });

  test(
    'signOut forgets the credential and demotes the device to read-only',
    () async {
      final api = _client(UserRole.admin);
      final provider = LibraryProvider.forTesting(
        repository: api,
        isHost: false,
      );
      expect(provider.canAdminister, isTrue);

      await provider.signOut();

      expect(api.authToken, isNull);
      expect(api.sessionUsername, isNull);
      expect(api.sessionRole, UserRole.viewer);
      expect(provider.hasSession, isFalse);
      expect(provider.canWrite, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('clientToken'), isNull);
    },
  );

  test('the host is always administrator and cannot sign itself out', () async {
    final provider = LibraryProvider.forTesting(
      repository: _FakeRepo(),
      isHost: true,
    );
    expect(provider.canAdminister, isTrue);
    await provider.signOut(); // no-op on the host
    expect(provider.canAdminister, isTrue);
  });

  test(
    'a non-admin client is refused account management before any request',
    () async {
      final provider = LibraryProvider.forTesting(
        repository: _client(UserRole.staff),
        isHost: false,
      );
      await expectLater(
        provider.listUsers(),
        throwsA(isA<UserAdminException>()),
      );
    },
  );
}

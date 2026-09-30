import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:library_manager/l10n/app_localizations.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/screens/password_management_screen.dart';
import 'package:library_manager/services/auth_service.dart';
import 'package:library_manager/services/repository.dart';

// FE2-11 (change-password leg): the old-password step used to be checked with
// the weak local `checkPassword`, which returns true for ANY input when the
// local SharedPreferences copy is blank — so a host whose real credential lived
// only server-side could overwrite or reset it without ever proving knowledge
// of it. These tests drive the real screen against an injected authoritative
// AuthService (no DB touched) and pin the fixed behavior: enforcement state
// comes from the server credential, and the old password is verified against
// it BEFORE any change is attempted.

class _FakeRepo implements LibraryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> _pumpScreen(WidgetTester tester, LibraryProvider provider) async {
  tester.view.physicalSize = const Size(1280, 1024);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<LibraryProvider>.value(
      value: provider,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // The real screen is always pushed as a secondary route and POP itself
        // on success; host it the same way so the post-pop SnackBar (shown via
        // the root ScaffoldMessenger) stays observable on the sentinel route.
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PasswordManagementScreen(),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  // initState's async enforcement lookup resolves on the first frames.
  await tester.pumpAndSettle();
}

/// Types into the [TextFormField] carrying [fieldKey] (enterText walks from an
/// ancestor widget down to its EditableText automatically).
Future<void> _type(WidgetTester tester, Key fieldKey, String value) async {
  await tester.enterText(find.byKey(fieldKey), value);
}

void main() {
  setUp(() {
    // changePassword writes the (client-side) SHA-256 copy to prefs; mock it so
    // no plugin channel is needed.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('enforced credential + WRONG old password: change is blocked', (
    tester,
  ) async {
    final auth = AuthService(store: InMemoryAuthStore());
    await auth.setPassword('s3cret');
    final provider = LibraryProvider.forTesting(
      repository: _FakeRepo(),
      isHost: true,
      authService: auth,
    );
    await _pumpScreen(tester, provider);

    // Enforcement is server-authoritative: the old field appears even though
    // this host's LOCAL prefs copy is blank (the old bypass window).
    expect(find.byKey(const Key('oldPassword')), findsOneWidget);

    await _type(tester, const Key('oldPassword'), 'wrong');
    await _type(tester, const Key('newPassword'), 'newpass');
    await _type(tester, const Key('confirmPassword'), 'newpass');
    await tester.tap(find.byKey(const Key('savePassword')));
    await tester.pump(); // let the async submit handler run

    expect(find.text('Wrong Password'), findsOneWidget);
    // The server credential is untouched — the change never reached submit.
    expect(await auth.verifyPassword('newpass'), isFalse);
    expect(await auth.verifyPassword('s3cret'), isTrue);
  });

  testWidgets('enforced credential + CORRECT old password: change succeeds', (
    tester,
  ) async {
    final auth = AuthService(store: InMemoryAuthStore());
    await auth.setPassword('s3cret');
    final provider = LibraryProvider.forTesting(
      repository: _FakeRepo(),
      isHost: true,
      authService: auth,
    );
    await _pumpScreen(tester, provider);

    expect(find.byKey(const Key('oldPassword')), findsOneWidget);
    await _type(tester, const Key('oldPassword'), 's3cret');
    await _type(tester, const Key('newPassword'), 'newpass');
    await _type(tester, const Key('confirmPassword'), 'newpass');
    await tester.tap(find.byKey(const Key('savePassword')));
    await tester.pump(); // handler runs verify + change before popping
    await tester.pumpAndSettle(); // pop / snackbar animation

    expect(await auth.verifyPassword('newpass'), isTrue);
    expect(await auth.verifyPassword('s3cret'), isFalse);
    expect(find.text('Password updated successfully'), findsOneWidget);
  });

  testWidgets(
    'bootstrap (no credential yet): no old-password step, set directly',
    (tester) async {
      final auth = AuthService(store: InMemoryAuthStore());
      final provider = LibraryProvider.forTesting(
        repository: _FakeRepo(),
        isHost: true,
        authService: auth,
      );
      await _pumpScreen(tester, provider);

      // First-time setup must never demand an old password that does not exist.
      expect(find.byKey(const Key('oldPassword')), findsNothing);
      expect(find.byKey(const Key('newPassword')), findsOneWidget);

      await _type(tester, const Key('newPassword'), 'firstpw');
      await _type(tester, const Key('confirmPassword'), 'firstpw');
      await tester.tap(find.byKey(const Key('savePassword')));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(await auth.verifyPassword('firstpw'), isTrue);
      expect(await provider.passwordEnforcementActive(), isTrue);
    },
  );
}

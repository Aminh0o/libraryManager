import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:library_manager/l10n/app_localizations.dart';
import 'package:library_manager/models/user_account.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/screens/users_roles_screen.dart';
import 'package:library_manager/services/auth_service.dart';
import 'package:library_manager/services/repository.dart';

// Phase 10.1c: the Users & Roles SURFACE. These tests drive the real screen
// against an injected authoritative AuthService (no DB, no socket) to pin that
// (1) a read-only session is shown no management affordance at all, (2) an
// administrator sees exactly the named accounts the auth core holds, and (3)
// the create-account dialog writes THROUGH that core — so the UI can never
// drift from (or bypass) the rules the server enforces. A client-side
// validation failure must block the mutation outright.

class _FakeRepo implements LibraryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> _pump(WidgetTester tester, LibraryProvider provider) async {
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
        home: const UsersRolesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a read-only (viewer) session is offered no management surface',
      (tester) async {
    // A client whose repository is not an ApiService resolves to the least
    // privileged role, so the screen must hide the list AND the create button.
    final provider = LibraryProvider.forTesting(
      repository: _FakeRepo(),
      isHost: false,
    );
    await _pump(tester, provider);

    expect(
      find.text('Only an administrator can manage accounts and roles.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('createAccountButton')), findsNothing);
  });

  testWidgets('a host administrator sees exactly the named accounts',
      (tester) async {
    final auth = AuthService(store: InMemoryAuthStore());
    await auth.addUser('librarian', 'password123', UserRole.staff);
    await auth.addUser('kiosk', 'password123', UserRole.viewer);
    final provider = LibraryProvider.forTesting(
      repository: _FakeRepo(),
      isHost: true,
      authService: auth,
    );
    await _pump(tester, provider);

    expect(find.byKey(const Key('user-librarian')), findsOneWidget);
    expect(find.byKey(const Key('user-kiosk')), findsOneWidget);
    expect(find.byKey(const Key('createAccountButton')), findsOneWidget);
  });

  testWidgets('the create dialog writes through the real auth core',
      (tester) async {
    final auth = AuthService(store: InMemoryAuthStore());
    await auth.addUser('librarian', 'password123', UserRole.staff);
    final provider = LibraryProvider.forTesting(
      repository: _FakeRepo(),
      isHost: true,
      authService: auth,
    );
    await _pump(tester, provider);

    await tester.tap(find.byKey(const Key('createAccountButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('createUsername')), 'counter2');
    await tester.enterText(
        find.byKey(const Key('createPassword')), 'password123');
    await tester.tap(find.byKey(const Key('createSubmit')));
    await tester.pumpAndSettle();

    final names = (await auth.users()).map((u) => u.username).toSet();
    expect(names, contains('counter2'));
    expect(find.byKey(const Key('user-counter2')), findsOneWidget);
  });

  testWidgets('a too-short password is refused before any write happens',
      (tester) async {
    final auth = AuthService(store: InMemoryAuthStore());
    await auth.addUser('librarian', 'password123', UserRole.staff);
    final provider = LibraryProvider.forTesting(
      repository: _FakeRepo(),
      isHost: true,
      authService: auth,
    );
    await _pump(tester, provider);

    await tester.tap(find.byKey(const Key('createAccountButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('createUsername')), 'okuser');
    await tester.enterText(find.byKey(const Key('createPassword')), 'short');
    await tester.tap(find.byKey(const Key('createSubmit')));
    await tester.pumpAndSettle();

    // The form stays open (validation blocked submission) and nothing is
    // persisted — the weak credential never reaches the core.
    expect(find.byKey(const Key('createSubmit')), findsOneWidget);
    final names = (await auth.users()).map((u) => u.username).toSet();
    expect(names, isNot(contains('okuser')));
  });
}

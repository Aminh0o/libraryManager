import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:library_manager/l10n/app_localizations.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/models/loan.dart';
import 'package:library_manager/models/member.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/screens/onboarding_screen.dart';
import 'package:library_manager/services/repository.dart';

// Phase K (frontend reconstruction) guard: the setup wizard is the FIRST
// screen a new install ever shows, and its finish path performs real writes
// (password change + setup-complete flag + navigation). These tests drive the
// rebuilt (tokenized) wizard end-to-end against the real provider to pin:
// (1) the step sequence renders in order, (2) the password step VALIDATES
// before advancing, (3) Finish persists the credential + the setup flag and
// replaces the route with the app, and (4) Back navigates. Presentation was
// rebuilt; none of this behavior may have drifted.
class _EmptyRepo implements LibraryRepository {
  @override
  Future<List<LibraryItem>> getItems(
          {int limit = 1000,
          int offset = 0,
          String? search,
          String? status,
          String? codeType,
    String? sort,
    bool ascending = true,
  }) async =>
      const [];
  @override
  Future<int> countItems({String? search, String? status, String? codeType,
    String? sort,
    bool ascending = true,
  }) async => 0;
  @override
  Future<List<Map<String, dynamic>>> getCodeDefinitions() async => const [];
  @override
  Future<List<Map<String, dynamic>>> getAttributeDefinitions(String? type) async => const [];
  @override
  Future<Map<String, dynamic>> getStats() async => const {};
  @override
  Future<List<Member>> getMembers() async => const [];
  @override
  Future<List<Loan>> getLoans({bool activeOnly = false}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<LibraryProvider> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final provider =
      LibraryProvider.forTesting(repository: _EmptyRepo(), isHost: false);
  await tester.pumpWidget(
    ChangeNotifierProvider<LibraryProvider>.value(
      value: provider,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        initialRoute: '/onboarding',
        routes: {
          '/onboarding': (_) => const OnboardingScreen(),
          '/': (_) => const Scaffold(body: Text('HOME-REACHED')),
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return provider;
}

Finder passwordField() => find.ancestor(
    of: find.byIcon(Icons.lock_outline), matching: find.byType(TextFormField));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'locale': 'en'}));

  testWidgets('the wizard walks every step and Finish persists + navigates',
      (tester) async {
    await _pump(tester);

    // Step 1: welcome with the triple-language greeting + language buttons.
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('العربية'), findsOneWidget);

    // Step 2: password.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.security_outlined), findsOneWidget);

    await tester.enterText(passwordField(), 'admin123');
    await tester.pump();

    // Step 3: configuration summary.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.tune_outlined), findsOneWidget);

    // Step 4: final, now offering Finish.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();

    // The real writes happened: hashed credential + setup flag, then the
    // route was REPLACED with the app (pushReplacementNamed('/')).
    expect(find.text('HOME-REACHED'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('is_setup_complete'), isTrue);
    expect(
      prefs.getString('adminPassword'),
      sha256.convert(utf8.encode('admin123')).toString(),
    );
  });

  testWidgets('an empty password blocks the step (validator, not a fake gate)',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.security_outlined), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Required field'), findsOneWidget);
    // Still on the password step: the wizard did NOT advance.
    expect(find.byIcon(Icons.security_outlined), findsOneWidget);
    expect(find.byIcon(Icons.tune_outlined), findsNothing);
  });

  testWidgets('Back returns to the previous step', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.security_outlined), findsOneWidget);

    await tester.tap(find.text('Cancel')); // the Back affordance
    await tester.pumpAndSettle();

    expect(find.text('Welcome'), findsOneWidget);
    expect(find.byIcon(Icons.security_outlined), findsNothing);
  });

  testWidgets('the language buttons drive the shared provider locale',
      (tester) async {
    final provider = await _pump(tester);
    // forTesting defaults to 'fr' (no prefs read); establish baseline.
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(provider.locale.languageCode, 'en');

    await tester.tap(find.text('Français'));
    await tester.pumpAndSettle();
    expect(provider.locale.languageCode, 'fr');

    await tester.tap(find.text('العربية'));
    await tester.pumpAndSettle();
    expect(provider.locale.languageCode, 'ar');
  });
}

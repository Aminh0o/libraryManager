import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:library_manager/l10n/app_localizations.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/models/loan.dart';
import 'package:library_manager/models/member.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/providers/appearance_controller.dart';
import 'package:library_manager/services/feature_flags.dart';
import 'package:library_manager/screens/settings_screen.dart';
import 'package:library_manager/services/repository.dart';

// Phase 14/17: prove the new Settings-center surfaces are genuinely wired --
// not decorative. The appearance picker must drive the shared
// [AppearanceController], the flag console must drive the shared
// [FeatureFlags], and -- crucially -- turning the "appearance" flag off must
// actually hide the appearance section (otherwise the flag is a lie).
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

class _Harness {
  _Harness(this.provider, this.appearance, this.flags);
  final LibraryProvider provider;
  final AppearanceController appearance;
  final FeatureFlags flags;
}

Future<_Harness> _pump(WidgetTester tester,
    {required bool isHost, Map<String, Object> prefs = const {}}) async {
  tester.view.physicalSize = const Size(1200, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);

  final provider =
      LibraryProvider.forTesting(repository: _EmptyRepo(), isHost: isHost);
  final appearance = await AppearanceController.load();
  final flags = await FeatureFlags.load();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryProvider>.value(value: provider),
        ChangeNotifierProvider<AppearanceController>.value(value: appearance),
        ChangeNotifierProvider<FeatureFlags>.value(value: flags),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(provider, appearance, flags);
}

void main() {
  // Phase J: Settings is a category layout; open a category before asserting
  // the wiring inside it. The assertions themselves are unchanged.
  Future<void> openCat(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(Key('settingsCat_$id')));
    await tester.pumpAndSettle();
  }

  testWidgets('appearance + feature sections are shown for a host (flag on)',
      (tester) async {
    await _pump(tester, isHost: true);
    expect(find.text('Appearance'), findsOneWidget); // category nav entry
    await openCat(tester, 'appearance');
    expect(find.text('Accent color'), findsOneWidget);
    await openCat(tester, 'advanced');
    expect(find.text('Features'), findsOneWidget);
  });

  testWidgets('the appearance section hides when its feature flag is off',
      (tester) async {
    await _pump(
      tester,
      isHost: true,
      prefs: {'feature.flag.appearanceSettings': false},
    );
    expect(find.text('Appearance'), findsNothing);
    // The rest of Settings still renders.
    expect(find.text('Connection mode'), findsOneWidget);
  });

  testWidgets('picking an accent swatch updates the shared controller',
      (tester) async {
    final h = await _pump(tester, isHost: true);
    expect(h.appearance.seedValue, AppearanceController.defaultSeedValue);

    await openCat(tester, 'appearance');
    await tester.tap(find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == 'Indigo'));
    await tester.pumpAndSettle();

    expect(h.appearance.seedValue, 0xFF3F51B5);
  });

  testWidgets('the theme segmented control switches the shared controller',
      (tester) async {
    final h = await _pump(tester, isHost: true);
    expect(h.appearance.themeMode, ThemeMode.system);

    await openCat(tester, 'appearance');
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(h.appearance.themeMode, ThemeMode.dark);
  });

  testWidgets('a non-admin (client) sees no feature console and no brand field',
      (tester) async {
    await _pump(tester, isHost: false);
    // Appearance is per-device and shown to everyone, but the admin-only
    // surfaces (the flag console + the white-label brand field) are gated.
    expect(find.text('Features'), findsNothing);
    expect(find.text('Brand name'), findsNothing);
  });

  testWidgets('toggling the appearance flag in the console really hides it',
      (tester) async {
    final h = await _pump(tester, isHost: true);
    expect(find.text('Appearance'), findsOneWidget);

    await openCat(tester, 'advanced');
    final appearanceSwitch = find.descendant(
      of: find.widgetWithText(SwitchListTile, 'Appearance / white-label settings'),
      matching: find.byType(Switch),
    );
    await tester.tap(appearanceSwitch);
    await tester.pumpAndSettle();

    expect(h.flags.isEnabled('appearanceSettings'), isFalse);
    // The gate is honest: the section it names disappears live.
    expect(find.text('Appearance'), findsNothing);
  });

  // Phase J surface, pinned here: the cross-category search must genuinely
  // reach into a category the operator never opened, and clearing it must
  // restore the plain category layout.
  testWidgets('settings search surfaces a matching setting from a closed '
      'category and clearing restores the layout', (tester) async {
    await _pump(tester, isHost: true);
    expect(find.text('Accent color'), findsNothing);

    await tester.enterText(find.byKey(const Key('settingsSearch')), 'accent');
    await tester.pumpAndSettle();
    expect(find.text('Accent color'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('settingsSearch')), '');
    await tester.pumpAndSettle();
    expect(find.text('Accent color'), findsNothing);
    expect(find.byKey(const Key('settingsCat_appearance')), findsOneWidget);
  });
}

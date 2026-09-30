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

// FE2-11 residual: the host-only admin/destructive tiles (Backup, Restore
// Database, Import, Manage variables, History, Admin password, and the Danger
// Zone 'Erase All Database' / reset-onboarding) were gated on the MUTABLE draft
// `_isHost` (the radio the operator is editing), not the COMMITTED role. So a
// CLIENT who merely unlocked editing and tapped the "Host" radio saw Erase/
// Restore/Reset appear even though the machine is still a client. They are now
// gated on `provider.isHost`, so flipping the unsaved radio cannot reveal them.
class _EmptyRepo implements LibraryRepository {
  @override
  Future<List<LibraryItem>> getItems({
    int limit = 1000,
    int offset = 0,
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) async => const [];
  @override
  Future<int> countItems({
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) async => 0;
  @override
  Future<List<Map<String, dynamic>>> getCodeDefinitions() async => const [];
  @override
  Future<List<Map<String, dynamic>>> getAttributeDefinitions(
    String? type,
  ) async => const [];
  @override
  Future<Map<String, dynamic>> getStats() async => const {};
  @override
  Future<List<Member>> getMembers() async => const [];
  @override
  Future<List<Loan>> getLoans({bool activeOnly = false}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> _pump(WidgetTester tester, {required bool isHost}) async {
  tester.view.physicalSize = const Size(
    1200,
    2400,
  ); // tall so the scroll view builds all tiles
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final provider = LibraryProvider.forTesting(
    repository: _EmptyRepo(),
    isHost: isHost,
  );
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
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Phase J: Settings is a category layout; the host-only groups live in
  // their own categories. The assertions themselves are unchanged.
  Future<void> openCat(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(Key('settingsCat_$id')));
    await tester.pumpAndSettle();
  }

  testWidgets('a CLIENT does not see the host-only destructive/admin tiles', (
    tester,
  ) async {
    await _pump(tester, isHost: false);

    // The screen rendered and the role editor (draft) is present ...
    expect(find.text('Host (main PC — server)'), findsOneWidget);
    // ... but the committed-role admin/destructive tiles are all hidden --
    // for a client even the categories that would hold them are not offered.
    expect(find.byKey(const Key('settingsCat_data')), findsNothing);
    expect(find.byKey(const Key('settingsCat_security')), findsNothing);
    expect(find.text('Data Protection'), findsNothing);
    expect(find.text('Restore Database'), findsNothing);
    expect(find.text('Danger Zone'), findsNothing);
    expect(find.text('Erase All Database'), findsNothing);
  });

  testWidgets(
    'draft-switching a client to Host WITHOUT saving does not reveal them',
    (tester) async {
      await _pump(tester, isHost: false);

      // Unlock editing -> the 'enter password' prompt appears (an unconfigured
      // client's local gate accepts anything).
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(find.text('Enter Admin Password'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'x',
      );
      await tester.tap(find.text('Validate'));
      await tester.pumpAndSettle();

      // Editing is now unlocked and the operator DRAFTS switching to Host ...
      await tester.tap(find.text('Host (main PC — server)'));
      await tester.pumpAndSettle();

      // ... but WITHOUT pressing Save the committed role is still client, so the
      // destructive host tiles must NOT appear. (Under the old `_isHost`-draft
      // gate this is exactly where they leaked through.)
      expect(find.text('Erase All Database'), findsNothing);
      expect(find.text('Restore Database'), findsNothing);
      expect(find.text('Data Protection'), findsNothing);
    },
  );

  testWidgets('a HOST sees the admin/destructive tiles', (tester) async {
    await _pump(tester, isHost: true);

    await openCat(tester, 'data');
    expect(find.text('Data Protection'), findsOneWidget);
    expect(find.text('Restore Database'), findsOneWidget);
    await openCat(tester, 'security');
    expect(find.text('Danger Zone'), findsOneWidget);
    expect(find.text('Erase All Database'), findsOneWidget);
  });
}

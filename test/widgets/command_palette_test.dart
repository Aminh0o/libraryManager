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
import 'package:library_manager/screens/home_screen.dart';
import 'package:library_manager/services/repository.dart';

// Phase 16: the command palette must be real navigation/action, gated honestly
// by its flag -- an entry that only ever offered a command the UI would then
// refuse (or a header button that appeared while the feature was off) would
// recreate exactly the "shipped as if functional" problem this whole audit is
// fixing. These pin the wiring, the role gating, and the live action.
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

/// Core Workflow Recovery: a repo variant that surfaces a fixed item when the
/// palette's data-search path queries with the matching search term. Proves
/// the palette is no longer navigation-only -- typing 'harr' resolves to the
/// Harry Potter title the operator was actually looking for.
class _SearchableRepo extends _EmptyRepo {
  @override
  Future<List<LibraryItem>> getItems({
    int limit = 1000,
    int offset = 0,
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) async {
    if (search == null || !search.toLowerCase().contains('harr')) {
      return const [];
    }
    return [
      LibraryItem(
        code: 'BK001',
        codeType: 'LIV',
        designation: 'Harry Potter and the Philosopher Stone',
        quantite: 3,
        emplacement: 'Fiction',
        emplacementStock: 'Shelf A',
        status: 'Disponible',
        taux: 1200,
      ),
    ];
  }
}

class _Harness {
  _Harness(this.appearance);
  final AppearanceController appearance;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required bool isHost,
  required bool paletteOn,
}) async {
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'feature.flag.commandPalette': paletteOn,
  });

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
        home: const HomeScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(appearance);
}

/// Same as [_pump] but with a repo whose `getItems` reacts to `search`, so
/// the palette's async data path has something real to surface.
Future<void> _pumpSearchable(
  WidgetTester tester, {
  required bool paletteOn,
}) async {
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'feature.flag.commandPalette': paletteOn,
  });
  final provider = LibraryProvider.forTesting(
    repository: _SearchableRepo(),
    isHost: true,
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
        home: const HomeScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the palette trigger appears only while the flag is on', (
    tester,
  ) async {
    await _pump(tester, isHost: true, paletteOn: true);
    expect(find.byTooltip('Command palette'), findsOneWidget);

    await _pump(tester, isHost: true, paletteOn: false);
    expect(find.byTooltip('Command palette'), findsNothing);
  });

  testWidgets(
    'opening the palette and running a theme command mutates the shared controller',
    (tester) async {
      final h = await _pump(tester, isHost: true, paletteOn: true);
      expect(h.appearance.themeMode, ThemeMode.system);

      await tester.tap(find.byTooltip('Command palette'));
      await tester.pumpAndSettle();
      // The palette is open with its search field.
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        findsOneWidget,
      );

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'dark',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Theme: Dark'));
      await tester.pumpAndSettle();

      expect(h.appearance.themeMode, ThemeMode.dark);
      // The dialog closed after running the command.
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('the palette never offers a staff command to a read-only session', (
    tester,
  ) async {
    await _pump(tester, isHost: false, paletteOn: true);
    await tester.tap(find.byTooltip('Command palette'));
    await tester.pumpAndSettle();

    // A universal command IS offered (so the palette is not empty for a viewer).
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'theme',
    );
    await tester.pumpAndSettle();
    expect(find.text('Theme: Dark'), findsOneWidget);

    // But the write action is gated exactly like the rest of the UI.
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'add',
    );
    await tester.pumpAndSettle();
    expect(find.text('Add Item'), findsNothing);
  });

  testWidgets(
    'typing 2+ characters surfaces live item matches under an Inventory section',
    (tester) async {
      // Core Workflow Recovery: proves Ctrl+K is now a "find anything"
      // launcher, not just a drawer of navigation commands. Data lookup is
      // debounced 300ms, so we advance fake time to allow it to complete.
      await _pumpSearchable(tester, paletteOn: true);
      await tester.tap(find.byTooltip('Command palette'));
      await tester.pumpAndSettle();

      final field = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, 'harr');
      // Let the 300ms debounce fire + the async itemMatches resolve.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Harry Potter'),
        findsOneWidget,
        reason: 'the data-search branch of the palette must render live items',
      );
      expect(
        find.text('Inventory'),
        findsWidgets,
        reason: 'item results are grouped under the inventory section header',
      );
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:library_manager/l10n/app_localizations.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/screens/dashboard_screen.dart';
import 'package:library_manager/services/repository.dart';

// FE2-10: the dashboard "Quick Scan" used to fire provider.search(code) and
// then do NOTHING -- the operator stayed on the dashboard and never saw the
// match. These tests prove the scan now (a) applies the code as a search and
// (b) asks the parent to open the inventory view (via onOpenInventory), and
// that cancelling the scan does neither.
class _FakeRepo implements LibraryRepository {
  @override
  Future<List<LibraryItem>> getItems({
    int limit = 1000,
    int offset = 0,
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) async =>
      const [];

  @override
  Future<int> countItems(
          {String? search, String? status, String? codeType,
    String? sort,
    bool ascending = true,
  }) async =>
      0;

  @override
  Future<List<Map<String, dynamic>>> getCodeDefinitions() async => const [];

  @override
  Future<List<Map<String, dynamic>>> getAttributeDefinitions(String? type) async =>
      const [];

  @override
  Future<Map<String, dynamic>> getStats() async => const {};

  // Everything else is irrelevant to the quick-scan path.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Widget _app(LibraryProvider provider, VoidCallback onOpenInventory) =>
    ChangeNotifierProvider<LibraryProvider>.value(
      value: provider,
      child: MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DashboardScreen(onOpenInventory: onOpenInventory),
        ),
      ),
    );

// The scan button is host-only; drive the real desktop scanner dialog (a text
// field + send button) that showBarcodeScanner opens on Windows.
Future<void> _tapQuickScan(WidgetTester tester) async {
  final scan = find.byIcon(Icons.qr_code_scanner);
  await tester.ensureVisible(scan);
  await tester.tap(scan);
  await tester.pumpAndSettle();
}

// The dashboard is a wide desktop layout; give the test a realistic surface so
// the header Row does not hit the (separately-tracked) overflow at 800px.
void _useDesktopSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('a completed scan applies the search and opens inventory (FE2-10)',
      (tester) async {
    _useDesktopSurface(tester);
    final provider =
        LibraryProvider.forTesting(repository: _FakeRepo(), isHost: true);
    var opened = 0;
    await tester.pumpWidget(_app(provider, () => opened++));

    await _tapQuickScan(tester);
    expect(find.byType(TextField), findsOneWidget,
        reason: 'the desktop scanner should present a code entry field');

    await tester.enterText(find.byType(TextField), 'ABC123');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump(); // dialog pops -> onPressed continuation runs

    expect(provider.searchQuery, 'ABC123',
        reason: 'the scanned code must become the active search');
    expect(opened, 1,
        reason: 'the operator must be moved to the inventory view');

    // Drain the 300ms search debounce so no timer is pending at teardown.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  });

  testWidgets('cancelling the scan does NOT search or navigate (FE2-10)',
      (tester) async {
    _useDesktopSurface(tester);
    final provider =
        LibraryProvider.forTesting(repository: _FakeRepo(), isHost: true);
    var opened = 0;
    await tester.pumpWidget(_app(provider, () => opened++));

    await _tapQuickScan(tester);
    // Close the dialog without submitting (tap the Cancel action).
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(provider.searchQuery, '',
        reason: 'an aborted scan must leave the query untouched');
    expect(opened, 0, reason: 'an aborted scan must not navigate');
  });
}

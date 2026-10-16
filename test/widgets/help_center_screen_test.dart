import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/l10n/app_localizations.dart';
import 'package:library_manager/screens/help_center_screen.dart';

void main() {
  Widget buildTestableWidget() {
    return const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: HelpCenterScreen(),
    );
  }

  testWidgets('HelpCenterScreen renders tutorial map and hardware guide', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    // Verify main definition card
    expect(find.byType(HelpCenterScreen), findsOneWidget);

    // Verify Tutorial Map card & title
    expect(find.text('Complete Operational Tutorial Map'), findsOneWidget);
    expect(find.text('System Initialization & Admin Setup'), findsOneWidget);
    expect(find.text('Catalog & Inventory Management'), findsOneWidget);
    expect(find.text('Circulation Desk (Checkout & Returns)'), findsOneWidget);

    // Scroll until Hardware Guide is visible
    final hardwareGuideFinder = find.text(
      'Hardware Peripherals & Desk Setup Guide',
    );
    await tester.scrollUntilVisible(
      hardwareGuideFinder,
      500.0,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    expect(hardwareGuideFinder, findsOneWidget);
  });
}

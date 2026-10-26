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
    expect(find.text('Welcome and first-run setup'), findsOneWidget);
    expect(find.text('Add titles and copies'), findsOneWidget);
    expect(find.text('Checkout, receipt and return'), findsOneWidget);

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

  testWidgets(
    'Phase 11: the footer shows Powered by Evenlio + verified contact',
    (tester) async {
      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      // Brand line + the two fields Evenlio actually publishes.
      final brandFinder = find.text('Powered by Evenlio');
      await tester.scrollUntilVisible(
        brandFinder,
        500.0,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();

      expect(brandFinder, findsOneWidget);
      expect(find.text('https://www.evenlio.com'), findsOneWidget);
      expect(find.text('evenlio.contact@gmail.com'), findsOneWidget);
      // No invented details: address / phone must NOT appear.
      expect(find.textContaining('updated soon'), findsNothing);
    },
  );

  testWidgets(
    'Phase 15: the tutorial map renders all 19 localized learning paths',
    (tester) async {
      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      // Every path Row carries a stable ordinal key; the last path (diagnostics)
      // is the tail of the map, so scrolling to it proves all 19 rendered in one
      // continuous 1..19 sequence rather than the old truncated 9.
      await tester.scrollUntilVisible(
        find.byKey(const Key('tutorialPath-19')),
        400.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      for (var n = 1; n <= 19; n++) {
        expect(
          find.byKey(Key('tutorialPath-$n')),
          findsOneWidget,
          reason: 'learning path #$n must be present in the tutorial map',
        );
      }
    },
  );
}

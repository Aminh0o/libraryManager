import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/l10n/app_localizations.dart';
import 'package:library_manager/widgets/item_delete_dialog.dart';

// FE2-01/02 (P9-9.28): the delete confirmation must await the operation and
// only close on success. Regression guard for the old fire-and-forget dialog
// that popped immediately, hiding failed deletes.
Future<void> _showDialog(
  WidgetTester tester,
  Future<void> Function() onConfirm,
) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const Key('openDialog'),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => ItemDeleteDialog(
                    itemLabel: 'ABC123',
                    onConfirm: onConfirm,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('openDialog')));
  await tester.pumpAndSettle();
  expect(find.byType(ItemDeleteDialog), findsOneWidget);
}

void main() {
  testWidgets('a failed delete keeps the dialog open and shows an error', (
    tester,
  ) async {
    var calls = 0;
    await _showDialog(tester, () async {
      calls++;
      throw StateError('server rejected the delete');
    });

    await tester.tap(find.byKey(const Key('confirmDelete')));
    await tester.pump(); // start the awaited delete
    await tester.pump(); // deliver the thrown error

    expect(calls, 1);
    expect(find.byType(ItemDeleteDialog), findsOneWidget); // still open
    expect(find.byType(SnackBar), findsOneWidget); // error surfaced

    // Let the SnackBar timer expire so teardown is clean.
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a successful delete closes the dialog', (tester) async {
    var calls = 0;
    await _showDialog(tester, () async {
      calls++;
    });

    await tester.tap(find.byKey(const Key('confirmDelete')));
    await tester.pump(); // start the awaited delete
    await tester.pumpAndSettle(); // success -> pop completes

    expect(calls, 1);
    expect(find.byType(ItemDeleteDialog), findsNothing); // closed
    expect(find.byType(SnackBar), findsNothing);
  });
}

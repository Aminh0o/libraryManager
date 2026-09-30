import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/l10n/app_localizations.dart';
import 'package:library_manager/widgets/confirm_action_dialog.dart';

// FE2-01/02 (P9-9.29): ConfirmActionDialog owns the await-then-close behaviour
// shared by the code-/attribute-management delete confirmations. These tests
// prove the engine: a throwing operation keeps the dialog open and surfaces the
// error; a successful one closes it. (The item wrapper is covered separately by
// item_delete_dialog_test.dart, which exercises this same engine.)
Future<void> _show(
    WidgetTester tester, Future<void> Function() onConfirm) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
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
                  builder: (_) => ConfirmActionDialog(
                    title: const Text('title'),
                    content: const Text('content'),
                    confirmLabel: const Text('do-it'),
                    cancelLabel: const Text('no'),
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
  expect(find.byType(ConfirmActionDialog), findsOneWidget);
}

void main() {
  testWidgets('a failed action keeps the dialog open and shows an error',
      (tester) async {
    var calls = 0;
    await _show(tester, () async {
      calls++;
      throw StateError('server rejected the delete');
    });

    await tester.tap(find.byKey(const Key('confirmAction')));
    await tester.pump(); // start the awaited action
    await tester.pump(); // deliver the thrown error

    expect(calls, 1);
    expect(find.byType(ConfirmActionDialog), findsOneWidget); // still open
    expect(find.byType(SnackBar), findsOneWidget); // error surfaced
    // FE2-12: the SnackBar shows a localized category, NOT the raw exception.
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    expect(find.textContaining('server rejected the delete'), findsNothing);

    await tester.pump(const Duration(seconds: 6)); // flush SnackBar timer
  });

  testWidgets('a successful action closes the dialog', (tester) async {
    var calls = 0;
    await _show(tester, () async {
      calls++;
    });

    await tester.tap(find.byKey(const Key('confirmAction')));
    await tester.pump(); // start the awaited action
    await tester.pumpAndSettle(); // success -> pop completes

    expect(calls, 1);
    expect(find.byType(ConfirmActionDialog), findsNothing); // closed
    expect(find.byType(SnackBar), findsNothing);
  });
}

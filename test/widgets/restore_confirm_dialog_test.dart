import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/l10n/app_localizations.dart';
import 'package:library_manager/widgets/restore_confirm_dialog.dart';

// FE2-03: restoring a backup destroys the live database, so it must be gated
// behind an explicit confirmation. These tests prove the gate's whole point:
// the restore operation is NOT run merely by opening the dialog, is run exactly
// once on confirm, and never on cancel.
Future<void> _show(
    WidgetTester tester, Future<void> Function() onConfirm) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const Key('open'),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => RestoreConfirmDialog(
                    filePath: r'C:\backups\lib.db',
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
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
  expect(find.byType(RestoreConfirmDialog), findsOneWidget);
}

void main() {
  testWidgets('merely opening the gate does NOT restore (FE2-03)',
      (tester) async {
    var calls = 0;
    await _show(tester, () async {
      calls++;
    });
    expect(calls, 0,
        reason: 'a picked file must not overwrite the DB until confirmed');
  });

  testWidgets('confirming runs the restore exactly once and closes (FE2-03)',
      (tester) async {
    var calls = 0;
    await _show(tester, () async {
      calls++;
    });
    await tester.tap(find.byKey(const Key('confirmRestore')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(RestoreConfirmDialog), findsNothing);
  });

  testWidgets('cancelling does NOT restore (FE2-03)', (tester) async {
    var calls = 0;
    await _show(tester, () async {
      calls++;
    });
    await tester.tap(find.byKey(const Key('cancelRestore')));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byType(RestoreConfirmDialog), findsNothing);
  });
}

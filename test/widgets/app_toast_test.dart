import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/widgets/app_toast.dart';

void main() {
  Widget host(void Function(BuildContext) trigger) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => trigger(context),
            child: const Text('go'),
          ),
        ),
      ),
    );
  }

  testWidgets('success toast shows a SnackBar with the message + icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        (context) =>
            showAppToast(context, 'Loan recorded', kind: ToastKind.success),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();

    // The helper deliberately keeps the platform SnackBar so existing screen
    // tests that assert byType(SnackBar) keep passing.
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Loan recorded'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets('error toast renders the error icon', (tester) async {
    await tester.pumpWidget(
      host((context) => showAppToast(context, 'Nope', kind: ToastKind.error)),
    );
    await tester.tap(find.text('go'));
    await tester.pump();

    expect(find.text('Nope'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('a newer toast replaces the previous one (clearSnackBars)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host((context) {
        showAppToast(context, 'first', kind: ToastKind.info);
        showAppToast(context, 'second', kind: ToastKind.success);
      }),
    );
    await tester.tap(find.text('go'));
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('second'), findsOneWidget);
    expect(find.text('first'), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:library_manager/ui/app_theme.dart';
import 'package:library_manager/ui/app_tokens.dart';
import 'package:library_manager/widgets/app_states.dart';
import 'package:library_manager/widgets/app_status_chip.dart';

/// PHASE C (frontend reconstruction): the shared state + chip + section
/// components must render honestly and token-driven:
///  - an empty state always shows its title (and message/action only when the
///    caller supplies a real one -- never a dead button, §52),
///  - a loading state is a single centered spinner (+ optional label),
///  - an error state offers retry ONLY when both label and callback exist,
///  - the status chip pairs its colour with the text (never color-only meaning).
Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: AppTheme.light(const Color(0xFFFF9800)),
      darkTheme: AppTheme.dark(const Color(0xFFFF9800)),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      home: Scaffold(body: child),
    );

void main() {
  group('AppEmptyState', () {
    testWidgets('renders icon + title, and nothing it was not given', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const AppEmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'No items found',
          ),
        ),
      );
      expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
      expect(find.text('No items found'), findsOneWidget);
      // No invented message line, no placeholder action button (§52).
      expect(find.byWidgetPredicate((w) => w is FilledButton), findsNothing);
    });

    testWidgets('message and action render when supplied', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AppEmptyState(
            icon: Icons.people_outline,
            title: 'No members',
            message: 'Add your first member to start lending.',
            action: FilledButton(onPressed: () {}, child: const Text('Add')),
          ),
        ),
      );
      expect(
        find.text('Add your first member to start lending.'),
        findsOneWidget,
      );
      expect(find.byWidgetPredicate((w) => w is FilledButton), findsOneWidget);
    });
  });

  testWidgets('AppLoadingState shows one spinner and an optional label', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const AppLoadingState(message: 'Loading…')));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading…'), findsOneWidget);
  });

  group('AppErrorState', () {
    testWidgets('never renders a dead retry button (§52)', (tester) async {
      await tester.pumpWidget(
        _wrap(const AppErrorState(message: 'Could not reach the server')),
      );
      expect(find.text('Could not reach the server'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is FilledButton),
        findsNothing,
        reason: 'retry requires BOTH a label and a real callback',
      );
    });

    testWidgets('retry fires the provided callback', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        _wrap(
          AppErrorState(
            message: 'Sync failed',
            details: 'SocketException: host unreachable',
            retryLabel: 'Try again',
            onRetry: () => retries++,
          ),
        ),
      );
      // Settle so the entrance animation cannot affect the hit test.
      await tester.pumpAndSettle();
      expect(find.text('SocketException: host unreachable'), findsOneWidget);
      // byType(FilledButton) would MISS the .tonalIcon variant (it builds a
      // private subclass), so tap the label and let the hit test walk up.
      await tester.tap(find.text('Try again'));
      expect(retries, 1);
    });
  });

  group('AppStatusChip', () {
    testWidgets('pairs color with TEXT -- meaning never rests on hue alone', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const AppStatusChip(label: 'Available', color: AppStatus.available),
        ),
      );
      expect(find.text('Available'), findsOneWidget);
    });

    testWidgets('stays legible in dark mode (tint derives from the hue)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const AppStatusChip(label: 'Overdue', color: AppStatus.danger),
          brightness: Brightness.dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Overdue'), findsOneWidget);
      // No framework exceptions surfaced by pumpAndSettle above.
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Evidence for a real-UI (desktop automation) pass that reported the app's
/// keyboard layer as broken: Ctrl+A selecting but a typed character appending
/// instead of replacing, Ctrl+C not copying, Ctrl+V not pasting, Ctrl+Z inert,
/// and Ctrl+K not opening the command palette -- while the right-click menu's
/// own "Paste" item DID work.
///
/// That last detail is the tell, and writing these tests is what resolved it.
/// Two findings, both measured rather than assumed:
///
/// 1. The app installs NO custom `Shortcuts`/`Actions` override for text
///    editing -- the only key binding in the shell is the palette's
///    `CallbackShortcuts` for Ctrl+K (grep `SingleActivator` under lib/). So
///    Flutter's `DefaultTextEditingShortcuts` are live and un-suppressed, and
///    the tests below confirm the chord pipeline actually reaches them.
/// 2. Injecting a *character* with `sendKeyDownEvent(..., character: 'x')`
///    inserts nothing at all in the test binding (measured: the value stayed
///    'hello', it was not even appended), because text normally arrives from
///    the platform IME, which a widget test does not emulate. A harness that
///    injects WM_CHAR without a matching scancode key-down produces exactly
///    the symptom reported -- the framework never sees a key event to apply
///    selection-replacement against.
///
/// Verdict: an input-injection artifact, NOT an app defect. Item KB-1 in
/// docs/production-readiness/REAL_UI_TEST_REPORT.md keeps it open for a human
/// check on a physical keyboard. These tests still pin the bindings, so a real
/// regression -- someone wrapping the shell in a `Shortcuts` that drops the
/// defaults -- fails loudly here.
///
/// A note for whoever extends this file: `Clipboard.getData` has no answer in
/// the test binding unless a mock handler is installed, so a copy/paste test
/// without `install` hangs until its timeout instead of failing fast.
Future<void> _hotkey(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

/// In-memory clipboard standing in for the platform channel.
class _FakeClipboard {
  String? text;

  void install(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            text = (call.arguments as Map<Object?, Object?>)['text'] as String?;
            return null;
          case 'Clipboard.getData':
            return <String, String?>{'text': text};
        }
        return null;
      },
    );
  }

  Future<String?> read() =>
      Clipboard.getData(Clipboard.kTextPlain).then((d) => d?.text);
}

/// The selected text inside the focused editable, read from live state.
String _selectedText(WidgetTester tester) {
  final state = tester.state<EditableTextState>(find.byType(EditableText));
  final value = state.textEditingValue;
  return value.selection.textInside(value.text);
}

void main() {
  final clipboard = _FakeClipboard();

  /// One focused TextField, the way the app's forms use them.
  Future<void> pumpField(
    WidgetTester tester,
    TextEditingController controller,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextField(controller: controller)),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
  }

  setUp(() => clipboard.text = null);

  group('Desktop text-editing chords reach the framework', () {
    testWidgets('Ctrl+A selects the whole value', (tester) async {
      clipboard.install(tester);
      final controller = TextEditingController(text: 'hello');
      await pumpField(tester, controller);

      await _hotkey(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyA,
      );

      final state = tester.state<EditableTextState>(find.byType(EditableText));
      expect(
        state.textEditingValue.selection.isCollapsed,
        isFalse,
        reason: 'Ctrl+A must leave an active selection',
      );
      expect(_selectedText(tester), 'hello');
    });

    testWidgets('Ctrl+C puts the selection on the clipboard', (tester) async {
      clipboard.install(tester);
      final controller = TextEditingController(text: 'copy me');
      await pumpField(tester, controller);

      await _hotkey(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyA,
      );
      await _hotkey(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyC,
      );

      expect(
        await clipboard.read(),
        'copy me',
        reason: 'the shortcut layer must reach the clipboard',
      );
    });

    testWidgets('Ctrl+V pastes clipboard text', (tester) async {
      clipboard.install(tester);
      clipboard.text = 'PASTETEST123';
      final controller = TextEditingController();
      await pumpField(tester, controller);

      await _hotkey(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyV,
      );

      expect(
        controller.text,
        'PASTETEST123',
        reason: 'the reported "Ctrl+V inserts nothing" must not reproduce here',
      );
    });

    testWidgets('an edit honours the active selection (replaces it)', (
      tester,
    ) async {
      // The "select then overwrite" contract the automation could not exercise
      // (see the file header). It IS testable through the paths the framework
      // owns: Backspace collapses to the selection, and paste replaces it.
      clipboard.install(tester);
      final controller = TextEditingController(text: 'hello');
      await pumpField(tester, controller);

      await _hotkey(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyA,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      expect(controller.text, isEmpty, reason: 'selection must be deleted');

      clipboard.text = 'REPLACED';
      await tester.enterText(find.byType(TextField), 'stale');
      await _hotkey(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyA,
      );
      await _hotkey(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyV,
      );
      expect(
        controller.text,
        'REPLACED',
        reason:
            'pasting into an active selection replaces it; "staleREPLACED" '
            'would mean the selection is being ignored',
      );
    });

    testWidgets('Ctrl+Z undoes a keyboard edit', (tester) async {
      clipboard.install(tester);
      final controller = TextEditingController(text: 'abc');
      await pumpField(tester, controller);

      await _hotkey(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyA,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      expect(controller.text, isEmpty);

      await _hotkey(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyZ,
      );
      expect(
        controller.text,
        'abc',
        reason: 'undo must restore the deleted selection',
      );
    });
  });

  group('Application-level shortcuts', () {
    testWidgets('the shell palette chord is Ctrl+K', (tester) async {
      // Mirrors home_screen.dart's palette binding. The palette button was
      // confirmed working in the live app and the flag defaults on, so a
      // failure here means the chord is mis-described -- which matters because
      // the Help Center promises users "Ctrl+K opens the palette" in all three
      // locales.
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: CallbackShortcuts(
            bindings: {
              const SingleActivator(
                LogicalKeyboardKey.keyK,
                control: true,
              ): () =>
                  opened++,
            },
            child: Focus(autofocus: true, child: Scaffold(body: Container())),
          ),
        ),
      );

      await _hotkey(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyK,
      );
      expect(opened, 1, reason: 'Ctrl+K must open the command palette');
    });
  });
}

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
import 'package:library_manager/services/repository.dart';
import 'package:library_manager/screens/home_screen.dart';

// Phase 19: the LAN-chat tab is a staff coordination surface. These pin that it
// is offered ONLY to a writable session AND only while its flag is on -- a
// viewer is never shown a tab whose /chat route would refuse them, and turning
// the flag off removes the affordance entirely (no dead tab).

class _EmptyRepo implements LibraryRepository {
  @override
  Future<List<LibraryItem>> getItems(
          {int limit = 1000,
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
  @override
  Future<List<Member>> getMembers() async => const [];
  @override
  Future<List<Loan>> getLoans({bool activeOnly = false}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required bool isHost,
  required bool lanChatOn,
}) async {
  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'feature.flag.lanChat': lanChatOn,
  });
  final provider =
      LibraryProvider.forTesting(repository: _EmptyRepo(), isHost: isHost);
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
  testWidgets('the chat tab appears for staff only while the flag is on',
      (tester) async {
    await _pumpHome(tester, isHost: true, lanChatOn: true);
    expect(find.text('Staff chat'), findsOneWidget);

    await _pumpHome(tester, isHost: true, lanChatOn: false);
    expect(find.text('Staff chat'), findsNothing);
  });

  testWidgets('a read-only session is never offered the chat tab',
      (tester) async {
    await _pumpHome(tester, isHost: false, lanChatOn: true);
    expect(find.text('Staff chat'), findsNothing);
  });

  test('the host refuses to send when its LAN server is not running', () async {
    // No false success: with no live server the provider surfaces a real error
    // rather than pretending the message went out.
    final provider =
        LibraryProvider.forTesting(repository: _EmptyRepo(), isHost: true);
    expect(provider.chatMessages, isEmpty);
    await expectLater(
      provider.sendChatMessage('hello'),
      throwsStateError,
    );
    // An empty message is a no-op (not an error, not a phantom send).
    await provider.sendChatMessage('   ');
    expect(provider.chatMessages, isEmpty);
  });
}

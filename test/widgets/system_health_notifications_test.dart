import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:library_manager/config/app_info.dart';
import 'package:library_manager/l10n/app_localizations.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/models/loan.dart';
import 'package:library_manager/models/member.dart';
import 'package:library_manager/models/fine.dart';
import 'package:library_manager/models/reservation.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/providers/appearance_controller.dart';
import 'package:library_manager/services/feature_flags.dart';
import 'package:library_manager/services/repository.dart';
import 'package:library_manager/screens/home_screen.dart';
import 'package:library_manager/screens/system_health_screen.dart';

// Phase 15: the system-health center and the notification center must report
// ONLY states the running app actually produced (rule / §52): a real version,
// a real "Never" for a backup that never ran, and a bell that hides from a
// read-only session rather than offering it an always-empty panel. These pin
// the honesty and the flag + role gating of both surfaces.

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
  Future<int> countItems({String? search, String? status, String? codeType,
    String? sort,
    bool ascending = true,
  }) async => 0;
  @override
  Future<List<Map<String, dynamic>>> getCodeDefinitions() async => const [];
  @override
  Future<List<Map<String, dynamic>>> getAttributeDefinitions(String? type) async => const [];
  @override
  Future<Map<String, dynamic>> getStats() async => const {};
  @override
  Future<List<Member>> getMembers() async => const [];
  @override
  Future<List<Loan>> getLoans({bool activeOnly = false}) async => const [];
  @override
  Future<List<Reservation>> readyForPickup() async => const [];
  @override
  Future<List<Fine>> getFines(
      {String? memberId, FineStatus? status}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> _pumpHealth(WidgetTester tester, {required bool isHost}) async {
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
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
        home: const SystemHealthScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
Future<void> _pumpHome(
  WidgetTester tester, {
  required bool isHost,
  required bool notificationOn,
}) async {
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'feature.flag.notificationCenter': notificationOn,
  });
  final provider =
      LibraryProvider.forTesting(repository: _EmptyRepo(), isHost: isHost);
  final flags = await FeatureFlags.load();
  final appearance = await AppearanceController.load();
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
  group('System-health center', () {
    testWidgets('shows the real app version and never-faked "Never" backup',
        (tester) async {
      await _pumpHealth(tester, isHost: true);

      expect(find.text('System health'), findsOneWidget);
      expect(find.text('App version'), findsOneWidget);
      // The version row is the app's actual constant, not a placeholder.
      expect(find.text(kAppVersion), findsOneWidget);
      expect(find.text('Database schema version'), findsOneWidget);
      expect(find.text('Operating mode'), findsOneWidget);
      // A host that has never backed up must be told "Never", not shown a
      // reassuring fake date.
      expect(find.text('Last backup'), findsOneWidget);
      expect(find.text('Never'), findsOneWidget);
      // Host-only internals are present for a host.
      expect(find.text('LAN server'), findsOneWidget);
    });

    testWidgets('client mode reports itself honestly (no host internals)',
        (tester) async {
      await _pumpHealth(tester, isHost: false);

      expect(find.text('Client'), findsOneWidget);
      // The LAN-server and connected-client rows are host-only internals and
      // must not render on a client.
      expect(find.text('LAN server'), findsNothing);
      expect(find.text('Connected clients'), findsNothing);
    });
  });

  group('Notification center', () {
    testWidgets('the bell appears for staff only while the flag is on',
        (tester) async {
      await _pumpHome(tester, isHost: true, notificationOn: true);
      expect(find.byTooltip('Notifications'), findsOneWidget);

      await _pumpHome(tester, isHost: true, notificationOn: false);
      expect(find.byTooltip('Notifications'), findsNothing);

      // A read-only session is never shown a bell it cannot legitimately fill.
      await _pumpHome(tester, isHost: false, notificationOn: true);
      expect(find.byTooltip('Notifications'), findsNothing);
    });

    testWidgets('opening the bell reports honestly when nothing needs attention',
        (tester) async {
      await _pumpHome(tester, isHost: true, notificationOn: true);
      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsWidgets);
      // An empty operational state shows the honest "nothing needs attention",
      // never a fabricated count.
      expect(find.text('Nothing needs attention'), findsOneWidget);
    });
  });
}

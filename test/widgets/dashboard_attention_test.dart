import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:library_manager/l10n/app_localizations.dart';
import 'package:library_manager/models/fine.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/models/loan.dart';
import 'package:library_manager/models/member.dart';
import 'package:library_manager/models/reservation.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/screens/dashboard_screen.dart';
import 'package:library_manager/services/repository.dart';

/// Core Workflow Recovery: dashboard "Needs Attention" panel.
///
/// Proves the panel is real operational signal, not decoration:
/// - when nothing is overdue / held / owed, the whole section disappears
///   (no false zeros, no noise -- the operator is not shown a 0 tile)
/// - when a source has a count, a tappable tile surfaces it AND a tap
///   actually asks the parent to switch to the matching rail tab.
class _Repo implements LibraryRepository {
  _Repo({
    this.loans = const [],
    this.fines = const [],
    this.ready = const [],
  });

  final List<Loan> loans;
  final List<Fine> fines;
  final List<Reservation> ready;

  @override
  Future<List<LibraryItem>> getItems({
    int limit = 1000,
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
          {String? search,
          String? status,
          String? codeType,
          String? sort,
          bool ascending = true}) async =>
      0;

  @override
  Future<List<Member>> getMembers() async => const [];

  @override
  Future<List<Loan>> getLoans({bool activeOnly = false}) async {
    if (activeOnly) return loans.where((l) => l.isActive).toList();
    return loans;
  }

  @override
  Future<List<Fine>> getFines(
          {String? memberId, FineStatus? status}) async =>
      fines
          .where((f) => status == null || f.status == status)
          .toList();

  @override
  Future<List<Reservation>> readyForPickup() async => ready;

  @override
  Future<List<Reservation>> getReservations({
    String? itemCode,
    String? memberId,
    ReservationStatus? status,
    bool liveOnly = false,
  }) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> getCodeDefinitions() async => const [];
  @override
  Future<List<Map<String, dynamic>>> getAttributeDefinitions(
          String? type) async =>
      const [];
  @override
  Future<Map<String, dynamic>> getStats() async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<LibraryProvider> _pump(
  WidgetTester tester, {
  required _Repo repo,
  void Function()? onOpenLoans,
  void Function()? onOpenReservations,
  void Function()? onOpenFines,
}) async {
  tester.view.physicalSize = const Size(1400, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final provider = LibraryProvider.forTesting(repository: repo, isHost: true);
  // Warm the in-memory loan cache the panel reads synchronously.
  await provider.reloadAllForTesting();
  await tester.pumpWidget(
    ChangeNotifierProvider<LibraryProvider>.value(
      value: provider,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DashboardScreen(
            onOpenLoans: onOpenLoans,
            onOpenReservations: onOpenReservations,
            onOpenFines: onOpenFines,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return provider;
}

/// A past-due `Active` loan, which is what `Loan.isOverdue` reads.
Loan _overdue() => Loan(
      itemCode: 'BK-001',
      memberId: 'M-001',
      memberName: 'A',
      itemTitle: 'T',
      loanDate: DateTime(2020, 1, 1),
      dueDate: DateTime(2020, 1, 16),
      status: 'Active',
    );

/// A due-date in the future is Active but NOT overdue; used by the "quiet
/// day" test to prove the panel keys off the DERIVED overdue flag, not just
/// "is there any active loan".
Loan _onTime() => Loan(
      itemCode: 'BK-002',
      memberId: 'M-001',
      memberName: 'B',
      itemTitle: 'U',
      loanDate: DateTime(2099, 1, 1),
      dueDate: DateTime(2099, 1, 16),
      status: 'Active',
    );

Fine _pendingFine() => const Fine(
      memberId: 'M-001',
      amount: 100,
      status: FineStatus.pending,
      reason: 'late',
    );

Reservation _holdReady() => const Reservation(
      itemCode: 'BK-099',
      memberId: 'M-001',
      status: ReservationStatus.available,
    );

void main() {
  testWidgets('a fully-quiet day hides the Needs Attention section entirely',
      (tester) async {
    await _pump(
      tester,
      repo: _Repo(loans: [_onTime()]),
    );
    // No section header, no alert tiles -- nothing to shout about.
    expect(find.text('Needs attention'), findsNothing);
  });

  testWidgets('an overdue loan raises a tappable alert tile',
      (tester) async {
    var tapped = 0;
    await _pump(
      tester,
      repo: _Repo(loans: [_overdue()]),
      onOpenLoans: () => tapped++,
    );
    expect(find.text('Needs attention'), findsOneWidget);
    expect(
      find.textContaining('overdue'),
      findsOneWidget,
      reason: 'the overdue count must be surfaced verbatim from l10n',
    );
    await tester.tap(find.textContaining('overdue'));
    await tester.pump();
    expect(
      tapped,
      1,
      reason: 'tapping the tile must hand off to the loans tab callback',
    );
  });

  testWidgets('holds-ready and pending-fines each raise their own tile',
      (tester) async {
    await _pump(
      tester,
      repo: _Repo(
        ready: [_holdReady()],
        fines: [_pendingFine()],
      ),
    );
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.textContaining('hold'), findsOneWidget);
    expect(find.textContaining('fine'), findsOneWidget);
  });
}

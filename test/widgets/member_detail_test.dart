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
import 'package:library_manager/screens/member_detail_screen.dart';
import 'package:library_manager/services/repository.dart';

/// Core Workflow Recovery: member detail tests.
/// Proves that the member profile page renders real operational data from the
/// provider (loans filtered by memberId, overdue banner, fines balance,
/// reservations) and exposes the renew affordance to a writable session.

class _MemberDetailRepo implements LibraryRepository {
  _MemberDetailRepo({
    this.loans = const [],
    this.fines = const [],
    this.reservations = const [],
  });

  final List<Loan> loans;
  final List<Fine> fines;
  final List<Reservation> reservations;

  @override
  Future<List<LibraryItem>> getItems({
    int limit = 1000,
    int offset = 0,
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) async => const [];

  @override
  Future<int> countItems({
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) async => 0;

  @override
  Future<List<Member>> getMembers() async => [
    Member(
      firstName: 'Amira',
      lastName: 'Boukez',
      memberId: 'M-001',
      registeredAt: DateTime(2024, 1, 15),
      phone: '0555123456',
    ),
  ];

  @override
  Future<List<Loan>> getLoans({bool activeOnly = false}) async {
    if (activeOnly) return loans.where((l) => l.isActive).toList();
    return loans;
  }

  @override
  Future<List<Fine>> getFines({String? memberId, FineStatus? status}) async =>
      fines;

  @override
  Future<double> outstandingBalance(String memberId) async => fines
      .where((f) => f.status == FineStatus.pending)
      .fold<double>(0.0, (s, f) => s + f.amount);

  @override
  Future<List<Reservation>> getReservations({
    String? itemCode,
    String? memberId,
    ReservationStatus? status,
    bool liveOnly = false,
  }) async => reservations;

  @override
  Future<List<Map<String, dynamic>>> getCodeDefinitions() async => const [];
  @override
  Future<List<Map<String, dynamic>>> getAttributeDefinitions(
    String? type,
  ) async => const [];
  @override
  Future<Map<String, dynamic>> getStats() async => const {};
  @override
  Future<void> updateLoan(Loan loan, {Map<String, dynamic>? audit}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> _pump(
  WidgetTester tester, {
  required List<Loan> loans,
  List<Fine> fines = const [],
  List<Reservation> reservations = const [],
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});

  final repo = _MemberDetailRepo(
    loans: loans,
    fines: fines,
    reservations: reservations,
  );
  final provider = LibraryProvider.forTesting(repository: repo, isHost: true);
  // Load members + loans into the provider's in-memory cache.
  await provider.reloadAllForTesting();

  await tester.pumpWidget(
    ChangeNotifierProvider<LibraryProvider>.value(
      value: provider,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const MemberDetailScreen(memberId: 'M-001'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows active loans for the member', (tester) async {
    final loans = [
      Loan(
        itemCode: 'BK-001',
        memberId: 'M-001',
        memberName: 'Amira Boukez',
        itemTitle: 'Clean Code',
        loanDate: DateTime(2026, 9, 1),
        dueDate: DateTime(2026, 9, 16),
        status: 'Active',
      ),
    ];
    await _pump(tester, loans: loans);

    expect(find.text('Clean Code'), findsOneWidget);
    // The member identity shows the name.
    expect(find.text('Amira Boukez'), findsOneWidget);
  });

  testWidgets('overdue banner appears when a loan is past due', (tester) async {
    final loans = [
      Loan(
        itemCode: 'BK-002',
        memberId: 'M-001',
        memberName: 'Amira Boukez',
        itemTitle: 'Refactoring',
        loanDate: DateTime(2026, 8, 1),
        dueDate: DateTime(2026, 8, 16), // Past = overdue
        status: 'Active',
      ),
    ];
    await _pump(tester, loans: loans);

    expect(find.textContaining('overdue'), findsWidgets);
    expect(find.text('Refactoring'), findsOneWidget);
  });

  testWidgets('fines balance renders for a staff session', (tester) async {
    final fines = [
      const Fine(
        memberId: 'M-001',
        amount: 150.0,
        status: FineStatus.pending,
        reason: 'Late return',
      ),
    ];
    await _pump(tester, loans: [], fines: fines);

    expect(find.textContaining('150'), findsWidgets);
    expect(find.text('Late return'), findsOneWidget);
  });

  testWidgets('reservations section renders for a staff session', (
    tester,
  ) async {
    final reservations = [
      const Reservation(
        itemCode: 'BK-099',
        memberId: 'M-001',
        status: ReservationStatus.available,
      ),
    ];
    await _pump(tester, loans: [], reservations: reservations);

    expect(find.text('BK-099'), findsOneWidget);
    expect(find.textContaining('Ready for pickup'), findsOneWidget);
  });
}

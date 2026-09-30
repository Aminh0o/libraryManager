import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:library_manager/l10n/app_localizations.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/models/loan.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/screens/loan_screen.dart';
import 'package:library_manager/services/repository.dart';

// FE2-15: the renewal / active-loans / overdue surface existed only in the
// provider (activeLoans, isOverdue, renewLoan) with ZERO UI. These tests drive
// the real LoanScreen third tab end-to-end against a fake repository to prove
// the desk can now see current loans, spot the overdue ones, and renew.
class _LoanRepo implements LibraryRepository {
  _LoanRepo(this.loans);

  final List<Loan> loans;
  int updateCalls = 0;
  Loan? lastUpdated;

  @override
  Future<List<Loan>> getLoans({bool activeOnly = false}) async =>
      List<Loan>.of(loans);

  @override
  Future<void> updateLoan(Loan loan, {Map<String, dynamic>? audit}) async {
    updateCalls++;
    lastUpdated = loan;
    final i = loans.indexWhere((l) => l.id == loan.id);
    if (i >= 0) loans[i] = loan;
  }

  // Empty catalogue / members are fine — the active-loans tab reads _loans only.
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
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<LibraryProvider> _pump(WidgetTester tester, _LoanRepo repo) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final provider = LibraryProvider.forTesting(repository: repo);
  await provider.reloadAllForTesting();

  await tester.pumpWidget(
    ChangeNotifierProvider<LibraryProvider>.value(
      value: provider,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const LoanScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return provider;
}

Loan _mk({required int id, required String member, required DateTime due}) {
  return Loan(
    id: id,
    itemCode: 'C$id',
    memberId: 'M$id',
    memberName: member,
    itemTitle: 'Title $id',
    loanDate: DateTime(2020),
    dueDate: due,
    status: LoanStatus.active.storage,
  );
}

void main() {
  testWidgets('active-loans tab lists loans and flags the overdue one', (
    tester,
  ) async {
    final repo = _LoanRepo([
      _mk(id: 1, member: 'Alice', due: DateTime(2099)), // on time
      _mk(id: 2, member: 'Bob', due: DateTime(2000)), // overdue
    ]);
    await _pump(tester, repo);

    // Switch to the third tab.
    await tester.tap(find.text('Active Loans'));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    // Exactly one Overdue chip — only the past-due loan is flagged.
    expect(find.text('Overdue'), findsOneWidget);
    // A Renew button per active loan.
    expect(find.byKey(const Key('renew_1')), findsOneWidget);
    expect(find.byKey(const Key('renew_2')), findsOneWidget);
  });

  testWidgets('renewing a loan calls the provider and confirms success', (
    tester,
  ) async {
    final repo = _LoanRepo([_mk(id: 1, member: 'Alice', due: DateTime(2099))]);
    final provider = await _pump(tester, repo);
    final before = provider.activeLoans.single.dueDate;

    await tester.tap(find.text('Active Loans'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('renew_1')));
    await tester.pump(); // start the awaited renew
    await tester.pumpAndSettle(); // success snackbar + reload

    expect(repo.updateCalls, 1);
    expect(repo.lastUpdated!.dueDate, before.add(const Duration(days: 15)));
    expect(find.text('Loan renewed successfully'), findsOneWidget);
    // The list reflects the extended due date after the internal reload.
    expect(
      provider.activeLoans.single.dueDate,
      before.add(const Duration(days: 15)),
    );
  });

  testWidgets('empty state shows when there are no active loans', (
    tester,
  ) async {
    final repo = _LoanRepo([]);
    await _pump(tester, repo);

    await tester.tap(find.text('Active Loans'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('noActiveLoans')), findsOneWidget);
    expect(find.text('No active loans.'), findsOneWidget);
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/models/loan.dart';
import 'package:library_manager/models/member.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/services/api_service.dart';
import 'package:library_manager/services/repository.dart';

// DEF-01 product observation, closed client-side: the server's 504 guard
// answers WITHOUT cancelling the handler, and the client's own request budget
// can expire before any definitive answer arrives. In both cases the checkout
// MAY have committed on the host even though the call throws. The provider
// must therefore RE-SYNC loans + items before rethrowing, so the operator
// never sits on a stale 'Disponible' for a copy the host already lent.
// The data invariant (idempotency key + active-copy claim) was never at risk;
// this is about the VIEW telling the truth after an unknown outcome.

class _CheckoutRepo implements LibraryRepository {
  _CheckoutRepo({this.failAddLoan});

  /// Thrown by [addLoan] when non-null (stands in for the unknown-outcome
  /// failures a real client sees: 504 gateway guard, TimeoutException, or a
  /// definitive 409 from a racing retry).
  final Object? failAddLoan;

  int addLoanCalls = 0;
  int getLoansCalls = 0;
  int getItemsCalls = 0;

  /// What the host reports AFTER the failing write — the test's way of
  /// proving the provider re-pulled state instead of trusting its cache.
  List<Loan> loansOnHost = const [];
  List<LibraryItem> itemsOnHost = const [];

  @override
  Future<void> addLoan(Loan loan, {Map<String, dynamic>? audit}) async {
    addLoanCalls++;
    if (failAddLoan != null) throw failAddLoan!;
  }

  @override
  Future<List<Loan>> getLoans({bool activeOnly = false}) async {
    getLoansCalls++;
    return loansOnHost;
  }

  @override
  Future<List<LibraryItem>> getItems({
    int limit = 1000,
    int offset = 0,
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) async {
    getItemsCalls++;
    return itemsOnHost;
  }

  @override
  Future<int> countItems({String? search, String? status, String? codeType}) =>
      Future.value(itemsOnHost.length);

  @override
  Future<Map<String, dynamic>> getStats() async => const {};

  // _loadItems also refreshes the definition lists; keep the fake total so
  // the reconciliation path stays error-free and the counts below stay true.
  @override
  Future<List<Map<String, dynamic>>> getCodeDefinitions() async => const [];

  @override
  Future<List<Map<String, dynamic>>> getAttributeDefinitions(
    String? type,
  ) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

LibraryItem _item(String code, {String status = 'Disponible'}) => LibraryItem(
  code: code,
  codeType: 'LIV',
  designation: 'Book $code',
  quantite: 1,
  emplacement: 'A1',
  taux: 0,
  emplacementStock: 'S1',
  status: status,
);

final _member = Member(
  firstName: 'Test',
  lastName: 'Member',
  memberId: 'M001',
  registeredAt: DateTime(2026),
);

void main() {
  group('checkOutItem reconciles the view after unknown-outcome failures', () {
    test(
      '504 (guard answered, handler may still commit) re-syncs and rethrows',
      () async {
        final repo = _CheckoutRepo(
          failAddLoan: ApiException(504, 'Request took too long'),
        );
        // The host DID commit the phantom loan; its next reads report it.
        final phantom = Loan(
          itemCode: 'P1',
          memberId: 'M001',
          memberName: 'Test Member',
          itemTitle: 'Book P1',
          loanDate: DateTime(2026, 1, 1),
          dueDate: DateTime(2026, 1, 16),
        );
        repo.loansOnHost = [phantom];
        repo.itemsOnHost = [_item('P1', status: 'Emprunté')];

        // isHost:false keeps the success path free of the 15 s backup timer.
        final provider = LibraryProvider.forTesting(
          repository: repo,
          isHost: false,
        );
        await expectLater(
          provider.checkOutItem(_item('P1'), _member),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 504),
          ),
        );

        expect(repo.addLoanCalls, 1);
        expect(
          repo.getLoansCalls,
          greaterThan(0),
          reason: 'the view must re-pull loans after the failure',
        );
        expect(
          repo.getItemsCalls,
          greaterThan(0),
          reason: 'the view must re-pull items after the failure',
        );
        // The stale-cache symptom is gone: the provider now SHOWS the loan the
        // timed-out write may have committed.
        expect(provider.loans.map((l) => l.itemCode), contains('P1'));
        expect(provider.items.first.status, 'Emprunté');
      },
    );

    test(
      'client TimeoutException also re-syncs before the error surfaces',
      () async {
        final repo = _CheckoutRepo(
          failAddLoan: TimeoutException('budget gone'),
        );
        final provider = LibraryProvider.forTesting(
          repository: repo,
          isHost: false,
        );
        await expectLater(
          provider.checkOutItem(_item('T1'), _member),
          throwsA(isA<TimeoutException>()),
        );
        expect(repo.getLoansCalls, greaterThan(0));
        expect(repo.getItemsCalls, greaterThan(0));
      },
    );

    test(
      'definitive 409 re-syncs too (racing retry proves the first commit)',
      () async {
        final repo = _CheckoutRepo(
          failAddLoan: ApiException(409, 'already on loan'),
        );
        final provider = LibraryProvider.forTesting(
          repository: repo,
          isHost: false,
        );
        await expectLater(
          provider.checkOutItem(_item('C1'), _member),
          throwsA(
            isA<ApiException>().having((e) => e.isConflict, 'isConflict', true),
          ),
        );
        expect(repo.getLoansCalls, greaterThan(0));
        expect(repo.getItemsCalls, greaterThan(0));
      },
    );

    test(
      'success path still refreshes exactly once and throws nothing',
      () async {
        final repo = _CheckoutRepo();
        repo.itemsOnHost = [_item('OK1', status: 'Emprunté')];
        final provider = LibraryProvider.forTesting(
          repository: repo,
          isHost: false,
        );
        await provider.checkOutItem(_item('OK1'), _member);
        expect(repo.addLoanCalls, 1);
        expect(repo.getLoansCalls, 1);
        expect(repo.getItemsCalls, 1);
        expect(provider.items.first.status, 'Emprunté');
      },
    );
  });
}

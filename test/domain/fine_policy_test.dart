import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/domain/fine_policy.dart';
import 'package:library_manager/models/loan.dart';

/// Phase 10.2 -- the money math, isolated from storage and HTTP. These are the
/// rules the accrual engine leans on, so they are proven exhaustively here:
/// partial-day rounding, the two disabled/zero guards, and the label.
void main() {
  group('FinePolicy.overdueDays', () {
    final due = DateTime(2026, 3, 1, 12);

    test('returned before the due date => 0', () {
      expect(
        FinePolicy.overdueDays(due, due.subtract(const Duration(days: 3))),
        0,
      );
    });

    test('returned exactly AT the due date => 0 (not strictly after)', () {
      expect(FinePolicy.overdueDays(due, due), 0);
    });

    test(
      'one minute late counts as a FULL day (never fractionally cheaper)',
      () {
        expect(
          FinePolicy.overdueDays(due, due.add(const Duration(minutes: 1))),
          1,
        );
      },
    );

    test('exact whole days', () {
      expect(FinePolicy.overdueDays(due, due.add(const Duration(days: 2))), 2);
    });

    test('whole days plus a partial day rounds UP', () {
      expect(
        FinePolicy.overdueDays(due, due.add(const Duration(days: 2, hours: 6))),
        3,
      );
    });
  });

  group('FinePolicy.amountFor', () {
    test('zero overdue days => 0', () => expect(FinePolicy.amountFor(0, 5), 0));
    test('a zero rate (disabled policy) => 0 even when overdue', () {
      expect(FinePolicy.amountFor(10, 0), 0);
    });
    test('a negative rate is clamped to 0, never a credit', () {
      expect(FinePolicy.amountFor(10, -3), 0);
    });
    test('days * rate', () {
      expect(FinePolicy.amountFor(3, 2.5), closeTo(7.5, 1e-9));
    });
  });

  group('FinePolicy.overdueDaysFor', () {
    Loan loanDue(DateTime due) => Loan(
      itemCode: '0001',
      memberId: '250001',
      memberName: 'Alice',
      itemTitle: 'Title',
      loanDate: due.subtract(const Duration(days: 14)),
      dueDate: due,
    );

    test('uses the supplied instant', () {
      final l = loanDue(DateTime(2026, 1, 10));
      expect(FinePolicy.overdueDaysFor(l, at: DateTime(2026, 1, 12)), 2);
    });

    test('not yet due => 0', () {
      final l = loanDue(DateTime(2026, 1, 10));
      expect(FinePolicy.overdueDaysFor(l, at: DateTime(2026, 1, 5)), 0);
    });
  });

  test('reasonFor is grammatical for one vs many', () {
    expect(FinePolicy.reasonFor(1), 'Overdue 1 day');
    expect(FinePolicy.reasonFor(4), 'Overdue 4 days');
  });
}

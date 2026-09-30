import '../models/loan.dart';

/// Pure, side-effect-free fine ACCRUAL rules (Phase 10.2 / BL "no fines"
/// feature). Living here keeps the money math in one exhaustively-testable
/// place, shared by the server engine that persists a fine at return time and
/// by any UI that previews a running overdue charge. The server is still the
/// authority that decides WHAT gets written; this only answers "how much".
class FinePolicy {
  FinePolicy._();

  /// Whole overdue days between [dueDate] and [returnedAt], counting any PART
  /// day as a full day (standard library policy: a book one minute late is one
  /// day late — never fractionally cheaper). Zero when returned on/before due.
  static int overdueDays(DateTime dueDate, DateTime returnedAt) {
    if (!returnedAt.isAfter(dueDate)) return 0;
    final delta = returnedAt.difference(dueDate);
    final whole = delta.inDays;
    final hasPartialDay = delta.inSeconds % 86400 != 0;
    return whole + (hasPartialDay ? 1 : 0);
  }

  /// Overdue days for a loan AT a moment in time — the amount owed if it were
  /// returned at [at] (defaults to now). Never negative, and zero once the
  /// grace of the due date is not exceeded.
  static int overdueDaysFor(Loan loan, {DateTime? at}) {
    final when = at ?? DateTime.now();
    return overdueDays(loan.dueDate, when);
  }

  /// Charge for [overdueDays] at [ratePerDay]. Guards the two degenerate cases
  /// (no days, no rate) to exactly 0.0 so a disabled policy can never accrue a
  /// rounding artefact.
  static double amountFor(int overdueDays, double ratePerDay) {
    if (overdueDays <= 0 || ratePerDay <= 0) return 0.0;
    return overdueDays * ratePerDay;
  }

  /// The fine text/label a ledger row carries, so the reason survives even if
  /// the rate is later changed by an admin.
  static String reasonFor(int overdueDays) =>
      'Overdue $overdueDays day${overdueDays == 1 ? '' : 's'}';
}

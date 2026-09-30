import '../models/loan.dart';

/// The canonical loan lifecycle state machine (Phase 2 / FB-01, BL-02).
///
/// Every legal transition between states lives here as pure, side-effect-free
/// functions so the rules have exactly one home and are exhaustively testable.
/// Illegal transitions *throw* rather than silently mutating state — this is
/// what previously allowed [LibraryProvider.renewLoan] to resurrect an already
/// returned loan (BL-02) and allowed a double check-in to double-return.
///
/// The server is the ultimate authority; the provider funnels all mutations
/// through these helpers so host and client agree on the rules.
class LoanTransitions {
  LoanTransitions._();

  /// Check the item out: a brand-new loan always starts [LoanStatus.active].
  static Loan checkOut({
    required String itemCode,
    required String memberId,
    required String memberName,
    required String itemTitle,
    required DateTime now,
    int durationDays = 15,
  }) {
    return Loan(
      itemCode: itemCode,
      memberId: memberId,
      memberName: memberName,
      itemTitle: itemTitle,
      loanDate: now,
      dueDate: now.add(Duration(days: durationDays)),
      status: LoanStatus.active.storage,
    );
  }

  /// Return an active loan. Throws if the loan is not active (guards against a
  /// double return / operating on an already-returned row).
  static Loan returnLoan(Loan loan, {DateTime? when}) {
    if (!loan.isActive) {
      throw StateError('Cannot return a loan that is not active.');
    }
    return loan.copyWith(
      status: LoanStatus.returned.storage,
      returnDate: when ?? DateTime.now(),
    );
  }

  /// Extend an active loan's due date. Throws if the loan is not active
  /// (BL-02: a returned loan must be checked out again, never "renewed" back
  /// to life, which used to erase its return date and corrupt history).
  static Loan renew(Loan loan, {int additionalDays = 15, DateTime? now}) {
    if (!loan.isActive) {
      throw StateError('Cannot renew a loan that is not active.');
    }
    return loan.copyWith(
      dueDate: loan.dueDate.add(Duration(days: additionalDays)),
      status: LoanStatus.active.storage,
    );
  }
}

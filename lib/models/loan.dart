/// Canonical loan lifecycle. This is the SINGLE source of truth for whether a
/// loan is currently on loan (Phase 2 / FB-01): previously "active" was defined
/// two ways — `status == 'Active'` in SQL and `returnDate == null` in Dart —
/// which could disagree. Now the stored [Loan.status] string is authoritative
/// and every predicate derives from it. "Overdue" is never stored; it is
/// derived from the due date of an *active* loan.
enum LoanStatus {
  active('Active'),
  returned('Returned');

  const LoanStatus(this.storage);

  /// Value persisted in the `loans.status` column (kept identical to the
  /// historical strings, so no data migration is required).
  final String storage;

  static LoanStatus parse(String? value) =>
      value == returned.storage ? LoanStatus.returned : LoanStatus.active;
}

class Loan {
  final int? id;
  final String itemCode; // Foreign key to LibraryItem
  final int?
  copyId; // Physical copy borrowed (Phase 2 / DB-02); null on legacy per-title loans
  final String memberId; // Foreign key to Member
  final String memberName; // Snapshot or Joined
  final String itemTitle; // Snapshot or Joined
  final DateTime loanDate;
  final DateTime dueDate;
  final DateTime? returnDate;
  final String status; // 'Active', 'Returned' (see [LoanStatus])

  Loan({
    this.id,
    required this.itemCode,
    this.copyId,
    required this.memberId,
    required this.memberName,
    required this.itemTitle,
    required this.loanDate,
    required this.dueDate,
    this.returnDate,
    this.status = 'Active',
  });

  /// Canonical lifecycle state derived from [status] (the authority).
  LoanStatus get loanStatus => LoanStatus.parse(status);

  /// A loan is active purely by its canonical [status]. `returnDate` is
  /// bookkeeping data, not the definition (FB-01).
  bool get isActive => loanStatus == LoanStatus.active;
  bool get isReturned => loanStatus == LoanStatus.returned;

  /// Derived, never stored: an active loan past its due date.
  bool get isOverdue => isActive && DateTime.now().isAfter(dueDate);

  Loan copyWith({
    int? id,
    String? itemCode,
    int? copyId,
    String? memberId,
    String? memberName,
    String? itemTitle,
    DateTime? loanDate,
    DateTime? dueDate,
    DateTime? returnDate,
    String? status,
  }) {
    return Loan(
      id: id ?? this.id,
      itemCode: itemCode ?? this.itemCode,
      copyId: copyId ?? this.copyId,
      memberId: memberId ?? this.memberId,
      memberName: memberName ?? this.memberName,
      itemTitle: itemTitle ?? this.itemTitle,
      loanDate: loanDate ?? this.loanDate,
      dueDate: dueDate ?? this.dueDate,
      returnDate: returnDate ?? this.returnDate,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'item_code': itemCode,
      'copy_id': copyId,
      'member_id': memberId,
      'member_name': memberName,
      'item_title': itemTitle,
      'loan_date': loanDate.toIso8601String(),
      'due_date': dueDate.toIso8601String(),
      'return_date': returnDate?.toIso8601String(),
      'status': status,
    };
  }

  factory Loan.fromMap(Map<String, dynamic> map) {
    return Loan(
      id: map['id']?.toInt(),
      itemCode: map['item_code'] ?? '',
      copyId: map['copy_id']?.toInt(),
      memberId: map['member_id'] ?? '',
      memberName: map['member_name'] ?? '',
      itemTitle: map['item_title'] ?? '',
      loanDate: DateTime.parse(map['loan_date']),
      dueDate: DateTime.parse(map['due_date']),
      returnDate: map['return_date'] != null
          ? DateTime.parse(map['return_date'])
          : null,
      status: map['status'] ?? 'Active',
    );
  }
}

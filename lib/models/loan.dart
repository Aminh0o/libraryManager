class Loan {
  final int? id;
  final String itemCode; // Foreign key to LibraryItem
  final String memberId; // Foreign key to Member
  final String memberName; // Snapshot or Joined
  final String itemTitle; // Snapshot or Joined
  final DateTime loanDate;
  final DateTime dueDate;
  final DateTime? returnDate;
  final String status; // 'Active', 'Returned', 'Overdue'

  Loan({
    this.id,
    required this.itemCode,
    required this.memberId,
    required this.memberName,
    required this.itemTitle,
    required this.loanDate,
    required this.dueDate,
    this.returnDate,
    this.status = 'Active',
  });

  bool get isReturned => returnDate != null;
  bool get isOverdue => !isReturned && DateTime.now().isAfter(dueDate);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'item_code': itemCode,
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
      memberId: map['member_id'] ?? '',
      memberName: map['member_name'] ?? '',
      itemTitle: map['item_title'] ?? '',
      loanDate: DateTime.parse(map['loan_date']),
      dueDate: DateTime.parse(map['due_date']),
      returnDate: map['return_date'] != null ? DateTime.parse(map['return_date']) : null,
      status: map['status'] ?? 'Active',
    );
  }
}

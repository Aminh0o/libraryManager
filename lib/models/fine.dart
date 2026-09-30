/// Fines & payments domain model (Phase 10.2).
///
/// A [Fine] is a single ledger entry assessing money on a member — created
/// automatically when an overdue loan is returned (see `FinePolicy` +
/// `DatabaseService` accrual) and resolved once it is PAID or WAIVED by an
/// operator. The ledger is append-mostly: a fine's `amount` is never mutated
/// after assessment; only its `status`/`resolved_*` change, so the financial
/// history stays trustworthy.
///
/// Deliberately free of Flutter/SQL so the server, the client and unit tests
/// share one vocabulary.
enum FineStatus {
  /// Assessed, not yet settled.
  pending('pending'),

  /// Collected (paid) by an operator.
  paid('paid'),

  /// Written off by an operator (goodwill / error); never collected.
  waived('waived');

  const FineStatus(this.storage);

  /// Exact value stored in the `fines.status` column.
  final String storage;

  /// STRICT parse for untrusted input (HTTP bodies / query params): returns
  /// null rather than guessing, so a forged/typo status can never silently
  /// resolve an open fine. Mirrors `UserRole.tryParse`.
  static FineStatus? tryParse(Object? value) {
    final s = value?.toString();
    for (final st in FineStatus.values) {
      if (st.storage == s) return st;
    }
    return null;
  }

  /// Lenient parse for ALREADY-Persisted rows: unknown => [pending] (the least
  /// favourable-to-member, most conservative state — an unrecognised entry is
  /// treated as still owed, never as silently settled).
  static FineStatus parse(Object? value) =>
      tryParse(value) ?? FineStatus.pending;
}

class Fine {
  const Fine({
    this.id,
    this.loanId,
    required this.memberId,
    required this.amount,
    this.status = FineStatus.pending,
    this.reason,
    this.createdAt,
    this.resolvedAt,
    this.resolvedBy,
  });

  final int? id;

  /// The loan that generated this fine (null for a manually-assessed fine).
  final int? loanId;

  /// The member card id (`members.id`) the fine is owed by.
  final String memberId;

  /// Amount assessed in the configured currency. Fixed at creation.
  final double amount;

  final FineStatus status;
  final String? reason;
  final String? createdAt;
  final String? resolvedAt;

  /// Username of the operator who paid/waived this fine (audit of WHO moved
  /// money — Phase 10.1 identity, wired through 10.2).
  final String? resolvedBy;

  bool get isOpen => status == FineStatus.pending;

  Fine copyWith({
    int? id,
    int? loanId,
    String? memberId,
    double? amount,
    FineStatus? status,
    String? reason,
    String? createdAt,
    String? resolvedAt,
    String? resolvedBy,
  }) {
    return Fine(
      id: id ?? this.id,
      loanId: loanId ?? this.loanId,
      memberId: memberId ?? this.memberId,
      amount: amount ?? this.amount,
      status: status ?? this.status,
      reason: reason ?? this.reason,
      createdAt: createdAt ?? this.createdAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      resolvedBy: resolvedBy ?? this.resolvedBy,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'loan_id': loanId,
    'member_id': memberId,
    'amount': amount,
    'status': status.storage,
    'reason': reason,
    'created_at': createdAt,
    'resolved_at': resolvedAt,
    'resolved_by': resolvedBy,
  };

  factory Fine.fromMap(Map<String, dynamic> map) => Fine(
    id: (map['id'] as num?)?.toInt(),
    loanId: (map['loan_id'] as num?)?.toInt(),
    memberId: (map['member_id'] ?? '').toString(),
    amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
    status: FineStatus.parse(map['status']),
    reason: map['reason']?.toString(),
    createdAt: map['created_at']?.toString(),
    resolvedAt: map['resolved_at']?.toString(),
    resolvedBy: map['resolved_by']?.toString(),
  );
}

/// The library's fine policy: how much accrues per overdue day, and the
/// currency label. Persisted in the `metadata` key/value table so it survives
/// a LAN client restart and is authored only by an administrator.
///
/// The DEFAULT rate is **0.0** — enabling fines is an explicit operator action,
/// so deploying this feature NEVER retroactively charges an existing member.
class FineSettings {
  const FineSettings({
    required this.ratePerDay,
    this.currency = defaultCurrency,
  });

  final double ratePerDay;
  final String currency;

  bool get enabled => ratePerDay > 0;

  static const String defaultCurrency = 'DZD';

  /// A disabled settings object (rate 0) — the safe default.
  static const FineSettings disabled = FineSettings(ratePerDay: 0.0);

  Map<String, dynamic> toMap() => {
    'rate_per_day': ratePerDay,
    'currency': currency,
  };

  factory FineSettings.fromMap(Map<dynamic, dynamic> map) => FineSettings(
    ratePerDay: (map['rate_per_day'] as num?)?.toDouble() ?? 0.0,
    currency: (map['currency'] ?? defaultCurrency).toString(),
  );
}

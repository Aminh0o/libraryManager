/// Reservations / hold queue domain model (Phase 10.3).
///
/// A [Reservation] is a member's place in the queue for a title. The SERVER
/// owns the queue lifecycle: a hold is queued, becomes `available` when a
/// copy is returned and promoted to that holder (with a pickup deadline), and
/// ends `fulfilled` (the holder borrowed the reserved copy), `expired` (the
/// pickup window lapsed) or `cancelled`. A queued hold reserves NO physical
/// copy; only a promoted hold claims one, via the same compare-and-swap copy
/// claims every other state transition uses (BL-01/TX-02 discipline).
///
/// Deliberately free of Flutter/SQL so host, server routes, client and tests
/// share one vocabulary.
enum ReservationStatus {
  /// In line, waiting for a copy to come back.
  queued('queued'),

  /// A copy was promoted to this holder; borrow it before [availableUntil].
  available('available'),

  /// Terminal: the holder checked the reserved copy out.
  fulfilled('fulfilled'),

  /// Terminal: the holder gave up their place / staff released the hold.
  cancelled('cancelled'),

  /// Terminal: the pickup window lapsed; the copy went back to the shelf.
  expired('expired');

  const ReservationStatus(this.storage);

  /// Exact value stored in the `reservations.status` column.
  final String storage;

  /// Terminal states leave the holder out of line.
  bool get isTerminal => this != queued && this != available;

  /// STRICT parse for untrusted input (HTTP bodies / query params / UI):
  /// returns null rather than guessing — the two-parser discipline from
  /// Phase 10.1/10.2.
  static ReservationStatus? tryParse(Object? value) {
    final s = value?.toString();
    for (final st in ReservationStatus.values) {
      if (st.storage == s) return st;
    }
    return null;
  }

  /// Lenient parse for ALREADY-Persisted rows: unknown => [queued] (the most
  /// conservative reading — an unrecognised entry still holds its place in
  /// line rather than silently vanishing or claiming a copy).
  static ReservationStatus parse(Object? value) =>
      tryParse(value) ?? ReservationStatus.queued;
}

class Reservation {
  const Reservation({
    this.id,
    required this.itemCode,
    required this.memberId,
    this.copyId,
    this.status = ReservationStatus.queued,
    this.createdAt,
    this.availableAt,
    this.availableUntil,
    this.endedAt,
    this.note,
    this.rank,
  });

  final int? id;

  /// The title (`library_items.code`) the member is waiting for.
  final String itemCode;

  /// The member card id (`members.member_id`) holding the place.
  final String memberId;

  /// The copy claimed by a PROMOTED hold (null while queued, and on every
  /// legacy per-title flow that models no copies).
  final int? copyId;

  final ReservationStatus status;

  /// ISO-8601 timestamps, stored as TEXT like every other table here.
  final String? createdAt;

  /// When the hold was promoted (copy handed to the front of the queue).
  final String? availableAt;

  /// Pickup deadline: promote time + the hold policy window.
  final String? availableUntil;

  /// When the hold reached a terminal state.
  final String? endedAt;

  final String? note;

  /// Pass 6: manual queue position within the item's queued holds.
  /// Nullable; `null` means "not manually ordered" and resolves to the
  /// row's `id` at read time (see `COALESCE(rank, id)` in the query).
  /// This is what makes the pre-Pass-6 723-row corpus behave identically
  /// to the new build: no backfill is required because NULL and unset are
  /// the same order the FIFO query used before this column existed.
  final int? rank;

  bool get isLive => !status.isTerminal;

  DateTime? get availableUntilDateTime =>
      availableUntil == null ? null : DateTime.tryParse(availableUntil!);

  Reservation copyWith({
    int? id,
    String? itemCode,
    String? memberId,
    int? copyId,
    ReservationStatus? status,
    String? createdAt,
    String? availableAt,
    String? availableUntil,
    String? endedAt,
    String? note,
    int? rank,
  }) {
    return Reservation(
      id: id ?? this.id,
      itemCode: itemCode ?? this.itemCode,
      memberId: memberId ?? this.memberId,
      copyId: copyId ?? this.copyId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      availableAt: availableAt ?? this.availableAt,
      availableUntil: availableUntil ?? this.availableUntil,
      endedAt: endedAt ?? this.endedAt,
      note: note ?? this.note,
      rank: rank ?? this.rank,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'item_code': itemCode,
    'member_id': memberId,
    'copy_id': copyId,
    'status': status.storage,
    'created_at': createdAt,
    'available_at': availableAt,
    'available_until': availableUntil,
    'ended_at': endedAt,
    'note': note,
    if (rank != null) 'rank': rank,
  };

  factory Reservation.fromMap(Map<String, dynamic> map) => Reservation(
    id: (map['id'] as num?)?.toInt(),
    itemCode: (map['item_code'] ?? '').toString(),
    memberId: (map['member_id'] ?? '').toString(),
    copyId: (map['copy_id'] as num?)?.toInt(),
    status: ReservationStatus.parse(map['status']),
    createdAt: map['created_at']?.toString(),
    availableAt: map['available_at']?.toString(),
    availableUntil: map['available_until']?.toString(),
    endedAt: map['ended_at']?.toString(),
    note: map['note']?.toString(),
    rank: (map['rank'] as num?)?.toInt(),
  );
}

/// The library's hold policy: how long a promoted holder has to pick the copy
/// up, and how long anyone may sit in a queue. Persisted in the existing
/// `metadata` key/value table (like the fine rate), so it survives restarts
/// and is authored only by an administrator.
///
/// The defaults are deliberately generous but FINITE: an uncollected hold must
/// never lock a copy away from the shelf forever.
class HoldSettings {
  const HoldSettings({required this.pickupDays, required this.queueMaxPerItem});

  /// Days a promoted (available) hold waits on the shelf for its holder.
  final int pickupDays;

  /// How many live holds one title may hold in total (queue length cap).
  final int queueMaxPerItem;

  static const int defaultPickupDays = 7;
  static const int defaultQueueMax = 20;

  /// The safe default — plain-library norms, capped queue.
  static const HoldSettings defaults = HoldSettings(
    pickupDays: defaultPickupDays,
    queueMaxPerItem: defaultQueueMax,
  );

  Map<String, dynamic> toMap() => {
    'pickup_days': pickupDays,
    'queue_max_per_item': queueMaxPerItem,
  };

  /// Lenient read for persisted rows: a malformed/negative/out-of-range value
  /// degrades to the DEFAULT rather than disabling expiry or unbounding the
  /// queue (mirrors the fine-rate degradation). Bounds are generous on
  /// purpose: 0 days would make holds pointless, and a 10000-strong queue is
  /// an accidental DoS on the shelf.
  factory HoldSettings.fromMap(Map<dynamic, dynamic> map) {
    int read(Object? raw, int fallback, int min, int max) {
      final v = (raw as num?)?.toInt();
      if (v == null || !v.isFinite || v < min || v > max) return fallback;
      return v;
    }

    return HoldSettings(
      pickupDays: read(map['pickup_days'], defaultPickupDays, 1, 90),
      queueMaxPerItem: read(map['queue_max_per_item'], defaultQueueMax, 1, 500),
    );
  }
}

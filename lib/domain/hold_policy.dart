import '../models/reservation.dart';

/// Pure, side-effect-free rules for the hold queue (Phase 10.3).
///
/// Same discipline as [FinePolicy] and [CopyLedger]: the decision logic lives
/// here, provable without a database or a socket, while `DatabaseService`
/// executes it inside transactions. Nothing in this file mutates state or
/// touches storage — expiry, pickup deadlines and queue ordering are all
/// deterministic functions of the timestamps the server stamped.
class HoldPolicy {
  HoldPolicy._();

  /// The deadline for a hold promoted at [promotedAt] under [settings].
  static DateTime deadlineFor(DateTime promotedAt, HoldSettings settings) =>
      promotedAt.add(Duration(days: settings.pickupDays));

  /// Whether an [available] hold has lapsed at [now] (strict: the deadline
  /// second itself is still the holder's). A queued hold NEVER expires —
  /// only a promoted copy sits on the shelf waiting.
  static bool isExpiredAt(Reservation r, DateTime now) {
    if (r.status != ReservationStatus.available) return false;
    final until = r.availableUntilDateTime;
    if (until == null) return false; // defensive: malformed row is not lapsed
    return now.isAfter(until);
  }

  /// Queue order: promoted holders are always "at the counter", then the
  /// line in operator-curated order. Within each status bucket the effective
  /// position is `rank ?? id` (mirrors the SQL `COALESCE(rank, id) ASC, id ASC`
  /// used by the host query), so an explicit rank set by the reorder UI wins
  /// over the original FIFO; rows with no rank still sort by id, which is
  /// insertion order on an AUTOINCREMENT table (identical to the pre-Pass-6
  /// `created_at ASC, id ASC` behaviour for every existing row).
  static int Function(Reservation, Reservation) get queueOrder => (a, b) {
    final statusRank = {
      ReservationStatus.available: 0,
      ReservationStatus.queued: 1,
    };
    final ra = statusRank[a.status]!, rb = statusRank[b.status]!;
    if (ra != rb) return ra.compareTo(rb);
    // Pass 6: effective position = rank if explicitly set, else id.
    final effA = a.rank ?? a.id ?? 0;
    final effB = b.rank ?? b.id ?? 0;
    final byEff = effA.compareTo(effB);
    if (byEff != 0) return byEff;
    return (a.id ?? 0).compareTo(b.id ?? 0);
  };

  /// 1-based position in line for a live hold within its title's queue
  /// ([holdsForItem] must be the LIVE holds of that one item). Returns null
  /// for terminal rows and for promoted holds (they have no "place in line" —
  /// they are already at the counter).
  static int? queuePosition(
    Reservation r,
    List<Reservation> holdsForItem,
    DateTime now,
  ) {
    if (r.status != ReservationStatus.queued) return null;
    final live =
        holdsForItem.where((h) => h.status == ReservationStatus.queued).toList()
          ..sort(queueOrder);
    final idx = live.indexWhere((h) => h.id == r.id);
    return idx < 0 ? null : idx + 1;
  }

  /// Human-readable reason a member cannot place another hold, or null when
  /// the request is allowed by the pure rules ([liveForItem] = the title's
  /// current live holds; the caller enforces existence checks, which are
  /// storage concerns).
  static String? refusalFor(
    Reservation? existingLiveBySameMember,
    int liveCount,
    HoldSettings settings,
  ) {
    if (existingLiveBySameMember != null) {
      return 'This member already has a live hold on this item.';
    }
    if (liveCount >= settings.queueMaxPerItem) {
      return 'The hold queue for this item is full '
          '(max ${settings.queueMaxPerItem}).';
    }
    return null;
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/models/reservation.dart';
import 'package:library_manager/domain/hold_policy.dart';

/// Phase 10.3 -- the PURE hold-queue rules, proven without a database or a
/// socket. Deadlines, expiry, queue ordering, position-in-line and the
/// place-a-hold refusals are deterministic functions of the timestamps and
/// settings the server stores; [DatabaseService] simply executes exactly these
/// rules inside its transactions.
void main() {
  Reservation hold({
    int? id,
    String member = 'M1',
    String item = '0001',
    ReservationStatus status = ReservationStatus.queued,
    String? created,
    String? until,
    int? copyId,
    int? rank,
  }) =>
      Reservation(
        id: id,
        itemCode: item,
        memberId: member,
        status: status,
        copyId: copyId,
        createdAt: created,
        availableUntil: until,
        rank: rank,
      );

  group('deadlineFor', () {
    test('adds the pickup window to the promotion instant', () {
      final promoted = DateTime(2026, 5, 1, 9);
      final d = HoldPolicy.deadlineFor(
          promoted, const HoldSettings(pickupDays: 7, queueMaxPerItem: 20));
      expect(d, DateTime(2026, 5, 8, 9));
    });
  });

  group('isExpiredAt', () {
    test('a queued hold never expires', () {
      final r = hold(status: ReservationStatus.queued, until: '2020-01-01T00:00:00.000');
      expect(HoldPolicy.isExpiredAt(r, DateTime(2026, 1, 1)), isFalse);
    });

    test('an available hold past its deadline is expired', () {
      final r = hold(
          status: ReservationStatus.available, until: '2026-05-01T00:00:00.000');
      expect(HoldPolicy.isExpiredAt(r, DateTime(2026, 5, 2)), isTrue);
    });

    test('the deadline instant itself is still the holder\'s (strict)', () {
      final r = hold(
          status: ReservationStatus.available, until: '2026-05-01T00:00:00.000');
      expect(HoldPolicy.isExpiredAt(r, DateTime(2026, 5, 1)), isFalse);
    });

    test('a malformed available hold (no deadline) is not lapsed', () {
      final r = hold(status: ReservationStatus.available, until: null);
      expect(HoldPolicy.isExpiredAt(r, DateTime(2026, 5, 2)), isFalse);
    });
  });

  group('queueOrder', () {
    test('promoted holders sit ahead of the line', () {
      final list = [
        hold(id: 1, status: ReservationStatus.queued, created: '2026-01-01T00:00:00.000'),
        hold(id: 2, status: ReservationStatus.available, created: '2026-06-01T00:00:00.000'),
      ]..sort(HoldPolicy.queueOrder);
      expect(list.first.id, 2); // the available hold wins despite a later stamp
    });

    test('the line is ordered by COALESCE(rank, id) — id when rank is NULL', () {
      // Pass 6: the SQL ORDER BY changed from `created_at ASC, id ASC` to
      // `COALESCE(rank, id) ASC, id ASC`. For NULL-rank rows the effective
      // position IS the id, so the order is id ASC regardless of dates.
      final list = [
        hold(id: 3, status: ReservationStatus.queued, created: '2026-01-01T00:00:00.000'),
        hold(id: 1, status: ReservationStatus.queued, created: '2026-01-01T00:00:00.000'),
        hold(id: 2, status: ReservationStatus.queued, created: '2025-12-31T00:00:00.000'),
      ]..sort(HoldPolicy.queueOrder);
      expect(list.map((r) => r.id).toList(), [1, 2, 3]);
    });

    test('an explicit rank overrides id order', () {
      // Operator moved id=5 to the front (rank=0); it now leads the line
      // even though its id is the highest.
      final list = [
        hold(id: 3, status: ReservationStatus.queued),
        hold(id: 5, status: ReservationStatus.queued, rank: 0),
        hold(id: 4, status: ReservationStatus.queued),
      ]..sort(HoldPolicy.queueOrder);
      expect(list.map((r) => r.id).toList(), [5, 3, 4]);
    });
  });

  group('queuePosition', () {
    final line = [
      hold(id: 10, status: ReservationStatus.queued, created: '2026-01-01T00:00:00.000'),
      hold(id: 11, status: ReservationStatus.queued, created: '2026-01-02T00:00:00.000'),
      hold(id: 5, status: ReservationStatus.available, created: '2026-01-03T00:00:00.000'),
    ];

    test('promoted and terminal rows have no place in line', () {
      expect(
          HoldPolicy.queuePosition(
              hold(id: 5, status: ReservationStatus.available), line, DateTime(2026)),
          isNull);
      expect(
          HoldPolicy.queuePosition(
              hold(id: 9, status: ReservationStatus.cancelled), line, DateTime(2026)),
          isNull);
    });

    test('a queued hold reports its 1-based position', () {
      expect(
          HoldPolicy.queuePosition(
              hold(id: 10, status: ReservationStatus.queued), line, DateTime(2026)),
          1);
      expect(
          HoldPolicy.queuePosition(
              hold(id: 11, status: ReservationStatus.queued), line, DateTime(2026)),
          2);
    });
  });

  group('refusalFor', () {
    const settings = HoldSettings(pickupDays: 7, queueMaxPerItem: 2);

    test('a member with a live hold cannot double-line', () {
      expect(
          HoldPolicy.refusalFor(hold(id: 1), 1, settings),
          contains('already has a live hold'));
    });

    test('a full queue refuses a new arrival', () {
      expect(
          HoldPolicy.refusalFor(null, 2, settings), contains('queue for this item is full'));
    });

    test('an eligible request is allowed', () {
      expect(HoldPolicy.refusalFor(null, 1, settings), isNull);
    });
  });
}

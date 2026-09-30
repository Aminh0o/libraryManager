import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/domain/report_query.dart';
import 'package:library_manager/models/report.dart';

// Phase 10.4 -- the pure report-query rules. These are the SINGLE source of
// truth shared by the route layer (to reject a bad request before any work) and
// the host engine (to resolve a default window), so proving them here proves
// host and LAN client agree on exactly the same window for the same input.

void main() {
  group('ReportKind.tryParse (strict, untrusted boundary)', () {
    test('accepts the exact stored tokens', () {
      for (final k in ReportKind.values) {
        expect(ReportKind.tryParse(k.storage), k);
      }
    });

    test('refuses anything else rather than guessing', () {
      expect(ReportKind.tryParse('nope'), isNull);
      expect(ReportKind.tryParse(''), isNull);
      expect(ReportKind.tryParse('Circulation'), isNull); // case-sensitive
      expect(ReportKind.tryParse(null), isNull);
    });
  });

  group('ReportQuery.usesWindow', () {
    test('circulation / fines / members are windowed', () {
      expect(ReportQuery.usesWindow(ReportKind.circulation), isTrue);
      expect(ReportQuery.usesWindow(ReportKind.fines), isTrue);
      expect(ReportQuery.usesWindow(ReportKind.members), isTrue);
    });

    test('overdue / inventory are not', () {
      expect(ReportQuery.usesWindow(ReportKind.overdue), isFalse);
      expect(ReportQuery.usesWindow(ReportKind.inventory), isFalse);
    });
  });

  group('ReportQuery.parseDay', () {
    test('null / blank => null (so a default can apply)', () {
      expect(ReportQuery.parseDay(null), isNull);
      expect(ReportQuery.parseDay('   '), isNull);
    });

    test('accepts a real YYYY-MM-DD day', () {
      expect(ReportQuery.parseDay('2026-02-28'), DateTime(2026, 2, 28));
    });

    test('rejects a non-calendar format', () {
      expect(() => ReportQuery.parseDay('2026/02/28'), throwsFormatException);
      expect(() => ReportQuery.parseDay('28-02-2026'), throwsFormatException);
      expect(() => ReportQuery.parseDay('2026-2-8'), throwsFormatException);
      expect(() => ReportQuery.parseDay('garbage'), throwsFormatException);
    });

    test('rejects a non-existent date (no silent rollover)', () {
      expect(() => ReportQuery.parseDay('2026-02-30'), throwsFormatException);
      expect(() => ReportQuery.parseDay('2026-13-01'), throwsFormatException);
      expect(() => ReportQuery.parseDay('2025-02-29'), throwsFormatException);
    });

    test('accepts a leap day that really exists', () {
      expect(ReportQuery.parseDay('2024-02-29'), DateTime(2024, 2, 29));
    });
  });

  group('ReportQuery.window', () {
    final now = DateTime(2026, 9, 21, 13, 45); // mid-afternoon

    test('a windowless kind returns null regardless of inputs', () {
      expect(
        ReportQuery.window(ReportKind.overdue, from: '2026-01-01'),
        isNull,
      );
      expect(
        ReportQuery.window(ReportKind.inventory, to: '2026-12-31'),
        isNull,
      );
    });

    test(
      'defaults to the last 30 days ending today (time-of-day stripped)',
      () {
        final w = ReportQuery.window(ReportKind.circulation, now: now)!;
        expect(w.toDay, '2026-09-21');
        expect(w.fromDay, '2026-08-22');
      },
    );

    test('honours an explicit inclusive window', () {
      final w = ReportQuery.window(
        ReportKind.members,
        from: '2026-09-01',
        to: '2026-09-10',
        now: now,
      )!;
      expect(w.fromDay, '2026-09-01');
      expect(w.toDay, '2026-09-10');
    });

    test('a reversed range is refused', () {
      expect(
        () => ReportQuery.window(
          ReportKind.fines,
          from: '2026-09-10',
          to: '2026-09-01',
          now: now,
        ),
        throwsFormatException,
      );
    });

    test('a malformed bound is refused before any defaulting', () {
      expect(
        () => ReportQuery.window(
          ReportKind.circulation,
          from: 'yesterday',
          now: now,
        ),
        throwsFormatException,
      );
    });

    test('an absurdly large span is refused (bounded work per request)', () {
      expect(
        () => ReportQuery.window(
          ReportKind.circulation,
          from: '1900-01-01',
          to: '2026-09-21',
          now: now,
        ),
        throwsFormatException,
      );
    });

    test('same-day window is allowed (from == to)', () {
      final w = ReportQuery.window(
        ReportKind.circulation,
        from: '2026-09-21',
        to: '2026-09-21',
        now: now,
      )!;
      expect(w.fromDay, w.toDay);
    });
  });
}

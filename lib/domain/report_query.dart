import '../models/report.dart';

/// A resolved, inclusive `[from, to]` calendar-day window. Both ends are
/// midnight-local day markers; the day strings (`YYYY-MM-DD`) are what the host
/// SQL compares against `substr(<date col>, 1, 10)` -- the stored loan / fine
/// timestamps are fixed-precision ISO, so slicing the leading 10 chars is a
/// format-stable way to compare by CALENDAR DAY and sidestep the time-of-day /
/// DST ambiguity DB-07 warns about (we never compare raw timestamp strings).
class ReportWindow {
  const ReportWindow(this.from, this.to);

  final DateTime from;
  final DateTime to;

  String get fromDay => _day(from);
  String get toDay => _day(to);

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// The pure report-query rules shared by the route layer (to reject a bad
/// request BEFORE any work) and the host engine (to resolve defaults). Keeping
/// date parsing here means host and LAN client agree on exactly the same window
/// for the same input, and gives the rules a home that is trivially unit-tested.
class ReportQuery {
  const ReportQuery._();

  /// When a windowed report is requested without explicit bounds, cover the
  /// most recent month -- a sensible default that is neither empty nor unbounded.
  static const int defaultLookbackDays = 30;

  /// Hard ceiling on a window span, so a typo'd or hostile range cannot make the
  /// host aggregate an absurd number of days in one request.
  static const int maxWindowDays = 3660; // ~10 years

  static final RegExp _dayPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  /// Whether [kind] is scoped by a date window (overdue / inventory are not).
  static bool usesWindow(ReportKind kind) =>
      kind == ReportKind.circulation ||
      kind == ReportKind.fines ||
      kind == ReportKind.members;

  /// STRICT calendar-day parse: throws [FormatException] on a malformed or
  /// non-existent date (e.g. 2026-02-30). Returns null for an empty/absent
  /// value so the caller can apply a default.
  static DateTime? parseDay(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final m = _dayPattern.firstMatch(raw.trim());
    if (m == null) {
      throw const FormatException('Date must be in YYYY-MM-DD form.');
    }
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    final dt = DateTime(y, mo, d);
    // Reject rollover (e.g. month 13 or Feb 30 normalise to a different date).
    if (dt.year != y || dt.month != mo || dt.day != d) {
      throw const FormatException('That is not a real calendar date.');
    }
    return dt;
  }

  /// Resolve the effective window for [kind], applying defaults when a bound is
  /// omitted. Throws [FormatException] for a malformed date, a reversed range,
  /// or an over-long span. Returns null for a windowless kind.
  static ReportWindow? window(
    ReportKind kind, {
    String? from,
    String? to,
    DateTime? now,
  }) {
    if (!usesWindow(kind)) return null;
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final f =
        parseDay(from) ??
        today.subtract(const Duration(days: defaultLookbackDays));
    final t = parseDay(to) ?? today;
    if (f.isAfter(t)) {
      throw const FormatException('The start date is after the end date.');
    }
    if (t.difference(f).inDays > maxWindowDays) {
      throw const FormatException('The requested date range is too large.');
    }
    return ReportWindow(f, t);
  }
}

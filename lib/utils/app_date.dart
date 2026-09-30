/// Shared, human-friendly date / time formatting for every user-facing
/// surface (Reports header, Users list subtitle, Reservations pickup deadline,
/// Chat timestamps, History rows, etc.).
///
/// Before this helper, three different screens interpolated a raw Dart
/// `DateTime.toString()` (or a stored ISO-8601 `String`) into UI copy, so a
/// user saw `2026-09-29T23:30:35.331300` in what should have been a friendly
/// subtitle. Centralising the format here means the locale, the calendar
/// granularity and the relative-day behaviour are all decided once, and any
/// screen can opt into the same voice without re-deriving it.
///
/// All methods are pure. No `intl` / `intl_utils` dependency: the product
/// ships with an English-biased technical audience, `yyyy-MM-dd` reads as
/// locale-neutral and unambiguous, and the relative forms ("today", "yesterday")
/// are the only prose the app needs. If a full localisation of month names is
/// required later, only this file changes.
abstract final class AppDate {
  /// Parse an ISO-8601 timestamp stored as TEXT in SQLite, or accept an
  /// already-typed [DateTime]. Returns `null` on malformed input; callers
  /// should surface an empty string rather than throw when the field is
  /// optional in the underlying model.
  static DateTime? tryParse(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  /// `2026-09-29` — unambiguous, sortable, locale-neutral. Used wherever a
  /// bare calendar date belongs (subtitle lines, table cells, export header).
  static String date(Object? raw) {
    final dt = tryParse(raw);
    if (dt == null) return '';
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// `2026-09-29 23:30` — day plus 24-hour time, without seconds or timezone
  /// noise. Suitable for audit-log rows, hold pickup deadlines and report
  /// generation timestamps.
  static String dateTime(Object? raw) {
    final dt = tryParse(raw);
    if (dt == null) return '';
    final local = dt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${date(local)} $hh:$mm';
  }

  /// `today` / `yesterday` / `2026-09-29` — collapses same-day and
  /// previous-day hits to prose so a chat sidebar or history row reads
  /// naturally, and falls back to [date] for anything older.
  static String relativeDay(Object? raw, {DateTime? now}) {
    final dt = tryParse(raw);
    if (dt == null) return '';
    final reference = (now ?? DateTime.now()).toLocal();
    final local = dt.toLocal();
    final a = DateTime(local.year, local.month, local.day);
    final b = DateTime(reference.year, reference.month, reference.day);
    final diff = b.difference(a).inDays;
    if (diff == 0) return 'today';
    if (diff == 1) return 'yesterday';
    if (diff == -1) return 'tomorrow';
    return date(local);
  }

  /// `23:30` — bare wall-clock time, for chat bubbles and inline metadata
  /// where the date is already implied by context.
  static String time(Object? raw) {
    final dt = tryParse(raw);
    if (dt == null) return '';
    final local = dt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

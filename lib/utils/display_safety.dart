/// Pure, throw-free display helpers for values that originate from stored rows
/// (SQLite maps / JSON) whose shape the UI cannot fully trust. A legacy,
/// restored, or pre-P9-9.7 client-forged history row can carry a null / empty /
/// malformed field, and the previous inline `DateTime.parse(...)` / direct
/// `Text(...)` calls raised an uncaught exception that blanked the whole screen
/// (FE2-08). These helpers turn a risky value into a safe one so a single bad
/// row degrades gracefully instead of crashing the view.
library;

/// Parses a stored ISO-8601 timestamp WITHOUT throwing. Returns `null` for a
/// missing, non-String, empty, or malformed value so the caller can show a
/// placeholder rather than letting `FormatException` tear down the widget tree.
DateTime? tryParseTimestamp(Object? raw) =>
    (raw is String && raw.isNotEmpty) ? DateTime.tryParse(raw) : null;

/// A non-null, display-safe string for a stored field. Returns [fallback]
/// (default em dash) when the value is null, not a [String], or blank after
/// trimming, so `Text(...)` never receives `null` and an empty cell renders a
/// visible placeholder instead of nothing.
String safeText(Object? value, {String fallback = '\u2014'}) {
  if (value is! String) return fallback;
  final trimmed = value.trim();
  return trimmed.isEmpty ? fallback : trimmed;
}

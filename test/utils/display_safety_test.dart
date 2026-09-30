import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/utils/display_safety.dart';

/// FE2-08: the history screen called `DateTime.parse(entry['timestamp'])` and
/// rendered stored fields directly, so a legacy / restored / pre-P9-9.7 forged
/// row carrying a null or malformed value threw an uncaught exception and blanked
/// the whole list. These are the throw-free guards it now routes through.
void main() {
  group('tryParseTimestamp', () {
    test('parses a valid ISO-8601 string', () {
      final dt = tryParseTimestamp('2026-09-21T10:30:00.000');
      expect(dt, isNotNull);
      expect(dt!.year, 2026);
    });

    test('returns null (never throws) for missing / bad input', () {
      expect(tryParseTimestamp(null), isNull);
      expect(tryParseTimestamp(''), isNull);
      expect(tryParseTimestamp('not-a-date'), isNull);
      expect(tryParseTimestamp(123), isNull); // non-String, e.g. an int column
    });
  });

  group('safeText', () {
    test('passes through a non-empty string', () {
      expect(safeText('hello'), 'hello');
      expect(safeText('  padded  '), 'padded');
    });

    test('substitutes the fallback for null / non-String / blank', () {
      expect(safeText(null), '\u2014');
      expect(safeText(''), '\u2014');
      expect(safeText('   '), '\u2014');
      expect(safeText(42), '\u2014');
      expect(safeText(null, fallback: '-'), '-');
      // The history operation badge relies on a '' fallback, not the default.
      expect(safeText(null, fallback: ''), '');
    });
  });
}

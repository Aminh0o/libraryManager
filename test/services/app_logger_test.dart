import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:library_manager/services/app_logger.dart';

/// REL/logging: the persisted, leveled, rotating diagnostics sink.
void main() {
  DateTime fixedClock() => DateTime.utc(2026, 1, 2, 3, 4, 5);

  group('AppLogger levels + formatting (injected sink)', () {
    test('drops records below minLevel and keeps those at/above', () {
      final lines = <String>[];
      final log = AppLogger(
        minLevel: LogLevel.info,
        sink: lines.add,
        clock: fixedClock,
      );

      log.debug('t', 'hidden');
      log.info('t', 'shown-info');
      log.warn('t', 'shown-warn');
      log.error('t', 'shown-error');

      expect(lines, hasLength(3));
      expect(lines.any((l) => l.contains('hidden')), isFalse);
      expect(lines[0], contains('INFO'));
      expect(lines[1], contains('WARN'));
      expect(lines[2], contains('ERROR'));
    });

    test('a debug-level logger emits everything', () {
      final lines = <String>[];
      final log = AppLogger(
        minLevel: LogLevel.debug,
        sink: lines.add,
        clock: fixedClock,
      );
      log.debug('t', 'now-visible');
      expect(lines.single, contains('DEBUG'));
      expect(lines.single, contains('now-visible'));
    });

    test('line format is "<iso> LEVEL [tag] message"', () {
      final lines = <String>[];
      final log = AppLogger(
        minLevel: LogLevel.info,
        sink: lines.add,
        clock: fixedClock,
      );
      log.info('http', 'listening 8080');
      expect(
        lines.single,
        '2026-01-02T03:04:05.000Z INFO [http] listening 8080',
      );
    });

    test('error()/warn() append error + stack detail lines', () {
      final lines = <String>[];
      final log = AppLogger(
        minLevel: LogLevel.info,
        sink: lines.add,
        clock: fixedClock,
      );
      log.error('db', 'write failed', StateError('boom'), StackTrace.empty);
      final out = lines.single;
      expect(out, contains('ERROR [db] write failed'));
      expect(out, contains('error: Bad state: boom'));
      expect(out, contains('stack:'));
    });

    test('a throwing sink never propagates to the caller', () {
      final log = AppLogger(
        minLevel: LogLevel.debug,
        clock: fixedClock,
        sink: (_) => throw StateError('sink down'),
      );
      expect(() => log.info('t', 'hi'), returnsNormally);
    });
  });

  group('AppLogger file persistence + rotation (real temp files)', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('lib_log_'));
    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('records are appended to the file and survive flush()', () async {
      final file = File(p.join(tmp.path, 'app.log'));
      final log = AppLogger(
        minLevel: LogLevel.info,
        logFile: file,
        clock: fixedClock,
      );
      log.info('a', 'first');
      log.warn('a', 'second');
      await log.flush();

      final text = file.readAsStringSync();
      expect(text, contains('INFO [a] first'));
      expect(text, contains('WARN [a] second'));
    });

    test('exceeding the byte cap rotates the current log to .1', () async {
      final file = File(p.join(tmp.path, 'app.log'));
      // Tiny cap forces rotation after only a couple of lines.
      final log = AppLogger(
        minLevel: LogLevel.info,
        logFile: file,
        clock: fixedClock,
        maxBytesPerFile: 60,
        keepFiles: 3,
      );
      for (var i = 0; i < 8; i++) {
        log.info('r', 'line-$i padding padding padding');
      }
      await log.flush();

      expect(file.existsSync(), isTrue);
      expect(File('${file.path}.1').existsSync(), isTrue);
    });

    test('at most keepFiles historical logs are retained', () async {
      final file = File(p.join(tmp.path, 'app.log'));
      final log = AppLogger(
        minLevel: LogLevel.info,
        logFile: file,
        clock: fixedClock,
        maxBytesPerFile: 40,
        keepFiles: 2,
      );
      for (var i = 0; i < 40; i++) {
        log.info('r', 'padding-$i aaaaaaaaaaaaaaaaaaaaaaaa');
      }
      await log.flush();

      final rotated = tmp
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('app.log.'))
          .map((f) => p.basename(f.path))
          .toSet();
      // Only .1 and .2 may exist (keepFiles = 2); .3 must never appear.
      expect(rotated, containsAll(<String>['app.log.1', 'app.log.2']));
      expect(rotated, isNot(contains('app.log.3')));
    });

    test(
      'file-IO failure is swallowed (logging must never crash the app)',
      () async {
        // Point the "file" at a directory so every write throws.
        final bad = Directory(p.join(tmp.path, 'not-a-file'));
        bad.createSync();
        final log = AppLogger(
          minLevel: LogLevel.info,
          logFile: File(bad.path),
          clock: fixedClock,
        );
        log.info('t', 'would-be-written');
        // flush() awaits the internal chain; it must complete without throwing.
        await expectLater(log.flush(), completes);
      },
    );
  });

  group('AppLogger.readLogContents + scrub (ARC-06 diagnostics)', () {
    test('a logger with no file sink reads back an empty string', () async {
      final log = AppLogger(minLevel: LogLevel.info, sink: (_) {});
      expect(await log.readLogContents(), isEmpty);
    });

    test('reads current + rotated history oldest-first', () async {
      final tmp = Directory.systemTemp.createTempSync('lib_read_');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      final file = File(p.join(tmp.path, 'app.log'));
      // Tiny cap so a couple of lines force a .1 rotation, keepFiles = 3.
      final log = AppLogger(
        minLevel: LogLevel.info,
        logFile: file,
        clock: fixedClock,
        maxBytesPerFile: 60,
        keepFiles: 3,
      );
      log.info('r', 'oldest-marker padding padding');
      log.info('r', 'newest-marker');
      final text = await log.readLogContents();
      // Both surviving records are present (rotation keeps history, not drops).
      expect(text, contains('newest-marker'));
      expect(File('${file.path}.1').existsSync(), isTrue);
      expect(text, contains('oldest-marker'));
      // Oldest (in .1) must appear before the current file's newest line.
      expect(
        text.indexOf('oldest-marker') < text.indexOf('newest-marker'),
        isTrue,
      );
    });

    test('scrub redacts secret-looking values but keeps the field name', () {
      final out = AppLogger.scrub(
        'connecting authorization: Bearer supersecret token=abc123 '
        'password="p@ss word" db_path=C:\\data\\lib.db',
      );
      expect(out, contains('[redacted]'));
      // The concrete secrets must not survive verbatim.
      expect(out, isNot(contains('supersecret')));
      expect(out, isNot(contains('abc123')));
      expect(out, isNot(contains('p@ss')));
      // A non-secret field is untouched, so the trace is still readable.
      expect(out, contains('db_path'));
    });

    test('readLogContents scrubs persisted lines', () async {
      final tmp = Directory.systemTemp.createTempSync('lib_scrub_');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      final file = File(p.join(tmp.path, 'app.log'));
      final log = AppLogger(
        minLevel: LogLevel.info,
        logFile: file,
        clock: fixedClock,
      );
      log.info('auth', 'login password=hunter2 for admin');
      final text = await log.readLogContents();
      expect(text, contains('password=[redacted]'));
      expect(text, isNot(contains('hunter2')));
    });
  });
}

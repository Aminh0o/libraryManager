import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Severity levels, ordered. A record is emitted only when its level is at or
/// above the logger's `minLevel`.
enum LogLevel { debug, info, warn, error }

/// A tiny, dependency-free, process-wide logging facade (REL/logging).
///
/// The app previously reported everything through `debugPrint`, which is a
/// no-op / invisible in a release build, so a field problem on a user's machine
/// (an unhandled server 500, a failed cleanup, a bind error) left no trace at
/// all. This logger mirrors every record to the console (dev parity) AND
/// appends it to a size-bounded, rotating log file so release builds stay
/// diagnosable.
///
/// Design notes:
///  * Logging is BEST-EFFORT and must never be the cause of a failure: a sink
///    or file-IO error is swallowed, and file writes are serialized onto an
///    internal [Future] chain so lines never interleave and rotation is safe.
///  * The sink, the clock and the destination file are all injectable, which is
///    what makes it unit-testable without touching the real filesystem.
///  * Call sites are responsible for not logging secrets; nothing here redacts.
class AppLogger {
  AppLogger({
    this.minLevel = LogLevel.info,
    void Function(String line)? sink,
    DateTime Function()? clock,
    this.logFile,
    this.maxBytesPerFile = 512 * 1024,
    this.keepFiles = 3,
  })  : _sink = sink,
        _clock = clock ?? DateTime.now;

  final LogLevel minLevel;
  final void Function(String line)? _sink;
  final DateTime Function() _clock;
  final File? logFile;
  final int maxBytesPerFile;
  final int keepFiles;

  // Serializes async file appends (never dropped; awaited by [flush]).
  Future<void> _pending = Future<void>.value();

  void debug(String tag, String message, [Object? error, StackTrace? stack]) =>
      _emit(LogLevel.debug, tag, message, error, stack);
  void info(String tag, String message, [Object? error, StackTrace? stack]) =>
      _emit(LogLevel.info, tag, message, error, stack);
  void warn(String tag, String message, [Object? error, StackTrace? stack]) =>
      _emit(LogLevel.warn, tag, message, error, stack);
  void error(String tag, String message, [Object? error, StackTrace? stack]) =>
      _emit(LogLevel.error, tag, message, error, stack);

  /// Completes once every queued file append has finished. Used at shutdown and
  /// by tests that assert on the persisted file.
  Future<void> flush() => _pending;

  /// Returns the concatenation of the rotated history (oldest first) and the
  /// current log file, for the diagnostics bundle. Best-effort: returns an
  /// empty string when no file sink is configured, and any per-file read error
  /// is swallowed so diagnostics collection can never be the cause of a
  /// failure. Values that look like credentials are redacted via [scrub].
  Future<String> readLogContents() async {
    final f = logFile;
    if (f == null) return '';
    // Drain queued appends first so the newest lines are actually on disk.
    await flush();
    final sb = StringBuffer();
    for (var i = keepFiles; i >= 1; i--) {
      final rot = File('${f.path}.$i');
      try {
        if (await rot.exists()) sb.write(await rot.readAsString());
      } catch (_) {
        // Ignore an unreadable rotation and keep collecting.
      }
    }
    try {
      if (await f.exists()) sb.write(await f.readAsString());
    } catch (_) {
      // Ignore an unreadable current log.
    }
    return scrub(sb.toString());
  }

  // Matches `key: value` / `key=value` pairs whose key names a secret-ish
  // field (value may be a `Bearer <token>` pair, a quoted string, or a bare
  // token), plus a bare `Bearer <token>` with no preceding key. Conservative:
  // only the VALUE after a recognized key is dropped, so ordinary messages
  // (and the `key:` label itself) stay readable.
  static final RegExp _secretPattern = RegExp(
    r'(\b(?:authorization|token|password|secret|api[-_]?key|pin)\b\s*[:=]\s*)(?:Bearer\s+\S+|"[^"]*"|\S+)|\bBearer\s+\S+',
    caseSensitive: false,
  );

  /// Redacts anything that looks like a credential from [input] before it can
  /// reach a shareable diagnostics file. The logger's contract is that call
  /// sites never log secrets; this is a defense-in-depth scrub for the bundle.
  static String scrub(String input) =>
      input.replaceAllMapped(_secretPattern, (m) {
        // Keep the `key:` prefix so a reader still sees WHICH field was set;
        // drop only the value. A bare `Bearer ...` has no prefix group.
        final prefix = m.group(1);
        return prefix == null ? '[redacted]' : '$prefix[redacted]';
      });

  void _emit(LogLevel level, String tag, String message,
      [Object? error, StackTrace? stack]) {
    if (level.index < minLevel.index) return;
    final ts = _clock().toUtc().toIso8601String();
    final sb = StringBuffer('$ts ${level.name.toUpperCase()} [$tag] $message');
    if (error != null) sb.write('\n  error: $error');
    if (stack != null) sb.write('\n  stack: ${stack.toString().trim()}');
    final line = sb.toString();

    // Console mirror (works in debug; harmless in release).
    debugPrint(line);

    final sink = _sink;
    if (sink != null) {
      try {
        sink(line);
      } catch (_) {
        // A logging sink must never propagate to the caller.
      }
    } else {
      _appendToFile(line);
    }
  }

  void _appendToFile(String line) {
    final f = logFile;
    if (f == null) return;
    _pending = _pending.then((_) async {
      try {
        await f.parent.create(recursive: true);
        if (await f.exists() && await f.length() > maxBytesPerFile) {
          _rotate(f);
        }
        await f.writeAsString('$line\n', mode: FileMode.append);
      } catch (_) {
        // File IO failures must never crash the app; logging is best-effort.
      }
    });
  }

  /// Shifts `log.1..log.(keepFiles-1)` up one slot and moves the current log to
  /// `log.1`, so at most [keepFiles] historical files survive. Synchronous by
  /// design (called from the already-serialized append chain, and rare).
  void _rotate(File f) {
    try {
      for (var i = keepFiles - 1; i >= 1; i--) {
        final src = File('${f.path}.$i');
        if (src.existsSync()) src.renameSync('${f.path}.${i + 1}');
      }
      if (f.existsSync()) f.renameSync('${f.path}.1');
    } catch (_) {
      // A failed rotation must not abort the write.
    }
  }
}

/// Process-wide logger. Console-only at info/debug until [initAppLogging]
/// points it at a file during startup. Call sites read this variable, so a
/// later re-init (or a test injecting a recording sink) takes effect without
/// touching them.
AppLogger appLog =
    AppLogger(minLevel: kReleaseMode ? LogLevel.info : LogLevel.debug);

/// Directs the global [appLog] to a rotating file under `docsDir/logs/`.
/// Call once from `main()`. Safe to call again (e.g. a test re-points it).
void initAppLogging({
  required Directory docsDir,
  LogLevel? minLevel,
  DateTime Function()? clock,
}) {
  final file = File(p.join(docsDir.path, 'logs', 'library_manager.log'));
  appLog = AppLogger(
    minLevel: minLevel ?? (kReleaseMode ? LogLevel.info : LogLevel.debug),
    logFile: file,
    clock: clock,
  );
}

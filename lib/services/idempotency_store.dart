import 'package:shelf/shelf.dart';

/// One previously-processed POST outcome, replayed verbatim when a client
/// retries a request carrying the same `Idempotency-Key`.
class IdempotencyRecord {
  IdempotencyRecord(this.status, this.body, this.at);
  final int status;
  final String body;
  final DateTime at;
}

/// A small, bounded, TTL-expiring cache of already-processed POST results
/// keyed by a client-supplied `Idempotency-Key` (REL-03 / TX-05).
///
/// The concrete failure this prevents: a mutation (`POST /items`, `/loans`,
/// `/members`, `/history`) commits on the server, but its response is lost to
/// a client-side timeout. [ApiService] retries the request; without a key the
/// retry re-executes and creates a **duplicate** row. With a stable key the
/// second arrival replays the first outcome instead of mutating again.
///
/// The store lives for the lifetime of the (single, long-running host) server
/// process — exactly the window in which a retry-after-timeout can arrive. It
/// is deliberately in-memory: it never has to survive a restart (a restart
/// means any in-flight client operation is long gone), and keeping it out of
/// the SQLite schema avoids coupling a transport concern to the domain store.
class IdempotencyStore {
  IdempotencyStore({
    this.ttl = const Duration(minutes: 10),
    this.maxEntries = 1000,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// How long a completed result stays replayable.
  final Duration ttl;

  /// Upper bound on retained keys; the oldest are evicted first.
  final int maxEntries;

  final DateTime Function() _clock;
  final Map<String, IdempotencyRecord> _records = {};

  /// Returns the stored result for [key], or `null` if unseen or expired.
  /// An expired entry is dropped on read.
  IdempotencyRecord? lookup(String key) {
    final rec = _records[key];
    if (rec == null) return null;
    if (_clock().difference(rec.at) > ttl) {
      _records.remove(key);
      return null;
    }
    return rec;
  }

  /// Records the outcome of [key] so a later replay can be returned. Trims to
  /// [maxEntries] by dropping the oldest entries first.
  void save(String key, int status, String body) {
    final now = _clock();
    _records[key] = IdempotencyRecord(status, body, now);
    if (_records.length > maxEntries) {
      final oldest = _records.entries.toList()
        ..sort((a, b) => a.value.at.compareTo(b.value.at));
      for (final e in oldest.take(_records.length - maxEntries)) {
        _records.remove(e.key);
      }
    }
  }

  /// Number of currently-retained keys (test/observability aid).
  int get length => _records.length;

  void clear() => _records.clear();
}

/// Shelf middleware enforcing idempotent replay of POST requests that carry an
/// `Idempotency-Key` header (REL-03 / TX-05).
///
/// Behaviour:
/// * Non-POST requests, and POSTs without the header, pass straight through —
///   so this is opt-in and fully backward compatible with older clients.
/// * A POST whose key was already resolved returns the cached status/body with
///   an `idempotency-replayed: true` marker, and **the inner handler is not run
///   again** (no second mutation).
/// * A first-time key runs the handler and caches the result. Server-side
///   failures (5xx) are **not** cached, so a genuine transient error remains
///   retryable; every deterministic outcome (2xx/4xx) is cached and replayed.
Middleware idempotencyMiddleware(IdempotencyStore store) {
  return (Handler inner) {
    return (Request request) async {
      if (request.method.toUpperCase() != 'POST') return inner(request);
      final key = request.headers['idempotency-key'];
      if (key == null || key.trim().isEmpty) return inner(request);

      final cached = store.lookup(key);
      if (cached != null) {
        return Response(
          cached.status,
          body: cached.body,
          headers: {
            'content-type': 'application/json',
            'idempotency-replayed': 'true',
          },
        );
      }

      final response = await inner(request);
      final bodyStr = await response.readAsString();
      if (response.statusCode < 500) {
        store.save(key, response.statusCode, bodyStr);
      }
      // Rebuild with the consumed body preserved; drop any stale content-length
      // so shelf recomputes it.
      final headers = Map<String, String>.from(response.headers)
        ..remove('content-length');
      return Response(response.statusCode, body: bodyStr, headers: headers);
    };
  };
}

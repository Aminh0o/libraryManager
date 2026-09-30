/// Clock-injectable token-bucket rate limiter (NET-13 / PROTO-04).
///
/// Guards *state-changing* requests against a runaway or malicious client that
/// would otherwise hammer the single shared SQLite database (e.g. a `POST
/// /history` flood, or a client retry-storm). Read requests are exempt at the
/// call site so the clients' 1-2s `/db-version` sync poll is never throttled.
///
/// One bucket per source key (the caller's IP). Each bucket holds up to
/// [capacity] tokens; tokens are consumed one per admitted write and are
/// replenished at a steady [refillPerMinute]. The bucket is computed lazily on
/// access, so there is no background timer and the whole thing is deterministic
/// under an injected [clock] -- which is what makes it unit-testable without
/// real waiting.
class RateLimiter {
  RateLimiter({
    this.capacity = 40,
    this.refillPerMinute = 120,
    DateTime Function()? clock,
  }) : assert(capacity > 0),
       assert(refillPerMinute > 0),
       _clock = clock ?? DateTime.now;

  /// Maximum burst of writes a single source may make instantaneously.
  final int capacity;

  /// Sustained writes per minute a source is allowed once the burst is spent.
  final double refillPerMinute;

  final DateTime Function() _clock;
  final Map<String, _TokenBucket> _buckets = {};

  /// Consumes one token for [key] if available. Returns `null` when the write
  /// is allowed, or a suggested `Retry-After` duration when it must be refused.
  Duration? tryAcquire(String key) {
    final now = _clock();
    final bucket = _buckets.putIfAbsent(
      key,
      () => _TokenBucket(capacity.toDouble(), now),
    );
    final elapsedMin =
        now.difference(bucket.updatedAt).inMicroseconds / 60000000.0;
    if (elapsedMin > 0) {
      bucket.tokens += elapsedMin * refillPerMinute;
      if (bucket.tokens > capacity) bucket.tokens = capacity.toDouble();
      bucket.updatedAt = now;
    }
    if (bucket.tokens >= 1) {
      bucket.tokens -= 1;
      return null;
    }
    // Time until a whole token is available (bucket currently holds < 1).
    final needed = 1 - bucket.tokens;
    final minutes = needed / refillPerMinute;
    var ms = (minutes * 60000).ceil();
    if (ms < 1) ms = 1;
    return Duration(milliseconds: ms);
  }

  /// Current token count for [key] (defaults to a full, untouched bucket).
  /// Exposed for tests and diagnostics only.
  double tokensFor(String key) => _buckets[key]?.tokens ?? capacity.toDouble();
}

class _TokenBucket {
  _TokenBucket(this.tokens, this.updatedAt);
  double tokens;
  DateTime updatedAt;
}

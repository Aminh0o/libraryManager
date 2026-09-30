import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/services/rate_limit.dart';

/// PROTO-04 / NET-13: per-source token-bucket write throttling. A clock is
/// injected so refill is deterministic (no real waiting).
void main() {
  group('RateLimiter token bucket (PROTO-04)', () {
    late DateTime now;
    RateLimiter build({int capacity = 3, double refillPerMinute = 60}) =>
        RateLimiter(
          capacity: capacity,
          refillPerMinute: refillPerMinute,
          clock: () => now,
        );

    setUp(() => now = DateTime(2026, 1, 1, 12));

    test('admits up to capacity instantaneously then throttles', () {
      final rl = build(capacity: 3);
      expect(rl.tryAcquire('a'), isNull);
      expect(rl.tryAcquire('a'), isNull);
      expect(rl.tryAcquire('a'), isNull);
      final retry = rl.tryAcquire('a');
      expect(retry, isNotNull);
      expect(retry!.inMilliseconds, greaterThan(0));
    });

    test('buckets are isolated per key', () {
      final rl = build(capacity: 1);
      expect(rl.tryAcquire('a'), isNull);
      expect(rl.tryAcquire('a'), isNotNull); // 'a' exhausted
      expect(rl.tryAcquire('b'), isNull); // 'b' untouched
    });

    test('refills over time so a throttled source recovers', () {
      final rl = build(capacity: 1, refillPerMinute: 1); // 1 token / minute
      expect(rl.tryAcquire('a'), isNull);
      expect(rl.tryAcquire('a'), isNotNull);
      now = now.add(const Duration(seconds: 30)); // ~0.5 token accrued
      expect(
        rl.tryAcquire('a'),
        isNotNull,
        reason: 'half a token must not admit a write',
      );
      now = now.add(const Duration(seconds: 30)); // ~1.0 token total
      expect(rl.tryAcquire('a'), isNull);
    });

    test('an idle refill never exceeds capacity (bounded burst)', () {
      final rl = build(capacity: 2, refillPerMinute: 600);
      now = now.add(
        const Duration(minutes: 10),
      ); // would add 6000 -> clamps to 2
      expect(rl.tryAcquire('a'), isNull);
      expect(rl.tryAcquire('a'), isNull);
      expect(
        rl.tryAcquire('a'),
        isNotNull,
        reason: 'burst stays capped at capacity despite long idleness',
      );
    });
  });
}

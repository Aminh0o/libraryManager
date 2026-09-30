import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/services/pairing_guard.dart';

void main() {
  group('PairingGuard (NET-02 attempt throttle)', () {
    // A controllable clock so lockout/window behaviour is proven without real
    // delays.
    late DateTime now;
    PairingGuard build({
      int max = 3,
      Duration window = const Duration(minutes: 5),
    }) {
      now = DateTime(2026, 1, 1, 12);
      return PairingGuard(
        maxFailedAttempts: max,
        lockoutWindow: window,
        now: () => now,
      );
    }

    test('a fresh source is allowed', () {
      final g = build();
      expect(g.allowAttempt('10.0.0.5'), isTrue);
      expect(g.trackedSources, 0, reason: 'allowAttempt alone records nothing');
    });

    test(
      'stays allowed until the failure budget is crossed, then locks out',
      () {
        final g = build(max: 3);
        g.recordFailure('ip');
        g.recordFailure('ip');
        expect(g.allowAttempt('ip'), isTrue, reason: '2 < 3 failures');
        g.recordFailure('ip'); // 3rd crosses the threshold -> lockout
        expect(g.allowAttempt('ip'), isFalse);
      },
    );

    test('a lockout releases once the window elapses', () {
      final g = build(max: 2);
      g.recordFailure('ip');
      g.recordFailure('ip'); // engage lockout until now + 5m
      expect(g.allowAttempt('ip'), isFalse);
      now = now.add(const Duration(minutes: 5));
      expect(
        g.allowAttempt('ip'),
        isTrue,
        reason: 'lockout expired -> attempts accepted again',
      );
    });

    test('a stale failure count decays after the activity window', () {
      final g = build(max: 3);
      g.recordFailure('ip');
      g.recordFailure('ip'); // 2 failures, no lockout yet
      now = now.add(const Duration(minutes: 6)); // window fully elapsed
      // allowAttempt observes the elapsed window and decays the stale count.
      expect(g.allowAttempt('ip'), isTrue);
      g.recordFailure('ip'); // treated as a fresh 1st failure
      expect(
        g.allowAttempt('ip'),
        isTrue,
        reason: 'prior failures expired, budget reset to 1 < 3',
      );
    });

    test('a success clears the source budget', () {
      final g = build(max: 3);
      g.recordFailure('ip');
      g.recordFailure('ip');
      g.recordSuccess('ip');
      g.recordFailure('ip'); // back to 1 after reset
      g.recordFailure('ip');
      expect(g.allowAttempt('ip'), isTrue, reason: 'reset means 2 < 3');
    });

    test('lockouts are per source (one attacker does not block everyone)', () {
      final g = build(max: 2);
      g.recordFailure('bad');
      g.recordFailure('bad');
      expect(g.allowAttempt('bad'), isFalse);
      expect(g.allowAttempt('good'), isTrue);
    });
  });
}

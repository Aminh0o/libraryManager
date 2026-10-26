import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:library_manager/services/update_notifier.dart';
import 'package:library_manager/services/update_service.dart';

/// Phase 13 — the startup update auto-check. These tests pin the four
/// invariants the feature must never violate: it is throttled, it announces
/// ONLY a real release, it de-dupes per version, and it can never crash or
/// disturb the session. Everything is driven with an injected fake `check` and
/// a mocked prefs store, so no network is touched.
UpdateCheckResult _r(UpdateStatus s, {String? v}) =>
    UpdateCheckResult(s, version: v);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('shouldRunCheck (throttle)', () {
    final now = DateTime(2026, 10, 19, 12);
    const window = Duration(hours: 12);

    test('never-checked runs', () {
      expect(UpdateNotifier.shouldRunCheck(null, now, window), isTrue);
    });

    test('a check inside the window is skipped', () {
      expect(
        UpdateNotifier.shouldRunCheck(
          now.subtract(const Duration(hours: 3)),
          now,
          window,
        ),
        isFalse,
      );
    });

    test('a check at/after the window runs', () {
      expect(
        UpdateNotifier.shouldRunCheck(now.subtract(window), now, window),
        isTrue,
      );
    });
  });

  group('announceVersion (honest gate + dedupe)', () {
    test('only an available result with a version announces', () {
      expect(
        UpdateNotifier.announceVersion(
          _r(UpdateStatus.available, v: '2.0.0'),
          null,
        ),
        '2.0.0',
      );
      expect(
        UpdateNotifier.announceVersion(
          _r(UpdateStatus.upToDate, v: '2.0.0'),
          null,
        ),
        isNull,
      );
      expect(
        UpdateNotifier.announceVersion(_r(UpdateStatus.notConfigured), null),
        isNull,
      );
      expect(
        UpdateNotifier.announceVersion(_r(UpdateStatus.failed), null),
        isNull,
      );
    });

    test('an empty version never announces', () {
      expect(
        UpdateNotifier.announceVersion(_r(UpdateStatus.available, v: ''), null),
        isNull,
      );
      expect(
        UpdateNotifier.announceVersion(_r(UpdateStatus.available), null),
        isNull,
      );
    });

    test('an already-announced version is suppressed', () {
      expect(
        UpdateNotifier.announceVersion(
          _r(UpdateStatus.available, v: '2.0.0'),
          '2.0.0',
        ),
        isNull,
      );
    });
  });

  group('runStartupCheck (orchestration)', () {
    test(
      'a first available release returns + persists version and timestamp',
      () async {
        final prefs = await SharedPreferences.getInstance();
        var calls = 0;
        final version = await UpdateNotifier.runStartupCheck(
          check: () async {
            calls++;
            return _r(UpdateStatus.available, v: '9.9.9');
          },
          prefsProvider: () async => prefs,
          now: DateTime(2026, 10, 19),
        );
        expect(version, '9.9.9');
        expect(calls, 1);
        expect(prefs.getString('lastAnnouncedVersion'), '9.9.9');
        expect(prefs.getString('lastUpdateCheckAt'), isNotNull);
      },
    );

    test('within the window the check is NOT called at all', () async {
      final prefs = await SharedPreferences.getInstance();
      final t0 = DateTime(2026, 10, 19, 9);
      await UpdateNotifier.runStartupCheck(
        check: () async => _r(UpdateStatus.available, v: '1.0.0'),
        prefsProvider: () async => prefs,
        now: t0,
      );
      var secondCalls = 0;
      final again = await UpdateNotifier.runStartupCheck(
        check: () async {
          secondCalls++;
          return _r(UpdateStatus.available, v: '1.0.1');
        },
        prefsProvider: () async => prefs,
        now: t0.add(const Duration(minutes: 5)),
      );
      expect(secondCalls, 0);
      expect(again, isNull);
    });

    test(
      'an up-to-date result stays silent but still stamps the attempt',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final version = await UpdateNotifier.runStartupCheck(
          check: () async => _r(UpdateStatus.upToDate),
          prefsProvider: () async => prefs,
          now: DateTime(2026, 10, 19),
        );
        expect(version, isNull);
        expect(prefs.getString('lastUpdateCheckAt'), isNotNull);
        expect(prefs.getString('lastAnnouncedVersion'), isNull);
      },
    );

    test('a throwing check is swallowed and never announces', () async {
      final prefs = await SharedPreferences.getInstance();
      final version = await UpdateNotifier.runStartupCheck(
        check: () async => throw Exception('offline'),
        prefsProvider: () async => prefs,
        now: DateTime(2026, 10, 19),
      );
      expect(version, isNull);
    });

    test('the same release is announced once, then suppressed', () async {
      final prefs = await SharedPreferences.getInstance();
      final first = await UpdateNotifier.runStartupCheck(
        check: () async => _r(UpdateStatus.available, v: '3.0.0'),
        prefsProvider: () async => prefs,
        now: DateTime(2026, 10, 19),
      );
      expect(first, '3.0.0');

      // Past the throttle window, same version -> deduped to silence.
      final second = await UpdateNotifier.runStartupCheck(
        check: () async => _r(UpdateStatus.available, v: '3.0.0'),
        prefsProvider: () async => prefs,
        now: DateTime(2026, 10, 20),
      );
      expect(second, isNull);
    });
  });
}

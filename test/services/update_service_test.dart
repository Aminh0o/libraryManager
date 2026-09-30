import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/services/update_service.dart';

/// ARC-06 (P18): the whole point of this remediation is that an update check
/// can no longer LIE. The pure, network-free helpers are what carry that
/// honesty, so they are pinned directly; and a default build (no
/// --dart-define=UPDATE_FEED_URL) must report `notConfigured`, NOT "up to
/// date" -- the exact §52 violation the old `return null` shipped.
void main() {
  group('isNewer', () {
    test('a higher minor/patch is newer', () {
      expect(UpdateService.isNewer('1.1.0', '1.0.0'), isTrue);
      expect(UpdateService.isNewer('1.0.1', '1.0.0'), isTrue);
    });
    test('equal and older are not newer', () {
      expect(UpdateService.isNewer('1.0.0', '1.0.0'), isFalse);
      expect(UpdateService.isNewer('0.9.9', '1.0.0'), isFalse);
    });
    test('a longer equal-prefix version counts as newer', () {
      expect(UpdateService.isNewer('1.0.0.1', '1.0.0'), isTrue);
    });
  });

  group('fromPayload', () {
    test('a GitHub release tag drives an available result', () {
      final r = UpdateService.fromPayload({
        'tag_name': 'v1.2.0',
        'html_url': 'https://example.test/release',
      }, currentVersion: '1.0.0');
      expect(r.status, UpdateStatus.available);
      expect(r.version, '1.2.0');
      expect(r.url, 'https://example.test/release');
      expect(r.hasUpdate, isTrue);
    });

    test(
      'a generic version field with no download url is available but not launchable',
      () {
        final r = UpdateService.fromPayload({
          'version': '2.0.0',
        }, currentVersion: '1.0.0');
        expect(r.status, UpdateStatus.available);
        expect(
          r.hasUpdate,
          isFalse,
          reason: 'no url means the Update Now action must not appear',
        );
      },
    );

    test('the current version reports upToDate (not a false "available")', () {
      final r = UpdateService.fromPayload({
        'tag_name': 'v1.0.0',
        'html_url': 'https://example.test/release',
      }, currentVersion: '1.0.0');
      expect(r.status, UpdateStatus.upToDate);
    });

    test(
      'an unusable payload reports failed rather than silently up-to-date',
      () {
        expect(
          UpdateService.fromPayload({}, currentVersion: '1.0.0').status,
          UpdateStatus.failed,
        );
        expect(
          UpdateService.fromPayload({
            'tag_name': 'v',
          }, currentVersion: '1.0.0').status,
          UpdateStatus.failed,
        );
      },
    );
  });

  test(
    'an unconfigured build honestly reports notConfigured (no network)',
    () async {
      // Tests run without --dart-define, so the feed URL is empty; the check must
      // say so instead of pretending it verified currency.
      final r = await UpdateService.checkForUpdate();
      expect(r.status, UpdateStatus.notConfigured);
    },
  );
}

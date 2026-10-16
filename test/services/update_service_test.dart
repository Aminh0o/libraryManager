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
    test('build metadata (+7) is stripped, so it never fakes a newer core', () {
      expect(UpdateService.isNewer('1.2.0+7', '1.2.0'), isFalse);
      expect(UpdateService.isNewer('1.2.0+7', '1.1.0'), isTrue);
      expect(UpdateService.isNewer('1.1.0+9', '1.2.0'), isFalse);
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

  group('channel policy (§313) — stable ignores drafts and prereleases', () {
    test('a draft is surfaced as a failed lookup, not "up to date"', () {
      final r = UpdateService.fromPayload({
        'tag_name': 'v9.9.9',
        'draft': true,
        'html_url': 'https://example.test/x',
      }, currentVersion: '1.0.0');
      expect(r.status, UpdateStatus.failed);
    });

    test('a prerelease flag is NOT offered on the stable channel', () {
      final r = UpdateService.fromPayload({
        'tag_name': 'v2.0.0',
        'prerelease': true,
        'html_url': 'https://example.test/x',
      }, currentVersion: '1.0.0');
      expect(r.status, UpdateStatus.upToDate);
      expect(r.hasUpdate, isFalse);
    });

    test('a -beta tag is treated as a prerelease even without the flag', () {
      final r = UpdateService.fromPayload({
        'tag_name': 'v2.0.0-beta.1',
        'html_url': 'https://example.test/x',
      }, currentVersion: '1.0.0');
      expect(r.status, UpdateStatus.upToDate);
    });

    test('allowPrerelease (beta channel) DOES offer a prerelease', () {
      final r = UpdateService.fromPayload(
        {'tag_name': 'v2.0.0-beta.1', 'html_url': 'https://example.test/x'},
        currentVersion: '1.0.0',
        allowPrerelease: true,
      );
      expect(r.status, UpdateStatus.available);
    });
  });

  group('isTrustworthyFeed (§317) — HTTPS-only update source', () {
    test('accepts a well-formed https endpoint', () {
      expect(
        UpdateService.isTrustworthyFeed(
          'https://api.github.com/repos/o/r/releases/latest',
        ),
        isTrue,
      );
    });
    test('rejects plaintext http, empty, and host-less values', () {
      expect(UpdateService.isTrustworthyFeed('http://example.test/x'), isFalse);
      expect(UpdateService.isTrustworthyFeed(''), isFalse);
      expect(UpdateService.isTrustworthyFeed('https://'), isFalse);
      expect(UpdateService.isTrustworthyFeed('not a url'), isFalse);
    });
  });

  test(
    'an explicitly-empty feed is honestly reported as notConfigured (no lie)',
    () async {
      // An operator who builds with `--dart-define=UPDATE_FEED_URL=` (a
      // self-hosted / air-gapped deployment) must get `notConfigured`, never a
      // fabricated "up to date" — the ARC-06 honesty guarantee.
      final r = await UpdateService.checkForUpdate(feedUrl: '');
      expect(r.status, UpdateStatus.notConfigured);
    },
  );

  test(
    'the production default feed is the canonical GitHub release endpoint',
    () {
      // The audit's finding was "the updater is disabled by default and only a
      // browser bookmark". The default is now a real HTTPS release feed that
      // ships downloadable, checksummed assets.
      expect(
        UpdateService.canonicalFeedUrl,
        'https://api.github.com/repos/Aminh0o/libraryManager/releases/latest',
      );
      expect(
        UpdateService.isTrustworthyFeed(UpdateService.canonicalFeedUrl),
        isTrue,
      );
    },
  );

  group('assetFromPayload — the real GitHub release asset contract', () {
    // Fixture mirrors `gh api repos/Aminh0o/libraryManager/releases/latest`
    // exactly (verified live): the zip asset plus its `.sha256sum` sibling.
    Map<String, dynamic> ghPayload({
      String tag = 'v1.2.0',
      bool draft = false,
      bool prerelease = false,
      bool withAssets = true,
    }) => {
      'tag_name': tag,
      'html_url': 'https://github.com/Aminh0o/libraryManager/releases/tag/$tag',
      'draft': draft,
      'prerelease': prerelease,
      'assets': withAssets
          ? <dynamic>[
              {
                'name': 'LibraryManager-1.2.0-windows-x64.zip',
                'size': 18607230,
                'content_type': 'application/zip',
                'browser_download_url':
                    'https://github.com/Aminh0o/libraryManager/releases/download/$tag/LibraryManager-1.2.0-windows-x64.zip',
              },
              {
                'name': 'LibraryManager-1.2.0-windows-x64.zip.sha256sum',
                'size': 102,
                'content_type': 'application/octet-stream',
                'browser_download_url':
                    'https://github.com/Aminh0o/libraryManager/releases/download/$tag/LibraryManager-1.2.0-windows-x64.zip.sha256sum',
              },
            ]
          : <dynamic>[],
    };

    test(
      'a newer release exposes a downloadable, checksum-paired artifact',
      () {
        final r = UpdateService.fromPayload(
          ghPayload(),
          currentVersion: '1.0.0',
        );
        expect(r.status, UpdateStatus.available);
        expect(r.canDownload, isTrue);
        final a = r.artifact!;
        expect(a.fileName, 'LibraryManager-1.2.0-windows-x64.zip');
        expect(a.sizeBytes, 18607230);
        expect(a.packageUrl, startsWith('https://github.com/'));
        expect(
          a.checksumUrl,
          'https://github.com/Aminh0o/libraryManager/releases/download/'
          'v1.2.0/LibraryManager-1.2.0-windows-x64.zip.sha256sum',
        );
      },
    );

    test(
      'a checksum-less package still parses, but is NOT offered for download',
      () {
        final r = UpdateService.fromPayload({
          'tag_name': 'v1.2.0',
          'html_url': 'https://example/r',
          'assets': <dynamic>[
            {
              'name': 'pkg.zip',
              'browser_download_url': 'https://example.test/pkg.zip',
            },
          ],
        }, currentVersion: '1.0.0');
        expect(r.artifact, isNotNull);
        expect(r.artifact!.checksumUrl, isNull);
        // downloadAndVerify refuses an unverified archive, so canDownload stays
        // true (the package IS HTTPS) yet the flow hard-stops without a manifest.
      },
    );

    test(
      'the `.sha256sum` sibling is never mistaken for the package itself',
      () {
        final a = UpdateService.assetFromPayload(ghPayload())!;
        expect(a.fileName!.endsWith('.zip'), isTrue);
        expect(a.fileName!.endsWith('.sha256sum'), isFalse);
      },
    );

    test(
      'a feed with no assets yields no artifact (browser fallback only)',
      () {
        expect(UpdateService.assetFromPayload({'assets': <dynamic>[]}), isNull);
        expect(UpdateService.assetFromPayload({}), isNull);
      },
    );

    test('a non-HTTPS package url makes canDownload false', () {
      final a = UpdateArtifact(
        packageUrl: 'http://evil.test/pkg.zip',
        checksumUrl: 'https://example.test/pkg.zip.sha256sum',
        fileName: 'pkg.zip',
      );
      expect(a.isDownloadable, isFalse);
    });
  });

  group('parseChecksumText — GNU sha256sum formats + rejection', () {
    const hex =
        'c17caf4700c9d3434eef91977ff4f318c9e8c75b574909aa8aac29e6795bb85c';
    test('parses the real two-space published format, lowercased', () {
      expect(
        UpdateService.parseChecksumText(
          '${hex.toUpperCase()}  LibraryManager-1.1.3-windows-x64.zip\n',
        ),
        hex,
      );
    });
    test('parses one-space and binary-mode (` *name`) separators', () {
      expect(UpdateService.parseChecksumText('$hex file.zip'), hex);
      expect(UpdateService.parseChecksumText('$hex *file.zip'), hex);
    });
    test('rejects non-64-hex, HTML error pages, and empty', () {
      expect(UpdateService.parseChecksumText('not-a-hash'), isNull);
      expect(UpdateService.parseChecksumText(hex.substring(1)), isNull);
      expect(
        UpdateService.parseChecksumText('<html>404 Not Found</html>'),
        isNull,
      );
      expect(UpdateService.parseChecksumText('   '), isNull);
    });
  });

  group('sanitizeFileName — download path-traversal defense', () {
    test('strips directories and dot-dot escape attempts', () {
      expect(
        UpdateService.sanitizeFileName(r'..\..\..\windows\system32\evil.zip'),
        'evil.zip',
      );
      expect(UpdateService.sanitizeFileName('../../etc/passwd'), 'passwd');
      expect(
        UpdateService.sanitizeFileName('/absolute/path/pkg.zip'),
        'pkg.zip',
      );
    });
    test('removes leading dots and non-safe characters', () {
      expect(UpdateService.sanitizeFileName('..hidden.zip'), 'hidden.zip');
      expect(
        UpdateService.sanitizeFileName('a b;rm -rf.zip'),
        matches(r'^[A-Za-z0-9._-]+$'),
      );
    });
    test('empty name falls back to a safe default', () {
      expect(UpdateService.sanitizeFileName(''), 'library_manager_update.zip');
      expect(
        UpdateService.sanitizeFileName('...'),
        'library_manager_update.zip',
      );
    });
  });
}

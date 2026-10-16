import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_logger.dart';

/// ARC-06: the outcome of an update check. This is deliberately an explicit
/// state enum rather than a nullable map so the UI can never conflate "I found
/// nothing newer" with "I could not look" or "no one configured a feed" -- the
/// old code returned `null` for all three, so an unconfigured deployment lied
/// with "You are using the latest version." (a §52 violation: the app asserted a
/// state it had not actually produced).
enum UpdateStatus {
  /// A newer release was found (see [UpdateCheckResult.version] / [url]).
  available,

  /// The feed was reached and this build is current.
  upToDate,

  /// No update feed is configured for this deployment (honest, not an error).
  notConfigured,

  /// The feed was configured but could not be reached / parsed.
  failed,
}

@immutable
class UpdateCheckResult {
  const UpdateCheckResult(this.status, {this.version, this.url, this.artifact});
  final UpdateStatus status;

  /// Human-readable latest version (tag stripped of a leading `v`).
  final String? version;

  /// The release *page* URL (`html_url`) — the browser fallback.
  final String? url;

  /// The concrete downloadable package (+ its published checksum), when the
  /// feed is a GitHub-style release that exposes `assets`. Null means the
  /// update can only be opened in a browser, not downloaded in-app.
  final UpdateArtifact? artifact;

  bool get hasUpdate =>
      status == UpdateStatus.available && (url != null && url!.isNotEmpty);

  /// True only when there is a real, HTTPS package the app can stream down
  /// itself. This is what gates the in-app "Download update" affordance — the
  /// app never offers to download something it cannot verify.
  bool get canDownload => artifact?.isDownloadable ?? false;
}

/// A downloadable release package plus the endpoint that publishes its
/// SHA-256, both taken from the release payload's `assets`. Keeping the
/// checksum as a *separate* same-origin endpoint (rather than trusting a value
/// embedded in the release JSON) means a corrupt or tampered archive fails
/// verification instead of being handed to the user as an "update".
@immutable
class UpdateArtifact {
  const UpdateArtifact({
    this.packageUrl,
    this.checksumUrl,
    this.fileName,
    this.sizeBytes,
    this.expectedSha256,
  });

  /// Direct HTTPS download URL of the archive (a `github.com/.../download/...`
  /// release asset), not the API page.
  final String? packageUrl;

  /// Endpoint publishing the archive's checksum (the `.sha256sum` sibling).
  final String? checksumUrl;

  /// Safe file name to write the download under (sanitised by the caller).
  final String? fileName;
  final int? sizeBytes;

  /// A checksum embedded in the feed, if any — only a cross-check; the
  /// authoritative value is fetched from [checksumUrl] when present.
  final String? expectedSha256;

  bool get isDownloadable => UpdateService.isTrustworthyFeed(packageUrl ?? '');
}

enum DownloadStatus { verified, checksumMismatch, failed, cancelled }

/// Result of an in-app download + integrity check. A failure or mismatch never
/// leaves a usable file behind, and `path` is only set for [verified] (or the
/// still-on-disk partial file of a [cancelled] download, which the caller may
/// delete).
@immutable
class DownloadOutcome {
  const DownloadOutcome(
    this.status, {
    this.path,
    this.error,
    this.receivedBytes,
    this.totalBytes,
  });
  final DownloadStatus status;
  final String? path;
  final String? error;
  final int? receivedBytes;
  final int? totalBytes;

  bool get isSuccess => status == DownloadStatus.verified;
}

/// Service to check for application updates against an operator-configured
/// release feed (a GitHub `releases/latest` JSON or any endpoint exposing
/// `tag_name`/`version` + `html_url`/`url`).
class UpdateService {
  /// The release-feed URL. It now defaults to this product's real GitHub
  /// release feed so a normal build genuinely detects and downloads updates
  /// (the audit's "disabled by default" finding), and an operator can still
  /// override it — or point it at an empty string to disable update checks for
  /// an air-gapped / self-hosted deployment that has no public feed:
  ///   flutter build windows --release \
  ///     --dart-define=UPDATE_FEED_URL=            # disables update checking
  static const String _feedOverride = String.fromEnvironment('UPDATE_FEED_URL');

  /// The canonical release feed for this product (the `releases/latest` JSON
  /// of the public GitHub repo, which the CI `release.yml` publishes to).
  static const String canonicalFeedUrl =
      'https://api.github.com/repos/Aminh0o/libraryManager/releases/latest';

  /// Resolved feed for this build: the operator override when non-empty,
  /// otherwise the canonical GitHub feed. Empty only when an operator set
  /// `UPDATE_FEED_URL=` deliberately, which [checkForUpdate] then reports as
  /// [UpdateStatus.notConfigured] rather than pretending the app is current.
  static String get resolvedFeedUrl =>
      _feedOverride.isNotEmpty ? _feedOverride : canonicalFeedUrl;

  static Future<UpdateCheckResult> checkForUpdate({String? feedUrl}) async {
    final feed = feedUrl ?? resolvedFeedUrl;
    if (feed.isEmpty) {
      return const UpdateCheckResult(UpdateStatus.notConfigured);
    }
    // §317: an update source is a code-delivery trust boundary. Refuse a
    // non-HTTPS / malformed configured feed outright rather than quietly
    // trusting a plaintext or garbage endpoint. This is a configuration failure
    // honestly reported as `failed`, never dressed up as "up to date".
    if (!isTrustworthyFeed(feed)) {
      return const UpdateCheckResult(UpdateStatus.failed);
    }
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final response = await http
          .get(Uri.parse(feed), headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        return const UpdateCheckResult(UpdateStatus.failed);
      }
      final decoded = json.decode(response.body);
      if (decoded is! Map) {
        return const UpdateCheckResult(UpdateStatus.failed);
      }
      return fromPayload(
        decoded.cast<String, dynamic>(),
        currentVersion: packageInfo.version,
      );
    } catch (e) {
      appLog.debug('update', 'Update check error: $e');
      return const UpdateCheckResult(UpdateStatus.failed);
    }
  }

  /// Pure, network-free interpretation of a release payload against the running
  /// version. Exposed (and unit-tested) so the version comparison + GitHub /
  /// generic-JSON shape handling is verifiable without a live endpoint.
  ///
  /// [allowPrerelease] is the stable/beta channel switch (§313): on the default
  /// stable channel a draft or prerelease is NOT offered as an update. A draft
  /// is never a real release at all, so it is reported as a failed lookup.
  static UpdateCheckResult fromPayload(
    Map<String, dynamic> data, {
    required String currentVersion,
    bool allowPrerelease = false,
  }) {
    final raw = data['tag_name'] ?? data['version'];
    if (raw == null) return const UpdateCheckResult(UpdateStatus.failed);
    final latest = raw.toString().replaceFirst('v', '').trim();
    if (latest.isEmpty) return const UpdateCheckResult(UpdateStatus.failed);
    // A draft is not a published release; pointing the feed at one is a config
    // error, surfaced honestly rather than as "nothing newer".
    if (data['draft'] == true) {
      return const UpdateCheckResult(UpdateStatus.failed);
    }
    final isPre = data['prerelease'] == true || _hasPrereleaseTag(latest);
    if (isPre && !allowPrerelease) {
      // Stable channel: only a prerelease exists, so there is nothing to offer.
      return const UpdateCheckResult(UpdateStatus.upToDate);
    }
    final downloadUrl = (data['html_url'] ?? data['url'])?.toString();
    if (isNewer(latest, currentVersion)) {
      return UpdateCheckResult(
        UpdateStatus.available,
        version: latest,
        url: downloadUrl,
        artifact: assetFromPayload(data),
      );
    }
    return const UpdateCheckResult(UpdateStatus.upToDate);
  }

  /// Picks the concrete downloadable package out of a release payload's
  /// `assets` (a GitHub-style release). It selects the Windows archive whose
  /// name ends in `.zip` and a sibling checksum asset whose name is the
  /// package name plus a checksum suffix (`.sha256sum` / `.sha256`), matching
  /// the exact convention this product's `release.yml` publishes. Returns null
  /// for a generic feed that exposes no `assets` — the caller then falls back
  /// to the browser link and never offers an unverifiable download.
  @visibleForTesting
  static UpdateArtifact? assetFromPayload(Map<String, dynamic> data) {
    final rawAssets = data['assets'];
    if (rawAssets is! List) return null;
    final assets = rawAssets.whereType<Map>().toList();
    Map<String, dynamic>? pkg;
    for (final a in assets) {
      final name = (a['name'] ?? '').toString();
      final lower = name.toLowerCase();
      if (!lower.endsWith('.zip') || lower.endsWith('.sha256sum')) continue;
      if (!_isArchiveFormat(lower)) continue;
      // Prefer a genuine download URL; the API `url` alone is not browser-.
      if ((a['browser_download_url'] ?? '').toString().isEmpty) continue;
      pkg = a.cast<String, dynamic>();
      break;
    }
    if (pkg == null) return null;
    final pkgName = pkg['name'].toString();
    Map<String, dynamic>? checksumAsset;
    for (final a in assets) {
      final n = (a['name'] ?? '').toString().toLowerCase();
      if (n == '$pkgName.sha256sum'.toLowerCase() ||
          n == '$pkgName.sha256'.toLowerCase()) {
        checksumAsset = a.cast<String, dynamic>();
        break;
      }
    }
    final size = pkg['size'];
    return UpdateArtifact(
      packageUrl: pkg['browser_download_url']?.toString(),
      checksumUrl: checksumAsset?['browser_download_url']?.toString(),
      fileName: pkgName,
      sizeBytes: size is int ? size : int.tryParse('$size'),
    );
  }

  /// Accepted package formats. Kept deliberately narrow (a Windows zip) so the
  /// app only ever downloads the artifact type its manual-install instructions
  /// describe, never an arbitrary file the release happened to attach.
  static bool _isArchiveFormat(String lowerName) => lowerName.endsWith('.zip');

  /// Parses a GNU `sha256sum`-style line (`<64-hex>  <name>`, one- or
  /// two-space or ` *` binary-mode separated) into just the lowercase hex
  /// digest. Returns null for anything that is not a clean 64-hex digest, so a
  /// malformed or HTML error page is never mistaken for a checksum.
  @visibleForTesting
  static String? parseChecksumText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    // Take the first whitespace-delimited token; the digest precedes the name.
    final first = trimmed.split(RegExp(r'\s+')).first;
    return RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(first)
        ? first.toLowerCase()
        : null;
  }

  /// Strips a path to a single safe file name: no directory separators, no
  /// `..`, only `[A-Za-z0-9._-]`. This is what makes the download destination
  /// immune to a `../` or absolute-path file name smuggled through the feed
  /// (a path-traversal / zip-slip style attack on the *download* name).
  static String sanitizeFileName(String name) {
    var s = name.replaceAll(r'\', '/');
    if (s.contains('/')) s = s.substring(s.lastIndexOf('/') + 1);
    s = s.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    while (s.startsWith('.')) {
      s = s.substring(1);
    } // no leading dot (hidden / `..`)
    if (s.isEmpty) s = 'library_manager_update.zip';
    if (s.length > 120) s = s.substring(0, 120);
    return s;
  }

  /// Streams [url] to [destPath], enforcing the update trust boundary: an
  /// HTTPS-only source (a plaintext download of an executable payload is
  /// refused outright, §317) and a hard connect/response [timeout]. The actual
  /// byte mechanics (progress, cancel, byte cap, partial cleanup) live in
  /// [streamResponseToFile] so they can be exercised over a local test server
  /// without weakening the HTTPS policy here.
  static Future<DownloadOutcome> downloadToPath(
    String url,
    String destPath, {
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
    int maxBytes = 512 * 1024 * 1024,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    if (!isTrustworthyFeed(url)) {
      return const DownloadOutcome(
        DownloadStatus.failed,
        error: 'insecure download url',
      );
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
      final resp = await req.close().timeout(timeout);
      return await streamResponseToFile(
        resp,
        client,
        destPath,
        onProgress: onProgress,
        isCancelled: isCancelled,
        maxBytes: maxBytes,
      );
    } catch (e) {
      client.close(force: true);
      try {
        await File(destPath).delete();
      } catch (_) {}
      return DownloadOutcome(DownloadStatus.failed, error: '$e');
    }
  }

  /// The streaming engine behind [downloadToPath]: drains an already-opened
  /// [HttpClientResponse] to [destPath] with byte progress, mid-stream
  /// cancellation, a [maxBytes] cap, and guaranteed partial-file cleanup on any
  /// stop. `verified` here means only "bytes fully written" — the caller must
  /// still verify the checksum before trusting the file. Exposed for testing so
  /// the mechanics run over a local server; the production entry point is
  /// [downloadToPath], which adds the HTTPS-only policy.
  @visibleForTesting
  static Future<DownloadOutcome> streamResponseToFile(
    HttpClientResponse resp,
    HttpClient client,
    String destPath, {
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
    int maxBytes = 512 * 1024 * 1024,
  }) async {
    if (resp.statusCode != HttpStatus.ok) {
      client.close(force: true);
      return DownloadOutcome(
        DownloadStatus.failed,
        error: 'HTTP ${resp.statusCode}',
      );
    }
    final total = resp.contentLength == -1 ? null : resp.contentLength;
    final file = File(destPath);
    // The destination lives in an app-owned subfolder (…/Documents/updates/) that
    // does not exist on a fresh install. File.openWrite() does NOT create
    // intermediate directories and on Windows throws FileSystemException when the
    // parent is absent, which would make EVERY in-app download fail. Create it
    // first (mirrors the database/logger writers, which all create their parent).
    try {
      await file.parent.create(recursive: true);
    } catch (_) {
      // Fall through: openWrite below surfaces the real error as a failed
      // outcome rather than throwing out of the streaming engine.
    }
    final IOSink sink;
    try {
      sink = file.openWrite();
    } catch (e) {
      client.close(force: true);
      return DownloadOutcome(
        DownloadStatus.failed,
        error: 'cannot open destination: $e',
      );
    }
    var received = 0;
    var stop = 0; // 0 none, 1 cancelled, 2 over-cap
    final completer = Completer<DownloadOutcome>();
    late final StreamSubscription<List<int>> sub;
    sub = resp.listen(
      (bytes) {
        if (isCancelled?.call() == true) {
          stop = 1;
          sub.pause();
          return;
        }
        received += bytes.length;
        if (received > maxBytes) {
          stop = 2;
          sub.pause();
          return;
        }
        sink.add(bytes);
        onProgress?.call(received, total);
      },
      onError: (Object e) async {
        await sink.close().catchError((_) {});
        client.close(force: true);
        try {
          await file.delete();
        } catch (_) {}
        if (!completer.isCompleted) {
          completer.complete(
            DownloadOutcome(DownloadStatus.failed, error: '$e'),
          );
        }
      },
      onDone: () async {
        // A failed close (disk full, file locked by AV/Explorer, quota) must NOT
        // hang the driver loop: if close throws, the completer would never
        // complete and Cancel could not break out (the stream is already done,
        // so isCancelled is never re-checked). Fail-safe it into an honest
        // 'failed' outcome and remove the partial file.
        try {
          await sink.close();
        } catch (e) {
          client.close(force: true);
          try {
            await file.delete();
          } catch (_) {}
          if (!completer.isCompleted) {
            completer.complete(
              DownloadOutcome(
                DownloadStatus.failed,
                error: 'write failed: $e',
                receivedBytes: received,
                totalBytes: total,
              ),
            );
          }
          return;
        }
        client.close();
        if (!completer.isCompleted) {
          completer.complete(
            DownloadOutcome(
              DownloadStatus.verified, // provisional: caller verifies hash
              path: destPath,
              receivedBytes: received,
              totalBytes: total,
            ),
          );
        }
      },
      cancelOnError: true,
    );
    // Wait until either the stream finishes (completer done) or a mid-stream
    // cancel / over-cap stop flags itself. On a stop the subscription is paused
    // so no further data is written; we then close the sink (flushing and
    // releasing the file handle), delete the partial file, and report. On normal
    // completion we leave the downloaded file untouched for the caller to
    // verify — the success path must NEVER delete it.
    while (stop == 0 && !completer.isCompleted) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    if (stop != 0) {
      await sub.cancel();
      await sink.close().catchError((_) {});
      client.close(force: true);
      try {
        await file.delete();
      } catch (_) {}
      if (!completer.isCompleted) {
        completer.complete(
          stop == 1
              ? DownloadOutcome(
                  DownloadStatus.cancelled,
                  receivedBytes: received,
                  totalBytes: total,
                )
              : const DownloadOutcome(
                  DownloadStatus.failed,
                  error: 'download exceeded size cap',
                ),
        );
      }
    }
    return completer.future;
  }

  /// Computes the SHA-256 of a file by streaming it (never loads the whole
  /// archive into memory).
  @visibleForTesting
  static Future<String> sha256OfFile(String path) async {
    final digest = await sha256.bind(File(path).openRead()).first;
    return digest.toString();
  }

  /// True when the file at [filePath] hashes to [expectedHash] (case-
  /// insensitive). A length/format-invalid expected hash returns false rather
  /// than throwing, so a garbage manifest fails closed.
  @visibleForTesting
  static Future<bool> fileMatchesHash(
    String filePath,
    String expectedHash,
  ) async {
    final expected = parseChecksumText(expectedHash);
    if (expected == null) return false;
    final actual = await sha256OfFile(filePath);
    return actual == expected;
  }

  /// The full safe download: fetch the published checksum manifest (from the
  /// release asset itself, not the JSON), stream the archive, then verify its
  /// SHA-256. On any mismatch the just-downloaded file is deleted and reported
  /// as [DownloadStatus.checksumMismatch] — the app never hands the user an
  /// archive it could not prove matches the publisher's checksum. If the feed
  /// exposed no checksum endpoint, the download is treated as UNVERIFIED and
  /// reported as a failure rather than silently trusted.
  static Future<DownloadOutcome> downloadAndVerify(
    UpdateArtifact artifact,
    String destPath, {
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
    int maxBytes = 512 * 1024 * 1024,
  }) async {
    if (!artifact.isDownloadable) {
      return const DownloadOutcome(
        DownloadStatus.failed,
        error: 'update package is not a trustworthy HTTPS source',
      );
    }
    final manifest = artifact.checksumUrl;
    if (manifest == null || !isTrustworthyFeed(manifest)) {
      // Refuse to present an unverified archive as an "update": no checksum
      // endpoint means no way to prove integrity, so this is a hard stop.
      return const DownloadOutcome(
        DownloadStatus.failed,
        error: 'no checksum manifest published for this release',
      );
    }
    try {
      final r = await http
          .get(Uri.parse(manifest), headers: const {'Accept': 'text/plain'})
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) {
        return DownloadOutcome(
          DownloadStatus.failed,
          error: 'checksum fetch HTTP ${r.statusCode}',
        );
      }
      final expected = parseChecksumText(r.body);
      if (expected == null) {
        return const DownloadOutcome(
          DownloadStatus.failed,
          error: 'malformed checksum manifest',
        );
      }
      final dl = await downloadToPath(
        artifact.packageUrl!,
        destPath,
        onProgress: onProgress,
        isCancelled: isCancelled,
        maxBytes: maxBytes,
      );
      if (dl.status != DownloadStatus.verified) return dl; // cancelled/failed
      final actual = await sha256OfFile(destPath);
      if (actual != expected) {
        try {
          File(destPath).deleteSync();
        } catch (_) {}
        return DownloadOutcome(
          DownloadStatus.checksumMismatch,
          error: 'expected $expected, got $actual',
        );
      }
      return DownloadOutcome(
        DownloadStatus.verified,
        path: destPath,
        receivedBytes: dl.receivedBytes,
        totalBytes: dl.totalBytes,
      );
    } catch (e) {
      try {
        File(destPath).deleteSync();
      } catch (_) {}
      return DownloadOutcome(DownloadStatus.failed, error: '$e');
    }
  }

  /// §317: a feed is trusted only over HTTPS with a real host. `http:`, a bare
  /// path, or an unparseable value are rejected so a plaintext or garbage
  /// update source can never be contacted.
  @visibleForTesting
  static bool isTrustworthyFeed(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  static bool _hasPrereleaseTag(String v) =>
      RegExp(r'-[0-9A-Za-z]').hasMatch(v);

  /// Numeric core of a version with any `-prerelease` / `+build` metadata
  /// stripped, so `1.2.0+7` and `1.2.0-beta.1` compare correctly as `1.2.0`.
  static List<int> _coreParts(String v) => v
      .split(RegExp(r'[-+]'))
      .first
      .split('.')
      .map((e) => int.tryParse(e.trim()) ?? 0)
      .toList();

  @visibleForTesting
  static bool isNewer(String latest, String current) {
    final latestParts = _coreParts(latest);
    final currentParts = _coreParts(current);

    for (var i = 0; i < latestParts.length && i < currentParts.length; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return latestParts.length > currentParts.length;
  }

  static Future<void> launchUpdate(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

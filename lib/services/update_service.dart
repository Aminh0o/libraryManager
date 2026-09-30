import 'dart:convert';
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
  const UpdateCheckResult(this.status, {this.version, this.url});
  final UpdateStatus status;
  final String? version;
  final String? url;

  bool get hasUpdate =>
      status == UpdateStatus.available && (url != null && url!.isNotEmpty);
}

/// Service to check for application updates against an operator-configured
/// release feed (a GitHub `releases/latest` JSON or any endpoint exposing
/// `tag_name`/`version` + `html_url`/`url`).
class UpdateService {
  /// The release-feed URL is supplied at build time via
  /// `--dart-define=UPDATE_FEED_URL=https://api.github.com/repos/OWNER/REPO/releases/latest`.
  /// Left unset (the honest default for a self-hosted deployment that has no
  /// public feed) the check reports [UpdateStatus.notConfigured] instead of
  /// pretending the app is up to date.
  static const String _updateApiUrl = String.fromEnvironment('UPDATE_FEED_URL');

  static Future<UpdateCheckResult> checkForUpdate() async {
    if (_updateApiUrl.isEmpty) {
      return const UpdateCheckResult(UpdateStatus.notConfigured);
    }
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final response = await http
          .get(
            Uri.parse(_updateApiUrl),
            headers: const {'Accept': 'application/json'},
          )
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
  static UpdateCheckResult fromPayload(
    Map<String, dynamic> data, {
    required String currentVersion,
  }) {
    final raw = data['tag_name'] ?? data['version'];
    if (raw == null) return const UpdateCheckResult(UpdateStatus.failed);
    final latest = raw.toString().replaceFirst('v', '').trim();
    if (latest.isEmpty) return const UpdateCheckResult(UpdateStatus.failed);
    final downloadUrl = (data['html_url'] ?? data['url'])?.toString();
    if (isNewer(latest, currentVersion)) {
      return UpdateCheckResult(
        UpdateStatus.available,
        version: latest,
        url: downloadUrl,
      );
    }
    return const UpdateCheckResult(UpdateStatus.upToDate);
  }

  @visibleForTesting
  static bool isNewer(String latest, String current) {
    final latestParts = latest
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final currentParts = current
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();

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

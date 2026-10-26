import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_service.dart';

/// Phase 13 — the app now NOTICES an update on its own.
///
/// The download/verify machinery already lived in [UpdateService]; what was
/// missing (and this audit confirmed by grep: a single call site) was any
/// AUTOMATIC detection — an update was only ever found when the operator
/// opened Settings and tapped "Check for Updates". The owner asked for the app
/// to notice a new version "if there is an internet connection" and "give a
/// notification or a toast" without re-downloading the world. This adds that
/// detection as a startup check, built so it can never nag or lie:
///
///  * **Admin-only surface.** It runs only for a session that can actually act
///    on the result (open Settings → download + install). Staff/viewers are
///    never surprised by a prompt they have no way to satisfy. (The install
///    itself remains manual/verified exactly as the Settings flow does — this
///    class only DECIDES whether to announce; it never downloads anything.)
///  * **Throttled.** At most one network check per [checkInterval]; the
///    timestamp is written BEFORE the request so a slow or failing feed is not
///    re-hit on every launch.
///  * **Honest.** Only a real [UpdateStatus.available] produces a toast.
///    `notConfigured`, `upToDate` and `failed` (no feed / no internet / feed
///    unreachable) stay completely silent — the absence of a connection is not
///    an announcement, mirroring the ARC-06 rule in [UpdateService].
///  * **De-duplicated per release.** A given version is announced once; it does
///    not re-toast on every start until the operator updates.
///
/// Every dependency is injectable ([check], [prefsProvider], [now]) so the
/// whole decision flow is unit-testable with no network and no real storage.
class UpdateNotifier {
  UpdateNotifier._();

  /// How often the startup check is allowed to hit the network.
  static const Duration checkInterval = Duration(hours: 12);

  static const String _lastCheckKey = 'lastUpdateCheckAt';
  static const String _lastAnnouncedKey = 'lastAnnouncedVersion';

  /// Pure throttle: run when we have never checked, or the [interval] has
  /// elapsed. `now` is injected so it is deterministic in tests.
  @visibleForTesting
  static bool shouldRunCheck(DateTime? last, DateTime now, Duration interval) {
    if (last == null) return true;
    return !now.isBefore(last.add(interval));
  }

  /// Pure honest gate + per-version dedupe. Returns the version to announce, or
  /// null when nothing should be shown. Only [UpdateStatus.available] with a
  /// non-empty version that differs from [lastAnnounced] announces anything.
  @visibleForTesting
  static String? announceVersion(UpdateCheckResult r, String? lastAnnounced) {
    if (r.status != UpdateStatus.available) return null;
    final v = r.version;
    if (v == null || v.isEmpty) return null;
    if (v == lastAnnounced) return null;
    return v;
  }

  /// The runtime hook the shell calls once after the first frame. Reads the
  /// throttle state, optionally runs the (injected) check, persists the new
  /// state, and returns the version the caller should announce — or null when
  /// nothing should be shown. Never throws: a throwing [check] is swallowed and
  /// reported as "nothing to show", because a diagnostic startup probe must not
  /// disturb the operator's session.
  static Future<String?> runStartupCheck({
    Future<UpdateCheckResult> Function()? check,
    Future<SharedPreferences> Function()? prefsProvider,
    DateTime? now,
    Duration interval = checkInterval,
  }) async {
    final prefs = await (prefsProvider ?? SharedPreferences.getInstance)();

    final stamp = prefs.getString(_lastCheckKey);
    final last = stamp == null ? null : DateTime.tryParse(stamp);
    final moment = now ?? DateTime.now();
    if (!shouldRunCheck(last, moment, interval)) return null;

    // Persist the attempt BEFORE the network call: a slow/failed check must not
    // be retried on every launch inside the window (do not hammer the feed).
    await prefs.setString(_lastCheckKey, moment.toIso8601String());

    final run = check ?? UpdateService.checkForUpdate;
    final UpdateCheckResult result;
    try {
      result = await run();
    } catch (e) {
      debugPrint('UpdateNotifier: startup check threw (ignored): $e');
      return null;
    }

    final announced = announceVersion(
      result,
      prefs.getString(_lastAnnouncedKey),
    );
    if (announced == null) return null;
    await prefs.setString(_lastAnnouncedKey, announced);
    return announced;
  }
}

import 'package:flutter/foundation.dart' show ChangeNotifier, immutable;
import 'package:shared_preferences/shared_preferences.dart';

/// Phase 14: a small, genuine feature-flag mechanism. Each flag gates an
/// optional product surface (the deferred tier-2 features built in later
/// Phases 15-19) so an operator can turn a surface off without a rebuild, and
/// so an unfinished/experimental affordance can ship dark.
///
/// This is intentionally a fixed, known catalog rather than an arbitrary string
/// map: a flag nobody can enumerate becomes dead config. Every flag here is
/// actually consulted by a widget (grep the [Flag] ids), and the defaults are
/// chosen so the shipped app behaves exactly as if the mechanism did not exist
/// (all built surfaces on). Persistence is per-device [SharedPreferences], like
/// the rest of the local settings.
class FeatureFlags extends ChangeNotifier {
  FeatureFlags._(this._values);

  /// The known flags and their shipped-by-default state. An operator toggles
  /// these from the admin Settings -> Features section.
  static const List<Flag> catalog = [
    Flag(id: 'commandPalette', label: 'Command palette (Ctrl+K)', defaultOn: true),
    Flag(id: 'notificationCenter', label: 'Notification center', defaultOn: true),
    Flag(id: 'systemHealth', label: 'System-health dashboard', defaultOn: true),
    Flag(id: 'lanChat', label: 'LAN staff chat', defaultOn: true),
    Flag(id: 'appearanceSettings', label: 'Appearance / white-label settings', defaultOn: true),
  ];

  static List<String> get knownIds => catalog.map((f) => f.id).toList();

  // id -> effective on/off (only for ids present in [catalog]).
  final Map<String, bool> _values;

  bool isEnabled(String id) => _values[id] ?? false;

  Future<void> setEnabled(String id, bool on) {
    if (!_values.containsKey(id)) return Future.value(); // unknown id: ignore
    if (_values[id] == on) return Future.value();
    _values[id] = on;
    notifyListeners();
    return _persist();
  }

  static Future<FeatureFlags> load() async {
    final values = <String, bool>{for (final f in catalog) f.id: f.defaultOn};
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final f in catalog) {
        values[f.id] = prefs.getBool('$_kPrefix${f.id}') ?? f.defaultOn;
      }
    } catch (_) {
      // keep defaults on any read failure
    }
    return FeatureFlags._(values);
  }

  static const String _kPrefix = 'feature.flag.';

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _values.forEach((id, on) => prefs.setBool('$_kPrefix$id', on));
    } catch (_) {
      // cosmetic-only persistence failure
    }
  }
}

/// A single named flag with its operator-facing label and shipped default.
@immutable
class Flag {
  const Flag({
    required this.id,
    required this.label,
    required this.defaultOn,
  });
  final String id;
  final String label;
  final bool defaultOn;
}

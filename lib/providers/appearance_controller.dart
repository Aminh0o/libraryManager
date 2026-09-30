import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/app_theme.dart';

/// Phase 14/17 (appearance + white-label): the single source of truth for the
/// app's visual identity, persisted so a rebuilt/restarted deployment keeps its
/// look. Before this the theme was a hardcoded `Colors.orange` seed in `main`
/// and there was no dark mode or brand name anywhere -- an operator could not
/// re-skin the app for their library, and the light-only UI was unforgiving on
/// the eyes across a full shift.
///
/// Deliberately stored in [SharedPreferences] (like the other local user
/// settings) and NOT in the shared database: appearance is per-device, not
/// per-library, so a client PC and the host may legitimately look different.
/// The brand/seed choices carry no security or integrity meaning -- they are
/// cosmetic -- so there is no server round-trip and no role gate on the model
/// itself (the Settings UI that edits it is where administer gating lives).
class AppearanceController extends ChangeNotifier {
  AppearanceController._({
    required ThemeMode mode,
    required int seedValue,
    required String brandName,
  })  : _mode = mode,
        _seedValue = seedValue,
        _brandName = brandName;

  static const String _kMode = 'appearance.themeMode';
  static const String _kSeed = 'appearance.seedValue';
  static const String _kBrand = 'appearance.brandName';

  /// Defaults mirror the pre-Phase-14 app exactly (Material3, orange seed, the
  /// original window title) so introducing them changes nothing until an
  /// operator opts in.
  static const int defaultSeedValue = 0xFFFF9800; // Material orange
  static const String defaultBrandName = 'Library Manager';

  ThemeMode _mode;
  int _seedValue;
  String _brandName;

  ThemeMode get themeMode => _mode;
  int get seedValue => _seedValue;
  Color get seedColor => Color(_seedValue);
  String get brandName => _brandName;

  /// Named seeds offered in the Settings appearance picker. A white-label
  /// operator picks one; the value is the ARGB int persisted in prefs.
  static const List<({String name, int value})> presetSeeds = [
    (name: 'Orange', value: 0xFFFF9800),
    (name: 'Indigo', value: 0xFF3F51B5),
    (name: 'Teal', value: 0xFF009688),
    (name: 'Blue', value: 0xFF2196F3),
    (name: 'Purple', value: 0xFF9C27B0),
    (name: 'Green', value: 0xFF4CAF50),
    (name: 'Brown', value: 0xFF795548),
    (name: 'Rose', value: 0xFFE91E63),
  ];

  /// Load the persisted appearance, falling back to the historical defaults on
  /// a first run or any unread value. Never throws -- a corrupt pref must not
  /// stop the app from starting.
  static Future<AppearanceController> load() async {
    ThemeMode mode = ThemeMode.system;
    int seed = defaultSeedValue;
    String brand = defaultBrandName;
    try {
      final prefs = await SharedPreferences.getInstance();
      mode = _decodeMode(prefs.getString(_kMode));
      seed = prefs.getInt(_kSeed) ?? defaultSeedValue;
      final stored = prefs.getString(_kBrand);
      if (stored != null && stored.trim().isNotEmpty) brand = stored.trim();
    } catch (_) {
      // Best-effort: keep defaults.
    }
    return AppearanceController._(
        mode: mode, seedValue: seed, brandName: brand);
  }

  static ThemeMode _decodeMode(String? raw) => switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Future<void> setThemeMode(ThemeMode mode) {
    if (_mode == mode) return Future.value();
    _mode = mode;
    notifyListeners();
    return _persist();
  }

  Future<void> setSeedColor(int value) {
    if (_seedValue == value) return Future.value();
    _seedValue = value;
    notifyListeners();
    return _persist();
  }

  /// Set the operator-visible product name. Blank/whitespace is rejected back
  /// to the default so the title bar / app bar never render empty.
  Future<void> setBrandName(String name) {
    final trimmed = name.trim();
    final next = trimmed.isEmpty ? defaultBrandName : trimmed;
    if (_brandName == next) return Future.value();
    _brandName = next;
    notifyListeners();
    return _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kMode, _mode.name);
      await prefs.setInt(_kSeed, _seedValue);
      await prefs.setString(_kBrand, _brandName);
    } catch (_) {
      // A failed persistence is cosmetic-only; the in-memory state is still
      // correct for this session.
    }
  }

  /// The [ColorScheme] implied by the current seed + brightness. Exposed
  /// separately from [themeFor] so the seed/brightness behaviour is unit-
  /// testable without touching `GoogleFonts` (which lazily fetches fonts over
  /// the network and is therefore hostile to a pure Dart test binding).
  ColorScheme colorSchemeFor(Brightness brightness) => ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
      );

  /// The full theme for [brightness], driven by the persisted seed. Delegates
  /// the whole visual system to [AppTheme] (Phase A) so light + dark are both
  /// designed from one place, then layers `outfit` (the app's established
  /// typeface) on top of that scale -- re-skinning never loses the font, and the
  /// seed now actually reaches the chrome instead of a hard-coded orange.
  ThemeData themeFor(Brightness brightness) {
    final themed = brightness == Brightness.dark
        ? AppTheme.dark(seedColor)
        : AppTheme.light(seedColor);
    return themed.copyWith(
      textTheme: GoogleFonts.outfitTextTheme(themed.textTheme),
    );
  }
}

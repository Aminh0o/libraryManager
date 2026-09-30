import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:library_manager/providers/appearance_controller.dart';

/// Phase 14/17: the appearance controller is per-device, persisted, and must
/// never throw on a corrupt/absent pref (a cosmetic store must not brick
/// startup). These prove the defaults, the persist-on-set behaviour, and the
/// blank-brand guard.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('load() falls back to the historical defaults on a first run',
      () async {
    final a = await AppearanceController.load();
    expect(a.themeMode, ThemeMode.system);
    expect(a.seedValue, AppearanceController.defaultSeedValue);
    expect(a.brandName, AppearanceController.defaultBrandName);
  });

  test('setThemeMode notifies, updates and persists across reload', () async {
    final a = await AppearanceController.load();
    var notified = 0;
    a.addListener(() => notified++);

    await a.setThemeMode(ThemeMode.dark);
    expect(a.themeMode, ThemeMode.dark);
    expect(notified, 1);
    // Same value is a no-op (no spurious notify / write).
    await a.setThemeMode(ThemeMode.dark);
    expect(notified, 1);

    final reloaded = await AppearanceController.load();
    expect(reloaded.themeMode, ThemeMode.dark);
  });

  test('setSeedColor persists', () async {
    final a = await AppearanceController.load();
    await a.setSeedColor(0xFF3F51B5);
    final reloaded = await AppearanceController.load();
    expect(reloaded.seedValue, 0xFF3F51B5);
    expect(reloaded.seedColor, const Color(0xFF3F51B5));
  });

  test('brand name is trimmed; a blank value reverts to the default', () async {
    final a = await AppearanceController.load();
    await a.setBrandName('  City Library  ');
    expect(a.brandName, 'City Library');

    await a.setBrandName('   ');
    expect(a.brandName, AppearanceController.defaultBrandName,
        reason: 'the title bar must never render empty');
  });

  test('colorSchemeFor honours the requested brightness + seed', () async {
    final a = await AppearanceController.load();
    await a.setSeedColor(0xFF009688);
    expect(a.colorSchemeFor(Brightness.light).brightness, Brightness.light);
    expect(a.colorSchemeFor(Brightness.dark).brightness, Brightness.dark);
    // fromSeed derives a coherent scheme; the seed itself need not survive
    // verbatim, but the light/dark distinction must.
    expect(
      a.colorSchemeFor(Brightness.light).primary,
      isNot(a.colorSchemeFor(Brightness.dark).primary),
    );
  });

  test('preset seeds carry unique values and cover the default', () {
    final values = AppearanceController.presetSeeds.map((e) => e.value).toList();
    expect(values.toSet().length, values.length);
    expect(values, contains(AppearanceController.defaultSeedValue));
  });
}

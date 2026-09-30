import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:library_manager/services/feature_flags.dart';

/// Phase 14: the flag mechanism is only honest if every flag is enumerable,
/// default-correct, persisting, and the setter refuses unknown ids (so config
/// can silently accumulate dead keys).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('catalog ids are unique', () {
    final ids = FeatureFlags.catalog.map((f) => f.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('all built surfaces ship enabled by default', () async {
    final flags = await FeatureFlags.load();
    for (final f in FeatureFlags.catalog) {
      expect(flags.isEnabled(f.id), f.defaultOn);
    }
  });

  test('setEnabled persists across reload and notifies once', () async {
    final flags = await FeatureFlags.load();
    var notified = 0;
    flags.addListener(() => notified++);

    final id = FeatureFlags.catalog.first.id;
    await flags.setEnabled(id, false);
    expect(flags.isEnabled(id), isFalse);
    expect(notified, 1);

    final reloaded = await FeatureFlags.load();
    expect(reloaded.isEnabled(id), isFalse);
  });

  test('an unknown id is ignored (no dead config, no throw)', () async {
    final flags = await FeatureFlags.load();
    expect(() => flags.setEnabled('not.a.real.flag', true), returnsNormally);
    expect(
      flags.isEnabled('not.a.real.flag'),
      isFalse,
      reason: 'a non-catalog id has no default and reports off',
    );
  });
}

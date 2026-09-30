import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/services/database_service.dart';

/// DB-01 (attribute determinism). `attribute_definitions` had NO
/// UNIQUE(type,value), so the same status/attribute could be inserted over and
/// over ("duplicate statuses"). Phase 9.15 adds the `uq_attr_type_value` index
/// defensively AND a typed pre-check in `addAttributeDefinition` -- mirroring
/// the barcode treatment -- so a duplicate is a clean `AttributeConflictException`
/// (server -> 409) rather than a raw UNIQUE ConstraintError (500). Runs against
/// a real file DB so the production schema (fresh install -> onCreate applies
/// the index over the seeded statuses) is genuinely exercised; a fake repository
/// would not enforce the index.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.documentsPath);
  final String documentsPath;
  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final svc = DatabaseService();
  late Directory tmp;
  late Database db;

  Future<int> count(String type, String value) async {
    final r = await db.rawQuery(
      'SELECT COUNT(*) c FROM attribute_definitions WHERE type = ? AND value = ?',
      [type, value],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('lib_attrconf_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    db = await svc.database; // fresh install -> onCreate + constraints
  });

  tearDownAll(() async {
    if (db.isOpen) await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('duplicate attribute (type,value) is a typed conflict (DB-01)', () {
    test('the seeded schema carries the uq_attr_type_value index', () async {
      final idx = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name = ?",
        ['uq_attr_type_value'],
      );
      expect(
        idx,
        isNotEmpty,
        reason: 'a fresh install must get the attribute UNIQUE index',
      );
    });

    test(
      're-adding an existing (STATUS, Disponible) throws the typed conflict',
      () async {
        // 'Disponible' is seeded by _onCreate. The duplicate must surface as the
        // typed conflict, NOT a raw DatabaseException, and add nothing.
        Object? caught;
        try {
          await svc.addAttributeDefinition('STATUS', 'Disponible');
        } catch (e) {
          caught = e;
        }
        expect(caught, isA<AttributeConflictException>());
        expect(caught, isNot(isA<DatabaseException>()));
        expect(await count('STATUS', 'Disponible'), 1);
      },
    );

    test(
      'same value under a DIFFERENT type is allowed (composite key)',
      () async {
        await svc.addAttributeDefinition('CATEGORY', 'Disponible');
        expect(await count('CATEGORY', 'Disponible'), 1);
        // And the STATUS one is untouched.
        expect(await count('STATUS', 'Disponible'), 1);
      },
    );

    test(
      'the index itself rejects a raw duplicate (bypassing the app check)',
      () async {
        // Proves the constraint is genuinely enforced at the DB layer, not just
        // the pre-check: a direct insert of a duplicate (type,value) blows up.
        await svc.addAttributeDefinition('SHELF', 'A1');
        await expectLater(
          db.insert('attribute_definitions', {'type': 'SHELF', 'value': 'A1'}),
          throwsA(isA<DatabaseException>()),
        );
      },
    );
  });

  group('migration resilience (DB-08 / DB-01)', () {
    test('an install that ALREADY has a duplicate attribute upgrades without '
        'boot-looping and keeps both rows (index skipped)', () async {
      // Simulate a legacy v9 file whose attribute table already holds a
      // duplicate (type,value), then reopen through the production path so
      // _applyConstraintsSafely runs over it. The violated index is skipped;
      // no rows are deleted and the upgrade does not throw.
      final legacyPath = p.join(tmp.path, 'legacy.db');
      final old = await databaseFactoryFfi.openDatabase(
        legacyPath,
        options: OpenDatabaseOptions(
          version: 14,
          singleInstance: false,
          onCreate: (d, _) async {
            await d.execute(
              '''CREATE TABLE attribute_definitions(
                id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT, value TEXT)''',
            );
            await d.execute(
              'CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT)',
            );
            await d.insert('attribute_definitions', {
              'type': 'STATUS',
              'value': 'Dup',
            });
            await d.insert('attribute_definitions', {
              'type': 'STATUS',
              'value': 'Dup',
            });
          },
        ),
      );
      await old.close();

      final migrated = await svc.openDatabaseAt(legacyPath);
      expect(await migrated.getVersion(), DatabaseService.currentSchemaVersion);
      final rows = await migrated.query(
        'attribute_definitions',
        where: "value = 'Dup'",
      );
      expect(rows.length, 2, reason: 'violators survive; none deleted');
      await migrated.close();
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/services/database_service.dart';

/// FW-03: bulk Excel import used `ConflictAlgorithm.replace`, so any imported
/// row whose `code` already existed SILENTLY overwrote the catalogue entry
/// (designation / quantity / status lost, no warning). Import now skips
/// existing codes, seeds per-copy state only for genuinely-new rows, and writes
/// its audit line + `db_version` stamp inside the same transaction (BE-09 /
/// RC-06). Runs against a real file DB so the production schema is exercised.
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

  LibraryItem item(
    String code, {
    String designation = 'Title',
    int quantite = 1,
  }) => LibraryItem(
    code: code,
    codeType: 'LIV',
    designation: designation,
    quantite: quantite,
    emplacement: 'A',
    taux: 10,
    emplacementStock: 'S',
    status: 'Disponible',
  );

  Future<Map<String, dynamic>?> row(String code) async {
    final r = await db.query(
      'library_items',
      where: 'code = ?',
      whereArgs: [code],
    );
    return r.isEmpty ? null : r.first;
  }

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('lib_importconf_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    db = await svc.database;
  });

  tearDownAll(() async {
    if (db.isOpen) await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('bulk import never clobbers existing rows (FW-03)', () {
    test(
      'an existing code is skipped, not overwritten; new rows are seeded',
      () async {
        // Seed a pre-existing title with a distinctive designation + 2 copies.
        await svc.addItem(item('0001', designation: 'Original', quantite: 2));

        final res = await svc.batchInsertItems([
          item('0001', designation: 'CLOBBERED', quantite: 9), // collision
          item('0002', designation: 'Fresh', quantite: 3), // new
        ]);

        expect(res.inserted, 1);
        expect(res.skippedCodes, contains('0001'));

        // The existing row is untouched (this is the data-loss the fix prevents).
        final kept = await row('0001');
        expect(kept, isNotNull);
        expect(kept!['designation'], 'Original');
        expect(kept['quantite'], 2);
        // Its copies were neither duplicated nor dropped by a delete+reinsert.
        expect(
          await db.query('item_copies', where: "item_code = '0001'"),
          hasLength(2),
        );

        // The new row landed and got its per-copy set seeded.
        expect(await row('0002'), isNotNull);
        expect(
          await db.query('item_copies', where: "item_code = '0002'"),
          hasLength(3),
        );
      },
    );

    test('a duplicate code within the same file inserts only once', () async {
      final res = await svc.batchInsertItems([
        item('0010', designation: 'First'),
        item('0010', designation: 'Second'),
      ]);
      expect(res.inserted, 1);
      expect(res.skippedCodes, contains('0010'));
      expect(
        await db.query('library_items', where: "code = '0010'"),
        hasLength(1),
      );
      // The surviving row is the FIRST one, not the overwrite.
      expect((await row('0010'))!['designation'], 'First');
    });

    test('import writes an accurate audit line atomically', () async {
      await svc.batchInsertItems(
        [item('0030')],
        audit: {
          'timestamp': DateTime.now().toIso8601String(),
          'operation': 'IMPORT',
          'details': '1 lignes analysees depuis Excel',
          'user': 'Host',
        },
      );
      final hist = await svc.getHistory(limit: 200);
      expect(hist.any((h) => h['operation'] == 'IMPORT'), isTrue);
    });

    test('a failing audit write rolls the whole batch back (atomic)', () async {
      // The audit row is inserted RAW (server/host-authored). A bogus column
      // makes the history insert throw, which must undo every item insert too
      // -- proving data + audit + version commit or fail as one unit.
      await expectLater(
        svc.batchInsertItems(
          [item('0040'), item('0041')],
          audit: {
            'timestamp': DateTime.now().toIso8601String(),
            'operation': 'IMPORT',
            'details': 'should roll back',
            'user': 'Host',
            'bogus': 'no-such-column',
          },
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(await row('0040'), isNull);
      expect(await row('0041'), isNull);
    });
  });
}

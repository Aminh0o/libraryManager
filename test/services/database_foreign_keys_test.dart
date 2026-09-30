import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/services/database_service.dart';

/// DB-01 foreign-key enforcement, driven through the REAL schema lifecycle
/// (onCreate + onUpgrade) against file-backed SQLite databases, exactly like
/// the migration suite. Covers the v16 -> v17 FK rebuild and the fresh-install
/// FK schema, including the defensive skip so a legacy DB that already holds
/// orphans still opens (no boot-loop).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final svc = DatabaseService();
  late Directory tmp;
  late String path;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lib_fk_');
    path = p.join(tmp.path, 'library_manager.db');
  });
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<List<Map<String, Object?>>> fkList(Database db, String table) =>
      db.rawQuery('PRAGMA foreign_key_list($table)');

  // A pre-v17 database: loans + item_copies WITHOUT foreign keys, library_items
  // WITH row_version. Reopening through `openDatabaseAt` runs onUpgrade 16->17.
  Future<Database> createV16() => databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 16,
          singleInstance: false,
          onCreate: (db, _) async {
            await db.execute('''CREATE TABLE library_items(
              code TEXT PRIMARY KEY, barcode TEXT, code_type TEXT,
              designation TEXT, quantite INTEGER, emplacement TEXT, taux REAL,
              emplacement_stock TEXT, status TEXT,
              row_version INTEGER NOT NULL DEFAULT 0)''');
            await db.execute('''CREATE TABLE item_copies(
              id INTEGER PRIMARY KEY AUTOINCREMENT, item_code TEXT NOT NULL,
              barcode TEXT, state TEXT NOT NULL DEFAULT 'Disponible',
              note TEXT, acquired_at TEXT)''');
            await db.execute('''CREATE TABLE loans(
              id INTEGER PRIMARY KEY AUTOINCREMENT, item_code TEXT,
              copy_id INTEGER, member_id TEXT, member_name TEXT, item_title TEXT,
              loan_date TEXT, due_date TEXT, return_date TEXT, status TEXT)''');
          },
        ),
      );

  test('a fresh install declares the foreign keys', () async {
    final db = await svc.openDatabaseAt(path);
    expect(await db.getVersion(), DatabaseService.currentSchemaVersion);

    final loanFks = await fkList(db, 'loans');
    final loanCols = loanFks.map((r) => r['from']).toSet();
    expect(loanCols, containsAll(['item_code', 'copy_id']));
    final copyFks = await fkList(db, 'item_copies');
    expect(copyFks.map((r) => r['from']), contains('item_code'));

    // A valid chain works, an orphan is rejected AT THE DB LAYER.
    await db.insert('library_items', {'code': '0500', 'designation': 'B'});
    final copyId = await db
        .insert('item_copies', {'item_code': '0500', 'state': 'Disponible'});
    await db.insert('loans', {
      'item_code': '0500', 'copy_id': copyId, 'status': 'Active'
    });
    await expectLater(
      db.insert('loans', {'item_code': 'NOPE', 'status': 'Active'}),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.insert('item_copies', {'item_code': 'GHOST', 'state': 'Disponible'}),
      throwsA(isA<DatabaseException>()),
    );
    await db.close();
  });

  test('a clean v16 DB upgrades to get FKs that then block orphans', () async {
    final old = await createV16();
    await old.insert('library_items', {'code': '0600', 'designation': 'Old'});
    final copyId = await old
        .insert('item_copies', {'item_code': '0600', 'state': 'Emprunté'});
    await old.insert('loans', {
      'id': 7, 'item_code': '0600', 'copy_id': copyId, 'status': 'Active'
    });
    await old.close();

    final db = await svc.openDatabaseAt(path); // runs 16 -> 17
    expect(await db.getVersion(), DatabaseService.currentSchemaVersion);

    // FKs now exist, and every pre-existing row survived the rebuild intact
    // (including the explicit loan id).
    expect((await fkList(db, 'loans')).map((r) => r['from']),
        containsAll(['item_code', 'copy_id']));
    final loan = (await db.query('loans')).single;
    expect(loan['id'], 7);
    expect(loan['item_code'], '0600');
    expect(loan['copy_id'], copyId);
    expect(await db.query('item_copies'), hasLength(1));

    await expectLater(
      db.insert('loans', {'item_code': 'MISSING', 'status': 'Active'}),
      throwsA(isA<DatabaseException>()),
    );
    await db.close();
  });

  test('a v16 DB WITH orphan loans still opens (FK skipped, no boot-loop)',
      () async {
    final old = await createV16();
    await old.insert('library_items', {'code': '0700', 'designation': 'Kept'});
    // Orphan: loan points at an item that does not exist.
    await old.insert('loans', {
      'item_code': 'GONE', 'status': 'Active', 'member_id': 'M1'
    });
    await old.close();

    // Must NOT throw despite the orphan -- the migration skips the FK rebuild.
    final db = await svc.openDatabaseAt(path);
    expect(await db.getVersion(), DatabaseService.currentSchemaVersion);

    // FKs were intentionally NOT added; the orphan row is preserved untouched.
    expect(await fkList(db, 'loans'), isEmpty);
    final loans = await db.query('loans');
    expect(loans, hasLength(1));
    expect(loans.single['item_code'], 'GONE');
    await db.close();
  });

  test('a v16 DB WITH orphan copies is skipped too (no boot-loop)', () async {
    final old = await createV16();
    await old.insert('item_copies', {'item_code': 'NO_SUCH', 'state': 'Disponible'});
    await old.close();

    final db = await svc.openDatabaseAt(path);
    expect(await db.getVersion(), DatabaseService.currentSchemaVersion);
    expect(await fkList(db, 'item_copies'), isEmpty);
    expect(await fkList(db, 'loans'), isEmpty);
    await db.close();
  });
}

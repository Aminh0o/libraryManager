import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/services/database_service.dart';

/// Drives the REAL schema lifecycle (`onCreate` + `onUpgrade` + `onConfigure`)
/// against a file-backed SQLite database via the production
/// `DatabaseService.openDatabaseAt`. The `useDatabaseForTesting` seam used by
/// the other suites injects an already-open database and therefore never runs
/// these callbacks — so this file is the DB-08 "migrations UNVERIFIED" proof.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  // The production `openDatabaseAt` uses the global sqflite `openDatabase`,
  // which requires the FFI factory to be the process-wide one.
  databaseFactory = databaseFactoryFfi;

  final svc = DatabaseService();
  late Directory tmp;
  late String path;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lib_migration_');
    path = p.join(tmp.path, 'library_manager.db');
  });

  tearDown(() async {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<bool> tableExists(Database db, String name) async {
    final r = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [name],
    );
    return r.isNotEmpty;
  }

  Future<Set<String>> indexes(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'",
    );
    return rows.map((r) => r['name'] as String).toSet();
  }

  // Builds a representative v9 database: before the auth tables (v10), the
  // copy ledger (v11) and loans.copy_id (v12) / indexes (v13).
  Future<Database> createV9() => databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 9,
      singleInstance: false,
      onCreate: (db, _) async {
        await db.execute('''CREATE TABLE library_items(
              code TEXT PRIMARY KEY, code_type TEXT, designation TEXT,
              quantite INTEGER, emplacement TEXT, taux REAL,
              emplacement_stock TEXT, status TEXT, barcode TEXT)''');
        await db.execute(
          'CREATE TABLE code_definitions(prefix TEXT PRIMARY KEY, label TEXT)',
        );
        await db.execute('''CREATE TABLE attribute_definitions(
              id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT, value TEXT)''');
        await db.execute('''CREATE TABLE history(
              id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT,
              operation TEXT, details TEXT, user TEXT)''');
        await db.execute(
          'CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT)',
        );
        await db.execute('''CREATE TABLE members(
              id INTEGER PRIMARY KEY AUTOINCREMENT, first_name TEXT,
              last_name TEXT, email TEXT, phone TEXT,
              member_id TEXT UNIQUE, registered_at TEXT)''');
        await db.execute('''CREATE TABLE loans(
              id INTEGER PRIMARY KEY AUTOINCREMENT, item_code TEXT,
              member_id TEXT, member_name TEXT, item_title TEXT,
              loan_date TEXT, due_date TEXT, return_date TEXT, status TEXT)''');
      },
    ),
  );

  test(
    'v9 database upgrades to the current schema with data preserved',
    () async {
      final old = await createV9();
      await old.insert('library_items', {
        'code': '0500',
        'code_type': 'LIV',
        'designation': 'Old Book',
        'quantite': 3,
        'emplacement': 'A',
        'taux': 12.5,
        'emplacement_stock': 'S',
        'status': 'Emprunté',
        'barcode': 'ISBN-0500',
      });
      await old.insert('loans', {
        'item_code': '0500',
        'member_id': '250001',
        'member_name': 'Alice',
        'item_title': 'Old Book',
        'loan_date': '2025-01-01T00:00:00.000',
        'due_date': '2025-01-16T00:00:00.000',
        'status': 'Active',
      });
      await old.close();

      // Reopen through the PRODUCTION path: this runs onUpgrade 9 -> current.
      final db = await svc.openDatabaseAt(path);

      // 1. The schema version advanced to the build's current version.
      expect(await db.getVersion(), DatabaseService.currentSchemaVersion);

      // 2. Original rows survive the migration untouched (no data loss).
      final items = await db.query('library_items', where: "code = '0500'");
      expect(items, hasLength(1));
      expect(items.single['designation'], 'Old Book');
      final loan = (await db.query('loans')).single;
      expect(loan['item_code'], '0500');
      expect(loan['status'], 'Active');

      // 3. loans.copy_id column was added; the pre-existing loan keeps a NULL
      //    copy id (legacy loans are not retroactively bound to a copy).
      final loanCols = await db.rawQuery('PRAGMA table_info(loans)');
      expect(loanCols.map((c) => c['name']), contains('copy_id'));
      expect(loan['copy_id'], isNull);

      // 4. item_copies was created AND backfilled from quantite. An 'Emprunté'
      //    title yields one on-loan copy + the rest available.
      final copies = await db.query('item_copies', where: "item_code = '0500'");
      expect(copies, hasLength(3));
      expect(copies.where((c) => c['state'] == 'Emprunté'), hasLength(1));
      expect(copies.where((c) => c['state'] == 'Disponible'), hasLength(2));

      // 5. The v10 auth tables exist on an upgraded database.
      expect(await tableExists(db, 'admin_credentials'), isTrue);
      expect(await tableExists(db, 'client_tokens'), isTrue);

      // 6. The v13 indexes exist on an upgraded database.
      expect(
        await indexes(db),
        containsAll(<String>[
          'idx_loans_status',
          'idx_loans_item',
          'idx_loans_copy',
          'idx_items_status',
          'idx_item_copies_item',
        ]),
      );

      // 6b. On clean data the v14 UNIQUE constraints are created too.
      expect(
        await indexes(db),
        containsAll(<String>[
          'uq_loans_active_copy',
          'uq_items_barcode',
          'uq_copies_barcode',
        ]),
      );

      // 7. onConfigure enabled foreign-key enforcement.
      expect(await fkEnabled(db), 1);

      await db.close();
    },
  );

  test('a fresh install (onCreate) produces the same current schema', () async {
    // No pre-existing file -> onCreate runs instead of onUpgrade.
    final db = await svc.openDatabaseAt(path);

    expect(await db.getVersion(), DatabaseService.currentSchemaVersion);
    expect(await tableExists(db, 'item_copies'), isTrue);
    expect(await tableExists(db, 'admin_credentials'), isTrue);
    final loanCols = await db.rawQuery('PRAGMA table_info(loans)');
    expect(loanCols.map((c) => c['name']), contains('copy_id'));
    expect(
      await indexes(db),
      containsAll(<String>[
        'idx_loans_status',
        'idx_items_status',
        'idx_item_copies_item',
        'uq_loans_active_copy',
        'uq_items_barcode',
      ]),
    );
    expect(await fkEnabled(db), 1);

    await db.close();
  });

  test(
    'upgrade with pre-existing violations does NOT abort (no boot-loop)',
    () async {
      final old = await createV9();
      // Two titles sharing one ISBN violate uq_items_barcode.
      await old.insert('library_items', {
        'code': '0600',
        'designation': 'A',
        'quantite': 1,
        'status': 'Disponible',
        'barcode': 'DUP-999',
      });
      await old.insert('library_items', {
        'code': '0601',
        'designation': 'B',
        'quantite': 1,
        'status': 'Disponible',
        'barcode': 'DUP-999',
      });
      await old.close();

      // Reopen must SUCCEED (no throw) despite the duplicate ISBN.
      final db = await svc.openDatabaseAt(path);
      expect(await db.getVersion(), DatabaseService.currentSchemaVersion);

      // No rows are deleted to satisfy a constraint — both violators survive.
      final items = await db.query('library_items');
      expect(items.map((r) => r['code']), containsAll(['0600', '0601']));

      // The violated constraint was skipped; the non-violated one still applied.
      final idx = await indexes(db);
      expect(idx, isNot(contains('uq_items_barcode')));
      expect(idx, contains('uq_loans_active_copy'));

      await db.close();
    },
  );

  test(
    'active-copy unique index blocks a 2nd active loan on one copy (BL-01)',
    () async {
      // Fresh install -> onCreate applies the constraints to an empty DB.
      final db = await svc.openDatabaseAt(path);
      await db.insert('library_items', {
        'code': '0700',
        'designation': 'X',
        'quantite': 1,
        'status': 'Emprunté',
      });
      final copyId = await db.insert('item_copies', {
        'item_code': '0700',
        'state': 'Emprunté',
      });

      Future<void> activeLoan() => db.insert('loans', {
        'item_code': '0700',
        'copy_id': copyId,
        'status': 'Active',
        'loan_date': '2026-01-01T00:00:00.000',
        'due_date': '2026-01-16T00:00:00.000',
      });

      await activeLoan();
      // A second ACTIVE loan on the same physical copy is rejected at the DB
      // layer, even bypassing addLoan's CAS.
      await expectLater(activeLoan(), throwsA(isA<DatabaseException>()));

      // A RETURNED duplicate is still allowed (the index is partial on Active).
      await db.insert('loans', {
        'item_code': '0700',
        'copy_id': copyId,
        'status': 'Returned',
      });
      final active = await db.query(
        'loans',
        where: "copy_id = ? AND status = 'Active'",
        whereArgs: [copyId],
      );
      expect(active, hasLength(1));

      await db.close();
    },
  );

  // Builds a file DB pinned to [version] whose schema is exactly [build]
  // (via onCreate), so reopening through `svc.openDatabaseAt` runs the REAL
  // onUpgrade from that version. Used to exercise PARTIAL / legacy schemas the
  // complete-v9 fixture above never hits (DB-08 boot-loop failure mode).
  Future<Database> createLegacy(
    int version,
    Future<void> Function(Database db) build,
  ) => databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: version,
      singleInstance: false,
      onCreate: (db, _) => build(db),
    ),
  );

  test(
    'a legacy DB MISSING library_items migrates without boot-looping',
    () async {
      // Every table the app relies on EXCEPT library_items. The raw
      // ADD-COLUMN / backfill / index steps that touch library_items must each
      // skip gracefully rather than abort onUpgrade (the DB-08 failure mode).
      final old = await createLegacy(9, (db) async {
        await db.execute(
          'CREATE TABLE code_definitions(prefix TEXT PRIMARY KEY, label TEXT)',
        );
        await db.execute('''CREATE TABLE attribute_definitions(
        id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT, value TEXT)''');
        await db.execute('''CREATE TABLE history(
        id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT,
        operation TEXT, details TEXT, user TEXT)''');
        await db.execute(
          'CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT)',
        );
        await db.execute('''CREATE TABLE members(
        id INTEGER PRIMARY KEY AUTOINCREMENT, first_name TEXT, last_name TEXT,
        email TEXT, phone TEXT, member_id TEXT UNIQUE, registered_at TEXT)''');
        await db.execute('''CREATE TABLE loans(
        id INTEGER PRIMARY KEY AUTOINCREMENT, item_code TEXT, member_id TEXT,
        member_name TEXT, item_title TEXT, loan_date TEXT, due_date TEXT,
        return_date TEXT, status TEXT)''');
        // library_items intentionally absent.
      });
      await old.close();

      // Reopening through the production path must NOT throw.
      final db = await svc.openDatabaseAt(path);
      expect(await db.getVersion(), DatabaseService.currentSchemaVersion);

      // Later steps still ran for the tables that DO exist: item_copies created,
      // auth tables created, loans.copy_id added, indexes/constraints applied.
      expect(await tableExists(db, 'item_copies'), isTrue);
      expect(await tableExists(db, 'admin_credentials'), isTrue);
      final loanCols = await db.rawQuery('PRAGMA table_info(loans)');
      expect(loanCols.map((c) => c['name']), contains('copy_id'));
      expect(await indexes(db), contains('idx_loans_status'));

      await db.close();
    },
  );

  test(
    'a library_items already carrying later columns migrates idempotently',
    () async {
      // A prior partial run (or a hand-edited legacy file) already added the
      // columns that v2/v3/v6/v16 would add. The guarded ADD-COLUMN steps must
      // skip the present columns without a duplicate-column abort.
      final old = await createLegacy(1, (db) async {
        await db.execute('''CREATE TABLE library_items(
        code TEXT PRIMARY KEY, designation TEXT, quantite INTEGER,
        emplacement TEXT, taux REAL, emplacement_stock TEXT,
        status TEXT, code_type TEXT, barcode TEXT,
        row_version INTEGER NOT NULL DEFAULT 0)''');
      });
      await old.insert('library_items', {
        'code': '0500',
        'designation': 'X',
        'quantite': 1,
        'status': 'Emprunté',
      });
      await old.close();

      final db = await svc.openDatabaseAt(path);
      expect(await db.getVersion(), DatabaseService.currentSchemaVersion);
      final rows = await db.query('library_items', where: "code = '0500'");
      expect(rows.single['designation'], 'X');
      final cols = await db.rawQuery('PRAGMA table_info(library_items)');
      expect(
        cols.map((c) => c['name']),
        containsAll(['status', 'code_type', 'barcode', 'row_version']),
      );
      // The backfill ran for this existing title (quantite 1 -> one copy).
      expect(
        await db.query('item_copies', where: "item_code = '0500'"),
        hasLength(1),
      );
      await db.close();
    },
  );

  test(
    're-seeding an already-populated code_definitions does not abort',
    () async {
      // v4 seeds default code prefixes; a partial install already holding one
      // must not make the plain insert abort the migration on a PK collision.
      final old = await createLegacy(3, (db) async {
        await db.execute('''CREATE TABLE library_items(
        code TEXT PRIMARY KEY, designation TEXT, quantite INTEGER,
        emplacement TEXT, taux REAL, emplacement_stock TEXT,
        status TEXT, code_type TEXT)''');
        await db.execute(
          'CREATE TABLE code_definitions(prefix TEXT PRIMARY KEY, label TEXT)',
        );
        await db.insert('code_definitions', {
          'prefix': 'LIV',
          'label': 'Livre',
        });
      });
      await old.close();

      final db = await svc.openDatabaseAt(path);
      expect(await db.getVersion(), DatabaseService.currentSchemaVersion);
      final defs = await db.query('code_definitions');
      expect(
        defs.map((r) => r['prefix']),
        containsAll(['LIV', 'REV', 'THE', 'MEM', 'PER', 'DOC']),
      );
      expect(defs.where((r) => r['prefix'] == 'LIV'), hasLength(1));
      await db.close();
    },
  );

  // BL-05 (migration leg): the v22 step makes copy state authoritative for
  // every title's status WITHOUT breaking existing data. We build a fully-migrated
  // current database, inject the PRE-migration state (a legacy copy-less loan,
  // a promoted hold, an orphan imported status, a correct multi-copy title),
  // then downgrade the recorded version to 21 and reopen so ONLY the v22 step
  // runs. Nothing loan-backed may wrongly flip to 'Disponible'; an orphan value
  // the rollup can never produce heals to its honest derived status; and the
  // one-time migration must not churn every row's concurrency token.
  test('v21 -> v22 reconciles title status from copies/loans/holds without '
      'data loss', () async {
    // 1. Open a fresh current schema (empty), seed the pre-v22 world, pin to 21.
    final seeded = await svc.openDatabaseAt(path);

    // (a) Legacy copy-LESS active loan: title says 'Disponible' (a lie), owns no
    //     copies, one active loan that only names the title (copy_id NULL).
    await seeded.insert('library_items', {
      'code': 'L1',
      'designation': 'Legacy Loan',
      'quantite': 1,
      'status': 'Disponible',
      'row_version': 0,
    });
    await seeded.insert('loans', {
      'item_code': 'L1',
      'member_id': '250001',
      'member_name': 'Alice',
      'loan_date': '2025-01-01T00:00:00.000',
      'due_date': '2025-01-16T00:00:00.000',
      'status': 'Active',
    });

    // (b) Promoted hold bound to a physical copy: title 'Disponible', one
    //     available copy, a reservation in the 'available' (promoted) state.
    await seeded.insert('library_items', {
      'code': 'R1',
      'designation': 'Promoted Copy',
      'quantite': 1,
      'status': 'Disponible',
      'row_version': 0,
    });
    final r1Copy = await seeded.insert('item_copies', {
      'item_code': 'R1',
      'state': 'Disponible',
    });
    await seeded.insert('reservations', {
      'item_code': 'R1',
      'member_id': '250002',
      'copy_id': r1Copy,
      'status': 'available',
    });

    // (c) Promoted hold naming only the title (copy_id NULL).
    await seeded.insert('library_items', {
      'code': 'R2',
      'designation': 'Promoted Item',
      'quantite': 1,
      'status': 'Disponible',
      'row_version': 0,
    });
    await seeded.insert('item_copies', {
      'item_code': 'R2',
      'state': 'Disponible',
    });
    await seeded.insert('reservations', {
      'item_code': 'R2',
      'member_id': '250003',
      'status': 'available',
    });

    // (d) Imported orphan status no rollup can produce ('Endommagé'); its two
    //     copies are both physically present, so the honest answer is 'Disponible'.
    await seeded.insert('library_items', {
      'code': 'I1',
      'designation': 'Imported Orphan',
      'quantite': 2,
      'status': 'Endommagé',
      'row_version': 0,
    });
    await seeded.insert('item_copies', {
      'item_code': 'I1',
      'state': 'Disponible',
    });
    await seeded.insert('item_copies', {
      'item_code': 'I1',
      'state': 'Disponible',
    });

    // (e) Already-correct multi-copy title: 1 out + 2 on shelf -> 'Disponible'.
    //     row_version is deliberately high to prove the migration preserves it.
    await seeded.insert('library_items', {
      'code': 'C1',
      'designation': 'Mixed',
      'quantite': 3,
      'status': 'Disponible',
      'row_version': 7,
    });
    final c1Out = await seeded.insert('item_copies', {
      'item_code': 'C1',
      'state': 'Emprunté',
    });
    await seeded.insert('item_copies', {
      'item_code': 'C1',
      'state': 'Disponible',
    });
    await seeded.insert('item_copies', {
      'item_code': 'C1',
      'state': 'Disponible',
    });
    await seeded.insert('loans', {
      'item_code': 'C1',
      'copy_id': c1Out,
      'member_id': '250009',
      'loan_date': '2025-02-01T00:00:00.000',
      'due_date': '2025-02-16T00:00:00.000',
      'status': 'Active',
    });

    // Pin the recorded version back to 21 so the reopen re-runs the v22 step.
    await seeded.setVersion(21);
    await seeded.close();

    // 2. Reopen through the PRODUCTION path -> runs _reconcileStatusesFromCopies.
    final db = await svc.openDatabaseAt(path);
    expect(await db.getVersion(), DatabaseService.currentSchemaVersion);

    Future<String?> status(String code) async {
      final r = await db.query(
        'library_items',
        columns: ['status'],
        where: 'code = ?',
        whereArgs: [code],
        limit: 1,
      );
      return r.isEmpty ? null : r.first['status'] as String?;
    }

    // (a) A real loan keeps the title Emprunté and gains a physical on-loan copy.
    expect(
      await status('L1'),
      'Emprunté',
      reason: 'a copy-less active loan must not flip the title to Disponible',
    );
    final l1Copies = await db.query('item_copies', where: "item_code = 'L1'");
    expect(l1Copies, hasLength(1));
    expect(l1Copies.single['state'], 'Emprunté');

    // (b) + (c) A promoted hold makes the title Reserve.
    expect(await status('R1'), 'Réservé');
    expect(await status('R2'), 'Réservé');

    // (d) The orphan 'Endommagé' heals to the honest rollup of its copies.
    expect(await status('I1'), 'Disponible');

    // (e) A correct multi-copy title is unchanged and its copies are intact.
    expect(await status('C1'), 'Disponible');
    expect(
      await db.query('item_copies', where: "item_code = 'C1'"),
      hasLength(3),
    );

    // The one-time migration must NOT bump row_version (would invalidate every
    // client's optimistic-concurrency token).
    final c1Row = await db.query(
      'library_items',
      columns: ['row_version'],
      where: "code = 'C1'",
      limit: 1,
    );
    expect(
      c1Row.single['row_version'],
      7,
      reason: 'migration must preserve the concurrency token',
    );

    // 3. Idempotency: re-running the step derives the same states.
    await db.setVersion(21);
    await db.close();
    final db2 = await svc.openDatabaseAt(path);
    Future<String?> status2(String code) async {
      final r = await db2.query(
        'library_items',
        columns: ['status'],
        where: 'code = ?',
        whereArgs: [code],
        limit: 1,
      );
      return r.isEmpty ? null : r.first['status'] as String?;
    }

    expect(await status2('L1'), 'Emprunté');
    expect(await status2('R1'), 'Réservé');
    expect(await status2('R2'), 'Réservé');
    expect(await status2('I1'), 'Disponible');
    expect(await status2('C1'), 'Disponible');
    // Copies were not duplicated by the second pass.
    expect(
      await db2.query('item_copies', where: "item_code = 'L1'"),
      hasLength(1),
    );
    await db2.close();
  });
}

Future<int> fkEnabled(Database db) async {
  final rows = await db.rawQuery('PRAGMA foreign_keys');
  return rows.first.values.first as int;
}

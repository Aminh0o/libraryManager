import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/domain/loan_transitions.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/models/loan.dart';
import 'package:library_manager/models/item_copy.dart';
import 'package:library_manager/services/database_service.dart';

/// Phase 5 / TX-01: a mutation and its `db_version` sync marker must be ONE
/// atomic transaction — never committed data with a stale version (which would
/// strand LAN clients polling an old `db_version`). Uses the real
/// DatabaseService against an in-memory database, forcing the version stamp to
/// fail (via the `debugBeforeVersionStamp` seam) to prove the data change rolls
/// back with it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final now = DateTime(2026, 1, 1, 12);
  late Database db;
  late DatabaseService svc;

  LibraryItem item(String code) => LibraryItem(
    code: code,
    codeType: 'LIV',
    designation: 'Designation $code',
    quantite: 1,
    emplacement: 'A',
    taux: 10,
    emplacementStock: 'S',
    status: 'Disponible',
  );

  Loan loanFor(String code) => LoanTransitions.checkOut(
    itemCode: code,
    memberId: '250001',
    memberName: 'Alice',
    itemTitle: 'Designation $code',
    now: now,
  );

  Future<void> seedItem(LibraryItem i) async =>
      db.insert('library_items', i.toMap());

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE library_items(
        code TEXT PRIMARY KEY, barcode TEXT, code_type TEXT,
        designation TEXT, quantite INTEGER, emplacement TEXT,
        taux REAL, emplacement_stock TEXT, status TEXT DEFAULT 'Disponible',
        row_version INTEGER NOT NULL DEFAULT 0)
    ''');
    await db.execute('''
      CREATE TABLE loans(
        id INTEGER PRIMARY KEY AUTOINCREMENT, item_code TEXT, copy_id INTEGER,
        member_id TEXT, member_name TEXT, item_title TEXT, loan_date TEXT,
        due_date TEXT, return_date TEXT, status TEXT)
    ''');
    await db.execute('CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT)');
    await db.execute('''
      CREATE TABLE item_copies(
        id INTEGER PRIMARY KEY AUTOINCREMENT, item_code TEXT NOT NULL,
        barcode TEXT, state TEXT NOT NULL DEFAULT 'Disponible',
        note TEXT, acquired_at TEXT)
    ''');
    await db.execute(
      'CREATE TABLE history(id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT, operation TEXT, details TEXT, user TEXT)',
    );
    await db.execute(
      'CREATE TABLE members(member_id TEXT PRIMARY KEY, name TEXT)',
    );
    // Phase 10.3: a checkout/return now also touches the hold queue, so the
    // reservations table a real v21 database always has must exist here too.
    await db.execute('''
          CREATE TABLE reservations(
            id INTEGER PRIMARY KEY AUTOINCREMENT, item_code TEXT NOT NULL,
            member_id TEXT NOT NULL, copy_id INTEGER, status TEXT NOT NULL,
            created_at TEXT, available_at TEXT, available_until TEXT,
            ended_at TEXT, note TEXT, rank INTEGER)
        ''');
    DatabaseService.useDatabaseForTesting(db);
    svc = DatabaseService();
  });

  tearDown(() async {
    svc.debugBeforeVersionStamp = null;
    await db.close();
  });

  test('a committed mutation advances the sync version', () async {
    final v0 = await svc.getDbVersion();
    await svc.addItem(item('5003'));
    expect(await svc.getDbVersion(), isNot(v0));
  });

  test(
    'a failed version stamp rolls back the mutation (data + version atomic)',
    () async {
      await seedItem(item('5002'));
      final v0 = await svc.getDbVersion();

      svc.debugBeforeVersionStamp = (txn) async => throw StateError('boom');
      await expectLater(svc.addItem(item('5099')), throwsA(isA<StateError>()));
      svc.debugBeforeVersionStamp = null;

      // The item was inserted inside the same transaction -> rolled back.
      expect(await db.query('library_items', where: "code = '5099'"), isEmpty);
      // And the version never advanced: no mutated-but-stale database.
      expect(await svc.getDbVersion(), v0);
    },
  );

  test(
    'a failed version stamp rolls back a checkout (copy stays available)',
    () async {
      await seedItem(item('5001'));
      final id = await svc.addCopy(ItemCopy(itemCode: '5001'));
      final v0 = await svc.getDbVersion();

      svc.debugBeforeVersionStamp = (txn) async => throw StateError('boom');
      await expectLater(
        svc.addLoan(loanFor('5001').copyWith(copyId: id)),
        throwsA(isA<StateError>()),
      );
      svc.debugBeforeVersionStamp = null;

      // The copy claim is part of the same transaction -> reverted to available.
      final copy = await db.query(
        'item_copies',
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(copy.first['state'], 'Disponible');
      // No loan row persisted, title status untouched, version unchanged.
      expect(await db.query('loans'), isEmpty);
      expect(await svc.getDbVersion(), v0);
    },
  );

  // ---- Phase 5 / 5.2: mutation + audit + version are ONE transaction ------

  Map<String, dynamic> auditFor(String op) => {
    'timestamp': now.toIso8601String(),
    'operation': op,
    'details': 'd-$op',
    'user': 'test',
  };

  test('a mutation writes its audit row in the same commit', () async {
    await svc.addItem(item('5100'), audit: auditFor('ADD'));
    expect(
      await db.query('library_items', where: "code = '5100'"),
      hasLength(1),
    );
    expect(await db.query('history', where: "operation = 'ADD'"), hasLength(1));
  });

  test(
    'a failing audit write rolls back the mutation (audit+data atomic)',
    () async {
      final v0 = await svc.getDbVersion();
      // `bogus` is not a column of `history` -> the audit insert throws.
      final badAudit = {...auditFor('ADD'), 'bogus': 1};
      await expectLater(
        svc.addItem(item('5101'), audit: badAudit),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.query('library_items', where: "code = '5101'"), isEmpty);
      expect(await db.query('history'), isEmpty);
      expect(await svc.getDbVersion(), v0);
    },
  );

  test(
    'a failing version stamp rolls back the audit row too (all three atomic)',
    () async {
      final v0 = await svc.getDbVersion();
      svc.debugBeforeVersionStamp = (txn) async => throw StateError('boom');
      await expectLater(
        svc.addItem(item('5102'), audit: auditFor('ADD')),
        throwsA(isA<StateError>()),
      );
      svc.debugBeforeVersionStamp = null;
      expect(await db.query('library_items', where: "code = '5102'"), isEmpty);
      expect(await db.query('history'), isEmpty); // audit rolled back with data
      expect(await svc.getDbVersion(), v0);
    },
  );
}

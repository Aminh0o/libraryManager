import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/domain/loan_transitions.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/models/loan.dart';
import 'package:library_manager/models/item_copy.dart';
import 'package:library_manager/services/database_service.dart';

/// Exercises the SERVER-side loan rules (FB-01, BL-02, availability) against a
/// real in-memory SQLite database using the production DatabaseService, proving
/// the guards cannot be bypassed by any client.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final now = DateTime(2026, 1, 1, 12);
  late Database db;
  late DatabaseService svc;

  Future<void> seedItem(LibraryItem item) async {
    await db.insert('library_items', item.toMap());
  }

  LibraryItem item(String code, {String status = 'Disponible'}) => LibraryItem(
        code: code,
        codeType: 'LIV',
        designation: 'Designation $code',
        quantite: 1,
        emplacement: 'A',
        taux: 10,
        emplacementStock: 'S',
        status: status,
      );

  Loan loanFor(String code) => LoanTransitions.checkOut(
        itemCode: code,
        memberId: '250001',
        memberName: 'Alice',
        itemTitle: 'Designation $code',
        now: now,
      );

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
        'CREATE TABLE members(member_id TEXT PRIMARY KEY, name TEXT)');
    // Phase 10.3: every borrow/return now touches the hold queue (walk-up
    // guards inside the txn + a post-commit promotion sweep), so the
    // reservations table is part of the schema a real v21 database always has.
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
    await db.close();
  });

  test('checkout succeeds and marks the item Emprunté', () async {
    await seedItem(item('0001'));
    await svc.addLoan(loanFor('0001'));

    final loaded = await db.query('library_items', where: "code = '0001'");
    expect(loaded.first['status'], 'Emprunté');
    final loans = await svc.getLoans(activeOnly: true);
    expect(loans, hasLength(1));
    expect(loans.first.isActive, isTrue);
  });

  test('FB-01: a second active loan for the same item is rejected', () async {
    await seedItem(item('0002'));
    await svc.addLoan(loanFor('0002'));
    expect(() => svc.addLoan(loanFor('0002')), throwsA(isA<Exception>()));
  });

  test('cannot lend a non-existent item', () async {
    expect(() => svc.addLoan(loanFor('missing')), throwsA(isA<Exception>()));
  });

  test('cannot lend an item that is not available (status preserved)', () async {
    await seedItem(item('0003', status: 'Archivé'));
    expect(() => svc.addLoan(loanFor('0003')), throwsA(isA<Exception>()));
    final loaded = await db.query('library_items', where: "code = '0003'");
    expect(loaded.first['status'], 'Archivé',
        reason: 'a rejected loan must not clobber a custom status');
  });

  test('checkout -> return restores availability', () async {
    await seedItem(item('0004'));
    await svc.addLoan(loanFor('0004'));
    final active = (await svc.getLoans(activeOnly: true)).first;

    await svc.updateLoan(LoanTransitions.returnLoan(active, when: now.add(const Duration(days: 2))));

    final loaded = await db.query('library_items', where: "code = '0004'");
    expect(loaded.first['status'], 'Disponible');
    expect(await svc.getLoans(activeOnly: true), isEmpty);
  });

  test('BL-02: reactivating a returned loan via updateLoan is rejected', () async {
    await seedItem(item('0005'));
    await svc.addLoan(loanFor('0005'));
    final active = (await svc.getLoans(activeOnly: true)).first;
    final returned = LoanTransitions.returnLoan(active, when: now);
    await svc.updateLoan(returned);

    final resurrect = returned.copyWith(status: 'Active', returnDate: null);
    expect(() => svc.updateLoan(resurrect), throwsA(isA<Exception>()),
        reason: 'server must refuse to reactivate a returned loan');
  });

  test('updateLoan on an unknown loan id is rejected', () async {
    final ghost = loanFor('0006').copyWith(id: 9999);
    expect(() => svc.updateLoan(ghost), throwsA(isA<Exception>()));
  });

  group('copy-level circulation (DB-02)', () {
    // These use real physical copies (added via svc.addCopy), which switches
    // the server onto the copy-level path.
    Future<List<int>> addCopies(String code, int n) async {
      final ids = <int>[];
      for (var i = 0; i < n; i++) {
        ids.add(await svc.addCopy(ItemCopy(itemCode: code)));
      }
      return ids;
    }

    Future<String> statusOf(String code) async {
      final r = await db.query('library_items', where: 'code = ?', whereArgs: [code]);
      return r.first['status'] as String;
    }

    test('a multi-copy title supports multiple concurrent loans', () async {
      await seedItem(item('1001'));
      final ids = await addCopies('1001', 2);

      await svc.addLoan(loanFor('1001').copyWith(copyId: ids[0]));
      // One of two still available -> title remains lendable.
      expect(await statusOf('1001'), 'Disponible');

      await svc.addLoan(loanFor('1001').copyWith(copyId: ids[1]));
      expect(await statusOf('1001'), 'Emprunté');
      expect(await svc.getLoans(activeOnly: true), hasLength(2));
    });

    test('returning one copy leaves the other copy loan intact', () async {
      await seedItem(item('1002'));
      final ids = await addCopies('1002', 2);
      await svc.addLoan(loanFor('1002').copyWith(copyId: ids[0]));
      await svc.addLoan(loanFor('1002').copyWith(copyId: ids[1]));
      expect(await svc.getLoans(activeOnly: true), hasLength(2));

      final firstOut = (await svc.getLoans(activeOnly: true))
          .firstWhere((l) => l.copyId == ids[0]);
      await svc.updateLoan(LoanTransitions.returnLoan(firstOut, when: now));

      // The other copy is STILL on loan — a per-copy return must not resurrect
      // or erase it (the historical bug marked the whole title available).
      expect(await svc.getLoans(activeOnly: true), hasLength(1));
      final copies = await svc.getCopies('1002');
      expect(copies.firstWhere((c) => c.id == ids[1]).isOnLoan, isTrue);
      expect(copies.firstWhere((c) => c.id == ids[0]).isAvailable, isTrue);
      // One copy is back on the shelf, so the title is lendable again.
      expect(await statusOf('1002'), 'Disponible');

      final secondOut = (await svc.getLoans(activeOnly: true)).single;
      await svc.updateLoan(LoanTransitions.returnLoan(secondOut, when: now));
      expect(await svc.getLoans(activeOnly: true), isEmpty);
      expect(await statusOf('1002'), 'Disponible');
    });

    test('the same copy can never be checked out twice', () async {
      await seedItem(item('1003'));
      final ids = await addCopies('1003', 1);
      await svc.addLoan(loanFor('1003').copyWith(copyId: ids[0]));
      expect(
        () => svc.addLoan(loanFor('1003').copyWith(copyId: ids[0])),
        throwsA(isA<Exception>()),
        reason: 'the only copy is already on loan',
      );
    });

    test('auto-pick refuses when no copy is available', () async {
      await seedItem(item('1004'));
      await addCopies('1004', 1);
      await svc.addLoan(loanFor('1004')); // server picks the lone copy
      expect(
        () => svc.addLoan(loanFor('1004')), // no copyId -> must find available
        throwsA(isA<Exception>()),
      );
    });

    test('an unknown copy id is rejected', () async {
      await seedItem(item('1005'));
      await addCopies('1005', 1);
      expect(
        () => svc.addLoan(loanFor('1005').copyWith(copyId: 999)),
        throwsA(isA<Exception>()),
      );
    });

    test('addItem seeds one copy per declared quantity', () async {
      await svc.addItem(LibraryItem(
        code: '1006',
        codeType: 'LIV',
        designation: 'Seeded',
        quantite: 3,
        emplacement: 'A',
        taux: 10,
        emplacementStock: 'S',
      ));
      final copies = await svc.getCopies('1006');
      expect(copies, hasLength(3));
      expect(copies.every((c) => c.isAvailable), isTrue);
    });

    test('shrinking quantity never removes an on-loan copy', () async {
      await svc.addItem(LibraryItem(
        code: '1007',
        codeType: 'LIV',
        designation: 'Reconcile',
        quantite: 3,
        emplacement: 'A',
        taux: 10,
        emplacementStock: 'S',
      ));
      final copies = await svc.getCopies('1007');
      await svc.addLoan(loanFor('1007').copyWith(copyId: copies.first.id));

      // Request to shrink to 1 copy, but 1 is on loan => keep at least that.
      await svc.updateItem(LibraryItem(
        code: '1007',
        codeType: 'LIV',
        designation: 'Reconcile',
        quantite: 1,
        emplacement: 'A',
        taux: 10,
        emplacementStock: 'S',
      ));
      final after = await svc.getCopies('1007');
      expect(after.where((c) => c.isOnLoan), hasLength(1),
          reason: 'an on-loan copy cannot be discarded');
    });

    test('concurrent auto-pick checkouts never exceed the copy count (BL-01)',
        () async {
      await seedItem(item('3001'));
      await addCopies('3001', 2); // only 2 physical copies

      // Fire 5 simultaneous checkouts for the same title (server auto-picks a
      // copy each). Exactly 2 may win; the rest must be refused.
      final results = await Future.wait(List.generate(
        5,
        (_) => svc
            .addLoan(loanFor('3001'))
            .then((_) => true)
            .catchError((_) => false),
      ));

      expect(results.where((r) => r).length, 2,
          reason: 'no more copies than physically exist can be lent');
      final copies = await svc.getCopies('3001');
      expect(copies.where((c) => c.isOnLoan), hasLength(2));
      expect(copies.where((c) => c.isAvailable), isEmpty);
      expect(await svc.getLoans(activeOnly: true), hasLength(2));
      // Each loan is bound to a distinct copy (no double-booked physical item).
      final loanedCopyIds =
          (await svc.getLoans(activeOnly: true)).map((l) => l.copyId).toSet();
      expect(loanedCopyIds, hasLength(2));
      expect(await statusOf('3001'), 'Emprunté');
    });

    test('concurrent legacy per-title checkouts allow exactly one loan (BL-01)',
        () async {
      await seedItem(item('3002')); // no copies -> legacy per-title path

      final results = await Future.wait(List.generate(
        5,
        (_) => svc
            .addLoan(loanFor('3002'))
            .then((_) => true)
            .catchError((_) => false),
      ));

      expect(results.where((r) => r).length, 1,
          reason: 'the status compare-and-swap lets only one checkout win');
      expect(await svc.getLoans(activeOnly: true), hasLength(1));
      expect(await statusOf('3002'), 'Emprunté');
    });
  });

  group('scan-to-return resolution (BL-03)', () {
    Future<void> seedWithIsbn(String code, String isbn) async {
      await seedItem(item(code));
      await db.update('library_items', {'barcode': isbn},
          where: 'code = ?', whereArgs: [code]);
    }

    test('resolves by item code, title ISBN, and per-copy barcode', () async {
      await seedWithIsbn('2001', 'ISBN-2001');
      final idA = await svc.addCopy(ItemCopy(itemCode: '2001', barcode: 'COPY-A'));
      final idB = await svc.addCopy(ItemCopy(itemCode: '2001', barcode: 'COPY-B'));
      await svc.addLoan(loanFor('2001').copyWith(copyId: idA));
      await svc.addLoan(loanFor('2001').copyWith(copyId: idB));

      // Per-copy barcode identifies the EXACT copy's loan (most specific).
      final byCopy = await svc.findActiveLoanByScan('COPY-A');
      expect(byCopy, isNotNull);
      expect(byCopy!.copyId, idA);

      // A shared ISBN resolves to an active loan of that title.
      final byIsbn = await svc.findActiveLoanByScan('ISBN-2001');
      expect(byIsbn, isNotNull);
      expect(byIsbn!.itemCode, '2001');

      // The raw item code still works.
      final byCode = await svc.findActiveLoanByScan('2001');
      expect(byCode, isNotNull);
      expect(byCode!.itemCode, '2001');
    });

    test('returns null for an unknown code or a fully-returned title', () async {
      await seedWithIsbn('2002', 'ISBN-2002');
      final id = await svc.addCopy(ItemCopy(itemCode: '2002'));
      final loan = await svc.findActiveLoanByScan('nope');
      expect(loan, isNull);

      await svc.addLoan(loanFor('2002').copyWith(copyId: id));
      final active = (await svc.getLoans(activeOnly: true))
          .firstWhere((l) => l.copyId == id);
      await svc.updateLoan(LoanTransitions.returnLoan(active, when: now));
      // No active loan remains -> null.
      expect(await svc.findActiveLoanByScan('ISBN-2002'), isNull);
    });
  });

  group('referential delete guards (BL-04)', () {
    Future<void> returnAllLoansOf(String code) async {
      for (final l in await svc.getLoans(activeOnly: true)) {
        if (l.itemCode == code) {
          await svc.updateLoan(LoanTransitions.returnLoan(l, when: now));
        }
      }
    }

    test('deleting an item with a legacy active loan is blocked, then allowed',
        () async {
      await seedItem(item('4001'));
      await svc.addLoan(loanFor('4001')); // no copies -> legacy active loan

      await expectLater(svc.deleteItem('4001'),
          throwsA(isA<ActiveLoanConflictException>()));
      expect(await db.query('library_items', where: "code = '4001'"),
          hasLength(1)); // item preserved, not deleted

      await returnAllLoansOf('4001');
      await svc.deleteItem('4001'); // now permitted
      expect(await db.query('library_items', where: "code = '4001'"), isEmpty);
    });

    test('deleting an item whose copy is on loan is blocked', () async {
      await seedItem(item('4002'));
      final id = await svc.addCopy(ItemCopy(itemCode: '4002'));
      await svc.addLoan(loanFor('4002').copyWith(copyId: id));

      await expectLater(svc.deleteItem('4002'),
          throwsA(isA<ActiveLoanConflictException>()));
      expect(
          await db.query('item_copies', where: "item_code = '4002'"),
          hasLength(1)); // copies untouched while on loan

      await returnAllLoansOf('4002');
      await svc.deleteItem('4002');
      expect(await db.query('library_items', where: "code = '4002'"), isEmpty);
      expect(await db.query('item_copies', where: "item_code = '4002'"),
          isEmpty); // copies cleaned with the item
    });

    test('deleting a member with an active loan is blocked, then allowed',
        () async {
      await db.insert('members', {'member_id': '250001', 'name': 'Alice'});
      await seedItem(item('4003'));
      await svc.addLoan(loanFor('4003')); // memberId = 250001

      await expectLater(svc.deleteMember('250001'),
          throwsA(isA<ActiveLoanConflictException>()));
      expect(await db.query('members', where: "member_id = '250001'"),
          hasLength(1));

      await returnAllLoansOf('4003');
      await svc.deleteMember('250001');
      expect(await db.query('members', where: "member_id = '250001'"), isEmpty);
    });

    test('an item / member with no loans deletes normally', () async {
      await seedItem(item('4004'));
      await db.insert('members', {'member_id': 'M-9', 'name': 'Bob'});
      await svc.deleteItem('4004');
      await svc.deleteMember('M-9');
      expect(await db.query('library_items', where: "code = '4004'"), isEmpty);
      expect(await db.query('members', where: "member_id = 'M-9'"), isEmpty);
    });
  });
}

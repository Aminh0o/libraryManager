import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/models/item_copy.dart';
import 'package:library_manager/models/report.dart';
import 'package:library_manager/services/database_service.dart';

/// Phase 10.4 -- the SERVER-side report engine, run against a real in-memory
/// SQLite database through the production [DatabaseService]. This proves the
/// numbers a client merely displays are computed correctly at the source: date
/// windows slice by CALENDAR DAY (time-of-day ignored), overdue is derived from
/// the canonical active status + due date, inventory counts physical copies via
/// the join, fines separate assessed / collected / waived / outstanding, and
/// the top-borrower ranking is real -- none of it can be faked by a caller.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late DatabaseService svc;

  Future<void> seedItem(String code, {String type = 'LIV', int copies = 0}) async {
    await db.insert('library_items', {
      'code': code,
      'code_type': type,
      'designation': 'Desig $code',
      'quantite': copies,
      'emplacement': 'A',
      'taux': 10,
      'emplacement_stock': 'S',
      'status': 'Disponible',
    });
    for (var i = 0; i < copies; i++) {
      await db.insert('item_copies', {
        'item_code': code,
        'state': CopyState.available.storage,
      });
    }
  }

  Future<void> seedLoan({
    required String member,
    String? memberName,
    String item = 'B1',
    String? loanDate,
    String? dueDate,
    String? returnDate,
    String status = 'Active',
  }) =>
      db.insert('loans', {
        'item_code': item,
        'member_id': member,
        'member_name': memberName ?? member,
        'item_title': 'Title $item',
        'loan_date': loanDate,
        'due_date': dueDate ?? '2999-01-01T00:00:00.000',
        'return_date': returnDate,
        'status': status,
      });

  Future<void> seedFine({
    required double amount,
    required String status,
    required String createdAt,
    String? resolvedAt,
  }) =>
      db.insert('fines', {
        'member_id': 'M-1',
        'amount': amount,
        'status': status,
        'reason': 'Overdue',
        'created_at': createdAt,
        'resolved_at': resolvedAt,
      });

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
    await db.execute('''
      CREATE TABLE members(
        id INTEGER PRIMARY KEY AUTOINCREMENT, member_id TEXT UNIQUE, name TEXT)
    ''');
    await db.execute('''
      CREATE TABLE fines(
        id INTEGER PRIMARY KEY AUTOINCREMENT, loan_id INTEGER,
        member_id TEXT NOT NULL, amount REAL NOT NULL, status TEXT NOT NULL,
        reason TEXT, created_at TEXT, resolved_at TEXT, resolved_by TEXT)
    ''');
    await db.execute('''
      CREATE TABLE history(
        id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT, operation TEXT,
        details TEXT, user TEXT)
    ''');
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

  String? cell(Report r, int row, int col) =>
      row < r.rows.length && col < r.columns.length ? r.rows[row][col] : null;

  group('circulation report', () {
    test('counts borrowed vs returned per calendar day within the window',
        () async {
      await seedLoan(member: 'M-1', loanDate: '2026-09-01T09:00:00.000');
      await seedLoan(member: 'M-2', loanDate: '2026-09-01T18:00:00.000');
      await seedLoan(
        member: 'M-3',
        loanDate: '2026-09-02T09:00:00.000',
        returnDate: '2026-09-03T09:00:00.000',
        status: 'Returned',
      );
      // Out of window (earlier) — must be excluded.
      await seedLoan(member: 'M-9', loanDate: '2026-08-01T09:00:00.000');

      final r = await svc.generateReport(
        ReportKind.circulation,
        from: '2026-09-01',
        to: '2026-09-30',
      );
      expect(r.kind, ReportKind.circulation);
      expect(r.from, '2026-09-01');
      expect(r.to, '2026-09-30');
      expect(r.columns, ['Date', 'Borrowed', 'Returned']);
      expect(cell(r, 0, 0), '2026-09-01');
      expect(cell(r, 0, 1), '2'); // two borrowed that day, time-of-day ignored
      expect(cell(r, 1, 0), '2026-09-02');
      expect(cell(r, 1, 1), '1');
      expect(cell(r, 2, 0), '2026-09-03');
      expect(cell(r, 2, 2), '1'); // the return shows on its own day
      expect(r.summary['Borrowed'], '3');
      expect(r.summary['Returned'], '1');
    });

    test('a reversed window is refused at the source (host path)', () async {
      await expectLater(
        svc.generateReport(
          ReportKind.circulation,
          from: '2026-09-10',
          to: '2026-09-01',
        ),
        throwsFormatException,
      );
    });
  });

  group('overdue report', () {
    test('lists only ACTIVE loans past their due date, with days overdue',
        () async {
      await seedLoan(
        member: 'Late',
        memberName: 'Late Borrower',
        dueDate: '2020-01-01T00:00:00.000',
        loanDate: '2019-12-01T00:00:00.000',
      );
      // Active but due far in the future — never overdue.
      await seedLoan(member: 'Early', dueDate: '2999-01-01T00:00:00.000');
      // Returned late — no longer outstanding, so not on the overdue shelf.
      await seedLoan(
        member: 'Returned',
        dueDate: '2020-01-01T00:00:00.000',
        returnDate: '2020-02-01T00:00:00.000',
        status: 'Returned',
      );

      final r = await svc.generateReport(ReportKind.overdue);
      expect(r.rows, hasLength(1));
      expect(r.rows.single[0], 'Late Borrower');
      expect(int.parse(r.rows.single[3]), greaterThan(0));
      expect(r.summary['Overdue loans'], '1');
    });

    test('ignores a malformed window because it is not a windowed report',
        () async {
      // Windowless kinds never touch from/to, so a garbage date is harmless.
      final r = await svc.generateReport(
        ReportKind.overdue,
        from: 'not-a-date',
        to: 'also-bad',
      );
      expect(r.kind, ReportKind.overdue);
      expect(r.from, isNull);
      expect(r.to, isNull);
    });
  });

  group('inventory report', () {
    test('counts titles and physical copies per type', () async {
      await seedItem('B1', copies: 3);
      await seedItem('B2', copies: 0);
      await seedItem('R1', type: 'REV', copies: 1);

      final r = await svc.generateReport(ReportKind.inventory);
      expect(r.columns, ['Type', 'Titles', 'Copies']);
      final byType = {for (final row in r.rows) row[0]: row};
      expect(byType['LIV']![1], '2'); // B1 + B2
      expect(byType['LIV']![2], '3'); // three copies
      expect(byType['REV']![1], '1');
      expect(byType['REV']![2], '1');
      expect(r.summary['Titles'], '3');
      expect(r.summary['Physical copies'], '4');
    });
  });

  group('fines report', () {
    test('separates assessed / collected / waived / outstanding by money',
        () async {
      await seedFine(
          amount: 5.0, status: 'pending', createdAt: '2026-09-05T00:00:00.000');
      await seedFine(
        amount: 3.0,
        status: 'paid',
        createdAt: '2026-09-01T00:00:00.000',
        resolvedAt: '2026-09-06T00:00:00.000',
      );
      await seedFine(
        amount: 2.0,
        status: 'waived',
        createdAt: '2026-09-02T00:00:00.000',
        resolvedAt: '2026-09-07T00:00:00.000',
      );
      // Assessed OUT of window — must not count toward the window's assessed.
      await seedFine(
          amount: 99.0, status: 'pending', createdAt: '2025-01-01T00:00:00.000');

      final r = await svc.generateReport(
        ReportKind.fines,
        from: '2026-09-01',
        to: '2026-09-30',
      );
      final metric = {for (final row in r.rows) row[0]: row};
      expect(metric['Assessed']![1], '3'); // the three in-window fines
      expect(metric['Assessed']![2], '10.00 DZD');
      expect(metric['Collected']![1], '1');
      expect(metric['Collected']![2], '3.00 DZD');
      expect(metric['Waived']![2], '2.00 DZD');
      // Outstanding counts every still-pending fine regardless of window.
      expect(metric['Still outstanding']![1], '2');
      expect(metric['Still outstanding']![2], '104.00 DZD');
      expect(r.summary['Currency'], 'DZD');
    });
  });

  group('members report', () {
    test('ranks borrowers by checkouts in the window and reports totals',
        () async {
      for (var i = 0; i < 3; i++) {
        await seedLoan(
          member: 'M-1',
          memberName: 'Alice',
          loanDate: '2026-09-0${i + 1}T00:00:00.000',
        );
      }
      await seedLoan(member: 'M-2', memberName: 'Bob', loanDate: '2026-09-02T00:00:00.000');
      await seedLoan(member: 'M-2', memberName: 'Bob', loanDate: '2025-01-01T00:00:00.000'); // out

      final r = await svc.generateReport(
        ReportKind.members,
        from: '2026-09-01',
        to: '2026-09-30',
      );
      expect(r.columns, ['Rank', 'Member', 'Items borrowed']);
      expect(r.rows.first[1], 'Alice');
      expect(r.rows.first[2], '3');
      expect(r.rows[1][1], 'Bob');
      expect(r.rows[1][2], '1');
      expect(r.summary['Active borrowers'], '2');
      expect(r.summary['Total checkouts'], '4');
    });
  });
}

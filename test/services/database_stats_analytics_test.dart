import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/models/loan.dart';
import 'package:library_manager/services/database_service.dart';

/// Phase 9 (dynamic analytics): the host now derives rolling circulation
/// health inside getStats so a LAN client reads identical numbers over /stats.
/// These tests run the REAL DatabaseService against an in-memory SQLite so the
/// date-window and status predicates are proven, not assumed.
///
/// Dates are seeded as local ISO-8601 strings (exactly what Loan.toMap stores),
/// so the lexicographic compare used in the SQL matches the chronological one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late DatabaseService svc;

  String iso(DateTime t) => t.toIso8601String();

  Future<void> insertLoan({
    required String loanDate,
    String? dueDate,
    String? returnDate,
    required String status,
  }) async {
    await db.insert('loans', {
      'item_code': 'L1',
      'member_id': 'M1',
      'member_name': 'Member',
      'item_title': 'Title',
      'loan_date': loanDate,
      'due_date': dueDate,
      'return_date': returnDate,
      'status': status,
    });
  }

  Future<void> seedItem(String code, {int quantite = 1}) async {
    await db.insert('library_items', {
      'code': code,
      'code_type': 'LIV',
      'designation': 'Title $code',
      'quantite': quantite,
      'emplacement': 'A',
      'taux': 10,
      'emplacement_stock': 'S',
      'status': 'Disponible',
    });
  }

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
      CREATE TABLE item_copies(
        id INTEGER PRIMARY KEY AUTOINCREMENT, item_code TEXT NOT NULL,
        barcode TEXT, state TEXT NOT NULL DEFAULT 'Disponible',
        note TEXT, acquired_at TEXT)
    ''');
    await db.execute('CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT)');
    await db.execute('''
      CREATE TABLE loans(
        id INTEGER PRIMARY KEY AUTOINCREMENT, item_code TEXT, copy_id INTEGER,
        member_id TEXT, member_name TEXT, item_title TEXT, loan_date TEXT,
        due_date TEXT, return_date TEXT, status TEXT)
    ''');
    DatabaseService.useDatabaseForTesting(db);
    svc = DatabaseService();
  });

  tearDown(() async {
    await db.close();
  });

  final now = DateTime.now();

  group('overdueLoans (active past due, derived)', () {
    test('counts only active loans whose due date has passed', () async {
      // Active, due in the past -> overdue.
      await insertLoan(
        loanDate: iso(now.subtract(const Duration(days: 20))),
        dueDate: iso(now.subtract(const Duration(days: 3))),
        status: LoanStatus.active.storage,
      );
      // Active, due in the future -> not overdue.
      await insertLoan(
        loanDate: iso(now.subtract(const Duration(days: 2))),
        dueDate: iso(now.add(const Duration(days: 12))),
        status: LoanStatus.active.storage,
      );
      // Returned late -> no longer counted (status is authoritative).
      await insertLoan(
        loanDate: iso(now.subtract(const Duration(days: 30))),
        dueDate: iso(now.subtract(const Duration(days: 10))),
        returnDate: iso(now.subtract(const Duration(days: 8))),
        status: LoanStatus.returned.storage,
      );
      final stats = await svc.getStats();
      expect(stats['overdueLoans'], 1);
    });

    test('an active loan with no due date is never counted overdue', () async {
      await insertLoan(
        loanDate: iso(now.subtract(const Duration(days: 40))),
        dueDate: null,
        status: LoanStatus.active.storage,
      );
      final stats = await svc.getStats();
      expect(stats['overdueLoans'], 0);
    });
  });

  group('weekBorrows / weekReturns (last 7 days)', () {
    test('counts activity inside the window and excludes older rows', () async {
      // Borrowed 2 days ago -> inside the window.
      await insertLoan(
        loanDate: iso(now.subtract(const Duration(days: 2))),
        dueDate: iso(now.add(const Duration(days: 12))),
        status: LoanStatus.active.storage,
      );
      // Borrowed 30 days ago -> outside the window.
      await insertLoan(
        loanDate: iso(now.subtract(const Duration(days: 30))),
        dueDate: iso(now.subtract(const Duration(days: 16))),
        status: LoanStatus.active.storage,
      );
      // Returned 1 day ago -> counts for both borrow and return windows.
      await insertLoan(
        loanDate: iso(now.subtract(const Duration(days: 5))),
        dueDate: iso(now.subtract(const Duration(days: 1))),
        returnDate: iso(now.subtract(const Duration(days: 1))),
        status: LoanStatus.returned.storage,
      );
      // Returned 20 days ago -> outside the return window.
      await insertLoan(
        loanDate: iso(now.subtract(const Duration(days: 40))),
        dueDate: iso(now.subtract(const Duration(days: 25))),
        returnDate: iso(now.subtract(const Duration(days: 20))),
        status: LoanStatus.returned.storage,
      );
      final stats = await svc.getStats();
      // In-window loans: the 2-day-old active + the 5-day-old returned.
      expect(stats['weekBorrows'], 2);
      // In-window returns: only the one returned a day ago.
      expect(stats['weekReturns'], 1);
    });

    test(
      'a returned loan missing its return date is not counted returned',
      () async {
        await insertLoan(
          loanDate: iso(now.subtract(const Duration(days: 1))),
          dueDate: iso(now.add(const Duration(days: 12))),
          returnDate: null,
          status: LoanStatus.returned.storage,
        );
        final stats = await svc.getStats();
        expect(stats['weekReturns'], 0);
      },
    );
  });

  test(
    'empty loans table yields zeroed analytics alongside real totals',
    () async {
      await seedItem('0500', quantite: 3);
      final stats = await svc.getStats();
      expect(stats['totalQuantity'], 3);
      expect(stats['overdueLoans'], 0);
      expect(stats['weekBorrows'], 0);
      expect(stats['weekReturns'], 0);
    },
  );
}

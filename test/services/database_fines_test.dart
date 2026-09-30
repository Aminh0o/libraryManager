import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/models/fine.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/models/loan.dart';
import 'package:library_manager/services/database_service.dart';

/// Phase 10.2 -- the SERVER-side money rules, run against a real in-memory
/// SQLite database through the production [DatabaseService]. This proves what a
/// client cannot fake: an overdue RETURN accrues a fine atomically, an on-time
/// or disabled-policy return accrues nothing, a settle records the operator and
/// can never be applied twice, and the balance only counts open fines.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

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

  Loan activeLoan(String code, {required DateTime due}) => Loan(
        itemCode: code,
        memberId: '250001',
        memberName: 'Alice',
        itemTitle: 'Designation $code',
        loanDate: due.subtract(const Duration(days: 14)),
        dueDate: due,
        status: 'Active',
      );

  /// Borrow [code], then return it at [returned]; the active loan is refetched
  /// so its persisted id flows into updateLoan exactly as the UI does.
  Future<void> borrowAndReturn(String code,
      {required DateTime due, required DateTime returned}) async {
    await db.insert('library_items', item(code).toMap());
    await svc.addLoan(activeLoan(code, due: due));
    final out = (await svc.getLoans(activeOnly: true)).single;
    await svc.updateLoan(out.copyWith(
      status: 'Returned',
      returnDate: returned,
    ));
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
    // Phase 10.3: a return now also drives the hold queue (post-commit
    // promotion), so the reservations table a real v21 database always has
    // must exist here too.
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

  test('the default fine policy is DISABLED (never retroactively charges)',
      () async {
    final s = await svc.getFineSettings();
    expect(s.ratePerDay, 0);
    expect(s.enabled, isFalse);
  });

  test('a malformed stored rate degrades to the safe disabled default',
      () async {
    await db.insert('metadata', {'key': 'fine_rate_per_day', 'value': 'abc'});
    final s = await svc.getFineSettings();
    expect(s.ratePerDay, 0);
    expect(s.enabled, isFalse);
  });

  test('setFineSettings persists and reads back', () async {
    await svc.setFineSettings(const FineSettings(ratePerDay: 2, currency: 'DZD'));
    final s = await svc.getFineSettings();
    expect(s.ratePerDay, 2);
    expect(s.currency, 'DZD');
    expect(s.enabled, isTrue);
  });

  test('an overdue return accrues ONE pending fine of rate * whole days',
      () async {
    await svc.setFineSettings(const FineSettings(ratePerDay: 2));
    final due = DateTime(2026, 5, 1, 12);
    await borrowAndReturn('0001',
        due: due, returned: due.add(const Duration(days: 3)));

    final fines = await svc.getFines();
    expect(fines, hasLength(1));
    final f = fines.single;
    expect(f.status, FineStatus.pending);
    expect(f.isOpen, isTrue);
    expect(f.amount, closeTo(6.0, 1e-9)); // 3 days * 2
    expect(f.memberId, '250001');
    expect(f.loanId, isNotNull);
    expect(f.reason, 'Overdue 3 days');
  });

  test('an on-time return accrues NOTHING', () async {
    await svc.setFineSettings(const FineSettings(ratePerDay: 2));
    final due = DateTime(2026, 5, 1, 12);
    await borrowAndReturn('0002',
        due: due, returned: due.subtract(const Duration(days: 1)));
    expect(await svc.getFines(), isEmpty);
  });

  test('with the policy disabled, an overdue return accrues NOTHING', () async {
    // rate left at 0 (default).
    final due = DateTime(2026, 5, 1, 12);
    await borrowAndReturn('0003',
        due: due, returned: due.add(const Duration(days: 10)));
    expect(await svc.getFines(), isEmpty);
  });

  test('a settle records the operator and cannot be applied twice', () async {
    await svc.setFineSettings(const FineSettings(ratePerDay: 1));
    final due = DateTime(2026, 5, 1);
    await borrowAndReturn('0004',
        due: due, returned: due.add(const Duration(days: 2)));
    final fine = (await svc.getFines()).single;

    await svc.payFine(fine.id!, operatorName: 'admin');
    final paid = (await svc.getFines()).single;
    expect(paid.status, FineStatus.paid);
    expect(paid.resolvedBy, 'admin');
    expect(paid.resolvedAt, isNotNull);

    // A second settle of the same ledger row is refused, not double-recorded.
    await expectLater(
      svc.payFine(fine.id!, operatorName: 'admin'),
      throwsA(isA<StateError>()),
    );
    expect((await svc.getFines()).single.status, FineStatus.paid);
  });

  test('waive resolves a pending fine and blocks a later pay', () async {
    await svc.setFineSettings(const FineSettings(ratePerDay: 5));
    final due = DateTime(2026, 5, 1);
    await borrowAndReturn('0005',
        due: due, returned: due.add(const Duration(days: 2)));
    final fine = (await svc.getFines()).single;

    await svc.waiveFine(fine.id!, operatorName: 'clerk');
    final waived = (await svc.getFines()).single;
    expect(waived.status, FineStatus.waived);
    expect(waived.resolvedBy, 'clerk');
    await expectLater(
      svc.payFine(fine.id!, operatorName: 'clerk'),
      throwsA(isA<StateError>()),
    );
  });

  test('paying an unknown fine is refused', () async {
    await expectLater(
      svc.payFine(9999, operatorName: 'admin'),
      throwsA(isA<StateError>()),
    );
  });

  test('outstandingBalance sums only pending fines', () async {
    await svc.setFineSettings(const FineSettings(ratePerDay: 2));
    final due = DateTime(2026, 5, 1);
    await borrowAndReturn('0006',
        due: due, returned: due.add(const Duration(days: 3))); // 6
    await borrowAndReturn('0007',
        due: due, returned: due.add(const Duration(days: 2))); // 4

    expect(await svc.outstandingBalance('250001'), closeTo(10.0, 1e-9));

    final open = await svc.getFines(status: FineStatus.pending);
    expect(open, hasLength(2));
    final settled = open.first;
    await svc.payFine(settled.id!, operatorName: 'admin');
    final remaining = open
        .where((f) => f.id != settled.id)
        .fold<double>(0, (s, f) => s + f.amount);
    expect(await svc.outstandingBalance('250001'), closeTo(remaining, 1e-9));
    expect(await svc.outstandingBalance('unknown-member'), 0);
  });

  test('getFines filters by member', () async {
    await svc.setFineSettings(const FineSettings(ratePerDay: 1));
    final due = DateTime(2026, 5, 1);
    await borrowAndReturn('0008',
        due: due, returned: due.add(const Duration(days: 1)));
    expect(await svc.getFines(memberId: '250001'), hasLength(1));
    expect(await svc.getFines(memberId: '999999'), isEmpty);
  });
}

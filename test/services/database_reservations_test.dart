import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/models/item_copy.dart';
import 'package:library_manager/models/loan.dart';
import 'package:library_manager/models/reservation.dart';
import 'package:library_manager/services/database_service.dart';

/// Phase 10.3 -- the SERVER-side hold queue, run against a real in-memory
/// SQLite database through the production [DatabaseService]. This proves what a
/// client cannot fake: a hold only ever QUEUES, a free copy is claimed at
/// PROMOTION with a compare-and-swap (and marked `Réservé`), a walk-up cannot
/// cut a promoted holder, a return promotes the next in line, an uncollected
/// hold expires and releases its copy, and a cancel is idempotency-safe.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late DatabaseService svc;

  Future<void> seedItem(String code, {int copies = 0}) async {
    await db.insert('library_items', {
      'code': code,
      'code_type': 'LIV',
      'designation': 'Designation $code',
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

  Future<void> seedMember(String id) =>
      db.insert('members', {'member_id': id, 'name': 'Member $id'});

  Future<String> copyState(int copyId) async {
    final rows = await db
        .query('item_copies', columns: ['state'], where: 'id = ?', whereArgs: [copyId]);
    return rows.first['state'] as String;
  }

  Future<List<Map<String, Object?>>> copyIds(String code) => db.rawQuery(
      'SELECT id FROM item_copies WHERE item_code = ? ORDER BY id', [code]);

  Loan loanFor(String code, String member, {int? copyId}) => Loan(
        itemCode: code,
        copyId: copyId,
        memberId: member,
        memberName: member,
        itemTitle: 'Designation $code',
        loanDate: DateTime(2026, 5, 1),
        dueDate: DateTime(2026, 5, 15),
        status: 'Active',
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

  group('hold policy', () {
    test('the default hold policy is generous but finite', () async {
      final s = await svc.getHoldSettings();
      expect(s.pickupDays, HoldSettings.defaultPickupDays);
      expect(s.queueMaxPerItem, HoldSettings.defaultQueueMax);
    });

    test('setHoldSettings persists sanitised values; a 0-day window degrades',
        () async {
      await svc.setHoldSettings(const HoldSettings(
          pickupDays: 3, queueMaxPerItem: 5));
      final s = await svc.getHoldSettings();
      expect(s.pickupDays, 3);
      expect(s.queueMaxPerItem, 5);

      // An out-of-range write can never be stored (0 days / unbounded queue).
      await svc.setHoldSettings(const HoldSettings(
          pickupDays: 0, queueMaxPerItem: 100000));
      final back = await svc.getHoldSettings();
      expect(back.pickupDays, HoldSettings.defaultPickupDays);
      expect(back.queueMaxPerItem, HoldSettings.defaultQueueMax);
    });
  });

  group('placeReservation', () {
    test('rejects an unknown item or member', () async {
      await seedMember('M1');
      await expectLater(svc.placeReservation('NOPE', 'M1'),
          throwsA(isA<StateError>()));
      await seedItem('0001');
      await expectLater(svc.placeReservation('0001', 'NOMEMBER'),
          throwsA(isA<StateError>()));
    });

    test('a copy-mode title promotes the first holder immediately', () async {
      await seedItem('0001', copies: 1);
      await seedMember('M1');
      final id = (await copyIds('0001')).first['id'] as int;

      final r = await svc.placeReservation('0001', 'M1');
      expect(r.status, ReservationStatus.available);
      expect(r.copyId, id);
      expect(r.availableUntil, isNotNull);
      // The copy is now claimed for M1: physically free, but `Réservé`.
      expect(await copyState(id), CopyState.reserved.storage);
    });

    test('a second holder queues behind the reserved copy', () async {
      await seedItem('0001', copies: 1);
      await seedMember('M1');
      await seedMember('M2');
      await svc.placeReservation('0001', 'M1');
      final second = await svc.placeReservation('0001', 'M2');
      expect(second.status, ReservationStatus.queued);
      expect(second.copyId, isNull);
    });

    test('a member cannot hold the same title twice', () async {
      await seedItem('0001', copies: 2);
      await seedMember('M1');
      await svc.placeReservation('0001', 'M1');
      await expectLater(svc.placeReservation('0001', 'M1'),
          throwsA(isA<StateError>()));
    });

    test('a full queue refuses a new arrival', () async {
      await svc.setHoldSettings(
          const HoldSettings(pickupDays: 7, queueMaxPerItem: 1));
      await seedItem('0001', copies: 1);
      await seedMember('M1');
      await seedMember('M2');
      await svc.placeReservation('0001', 'M1'); // promoted, still live
      await expectLater(svc.placeReservation('0001', 'M2'),
          throwsA(isA<StateError>()));
    });

    test('a legacy no-copy title promotes the front holder with no copy',
        () async {
      await seedItem('0001', copies: 0);
      await seedMember('M1');
      final r = await svc.placeReservation('0001', 'M1');
      expect(r.status, ReservationStatus.available);
      expect(r.copyId, isNull);
    });
  });

  group('walk-up protection', () {
    test('a walk-up cannot borrow a copy reserved for another member',
        () async {
      await seedItem('0001', copies: 1);
      await seedMember('M1');
      await seedMember('M2');
      final held = await svc.placeReservation('0001', 'M1');
      final id = (await copyIds('0001')).first['id'] as int;

      await expectLater(
        svc.addLoan(loanFor('0001', 'M2', copyId: id)),
        throwsA(isA<StateError>()),
      );
      // The reserved copy is untouched and still belongs to M1's hold.
      expect(await copyState(id), CopyState.reserved.storage);
      expect((await svc.getReservations(itemCode: '0001')).first.status,
          ReservationStatus.available);
      expect(held.memberId, 'M1');
    });

    test('auto-pick skips a copy reserved for someone else', () async {
      await seedItem('0001', copies: 2);
      await seedMember('M1');
      await seedMember('M2');
      final ids = (await copyIds('0001')).map((r) => r['id'] as int).toList();
      await svc.placeReservation('0001', 'M1'); // claims ids[0]
      // M2 borrows without naming a copy: it must land on the OTHER copy.
      await svc.addLoan(loanFor('0001', 'M2'));
      final m2loan = (await svc.getLoans(activeOnly: true))
          .firstWhere((l) => l.memberId == 'M2');
      expect(m2loan.copyId, ids[1]);
      expect(await copyState(ids[0]), CopyState.reserved.storage);
    });

    test('a legacy title with a live hold refuses a walk-up borrower',
        () async {
      await seedItem('0001', copies: 0);
      await seedMember('M1');
      await seedMember('M2');
      await svc.placeReservation('0001', 'M1');
      await expectLater(
        svc.addLoan(loanFor('0001', 'M2')),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('fulfilment', () {
    test('the holder borrowing the reserved copy fulfils the hold', () async {
      await seedItem('0001', copies: 1);
      await seedMember('M1');
      final r = await svc.placeReservation('0001', 'M1');
      await svc.addLoan(loanFor('0001', 'M1', copyId: r.copyId));

      final after = (await svc.getReservations(itemCode: '0001')).single;
      expect(after.status, ReservationStatus.fulfilled);
      expect(after.endedAt, isNotNull);
      expect(await copyState(r.copyId!), CopyState.onLoan.storage);
    });
  });

  group('auto-promotion on return', () {
    test('a return hands the freed copy to the next holder in line', () async {
      await seedItem('0001', copies: 1);
      await seedMember('M1');
      await seedMember('M2');
      // M1 borrows the copy outright (no hold), so M2's hold stays queued.
      await svc.addLoan(loanFor('0001', 'M1', copyId: (await copyIds('0001')).first['id'] as int));
      final queued = await svc.placeReservation('0001', 'M2');
      expect(queued.status, ReservationStatus.queued);

      final out = (await svc.getLoans(activeOnly: true)).single;
      await svc.updateLoan(out.copyWith(
        status: 'Returned',
        returnDate: DateTime(2026, 5, 10),
      ));

      final promoted =
          (await svc.getReservations(itemCode: '0001')).single;
      expect(promoted.status, ReservationStatus.available);
      expect(promoted.copyId, isNotNull);
      expect(await copyState(promoted.copyId!), CopyState.reserved.storage);
    });
  });

  group('expiry', () {
    test('a lapsed pickup window releases the copy and promotes the next',
        () async {
      await seedItem('0001', copies: 1);
      await seedMember('M1');
      await seedMember('M2');
      final first = await svc.placeReservation('0001', 'M1');
      final id = first.copyId!;
      // Force M1's hold to have lapsed.
      await db.update(
        'reservations',
        {'available_until': DateTime(2020).toIso8601String()},
        where: 'id = ?',
        whereArgs: [first.id],
      );
      // Any later queue touch sweeps expiry, frees the copy and promotes M2.
      final second = await svc.placeReservation('0001', 'M2');

      expect(second.status, ReservationStatus.available);
      expect((await svc.getReservations(itemCode: '0001'))
              .firstWhere((r) => r.id == first.id)
              .status,
          ReservationStatus.expired);
      expect(await copyState(id), CopyState.reserved.storage);
      expect(second.copyId, id); // the freed copy rolled to M2
    });

    test('readyForPickup lists only unexpired promoted holds', () async {
      await seedItem('0001', copies: 1);
      await seedItem('0002', copies: 1);
      await seedMember('M1');
      await seedMember('M2');
      final a = await svc.placeReservation('0001', 'M1'); // fresh, ready
      final b = await svc.placeReservation('0002', 'M2');
      await db.update(
        'reservations',
        {'available_until': DateTime(2020).toIso8601String()},
        where: 'id = ?',
        whereArgs: [b.id],
      );

      final ready = await svc.readyForPickup();
      expect(ready.map((r) => r.id), contains(a.id));
      expect(ready.map((r) => r.id), isNot(contains(b.id)));
    });
  });

  group('cancelReservation', () {
    test('cancelling a promoted hold releases its copy and promotes the next',
        () async {
      await seedItem('0001', copies: 1);
      await seedMember('M1');
      await seedMember('M2');
      final first = await svc.placeReservation('0001', 'M1');
      final second = await svc.placeReservation('0001', 'M2');
      expect(second.status, ReservationStatus.queued);

      await svc.cancelReservation(first.id!);
      final after = await svc.getReservations(itemCode: '0001');
      expect(after.firstWhere((r) => r.id == first.id).status,
          ReservationStatus.cancelled);
      // M2 inherited the released copy.
      expect(after.firstWhere((r) => r.id == second.id).status,
          ReservationStatus.available);
      expect(after.firstWhere((r) => r.id == second.id).copyId, first.copyId);
    });

    test('cancelling an unknown or already-closed hold is refused', () async {
      await expectLater(svc.cancelReservation(9999),
          throwsA(isA<StateError>()));
      await seedItem('0001', copies: 1);
      await seedMember('M1');
      final r = await svc.placeReservation('0001', 'M1');
      await svc.cancelReservation(r.id!);
      await expectLater(svc.cancelReservation(r.id!),
          throwsA(isA<StateError>()));
    });
  });

  group('getReservations queries', () {
    test('filters by member and by live-only', () async {
      await seedItem('0001', copies: 1);
      await seedMember('M1');
      await seedMember('M2');
      final a = await svc.placeReservation('0001', 'M1'); // available
      await svc.placeReservation('0001', 'M2'); // queued
      await svc.cancelReservation(a.id!); // one terminal row now

      final live = await svc.getReservations(itemCode: '0001', liveOnly: true);
      expect(live.every((r) => r.isLive), isTrue);
      final forM2 = await svc.getReservations(memberId: 'M2');
      expect(forM2, hasLength(1));
      final cancelled =
          await svc.getReservations(itemCode: '0001', status: ReservationStatus.cancelled);
      expect(cancelled.map((r) => r.id), contains(a.id));
    });
  });
}

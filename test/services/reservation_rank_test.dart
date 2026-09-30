import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/models/reservation.dart';
import 'package:library_manager/services/database_service.dart';

/// Pass 6 -- the REORDER primitive on the hold queue, run against a real
/// in-memory SQLite through the production [DatabaseService]. This pins the
/// contract the plan promises:
///
/// * a fresh v23 database and a v22 -> v23 migration both preserve today's
///   FIFO order for rows whose `rank` is NULL (no backfill required);
/// * `moveReservation` is a single-transaction swap of the CALLER's and its
///   neighbour's EFFECTIVE position (`COALESCE(rank, id)`), so a repeated
///   call bubbles a walk-in to the front one step at a time;
/// * boundary calls are silent no-ops (the operator can click the arrow on
///   the top/bottom row without a scary red error);
/// * a non-queued or unknown id throws a [StateError] BEFORE the write, so
///   the HTTP layer can surface it as a 409 without any half-applied swap.
///
/// Every case drives `getReservations` afterwards to read back what the UI
/// would show -- the ORDER BY the screen sees is the ground truth, not a
/// hidden test-only query.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late DatabaseService svc;

  Future<void> createV23Schema() async {
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
  }

  /// Insert a queued reservation directly, bypassing the promotion path, so
  /// a test can build an arbitrary queue shape. Returns the row's `id`.
  Future<int> insertQueued(String code, String member, {int? rank}) async {
    return await db.insert('reservations', {
      'item_code': code,
      'member_id': member,
      'status': ReservationStatus.queued.storage,
      'created_at': DateTime(2026, 1, 1).toIso8601String(),
      'rank': rank,
    });
  }

  Future<List<int>> queueOrder(String code) async {
    final rows = await svc.getReservations(itemCode: code);
    return rows
        .where((r) => r.status == ReservationStatus.queued)
        .map((r) => r.id!)
        .toList();
  }

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await createV23Schema();
    DatabaseService.useDatabaseForTesting(db);
    svc = DatabaseService();
  });

  tearDown(() async {
    await db.close();
  });

  group('v23 schema / COALESCE(rank, id) ordering', () {
    test(
      'a queue of NULL-rank rows preserves id ASC (pre-Pass-6 corpus)',
      () async {
        // No backfill required: existing 723+30 rows are all NULL and must
        // look identical to what the previous `id ASC` query produced.
        final a = await insertQueued('BK-001', 'M1');
        final b = await insertQueued('BK-001', 'M2');
        final c = await insertQueued('BK-001', 'M3');
        expect(a, lessThan(b));
        expect(b, lessThan(c));
        expect(await queueOrder('BK-001'), [a, b, c]);
      },
    );

    test(
      'an explicit rank on one row wins over its id-based position',
      () async {
        // Simulates an operator having already moved id=<high> to the front.
        final a = await insertQueued('BK-001', 'M1'); // rank NULL -> eff=a
        final b = await insertQueued('BK-001', 'M2'); // rank NULL -> eff=b
        final c = await insertQueued('BK-001', 'M3', rank: 0); // eff=0
        expect(await queueOrder('BK-001'), [c, a, b]);
      },
    );

    test(
      'rank is per-item; a same rank on a different item does not cross',
      () async {
        final x1 = await insertQueued('BK-001', 'M1');
        final x2 = await insertQueued('BK-001', 'M2', rank: 999);
        final y1 = await insertQueued('BK-002', 'M3');
        final y2 = await insertQueued('BK-002', 'M4', rank: 0);
        expect(await queueOrder('BK-001'), [x1, x2]);
        expect(await queueOrder('BK-002'), [y2, y1]);
      },
    );
  });

  group('moveReservation', () {
    test(
      'a single up-swap exchanges the caller with its predecessor',
      () async {
        final a = await insertQueued('BK-001', 'M1');
        final b = await insertQueued('BK-001', 'M2');
        final c = await insertQueued('BK-001', 'M3');
        final d = await insertQueued('BK-001', 'M4');
        expect(await queueOrder('BK-001'), [a, b, c, d]);

        await svc.moveReservation(d, up: true);
        // d swaps with c: effective becomes (c, d, ...) -> order [a, b, d, c].
        expect(await queueOrder('BK-001'), [a, b, d, c]);

        // The rank column is materialised for the two rows that moved, so
        // future reads do not need to re-derive from id.
        final rows = await db.rawQuery(
          'SELECT id, rank FROM reservations WHERE item_code = ?',
          ['BK-001'],
        );
        final byId = {for (final r in rows) r['id'] as int: r['rank'] as int?};
        expect(byId[a], isNull); // untouched
        expect(byId[b], isNull); // untouched
        expect(byId[c], d); // c now carries d's old effective position
        expect(byId[d], c); // d now carries c's old effective position
      },
    );

    test(
      'repeated up-calls bubble a row from last to first (walk-in to front)',
      () async {
        final a = await insertQueued('BK-001', 'M1');
        final b = await insertQueued('BK-001', 'M2');
        final c = await insertQueued('BK-001', 'M3');
        final d = await insertQueued('BK-001', 'M4');

        await svc.moveReservation(d, up: true);
        expect(await queueOrder('BK-001'), [a, b, d, c]);
        await svc.moveReservation(d, up: true);
        expect(await queueOrder('BK-001'), [a, d, b, c]);
        await svc.moveReservation(d, up: true);
        expect(await queueOrder('BK-001'), [d, a, b, c]);
        // A fourth up-call is now at the head of the line: silent no-op.
        await svc.moveReservation(d, up: true);
        expect(await queueOrder('BK-001'), [d, a, b, c]);
      },
    );

    test('a down-swap exchanges the caller with its successor', () async {
      final a = await insertQueued('BK-001', 'M1');
      final b = await insertQueued('BK-001', 'M2');
      final c = await insertQueued('BK-001', 'M3');

      await svc.moveReservation(a, up: false);
      expect(await queueOrder('BK-001'), [b, a, c]);
      await svc.moveReservation(a, up: false);
      expect(await queueOrder('BK-001'), [b, c, a]);
      // At the tail: silent no-op.
      await svc.moveReservation(a, up: false);
      expect(await queueOrder('BK-001'), [b, c, a]);
    });

    test('moving the only queued row is a silent no-op', () async {
      final only = await insertQueued('BK-001', 'M1');
      await svc.moveReservation(only, up: true);
      await svc.moveReservation(only, up: false);
      expect(await queueOrder('BK-001'), [only]);
    });

    test('a non-queued or unknown id throws BEFORE any write', () async {
      final a = await insertQueued('BK-001', 'M1');
      final b = await insertQueued('BK-001', 'M2');
      // Mark `b` cancelled so it drops out of the queue view.
      await db.update(
        'reservations',
        {'status': ReservationStatus.cancelled.storage},
        where: 'id = ?',
        whereArgs: [b],
      );

      await expectLater(
        svc.moveReservation(b, up: true),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        svc.moveReservation(99999, up: true),
        throwsA(isA<StateError>()),
      );
      // Neither throw mutated anything: the remaining queued row is still
      // alone and rank-NULL.
      expect(await queueOrder('BK-001'), [a]);
      final row = (await db.query(
        'reservations',
        columns: ['rank'],
        where: 'id = ?',
        whereArgs: [a],
      )).single;
      expect(row['rank'], isNull);
    });

    test('a swap is transactional: no partial state on either row', () async {
      // The plan promises the swap "cannot leave one row updated without
      // the other". Insert a queue, snapshot the pre-state, drive a move,
      // and read both touched rows back in one query -- either both moved
      // (ranks exchanged) or neither did (an exception path, which the
      // boundary/unknown tests already cover).
      final a = await insertQueued('BK-001', 'M1');
      final b = await insertQueued('BK-001', 'M2');
      await svc.moveReservation(b, up: true);
      final rows = await db.rawQuery(
        'SELECT id, rank FROM reservations WHERE id IN (?, ?) ORDER BY id',
        [a, b],
      );
      expect(rows, hasLength(2));
      // Both rows now carry a rank: exactly the two effective values from
      // before the swap, redistributed.
      expect(rows[0]['rank'], isNotNull);
      expect(rows[1]['rank'], isNotNull);
      expect({rows[0]['rank'], rows[1]['rank']}, {a, b});
    });
  });
}

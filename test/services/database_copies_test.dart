import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/models/item_copy.dart';
import 'package:library_manager/services/database_service.dart';

/// Proves the Phase 2 / DB-02 copy persistence added in increment 2.2b against
/// a real in-memory SQLite database using the production DatabaseService:
/// the idempotent backfill from library_items.quantite and the copy CRUD.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late DatabaseService svc;

  Future<void> seedItem(String code,
      {required int quantite, String status = 'Disponible'}) async {
    await db.insert('library_items', {
      'code': code,
      'code_type': 'LIV',
      'designation': 'Title $code',
      'quantite': quantite,
      'emplacement': 'A',
      'taux': 10,
      'emplacement_stock': 'S',
      'status': status,
    });
  }

  Future<int> copyCount(String code) async {
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM item_copies WHERE item_code = ?',
      [code],
    );
    return r.first['c'] as int;
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
    DatabaseService.useDatabaseForTesting(db);
    svc = DatabaseService();
  });

  tearDown(() async {
    await db.close();
  });

  group('backfill from quantite', () {
    test('creates one available copy per unit', () async {
      await seedItem('0001', quantite: 3);
      final created = await svc.backfillCopiesFromItems();
      expect(created, 3);
      expect(await copyCount('0001'), 3);
      final copies = await svc.getCopies('0001');
      expect(copies.every((c) => c.isAvailable), isTrue);
    });

    test('a 0/absent quantity still yields one physical copy', () async {
      await seedItem('0002', quantite: 0);
      await svc.backfillCopiesFromItems();
      expect(await copyCount('0002'), 1);
    });

    test('an Emprunté title marks exactly one copy on loan', () async {
      await seedItem('0003', quantite: 4, status: 'Emprunté');
      await svc.backfillCopiesFromItems();
      final copies = await svc.getCopies('0003');
      expect(copies.where((c) => c.isOnLoan).length, 1);
      expect(copies.where((c) => c.isAvailable).length, 3);
    });

    test('a Perdu title propagates the state to every copy', () async {
      await seedItem('0004', quantite: 2, status: 'Perdu');
      await svc.backfillCopiesFromItems();
      final copies = await svc.getCopies('0004');
      expect(copies.every((c) => c.copyState == CopyState.lost), isTrue);
    });

    test('is idempotent — re-running never duplicates', () async {
      await seedItem('0005', quantite: 2);
      expect(await svc.backfillCopiesFromItems(), 2);
      expect(await svc.backfillCopiesFromItems(), 0);
      expect(await copyCount('0005'), 2);
    });
  });

  group('copy data-access', () {
    test('addCopy -> getCopyById round-trips', () async {
      await seedItem('0006', quantite: 1);
      final id = await svc.addCopy(ItemCopy(itemCode: '0006', barcode: 'BC-6'));
      final loaded = await svc.getCopyById(id);
      expect(loaded, isNotNull);
      expect(loaded!.itemCode, '0006');
      expect(loaded.barcode, 'BC-6');
      expect(loaded.isAvailable, isTrue);
    });

    test('getCopyByBarcode resolves a per-copy barcode (BL-03 seam)', () async {
      final id =
          await svc.addCopy(ItemCopy(itemCode: '0007', barcode: 'SCAN-7'));
      final found = await svc.getCopyByBarcode('SCAN-7');
      expect(found?.id, id);
      expect(await svc.getCopyByBarcode('missing'), isNull);
    });

    test('updateCopy changes state', () async {
      final id = await svc.addCopy(ItemCopy(itemCode: '0008'));
      final c = (await svc.getCopyById(id))!;
      await svc.updateCopy(c.copyWith(state: CopyState.onLoan.storage));
      expect((await svc.getCopyById(id))!.isOnLoan, isTrue);
    });

    test('deleteCopiesForItem clears only that title', () async {
      await svc.addCopy(ItemCopy(itemCode: '0009'));
      await svc.addCopy(ItemCopy(itemCode: '0009'));
      await svc.addCopy(ItemCopy(itemCode: '0010'));
      await svc.deleteCopiesForItem('0009');
      expect(await svc.getCopies('0009'), isEmpty);
      expect(await svc.getCopies('0010'), hasLength(1));
    });
  });

  group('getStats derives from copies (BL-06)', () {
    test('counts physical copies, not titles', () async {
      await seedItem('0100', quantite: 3); // all available after backfill
      await seedItem('0101', quantite: 2, status: 'Emprunté'); // 1 on loan
      await svc.backfillCopiesFromItems();

      final stats = await svc.getStats();
      expect(stats['totalQuantity'], 5); // 3 + 2 physical copies
      expect(stats['onLoan'], 1); // only the one copy marked Emprunté
    });

    test('legacy copy-less title falls back to declared quantite', () async {
      await seedItem('0200', quantite: 4, status: 'Emprunté'); // no copies
      final stats = await svc.getStats();
      expect(stats['totalQuantity'], 4);
      expect(stats['onLoan'], 4);
    });

    test('a Perdu copy is not counted as on loan', () async {
      await seedItem('0300', quantite: 2, status: 'Perdu'); // backfill => 2 Perdu
      await svc.backfillCopiesFromItems();
      final stats = await svc.getStats();
      expect(stats['totalQuantity'], 2);
      expect(stats['onLoan'], 0);
    });
  });
}

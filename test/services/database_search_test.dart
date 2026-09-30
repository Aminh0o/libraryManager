import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/services/database_service.dart';

/// Proves search / filter / pagination / count are executed **server-side** by
/// the database (FE-05 / FE2-05 / Phase 7), over a catalogue far larger than
/// one page — the exact case the old in-memory filter over ≤20 cached rows got
/// wrong.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late DatabaseService svc;

  LibraryItem mk(String code,
      {String type = 'LIV',
      String status = 'Disponible',
      String? designation,
      String? barcode,
      String emplacement = 'A'}) {
    return LibraryItem(
      code: code,
      codeType: type,
      designation: designation ?? 'Titre $code',
      quantite: 1,
      emplacement: emplacement,
      taux: 10,
      emplacementStock: 'S',
      status: status,
      barcode: barcode,
    );
  }

  Future<void> insert(LibraryItem item) =>
      db.insert('library_items', item.toMap());

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE library_items(
        code TEXT PRIMARY KEY, barcode TEXT, code_type TEXT,
        designation TEXT, quantite INTEGER, emplacement TEXT,
        taux REAL, emplacement_stock TEXT, status TEXT DEFAULT 'Disponible',
        row_version INTEGER NOT NULL DEFAULT 0)
    ''');
    DatabaseService.useDatabaseForTesting(db);
    svc = DatabaseService();

    // 60 items, codes 0001..0060, ALL code_type LIV so the (code_type, code)
    // ordering is a clean ascending run of codes; alternating status (30 each).
    for (var i = 1; i <= 60; i++) {
      final code = i.toString().padLeft(4, '0');
      await insert(mk(code, status: i.isEven ? 'Disponible' : 'Emprunté'));
    }
    // A second code_type, under codes that sort after the LIV block, so it does
    // not disturb the pagination indices above.
    for (var i = 1; i <= 10; i++) {
      await insert(mk('03${i.toString().padLeft(2, '0')}', type: 'REV'));
    }
    // Items whose designation contains LIKE wildcards, to prove escaping.
    await insert(mk('0100', designation: 'Sold 50% off_now'));
    await insert(mk('0101', designation: 'Ordinary book'));
  });

  tearDown(() async {
    await db.close();
  });

  group('pagination over the whole catalogue', () {
    test('pages are disjoint slices of the ordered set (find #1/#21/#40/#60)',
        () async {
      final p1 = await svc.getItems(limit: 20, offset: 0);
      final p2 = await svc.getItems(limit: 20, offset: 20);
      final p3 = await svc.getItems(limit: 20, offset: 40);
      expect(p1.first.code, '0001'); // #1
      expect(p1.length, 20);
      expect(p2.first.code, '0021'); // #21
      expect(p3.first.code, '0041'); // #41
      // The last LIV page ends right before the REVs; walk to #60 explicitly.
      final all = await svc.getItems(limit: 1000);
      expect(all.map((e) => e.code).toList()[59], '0060'); // #60
    });

    test('a page deep in the list returns rows the ≤20 cache could not',
        () async {
      final page = await svc.getItems(limit: 20, offset: 45);
      final codes = page.map((e) => e.code).toList();
      expect(codes, containsAll(<String>['0046', '0055', '0060']));
    });
  });

  group('count agrees with the page', () {
    test('unfiltered count is the full catalogue', () async {
      expect(await svc.countItems(), 72); // 60 LIV + 10 REV + 2 wildcard-name
    });

    test('count matches the length of an unbounded query for every filter',
        () async {
      for (final status in ['Disponible', 'Emprunté']) {
        final c = await svc.countItems(status: status);
        final rows = await svc.getItems(limit: 1000, status: status);
        expect(c, rows.length, reason: 'status=$status');
      }
      for (final type in ['LIV', 'REV']) {
        final c = await svc.countItems(codeType: type);
        final rows = await svc.getItems(limit: 1000, codeType: type);
        expect(c, rows.length, reason: 'codeType=$type');
      }
    });
  });

  group('server-side filters', () {
    test('status filter narrows both page and count', () async {
      // 30 of the 60 seeded items are Emprunté (odd i).
      expect(await svc.countItems(status: 'Emprunté'), 30);
      final page = await svc.getItems(limit: 1000, status: 'Emprunté');
      expect(page.every((e) => e.status == 'Emprunté'), isTrue);
    });

    test('codeType filter narrows both page and count', () async {
      expect(await svc.countItems(codeType: 'REV'), 10);
      final page = await svc.getItems(limit: 1000, codeType: 'REV');
      expect(page.every((e) => e.codeType == 'REV'), isTrue);
    });

    test('search matches designation, code, barcode and full code', () async {
      expect(await svc.countItems(search: 'Titre 0007'), 1);
      expect(await svc.countItems(search: '0007'), 1); // code substring
      // fullCode = CODE_TYPE-code, e.g. "LIV-0007"
      expect((await svc.getItems(search: 'LIV-0007')).single.code, '0007');
      await insert(mk('0200', barcode: '978-X-123'));
      expect((await svc.getItems(search: '978-X-123')).single.code, '0200');
    });

    test('combined search + status + codeType filters intersect', () async {
      final page = await svc.getItems(
          limit: 1000, search: 'Titre 00', status: 'Emprunté', codeType: 'LIV');
      expect(page.every((e) => e.status == 'Emprunté' && e.codeType == 'LIV'),
          isTrue);
      expect(await svc.countItems(
          search: 'Titre 00', status: 'Emprunté', codeType: 'LIV'),
          page.length);
    });

    test('search is case-insensitive (ASCII)', () async {
      expect(await svc.countItems(search: 'titre 0007'), 1);
      expect(await svc.countItems(search: 'TITRE 0007'), 1);
    });

    test('LIKE wildcards in the term are treated literally (escaping)',
        () async {
      // '50%' must match only the item literally containing "50%", not all.
      final pct = await svc.getItems(search: '50%');
      expect(pct.map((e) => e.code).toList(), ['0100']);
      // '_' is a single-char wildcard in LIKE; escaping keeps it literal.
      final underscore = await svc.getItems(search: 'off_now');
      expect(underscore.map((e) => e.code).toList(), ['0100']);
      // A bare '%' is a wildcard; escaped, it must NOT match everything.
      expect(await svc.countItems(search: '%'), 1);
    });
  });
}

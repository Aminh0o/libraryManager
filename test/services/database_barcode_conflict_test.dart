import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/services/database_service.dart';

/// DB-01 (barcode determinism). Phase 4 added the partial UNIQUE index
/// `uq_items_barcode` (blank barcodes exempt) so a scanned ISBN resolves to
/// exactly one catalogue row -- but the write paths only guarded the PRIMARY
/// KEY, so a repeated non-empty barcode surfaced as a raw SQLite
/// `ConstraintError` -> an opaque HTTP 500 (and, on bulk import, aborted and
/// rolled back the ENTIRE batch). The repository now detects the clash first and
/// throws a typed `BarcodeConflictException` (the server maps it to 409), and
/// import SKIPS + reports barcode collisions instead of failing. Runs against a
/// real file DB so the production schema -- including the UNIQUE index -- is
/// genuinely exercised (a fake would not enforce it).
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.documentsPath);
  final String documentsPath;
  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final svc = DatabaseService();
  late Directory tmp;
  late Database db;

  LibraryItem item(
    String code, {
    String? barcode,
    String designation = 'Title',
    int quantite = 1,
  }) {
    final m = <String, dynamic>{
      'code': code,
      'code_type': 'LIV',
      'designation': designation,
      'quantite': quantite,
      'emplacement': 'A',
      'taux': 10,
      'emplacement_stock': 'S',
      'status': 'Disponible',
    };
    if (barcode != null) m['barcode'] = barcode;
    return LibraryItem.fromMap(m);
  }

  Future<Map<String, dynamic>?> row(String code) async {
    final r = await db.query(
      'library_items',
      where: 'code = ?',
      whereArgs: [code],
    );
    return r.isEmpty ? null : r.first;
  }

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('lib_bccode_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    db = await svc.database; // opens + creates the production schema
  });

  tearDownAll(() async {
    if (db.isOpen) await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('duplicate barcode is a typed conflict, not a 500 (DB-01)', () {
    test('addItem with a barcode already used by another title throws the '
        'typed conflict and inserts nothing', () async {
      await svc.addItem(item('B100', barcode: 'ISBN-999'));
      await expectLater(
        svc.addItem(item('B101', barcode: 'ISBN-999')),
        throwsA(isA<BarcodeConflictException>()),
      );
      // The first title is intact; the clashing one never landed.
      expect(await row('B100'), isNotNull);
      expect(await row('B101'), isNull);
    });

    test(
      'the typed conflict (not a raw DatabaseException) is what surfaces',
      () async {
        // Guards the specific regression: without the pre-check the UNIQUE index
        // raises a DatabaseException, which the server turns into a 500.
        await svc.addItem(item('B200', barcode: 'ISBN-777'));
        Object? caught;
        try {
          await svc.addItem(item('B201', barcode: 'ISBN-777'));
        } catch (e) {
          caught = e;
        }
        expect(caught, isA<BarcodeConflictException>());
        expect(caught, isNot(isA<DatabaseException>()));
      },
    );

    test('null and blank barcodes never collide', () async {
      // Two items with no barcode, then two with an empty one -- the partial
      // index exempts NULL/'' so all must insert cleanly.
      await svc.addItem(item('B300'));
      await svc.addItem(item('B301'));
      await svc.addItem(item('B302', barcode: ''));
      await svc.addItem(item('B303', barcode: ''));
      expect(await row('B300'), isNotNull);
      expect(await row('B301'), isNotNull);
      expect(await row('B302'), isNotNull);
      expect(await row('B303'), isNotNull);
    });

    test('updateItem to a barcode held by another title conflicts; keeping '
        'its own barcode is fine', () async {
      await svc.addItem(item('B400', barcode: 'ISBN-AAA'));
      await svc.addItem(item('B401', barcode: 'ISBN-BBB'));

      // Stealing B400's barcode is rejected.
      await expectLater(
        svc.updateItem(item('B401', barcode: 'ISBN-AAA')),
        throwsA(isA<BarcodeConflictException>()),
      );
      // B401 still holds its original barcode (the update rolled back).
      expect((await row('B401'))!['barcode'], 'ISBN-BBB');

      // Re-saving B401 with its OWN barcode must not be a self-clash.
      await svc.updateItem(
        item('B401', barcode: 'ISBN-BBB', designation: 'Renamed'),
      );
      expect((await row('B401'))!['designation'], 'Renamed');
      expect((await row('B401'))!['barcode'], 'ISBN-BBB');
    });
  });

  group(
    'bulk import skips barcode collisions instead of failing the batch',
    () {
      test('a row whose barcode duplicates an existing catalogue row is '
          'skipped and reported; valid new rows still commit', () async {
        await svc.addItem(item('I500', barcode: 'ISBN-500'));

        final res = await svc.batchInsertItems([
          item('I501', barcode: 'ISBN-500'), // collides with existing -> skip
          item('I502', barcode: 'ISBN-502'), // new -> insert
        ]);

        expect(res.inserted, 1);
        expect(res.skippedBarcodes, contains('I501'));
        expect(await row('I501'), isNull);
        expect(await row('I502'), isNotNull);
        // The pre-existing holder is untouched.
        expect((await row('I500'))!['barcode'], 'ISBN-500');
      });

      test(
        'a barcode duplicated WITHIN one file inserts only the first',
        () async {
          final res = await svc.batchInsertItems([
            item('I600', barcode: 'ISBN-600', designation: 'First'),
            item('I601', barcode: 'ISBN-600', designation: 'Second'),
          ]);
          expect(res.inserted, 1);
          expect(res.skippedBarcodes, contains('I601'));
          expect(await row('I600'), isNotNull);
          expect(await row('I601'), isNull);
        },
      );
    },
  );
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/models/item_copy.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/services/database_service.dart';

/// BL-05 (write-path leg): a title's status is ALWAYS the rollup of its
/// physical copies, so no write path may persist an arbitrary title-level
/// status. This exercises the production DatabaseService against a real file
/// DB (full v22 schema): create/import materialize available copies and derive
/// the stored status; add/update REFUSE an out-of-vocabulary status with a typed
/// [InvalidStatusException] (server -> 400); and an inbound status that merely
/// CONTRADICTS the copies is validated then IGNORED -- the copies win.
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
    int quantite = 1,
    String status = 'Disponible',
  }) => LibraryItem(
    code: code,
    codeType: 'LIV',
    designation: 'Title $code',
    quantite: quantite,
    emplacement: 'A',
    taux: 10,
    emplacementStock: 'S',
    status: status,
  );

  Future<String?> storedStatus(String code) async {
    final r = await db.query(
      'library_items',
      columns: ['status'],
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    return r.isEmpty ? null : r.first['status'] as String?;
  }

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('lib_bl05_write_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    db = await svc.database; // onCreate -> current (v22) schema
  });

  tearDownAll(() async {
    if (db.isOpen) await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('addItem is copy-driven (BL-05)', () {
    test('rejects an out-of-vocabulary status and creates nothing', () async {
      await expectLater(
        svc.addItem(item('W100', status: 'Endommagé')),
        throwsA(isA<InvalidStatusException>()),
      );
      expect(
        await storedStatus('W100'),
        isNull,
        reason: 'a refused add must leave no orphan title row',
      );
    });

    test('stores the derived rollup and seeds available copies, ignoring a '
        'valid-but-contradicting supplied status', () async {
      // A new title is born with N physically-present copies, so it is always
      // 'Disponible' no matter what status the caller supplies.
      await svc.addItem(item('W101', quantite: 3, status: 'Emprunté'));
      expect(await storedStatus('W101'), 'Disponible');
      final copies = await svc.getCopies('W101');
      expect(copies, hasLength(3));
      expect(copies.every((c) => c.copyState == CopyState.available), isTrue);
    });
  });

  group('updateItem is copy-driven (BL-05)', () {
    test(
      'rejects an out-of-vocabulary status and rolls the edit back',
      () async {
        await svc.addItem(item('W200'));
        await expectLater(
          svc.updateItem(item('W200', status: 'Payé')),
          throwsA(isA<InvalidStatusException>()),
        );
        // The stored row is untouched (still the derived 'Disponible').
        expect(await storedStatus('W200'), 'Disponible');
      },
    );

    test('derives the stored status from the copies, overriding the inbound '
        'status (which is only validated)', () async {
      await svc.addItem(item('W201')); // 1 available copy -> 'Disponible'
      final copy = (await svc.getCopies('W201')).single;
      // Simulate a genuine loan: the physical copy is now out.
      await db.update(
        'item_copies',
        {'state': CopyState.onLoan.storage},
        where: 'id = ?',
        whereArgs: [copy.id],
      );
      expect(
        await storedStatus('W201'),
        'Disponible',
        reason: 'status is not recomputed until a write path runs',
      );

      // A metadata-only edit that also (wrongly / stalely) claims 'Disponible':
      // the inbound value is a VALID word so it is accepted, but the stored
      // status must be the rollup of the (on-loan) copy, i.e. 'Emprunté'.
      await svc.updateItem(
        LibraryItem(
          code: 'W201',
          codeType: 'LIV',
          designation: 'Renamed',
          quantite: 1,
          emplacement: 'A',
          taux: 10,
          emplacementStock: 'S',
          status: 'Disponible',
        ),
      );
      expect(
        await storedStatus('W201'),
        'Emprunté',
        reason: 'the on-loan copy makes the title Emprunté regardless of input',
      );
      final desig = await db.query(
        'library_items',
        columns: ['designation'],
        where: "code = 'W201'",
      );
      expect(
        desig.first['designation'],
        'Renamed',
        reason: 'the legitimate metadata edit still lands',
      );
    });
  });

  group('batchInsertItems is copy-driven (BL-05)', () {
    test(
      'imports every row as the derived rollup, materializes copies, and '
      'reports out-of-vocabulary imported statuses without rejecting the row',
      () async {
        final res = await svc.batchInsertItems([
          item('W300', quantite: 2, status: 'Endommagé'), // out of vocabulary
          item('W301', quantite: 1, status: 'Disponible'), // fine
        ]);
        expect(
          res.inserted,
          2,
          reason:
              'an invalid status is reported, never a reason to drop the row',
        );
        expect(res.invalidStatusCodes, contains('W300'));
        expect(res.invalidStatusCodes, isNot(contains('W301')));

        // Both are stored as the honest rollup and own available copies.
        expect(await storedStatus('W300'), 'Disponible');
        expect(await storedStatus('W301'), 'Disponible');
        expect(await svc.getCopies('W300'), hasLength(2));
        expect(await svc.getCopies('W301'), hasLength(1));
      },
    );
  });
}

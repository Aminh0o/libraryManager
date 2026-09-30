import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/models/item_copy.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/services/database_service.dart';

/// Phase 13 (per-copy add / remove / barcode): staff can grow or shrink a
/// title's physical set one copy at a time. The governing invariant is that
/// `library_items.quantite` MUST stay in lock-step with the real copy count
/// (BL-05 made copies authoritative; if the declared quantity drifted, a later
/// item-form save would silently add/remove copies under the editor). Removal
/// is guarded exactly like [_reconcileCopies]: never the last copy of a title,
/// never a copy that is on loan / reserved. Per-copy barcodes are UNIQUE when
/// present (the `uq_copies_barcode` partial index), so a collision is refused
/// with a typed [BarcodeConflictException]. Proven against the production
/// DatabaseService on a real file DB (full v22 schema).
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

  Future<void> seed(String code, {int quantite = 1}) => svc.addItem(LibraryItem(
        code: code,
        codeType: 'LIV',
        designation: 'Title $code',
        quantite: quantite,
        emplacement: 'A',
        taux: 10,
        emplacementStock: 'S',
      ));

  Future<int> storedQuantite(String code) async {
    final r = await db.query('library_items',
        columns: ['quantite'], where: 'code = ?', whereArgs: [code], limit: 1);
    return ((r.first['quantite'] as num?) ?? 0).toInt();
  }

  Future<String?> storedStatus(String code) async {
    final r = await db.query('library_items',
        columns: ['status'], where: 'code = ?', whereArgs: [code], limit: 1);
    return r.isEmpty ? null : r.first['status'] as String?;
  }

  Future<int> rowVersion(String code) async {
    final r = await db.query('library_items',
        columns: ['row_version'],
        where: 'code = ?',
        whereArgs: [code],
        limit: 1);
    return ((r.first['row_version'] as num?) ?? 0).toInt();
  }

  Future<int> copyCount(String code) async => (await svc.getCopies(code)).length;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('lib_copy_crud_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    db = await svc.database; // onCreate -> current (v22) schema
  });

  tearDownAll(() async {
    if (db.isOpen) await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('addCopyForItem grows the set, re-syncs quantite, re-derives, audited',
      () async {
    await seed('C1');
    final before = await rowVersion('C1');
    expect(await copyCount('C1'), 1);

    final newId = await svc.addCopyForItem(
      'C1',
      audit: {
        'timestamp': DateTime.now().toIso8601String(),
        'operation': 'COPY_ADD',
        'details': 'Added a copy of C1',
        'user': 'Host',
      },
    );

    expect(newId, greaterThan(0));
    expect(await copyCount('C1'), 2);
    expect(await storedQuantite('C1'), 2,
        reason: 'quantite must equal the new copy count, not drift');
    expect(await storedStatus('C1'), 'Disponible');
    expect(await rowVersion('C1'), greaterThan(before),
        reason: 'a real committed change bumps the token');
    final hist = await db.query('history',
        where: "operation = ? AND details LIKE ?",
        whereArgs: ['COPY_ADD', '%C1%']);
    expect(hist, isNotEmpty);
  });

  test('removeCopy shrinks the set and re-syncs quantite', () async {
    await seed('C2', quantite: 2);
    final copies = await svc.getCopies('C2');

    await svc.removeCopy(
      copies.first.id!,
      audit: {
        'timestamp': DateTime.now().toIso8601String(),
        'operation': 'COPY_DEL',
        'details': 'Removed a copy of C2',
        'user': 'Host',
      },
    );

    expect(await copyCount('C2'), 1);
    expect(await storedQuantite('C2'), 1);
    final hist = await db.query('history',
        where: "operation = ? AND details LIKE ?",
        whereArgs: ['COPY_DEL', '%C2%']);
    expect(hist, isNotEmpty);
  });

  test('the LAST copy of a title cannot be removed (delete the item instead)',
      () async {
    await seed('C3');
    final copy = (await svc.getCopies('C3')).single;

    await expectLater(
      svc.removeCopy(copy.id!),
      throwsA(isA<CopyConflictException>()),
      reason: 'a title must always keep a physical unit',
    );
    expect(await copyCount('C3'), 1);
    expect(await storedQuantite('C3'), 1,
        reason: 'a refused removal must not touch quantite');
  });

  test('a copy that is on loan cannot be removed (CAS)', () async {
    await seed('C4', quantite: 2);
    var copies = await svc.getCopies('C4');
    final loaned = copies.first;
    // Simulate a genuine loan: the physical copy is now checked out.
    await db.update('item_copies', {'state': CopyState.onLoan.storage},
        where: 'id = ?', whereArgs: [loaned.id]);

    await expectLater(
      svc.removeCopy(loaned.id!),
      throwsA(isA<CopyConflictException>()),
      reason: 'the loan owns this copy — it cannot be hand-deleted',
    );
    copies = await svc.getCopies('C4');
    expect(copies.length, 2);
    expect(await storedQuantite('C4'), 2);
    expect(copies.first.state, CopyState.onLoan.storage);
  });

  test('a copy may be removed while ANOTHER copy of the title is on loan',
      () async {
    await seed('C5', quantite: 2);
    final copies = await svc.getCopies('C5');
    final loaned = copies.first;
    final spare = copies.last;
    await db.update('item_copies', {'state': CopyState.onLoan.storage},
        where: 'id = ?', whereArgs: [loaned.id]);

    // The spare is still available, so removing it is legitimate: the title
    // keeps the (on-loan) copy and never drops below one unit.
    await svc.removeCopy(spare.id!);
    final remaining = await svc.getCopies('C5');
    expect(remaining.length, 1);
    expect(remaining.single.state, CopyState.onLoan.storage);
    expect(await storedQuantite('C5'), 1);
    // The title is entirely on loan now, so the rollup reflects it.
    expect(await storedStatus('C5'), 'Emprunté');
  });

  test('setCopyBarcode enforces uniqueness across copies', () async {
    await seed('C6', quantite: 2);
    final copies = await svc.getCopies('C6');
    final a = copies.first, b = copies.last;

    await svc.setCopyBarcode(a.id!, '  BC-001  ');
    expect((await svc.getCopies('C6')).first.barcode, 'BC-001',
        reason: 'the value is trimmed before it is stored');

    await expectLater(
      svc.setCopyBarcode(b.id!, 'BC-001'),
      throwsA(isA<BarcodeConflictException>()),
      reason: 'a non-empty barcode must be unique across copies',
    );

    await svc.setCopyBarcode(b.id!, 'BC-002');
    final updated = await svc.getCopies('C6');
    expect(
      updated.map((c) => c.barcode).toSet(),
      {'BC-001', 'BC-002'},
    );
  });

  test('a blank barcode clears the copy barcode (null, not empty)', () async {
    await seed('C7');
    final copy = (await svc.getCopies('C7')).single;
    await svc.setCopyBarcode(copy.id!, 'BC-CLR');
    expect((await svc.getCopies('C7')).single.barcode, 'BC-CLR');

    await svc.setCopyBarcode(copy.id!, '   ');
    expect((await svc.getCopies('C7')).single.barcode, isNull);
  });

  test('add then remove restores the original quantite (no drift)', () async {
    await seed('C8', quantite: 3);
    expect(await storedQuantite('C8'), 3);

    final id = await svc.addCopyForItem('C8');
    expect(await copyCount('C8'), 4);
    expect(await storedQuantite('C8'), 4);

    await svc.removeCopy(id);
    expect(await copyCount('C8'), 3);
    expect(await storedQuantite('C8'), 3);
  });
}

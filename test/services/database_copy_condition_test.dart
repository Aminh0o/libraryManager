import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/models/item_copy.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/services/database_service.dart';

/// Phase 12 (copy-condition editor): staff may set an in-hand copy's CONDITION
/// to available / in-repair / lost / archived, and the title status is re-derived
/// from the copy rollup in the SAME write (BL-05 stays authoritative). The
/// circulation states are off-limits: a non-editable TARGET is refused with a
/// typed [InvalidStatusException], and a copy that is CURRENTLY on loan /
/// reserved cannot be hand-edited ([StateError]) — it must go through the
/// loan / hold flow. Proven against the production DatabaseService on a real
/// file DB (full v22 schema).
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

  Future<void> seed(String code, {int quantite = 1}) => svc.addItem(
    LibraryItem(
      code: code,
      codeType: 'LIV',
      designation: 'Title $code',
      quantite: quantite,
      emplacement: 'A',
      taux: 10,
      emplacementStock: 'S',
    ),
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

  Future<int> rowVersion(String code) async {
    final r = await db.query(
      'library_items',
      columns: ['row_version'],
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    return ((r.first['row_version'] as num?) ?? 0).toInt();
  }

  Future<ItemCopy> onlyCopy(String code) async =>
      (await svc.getCopies(code)).single;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('lib_copy_condition_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    db = await svc.database; // onCreate -> current (v22) schema
  });

  tearDownAll(() async {
    if (db.isOpen) await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test(
    'available -> maintenance sets the copy and derives the title',
    () async {
      await seed('Q1');
      final copy = await onlyCopy('Q1');
      final before = await rowVersion('Q1');

      await svc.setCopyCondition(
        copy.id!,
        CopyState.maintenance,
        audit: {
          'timestamp': DateTime.now().toIso8601String(),
          'operation': 'COPY_STATE',
          'details': 'Copie #${copy.id} de Q1 -> En Réparation',
          'user': 'Host',
        },
      );

      expect((await onlyCopy('Q1')).state, CopyState.maintenance.storage);
      // The single copy is now non-lendable, so the rollup reflects it exactly.
      expect(await storedStatus('Q1'), 'En Réparation');
      // The title token bumps so LAN clients refresh (a real committed change).
      expect(await rowVersion('Q1'), greaterThan(before));
      final hist = await db.query(
        'history',
        where: "operation = ? AND details LIKE ?",
        whereArgs: ['COPY_STATE', '%Q1%'],
      );
      expect(hist, isNotEmpty, reason: 'the copy change is audited in-txn');
    },
  );

  test(
    'one lost copy among an available one keeps the title Disponible',
    () async {
      await seed('Q2', quantite: 2);
      final copies = await svc.getCopies('Q2');
      await svc.setCopyCondition(copies.first.id!, CopyState.lost);

      expect((await svc.getCopies('Q2')).first.state, CopyState.lost.storage);
      expect(
        await storedStatus('Q2'),
        'Disponible',
        reason: 'an available copy still makes the title lendable (BL-05)',
      );
    },
  );

  test(
    'a lost copy can be restored to available, re-deriving the title',
    () async {
      await seed('Q3');
      var copy = await onlyCopy('Q3');
      await svc.setCopyCondition(copy.id!, CopyState.lost);
      expect(await storedStatus('Q3'), 'Perdu');

      copy = await onlyCopy('Q3');
      await svc.setCopyCondition(copy.id!, CopyState.available);
      expect((await onlyCopy('Q3')).state, CopyState.available.storage);
      expect(await storedStatus('Q3'), 'Disponible');
    },
  );

  test(
    'a non-editable TARGET (on loan / reserved) is refused, copy unchanged',
    () async {
      await seed('Q4');
      final copy = await onlyCopy('Q4');

      await expectLater(
        svc.setCopyCondition(copy.id!, CopyState.onLoan),
        throwsA(isA<InvalidStatusException>()),
      );
      await expectLater(
        svc.setCopyCondition(copy.id!, CopyState.reserved),
        throwsA(isA<InvalidStatusException>()),
      );
      expect(
        (await onlyCopy('Q4')).state,
        CopyState.available.storage,
        reason: 'a refused request must not mutate the copy',
      );
    },
  );

  test(
    'a copy that is CURRENTLY on loan cannot be hand-edited (CAS)',
    () async {
      await seed('Q5');
      final copy = await onlyCopy('Q5');
      // Simulate a genuine loan: the physical copy is now checked out.
      await db.update(
        'item_copies',
        {'state': CopyState.onLoan.storage},
        where: 'id = ?',
        whereArgs: [copy.id],
      );

      await expectLater(
        svc.setCopyCondition(copy.id!, CopyState.archived),
        throwsA(isA<CopyConflictException>()),
        reason: 'the loan owns this copy — staff must return it first',
      );
      expect(
        (await onlyCopy('Q5')).state,
        CopyState.onLoan.storage,
        reason: 'the guarded update must be a no-op on a locked copy',
      );
    },
  );
}

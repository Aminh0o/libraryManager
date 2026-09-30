import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/services/database_service.dart';

/// Regression guard for the interaction between the DB-01 foreign keys (added in
/// P9-9.21) and BL-04's documented delete semantics. BL-04 allows deleting a
/// title that has NO active loan and deliberately KEEPS its historical (returned)
/// loans. A child `loans.item_code ... ON DELETE RESTRICT` FK makes SQLite refuse
/// that delete (a returned loan still references the parent), turning an allowed
/// delete into an uncaught DatabaseException -> HTTP 500. The FK actions were
/// therefore corrected to ON DELETE SET NULL: the historical loan row survives
/// with its snapshot fields, only the dead item/copy reference is cleared.
///
/// This runs against a REAL file DB opened through the production `openDatabaseAt`
/// (so it genuinely carries the v17 FKs + `foreign_keys=ON`); the in-memory
/// `useDatabaseForTesting` schema has no FKs and is exactly why the original
/// BL-04 tests never caught this.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final svc = DatabaseService();
  late Directory tmp;
  late String path;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lib_delhist_');
    path = p.join(tmp.path, 'library_manager.db');
  });
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test(
    'an item with only RETURNED loan history deletes cleanly and keeps history',
    () async {
      final db = await svc.openDatabaseAt(path);
      DatabaseService.useDatabaseForTesting(db);

      await db.insert('library_items', {
        'code': '0500',
        'designation': 'Old Book',
        'status': 'Disponible',
      });
      final copyId = await db.insert('item_copies', {
        'item_code': '0500',
        'state': 'Disponible',
      });
      await db.insert('loans', {
        'item_code': '0500',
        'copy_id': copyId,
        'member_id': 'AA0001',
        'member_name': 'Ada',
        'item_title': 'Old Book',
        'loan_date': '2020-01-01T00:00:00.000',
        'due_date': '2020-01-16T00:00:00.000',
        'return_date': '2020-01-10T00:00:00.000',
        'status': 'Returned',
      });

      // BL-04: no active loan => the delete must be permitted (previously threw a
      // DatabaseException under ON DELETE RESTRICT).
      await svc.deleteItem('0500');

      // The title and its physical copies are gone...
      expect(await db.query('library_items', where: "code='0500'"), isEmpty);
      expect(await db.query('item_copies', where: "item_code='0500'"), isEmpty);

      // ...but the historical loan survives as an audit record; only its dead
      // item / copy references were severed by ON DELETE SET NULL.
      final loans = await db.query('loans');
      expect(loans, hasLength(1));
      expect(loans.single['status'], 'Returned');
      expect(loans.single['item_title'], 'Old Book'); // snapshot retained
      expect(loans.single['member_id'], 'AA0001'); // snapshot retained
      expect(loans.single['item_code'], isNull);
      expect(loans.single['copy_id'], isNull);

      await db.close();
    },
  );

  test(
    'an item with an ACTIVE loan is still refused (app guard, not the FK)',
    () async {
      final db = await svc.openDatabaseAt(path);
      DatabaseService.useDatabaseForTesting(db);

      await db.insert('library_items', {
        'code': '0600',
        'designation': 'On Loan',
      });
      await db.insert('loans', {
        'item_code': '0600',
        'member_id': 'BB0002',
        'item_title': 'On Loan',
        'loan_date': '2020-01-01T00:00:00.000',
        'due_date': '2020-01-16T00:00:00.000',
        'status': 'Active',
      });

      await expectLater(
        svc.deleteItem('0600'),
        throwsA(isA<ActiveLoanConflictException>()),
      );
      // The active-loan guard fires first, so the title and its loan are intact.
      expect(
        await db.query('library_items', where: "code='0600'"),
        hasLength(1),
      );
      expect(await db.query('loans'), hasLength(1));

      await db.close();
    },
  );
}

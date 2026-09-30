import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/services/database_service.dart';

/// Points `getApplicationDocumentsDirectory()` (and thus the production
/// `DatabaseService` live path + its `library_backups` dir) at a throwaway
/// directory so the pre-wipe safety backup runs against a REAL file database
/// exactly as it does on a host (BR-04 / REL-02).
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.documentsPath);
  final String documentsPath;
  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

/// Opens [path] read-only (no migrations) to inspect a produced snapshot
/// independently of the live database.
Future<Database> _openReadOnly(String path) => databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final svc = DatabaseService();
  late Directory tmp;
  Directory backupsDir() => Directory(p.join(tmp.path, 'library_backups'));

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('lib_prewrite_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    await svc.database;
  });

  tearDownAll(() async {
    final db = await svc.database;
    if (db.isOpen) await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    if (backupsDir().existsSync()) backupsDir().deleteSync(recursive: true);
    final db = await svc.database;
    await db.delete('library_items');
  });

  Future<void> putItem(String code) async {
    final db = await svc.database;
    await db.insert('library_items', {
      'code': code,
      'code_type': 'LIV',
      'designation': 'Title $code',
      'quantite': 1,
      'emplacement': 'A',
      'taux': 0,
      'emplacement_stock': 'S',
      'status': 'Disponible',
    });
  }

  Future<int> countItem(String code) async {
    final db = await svc.database;
    final r = await db
        .rawQuery('SELECT COUNT(*) c FROM library_items WHERE code = ?', [code]);
    return r.first['c'] as int;
  }

  List<File> safetyFiles() => backupsDir()
      .listSync()
      .whereType<File>()
      .where((f) => p.basename(f.path).startsWith('pre_wipe_'))
      .toList();

  group('pre-wipe safety backup (BR-04 / REL-02)', () {
    test('a wipe writes a recoverable snapshot and the wipe still resets data',
        () async {
      await putItem('WIPE1');
      expect(await countItem('WIPE1'), 1);

      await svc.clearAllData();

      // Live DB is wiped and re-seeded with the 6 default code prefixes.
      expect(await countItem('WIPE1'), 0);
      final db = await svc.database;
      final codes =
          await db.rawQuery('SELECT COUNT(*) c FROM code_definitions');
      expect(codes.first['c'], 6);

      // A durable pre_wipe snapshot exists and still contains the pre-wipe row.
      final safes = safetyFiles();
      expect(safes, isNotEmpty,
          reason: 'clearAllData must write a pre_wipe snapshot before erasing');
      final probe = await _openReadOnly(safes.last.path);
      try {
        final ok = await probe.rawQuery('PRAGMA integrity_check');
        expect('${ok.first.values.first}', 'ok');
        final kept = await probe
            .rawQuery('SELECT COUNT(*) c FROM library_items WHERE code = ?',
                ['WIPE1']);
        expect(kept.first['c'], 1,
            reason: 'the snapshot must let a mistaken erase be recovered');
      } finally {
        await probe.close();
      }
    });

    test('a complete erase also clears the per-copy table, not just items (RC-05)',
        () async {
      final db = await svc.database;
      await putItem('COP1');
      await db.insert(
          'item_copies', {'item_code': 'COP1', 'state': 'Disponible'});
      await db.insert('item_copies', {'item_code': 'COP1', 'state': 'Emprunté'});
      final before = await db
          .rawQuery('SELECT COUNT(*) c FROM item_copies WHERE item_code = ?',
              ['COP1']);
      expect(before.first['c'], 2);

      await svc.clearAllData();

      // item_copies was added after the original 6-table wipe list; without
      // clearing it a "complete erase" leaves orphaned copy rows (stale
      // on-loan state, double-seeded copies on re-add).
      final left =
          await db.rawQuery('SELECT COUNT(*) c FROM item_copies');
      expect(left.first['c'], 0,
          reason: 'a complete wipe must leave no orphaned item_copies rows');
    });

    test('the wipe succeeds even while loans still reference items/copies (DB-01 FK)',
        () async {
      // Guards clearAllData's delete ORDER against the real DB-01 foreign keys.
      // It deletes `library_items` FIRST while loans still reference it, which
      // only works because those FKs are ON DELETE SET NULL / CASCADE (the
      // P9-9.24 correction). Under the original P9-9.21 ON DELETE RESTRICT the
      // very first `DELETE FROM library_items` threw a DatabaseException and
      // aborted the whole wipe. This is a REAL file DB opened through the
      // production path (foreign_keys=ON + the v17 FKs), so the constraint is
      // genuinely enforced here -- the exact case the no-FK in-memory schemas
      // used by the other delete tests never exercise.
      final db = await svc.database;
      await putItem('FKW1');
      final copyId = await db.insert(
          'item_copies', {'item_code': 'FKW1', 'state': 'Emprunté'});
      await db.insert('members', {
        'member_id': 'FKM1',
        'first_name': 'Loan',
        'last_name': 'Ref',
        'registered_at': '2020-01-01T00:00:00.000',
      });
      await db.insert('loans', {
        'item_code': 'FKW1',
        'copy_id': copyId,
        'member_id': 'FKM1',
        'member_name': 'Loan Ref',
        'item_title': 'FKW1 title',
        'loan_date': '2020-01-01T00:00:00.000',
        'due_date': '2020-01-16T00:00:00.000',
        'status': 'Active',
      });
      await db.insert('loans', {
        'item_code': 'FKW1',
        'member_id': 'FKM1',
        'member_name': 'Loan Ref',
        'item_title': 'FKW1 title',
        'loan_date': '2020-02-01T00:00:00.000',
        'due_date': '2020-02-16T00:00:00.000',
        'return_date': '2020-02-09T00:00:00.000',
        'status': 'Returned',
      });

      // Must NOT throw: proves the SET NULL / CASCADE actions let the
      // parent-first wipe run over a fully-referenced graph.
      await svc.clearAllData();

      for (final table in [
        'library_items',
        'item_copies',
        'members',
        'loans',
      ]) {
        final r = await db.rawQuery('SELECT COUNT(*) c FROM $table');
        expect(r.first['c'], 0,
            reason: 'a complete wipe must leave $table empty');
      }
    });

    test('rotation prunes only library_backup_* and never a safety snapshot',
        () async {
      await putItem('DUMMY');
      backupsDir().createSync(recursive: true);
      for (var i = 0; i < 12; i++) {
        File(p.join(backupsDir().path, 'library_backup_fake$i.db')).createSync();
      }
      final keeper = File(p.join(backupsDir().path, 'pre_wipe_keep.db'))
        ..createSync();

      await svc.createAutoBackup(); // writes 1 real backup + prunes

      final rotating = backupsDir()
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('library_backup_'))
          .toList();
      expect(rotating.length, 10,
          reason: 'keep-last-10 applies to the rotating backups only');
      expect(keeper.existsSync(), isTrue,
          reason: 'safety snapshots must survive the rotation');
    });

    test('the wipe ABORTS with data intact if the snapshot cannot be written',
        () async {
      await putItem('KEEP1');
      expect(await countItem('KEEP1'), 1);

      // Make the documents path un-creatable: nest it under a regular FILE, so
      // Directory.create() fails inside createSafetyBackup (the already-open DB
      // handle is unaffected, so only the backup step can fail).
      File(p.join(tmp.path, 'blocker')).createSync();
      PathProviderPlatform.instance =
          _FakePathProvider(p.join(tmp.path, 'blocker', 'nested'));

      await expectLater(
        () => svc.clearAllData(),
        throwsA(isA<BackupFailedException>()),
      );

      // Data must be untouched: no silent destructive wipe without a net.
      expect(await countItem('KEEP1'), 1);

      PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    });
  });
}

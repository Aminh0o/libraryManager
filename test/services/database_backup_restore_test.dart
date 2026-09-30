import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/services/database_service.dart';

/// Points `getApplicationDocumentsDirectory()` (and thus the production
/// `DatabaseService` live path) at a throwaway directory, so backup/restore run
/// against a REAL file database exactly as they do on a host (DB-03 / DB-04).
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.documentsPath);
  final String documentsPath;
  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

/// Opens the file at [path] read-only without migrations so a produced backup
/// can be inspected independently of the live database.
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
  late String livePath;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('lib_backup_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    livePath = p.join(tmp.path, 'library_manager.db');
    // Open the production schema at the faked documents dir.
    await svc.database;
  });

  tearDownAll(() async {
    final db = await svc.database;
    if (db.isOpen) await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<int> liveCount(String code) async {
    final db = await svc.database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) c FROM library_items WHERE code = ?',
      [code],
    );
    return r.first['c'] as int;
  }

  Future<void> putItem(String code, String title) async {
    final db = await svc.database;
    await db.insert('library_items', {
      'code': code,
      'code_type': 'LIV',
      'designation': title,
      'quantite': 1,
      'emplacement': 'A',
      'taux': 0,
      'emplacement_stock': 'S',
      'status': 'Disponible',
    });
  }

  group('backup / restore (Phase 9.1)', () {
    test(
      'VACUUM INTO yields a consistent, independently-valid snapshot',
      () async {
        await putItem('BK01', 'Backed Up');
        final backup = p.join(tmp.path, 'snap1.db');

        await svc.backupDatabase(backup);

        expect(await File(backup).exists(), isTrue);
        final probe = await _openReadOnly(backup);
        try {
          final integrity = await probe.rawQuery('PRAGMA integrity_check');
          expect(
            integrity.first.values.first,
            'ok',
            reason: 'the backup must pass integrity_check (not a torn copy)',
          );
          final rows = await probe.rawQuery(
            "SELECT designation FROM library_items WHERE code='BK01'",
          );
          expect(rows.single['designation'], 'Backed Up');
        } finally {
          await probe.close();
        }
      },
    );

    test('restore of a valid backup replaces the live data', () async {
      // backup snapshot already taken above contains BK01 only.
      await putItem('LIVE2', 'Added After Backup');
      expect(await liveCount('LIVE2'), 1);

      await svc.restoreDatabase(p.join(tmp.path, 'snap1.db'));

      // The reopened live DB matches the snapshot: BK01 present, LIVE2 gone.
      expect(await liveCount('BK01'), 1);
      expect(await liveCount('LIVE2'), 0);
      // A pre-restore safety snapshot of the previous live DB was written.
      expect(await File('$livePath.pre_restore').exists(), isTrue);
    });

    test(
      'a non-database file is rejected and leaves the live DB untouched',
      () async {
        await putItem('KEEP1', 'Must Survive');
        final bad = File(p.join(tmp.path, 'garbage.db'));
        await bad.writeAsBytes(List<int>.generate(4096, (i) => (i * 7) % 256));

        await expectLater(
          svc.restoreDatabase(bad.path),
          throwsA(isA<RestoreException>()),
        );

        // Live DB is still open and intact.
        expect(await liveCount('KEEP1'), 1);
      },
    );

    test(
      'a valid SQLite db that is not a library backup is rejected',
      () async {
        final foreign = p.join(tmp.path, 'foreign.db');
        final other = await databaseFactoryFfi.openDatabase(
          foreign,
          options: OpenDatabaseOptions(singleInstance: false),
        );
        await other.execute('CREATE TABLE unrelated(id INTEGER PRIMARY KEY)');
        await other.close();

        await expectLater(
          svc.restoreDatabase(foreign),
          throwsA(isA<RestoreException>()),
        );
        expect(
          await liveCount('KEEP1'),
          1,
          reason: 'the live library must survive a rejected foreign restore',
        );
      },
    );

    test('a missing backup path is rejected before anything happens', () async {
      await expectLater(
        svc.restoreDatabase(p.join(tmp.path, 'does_not_exist.db')),
        throwsA(isA<RestoreException>()),
      );
    });
  });
}

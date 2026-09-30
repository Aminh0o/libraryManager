import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/services/database_service.dart';

/// Real-file DB so backup CREATION + post-write verification (BR-02 / REL-01)
/// run exactly as on a host. The documents dir is faked so the `library_backups`
/// safety files land in a throwaway directory.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.documentsPath);
  final String documentsPath;
  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

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

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('lib_bverify_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    await svc.database;
    final db = await svc.database;
    await db.insert('library_items', {
      'code': 'BVAL',
      'code_type': 'LIV',
      'designation': 'Verified',
      'quantite': 1,
      'emplacement': 'A',
      'taux': 0,
      'emplacement_stock': 'S',
      'status': 'Disponible',
    });
  });

  tearDownAll(() async {
    final db = await svc.database;
    if (db.isOpen) await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('backup integrity verified at creation (BR-02 / REL-01)', () {
    test('a produced backup is a complete, restorable snapshot', () async {
      final path = await svc.createSafetyBackup('verify');
      expect(File(path).existsSync(), isTrue);

      // createSafetyBackup -> backupDatabase -> verifyBackupOrThrow already ran
      // and PASSED (it would have thrown otherwise). Independently confirm the
      // artifact on disk is genuinely restorable and carries the data.
      final probe = await _openReadOnly(path);
      try {
        final ok = await probe.rawQuery('PRAGMA integrity_check');
        expect('${ok.first.values.first}', 'ok');
        final kept = await probe
            .rawQuery('SELECT COUNT(*) c FROM library_items WHERE code = ?',
                ['BVAL']);
        expect(kept.first['c'], 1);
      } finally {
        await probe.close();
      }
    });

    test('a non-database file is rejected by the verifier', () async {
      final bad = File(p.join(tmp.path, 'garbage.db'))
        ..writeAsBytesSync(utf8.encode('this is not a sqlite database'));
      await expectLater(
        () => svc.verifyBackupOrThrow(bad.path),
        throwsA(isA<BackupFailedException>()),
      );
    });

    test('a truncated backup (crash mid-write) is rejected', () async {
      // Simulate REL-01: a snapshot cut off so only its header magic survives.
      final good = await svc.createSafetyBackup('totrunc');
      final bytes = await File(good).readAsBytes();
      final header = bytes.sublist(0, 8); // magic prefix only
      final trunc = File(p.join(tmp.path, 'truncated.db'))
        ..writeAsBytesSync(header);
      await expectLater(
        () => svc.verifyBackupOrThrow(trunc.path),
        throwsA(isA<BackupFailedException>()),
      );
    });

    test('a valid, integral backup passes the verifier', () async {
      final good = await svc.createSafetyBackup('vgood');
      await svc.verifyBackupOrThrow(good); // must NOT throw
    });
  });
}

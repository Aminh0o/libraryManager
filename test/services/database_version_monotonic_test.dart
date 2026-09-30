import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/services/database_service.dart';

/// DB-06 / RC-06: `metadata.db_version` is a CHANGE TOKEN (clients only compare
/// it for inequality), but it used to be written as a bare
/// `millisecondsSinceEpoch`. Two commits inside the same millisecond produced an
/// IDENTICAL token, and a host clock rollback produced a LOWER one -- either way
/// a polling LAN client saw "no change" and silently missed the write. The
/// stamper now reads the current token in-transaction and guarantees strict
/// monotonicity. Runs against a real file DB exactly as on a host.
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

  LibraryItem item(String code) => LibraryItem(
        code: code,
        codeType: 'LIV',
        designation: 'Title $code',
        quantite: 1,
        emplacement: 'A',
        taux: 0,
        emplacementStock: 'S',
      );

  Future<int> version() async => int.tryParse(await svc.getDbVersion()) ?? 0;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('lib_version_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    db = await svc.database;
  });

  tearDownAll(() async {
    if (db.isOpen) await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('db_version change token is strictly monotonic (DB-06 / RC-06)', () {
    test('rapid same-ms commits always advance the token and never repeat it',
        () async {
      final seen = <int>{};
      for (var i = 0; i < 10; i++) {
        final before = await version();
        await svc.addItem(item('v$i'));
        final after = await version();
        expect(after, greaterThan(before),
            reason: 'each commit must advance the token, even in the same ms');
        seen.add(after);
      }
      expect(seen.length, 10, reason: 'no two commits may share a token');
    });

    test('a host clock rollback cannot stall client refresh', () async {
      // Force the token far into the future (as if the clock had been ahead,
      // then rolled back). The next commit must still INCREASE the token, never
      // reset it to wall-clock now (which would be <= the old value and read as
      // "no change" to every client).
      final future =
          DateTime.now().millisecondsSinceEpoch + 10 * 60 * 60 * 1000;
      await db.insert('metadata',
          {'key': 'db_version', 'value': future.toString()},
          conflictAlgorithm: ConflictAlgorithm.replace);

      await svc.addItem(item('clk'));
      expect(await version(), greaterThan(future));
    });
  });
}

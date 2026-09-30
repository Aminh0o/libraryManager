import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/services/database_service.dart';

/// Pass 5: `getHistory(subject:)` narrows the audit query to rows whose
/// `details` mention [subject]. Runs against a real file DB (the same engine
/// a host uses) so the LIKE + ESCAPE SQL is exercised verbatim, not mocked
/// away. Three properties pinned:
///  * a subject filter returns ONLY the matching rows in DESC order,
///  * empty string behaves like "no filter" (never accidentally LIKE '%%'),
///  * null keeps the pre-Pass-5 unfiltered behaviour, so the existing 723
///    baseline callers cannot regress.
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

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('lib_histsubject_');
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

  Future<void> seed(String details, String stamp) async {
    await svc.addHistoryEntry({
      'timestamp': stamp,
      'operation': 'UPDATE',
      'details': details,
      'user': 'tester',
    });
  }

  test('subject narrows the response to matching rows in timestamp DESC',
      () async {
    // Wipe any prior rows so ordering assertions are deterministic.
    final db = await svc.database;
    await db.delete('history');
    await seed('Copie #1 de BK-001 -> available', '2026-01-01T10:00:00.000');
    await seed('Copie #2 de BK-001 -> maintenance', '2026-01-02T10:00:00.000');
    await seed('Emprunt: BK-001 par Amira', '2026-01-03T10:00:00.000');
    await seed('Hold placed: M-999 for BK-777', '2026-01-04T10:00:00.000');
    await seed('Item ajouté: M-999', '2026-01-05T10:00:00.000');

    final hits = await svc.getHistory(subject: 'BK-001', limit: 50);
    expect(hits.length, 3);
    // DESC order: the most-recent (2026-01-03) comes first.
    expect(hits.first['timestamp'], '2026-01-03T10:00:00.000');
    expect(hits.last['timestamp'], '2026-01-01T10:00:00.000');
    // Sanity: none of the two non-matching rows leaked in.
    expect(
      hits.any((r) => (r['details'] as String).contains('BK-777')),
      isFalse,
    );
  });

  test('empty-string subject behaves like no filter (never LIKE \'%%\')',
      () async {
    final byEmpty = await svc.getHistory(subject: '', limit: 50);
    final byNull = await svc.getHistory(limit: 50);
    expect(byEmpty.length, byNull.length);
    expect(byEmpty.length, 5);
  });

  test('null subject preserves the pre-Pass-5 unfiltered behaviour',
      () async {
    final rows = await svc.getHistory(limit: 50);
    // Every seeded row from the previous test is still present: 3 BK-001,
    // 1 BK-777, 1 M-999.
    expect(rows.length, 5);
    expect(rows.first['timestamp'], '2026-01-05T10:00:00.000');
  });
}

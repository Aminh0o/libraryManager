import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/models/member.dart';
import 'package:library_manager/services/database_service.dart';

/// BE-07 / BE-08: `generateNextCode` must not be poisoned by legacy non-numeric
/// codes, and a duplicate item `code` / member `member_id` must fail as a clean
/// typed conflict (that the server maps to 409) instead of a raw PRIMARY KEY /
/// UNIQUE ConstraintError -> opaque 500. Runs against a real file DB so the
/// production schema (library_items, item_copies, members, history, metadata)
/// is exactly what a host uses.
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

  LibraryItem item(String code, {String type = 'LIV'}) => LibraryItem(
        code: code,
        codeType: type,
        designation: 'Title $code',
        quantite: 1,
        emplacement: 'A',
        taux: 10,
        emplacementStock: 'S',
        status: 'Disponible',
      );
  Member member(String id) => Member(
        firstName: 'A',
        lastName: 'B',
        memberId: id,
        registeredAt: DateTime(2026, 1, 1),
      );

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('lib_codeconf_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    db = await svc.database;
  });

  tearDownAll(() async {
    if (db.isOpen) await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('code/member uniqueness + generation (BE-07 / BE-08 / Phase 9.8)', () {
    test('generateNextCode ignores non-numeric legacy codes', () async {
      // A legacy "12A" code made the old CAST(...) ORDER BY treat it as the
      // highest, then int.tryParse("12A") == null -> restart at 0001 and collide.
      await svc.addItem(item('0009'));
      await svc.addItem(item('12A'));
      expect(await svc.generateNextCode('LIV'), '0010');
      // An empty type still starts at 0001.
      expect(await svc.generateNextCode('THE'), '0001');
    });

    test('a duplicate item code throws ItemCodeConflictException, not a 500',
        () async {
      await svc.addItem(item('7000'));
      await expectLater(
          svc.addItem(item('7000')), throwsA(isA<ItemCodeConflictException>()));
      // Exactly one row survived and its copies were not double-seeded (the
      // whole second add rolled back).
      final rows = await db.query('library_items', where: "code = '7000'");
      expect(rows, hasLength(1));
      final copies = await db.query('item_copies', where: "item_code = '7000'");
      expect(copies, hasLength(1));
    });

    test('a duplicate member card id throws MemberIdConflictException',
        () async {
      await svc.addMember(member('CARD-77'));
      await expectLater(svc.addMember(member('CARD-77')),
          throwsA(isA<MemberIdConflictException>()));
      final rows =
          await db.query('members', where: "member_id = 'CARD-77'");
      expect(rows, hasLength(1));
    });

    test('distinct codes/ids still insert normally', () async {
      await svc.addItem(item('8001'));
      await svc.addItem(item('8002'));
      expect(
          await db.query('library_items', where: "code IN ('8001','8002')"),
          hasLength(2));
    });
  });
}

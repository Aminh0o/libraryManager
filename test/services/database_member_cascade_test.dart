import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/models/loan.dart';
import 'package:library_manager/models/member.dart';
import 'package:library_manager/services/database_service.dart';

/// DB-01 application-layer integrity (Phase 4.4): `loans` join members on the
/// TEXT `member_id`, but `updateMember` writes by numeric `id`. Renaming a
/// card id used to silently orphan that member's loan history -- and blind
/// `deleteMember`'s active-loan guard, which looks loans up by the NEW id. Runs
/// against a REAL file database via the production `DatabaseService`.
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
    tmp = Directory.systemTemp.createTempSync('lib_member_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    final db = await svc.database;
    // DB-01 (v17): loans.item_code now carries a real FOREIGN KEY to
    // library_items(code). addLoan below reuses the item code 'IT1', so seed
    // that parent once (per shared file DB) -- otherwise the FK correctly
    // rejects every loan and the fixture is an orphan. The behavior under test
    // (member_id cascade) is unrelated to items and stays fully exercised.
    await db.insert('library_items', {'code': 'IT1', 'designation': 'Test item'});
  });

  tearDownAll(() async {
    final db = await svc.database;
    if (db.isOpen) await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<int> addMember(String cardId) async {
    await svc.addMember(Member(
      firstName: cardId,
      lastName: 'Doe',
      memberId: cardId,
      registeredAt: DateTime(2020),
    ));
    final db = await svc.database;
    final r = await db
        .query('members', columns: ['id'], where: 'member_id = ?', whereArgs: [cardId]);
    return r.first['id'] as int;
  }

  Future<void> addLoan(String cardId, {String status = 'Active'}) async {
    final db = await svc.database;
    await db.insert('loans', {
      'item_code': 'IT1',
      'member_id': cardId,
      'member_name': 'n',
      'item_title': 't',
      'loan_date': '2020-01-01',
      'due_date': '2099-01-01',
      'status': status,
    });
  }

  Future<int> loanCount(String cardId) async {
    final db = await svc.database;
    final r = await db
        .rawQuery('SELECT COUNT(*) c FROM loans WHERE member_id = ?', [cardId]);
    return r.first['c'] as int;
  }

  Future<String?> cardIdOf(int id) async {
    final db = await svc.database;
    final r = await db
        .query('members', columns: ['member_id'], where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : r.first['member_id'] as String?;
  }

  Member memberWithCard(int id, String cardId, {String? phone}) => Member(
        id: id,
        firstName: cardId,
        lastName: 'Doe',
        email: null,
        phone: phone,
        memberId: cardId,
        registeredAt: DateTime(2020),
      );

  group('updateMember member_id cascade (DB-01 / Phase 4.4)', () {
    test('renaming a card id cascades to the member loans', () async {
      final id = await addMember('AA0001');
      await addLoan('AA0001');
      await addLoan('AA0001', status: 'Returned');
      expect(await loanCount('AA0001'), 2);

      await svc.updateMember(memberWithCard(id, 'AA0099'));

      expect(await cardIdOf(id), 'AA0099');
      expect(await loanCount('AA0099'), 2,
          reason: 'both loans must follow the renamed member');
      expect(await loanCount('AA0001'), 0,
          reason: 'no history may be left on the stale id');
    });

    test('a rename onto another member is rejected and changes nothing',
        () async {
      final a = await addMember('BB0001');
      await addMember('CC0001');
      await addLoan('BB0001');

      await expectLater(
        svc.updateMember(memberWithCard(a, 'CC0001')),
        throwsA(isA<MemberIdConflictException>()),
      );

      // Atomic rollback: A keeps its card, its loans are intact, B untouched.
      expect(await cardIdOf(a), 'BB0001');
      expect(await loanCount('BB0001'), 1);
      expect(await loanCount('CC0001'), 0);
    });

    test('an edit that keeps the card id does not touch loans', () async {
      final id = await addMember('DD0001');
      await addLoan('DD0001');

      await svc.updateMember(memberWithCard(id, 'DD0001', phone: '555'));

      expect(await cardIdOf(id), 'DD0001');
      expect(await loanCount('DD0001'), 1, reason: 'no spurious cascade');
      final db = await svc.database;
      final r = await db
          .query('members', columns: ['phone'], where: 'id = ?', whereArgs: [id]);
      expect(r.first['phone'], '555');
    });

    test('cascade un-blinds the delete guard for an active loan', () async {
      final id = await addMember('EE0001');
      await addLoan('EE0001', status: LoanStatus.active.storage);
      await svc.updateMember(memberWithCard(id, 'EE0099'));

      // After the cascade the active loan is reachable under the NEW id, so
      // deleting the member must be refused (previously the guard looked up the
      // stale id, found nothing, and let an active loan orphan).
      await expectLater(
        svc.deleteMember('EE0099'),
        throwsA(isA<ActiveLoanConflictException>()),
      );
      expect(await loanCount('EE0099'), 1);
    });
  });
}

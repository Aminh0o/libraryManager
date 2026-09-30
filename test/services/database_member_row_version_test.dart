import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/domain/loan_transitions.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/models/member.dart';
import 'package:library_manager/services/database_service.dart';

/// TX-06b (lost updates on the MEMBER row). P9-9.46 opted the ITEM whole-row
/// save into optimistic concurrency; the named residual was that the members
/// edit (`PUT /members`) stayed last-write-wins -- two clients editing the same
/// patron silently clobbered each other. `members` now carries its own per-row
/// `row_version` token (schema v17 -> v18, added DEFENSIVELY so a legacy /
/// partial install can never abort onUpgrade -- the DB-08 boot-loop mode) that
/// the repository advances on every successful write, and `updateMember` accepts
/// an OPTIONAL `expectedVersion` (the version the caller read): when supplied a
/// mismatch refuses the write with a typed `ConcurrentUpdateConflictException`
/// (the server maps it to 409) and NOTHING commits -- the rename cascade, the
/// audit line and the token all roll back together, because the guard runs
/// inside the mutation transaction. A null `expectedVersion` keeps the
/// unconditional host/legacy write but still advances the token. Runs against a
/// real file DB so the actual column, migration and transactional rollback are
/// exercised.
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
  final reg = DateTime(2026, 1, 1);

  Member member(String cardId, {String first = 'Alice', String last = 'Doe'}) =>
      Member(
        firstName: first,
        lastName: last,
        memberId: cardId,
        registeredAt: reg,
      );

  LibraryItem item(String code) => LibraryItem.fromMap({
    'code': code,
    'code_type': 'LIV',
    'designation': 'Title',
    'quantite': 1,
    'emplacement': 'A',
    'taux': 10,
    'emplacement_stock': 'S',
    'status': 'Disponible',
  });

  Future<Map<String, dynamic>?> rowByCard(String cardId) async {
    final r = await db.query(
      'members',
      where: 'member_id = ?',
      whereArgs: [cardId],
    );
    return r.isEmpty ? null : r.first;
  }

  Future<int> versionByCard(String cardId) async =>
      ((await rowByCard(cardId))!['row_version'] as num).toInt();

  /// A client edits a row it has READ, so the outbound Member always carries the
  /// database `id` (the row locator). Resolve it by card id before updating --
  /// exactly what `getMembers` -> the edit dialog does in the real app.
  Future<Member> edit(String cardId, {String first = 'Alice'}) async {
    final r = (await rowByCard(cardId))!;
    return Member(
      id: r['id'] as int,
      firstName: first,
      lastName: 'Doe',
      memberId: cardId,
      registeredAt: reg,
      rowVersion: (r['row_version'] as num).toInt(),
    );
  }

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('lib_memver_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    db = await svc.database; // opens + creates the production schema
  });

  tearDownAll(() async {
    if (db.isOpen) await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('member per-row optimistic concurrency token (TX-06b)', () {
    test(
      'the members table carries a row_version column (schema v18)',
      () async {
        final cols = await db.rawQuery('PRAGMA table_info(members)');
        expect(cols.map((c) => c['name']), contains('row_version'));
      },
    );

    test('a freshly added member starts at row_version 0', () async {
      await svc.addMember(member('M100'));
      expect(await rowByCard('M100'), isNotNull);
      expect(await versionByCard('M100'), 0);
    });

    test('an update carrying the matching expected version commits and '
        'advances the token', () async {
      await svc.addMember(member('M200', first: 'Original'));
      final id = (await rowByCard('M200'))!['id'] as int;
      expect(await versionByCard('M200'), 0);

      await svc.updateMember(
        await edit('M200', first: 'Edited'),
        expectedVersion: 0,
      );

      expect((await rowByCard('M200'))!['first_name'], 'Edited');
      expect(await versionByCard('M200'), 1);
      final reloaded = (await svc.getMembers()).firstWhere((m) => m.id == id);
      expect(
        reloaded.rowVersion,
        1,
        reason:
            'the fresh token is surfaced on reads so a client can send '
            'it back on its next edit',
      );
    });

    test('an update carrying a STALE expected version is refused and nothing '
        'clobbers (the lost-update guard)', () async {
      await svc.addMember(member('M300', first: 'Real'));
      await svc.updateMember(
        await edit('M300', first: 'Real'),
        expectedVersion: 0,
      ); // -> v1
      expect(await versionByCard('M300'), 1);

      // A second client still believing the row is at v0 tries to overwrite it.
      await expectLater(
        svc.updateMember(
          await edit('M300', first: 'Clobber'),
          expectedVersion: 0,
        ),
        throwsA(isA<ConcurrentUpdateConflictException>()),
      );
      expect((await rowByCard('M300'))!['first_name'], 'Real');
      expect(await versionByCard('M300'), 1);
    });

    test('a null expected version is an unconditional (host/legacy) write '
        'that still advances the token', () async {
      await svc.addMember(member('M400', first: 'V0'));
      expect(await versionByCard('M400'), 0);

      await svc.updateMember(await edit('M400', first: 'V1'));
      expect((await rowByCard('M400'))!['first_name'], 'V1');
      expect(await versionByCard('M400'), 1);

      await svc.updateMember(await edit('M400', first: 'V2'));
      expect((await rowByCard('M400'))!['first_name'], 'V2');
      expect(await versionByCard('M400'), 2);

      // And an optimistic write against the now-stale version 1 is refused.
      await expectLater(
        svc.updateMember(
          await edit('M400', first: 'Stale'),
          expectedVersion: 1,
        ),
        throwsA(isA<ConcurrentUpdateConflictException>()),
      );
      expect((await rowByCard('M400'))!['first_name'], 'V2');
    });

    test('a REFUSED rename does not cascade to loans and does not move the '
        'token (rollback is whole-transaction)', () async {
      // Seed a parent item (loans.item_code carries an FK), add a member, then
      // a loan that references BOTH the member's card id and the item.
      await svc.addItem(item('TXB1'));
      await svc.addMember(member('M500', first: 'Renamer'));
      await svc.addLoan(
        LoanTransitions.checkOut(
          itemCode: 'TXB1',
          memberId: 'M500',
          memberName: 'Renamer Doe',
          itemTitle: 'Title',
          now: reg,
        ),
      );

      // Bump the member to v1 with a legitimate write so v0 is now stale.
      await svc.updateMember(
        await edit('M500', first: 'Renamer'),
        expectedVersion: 0,
      );
      expect(await versionByCard('M500'), 1);

      // A STALE RENAME attempt (row id = M500's, new card id M501, still
      // believing the version is 0) must be refused BEFORE the loans cascade
      // runs -- proving the guarded write + the rename cascade + audit share one
      // transaction and nothing half-applies.
      final rowId = (await rowByCard('M500'))!['id'] as int;
      final staleRename = Member(
        id: rowId,
        firstName: 'Renamer',
        lastName: 'Doe',
        memberId: 'M501',
        registeredAt: reg,
        rowVersion: 0,
      );
      await expectLater(
        svc.updateMember(staleRename, expectedVersion: 0),
        throwsA(isA<ConcurrentUpdateConflictException>()),
      );

      final kept = await db.query(
        'loans',
        where: 'member_id = ?',
        whereArgs: ['M500'],
      );
      expect(
        kept,
        isNotEmpty,
        reason: 'the refused rename must NOT have cascaded the loan to M501',
      );
      final moved = await db.query(
        'loans',
        where: 'member_id = ?',
        whereArgs: ['M501'],
      );
      expect(moved, isEmpty);
      expect(await versionByCard('M500'), 1);
      expect((await rowByCard('M500'))!['member_id'], 'M500');
    });

    test('optimistic save targeting a row deleted mid-session is refused, '
        'not silently re-inserted', () async {
      await svc.addMember(member('M600'));
      // Delete it out from under a client that still holds version 0.
      await db.delete('members', where: 'member_id = ?', whereArgs: ['M600']);

      await expectLater(
        svc.updateMember(member('M600', first: 'Ghost'), expectedVersion: 0),
        throwsA(isA<ConcurrentUpdateConflictException>()),
      );
      expect(await rowByCard('M600'), isNull);
    });
  });
}

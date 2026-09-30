import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/domain/loan_transitions.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/models/loan.dart';
import 'package:library_manager/services/database_service.dart';

/// TX-06 (lost updates). A whole-row PUT used to overwrite whatever was stored,
/// so two clients editing the same title concurrently silently clobbered each
/// other (last-write-wins). `library_items` now carries a per-row `row_version`
/// token that the repository advances on every successful write, and
/// `updateItem` accepts an OPTIONAL `expectedVersion` (the version the caller
/// read): when supplied, a mismatch refuses the write with a typed
/// `ConcurrentUpdateConflictException` (the server maps it to 409) and NOTHING
/// commits -- data, copies, audit and version all roll back together, because
/// the guard runs inside the mutation transaction. A null `expectedVersion`
/// keeps the unconditional host/legacy write, but still advances the token so a
/// future optimistic check is meaningful. Runs against a real file DB so the
/// actual column, migration and transactional rollback are exercised.
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

  LibraryItem item(String code,
      {String designation = 'Title', int quantite = 1, String? barcode}) {
    final m = <String, dynamic>{
      'code': code,
      'code_type': 'LIV',
      'designation': designation,
      'quantite': quantite,
      'emplacement': 'A',
      'taux': 10,
      'emplacement_stock': 'S',
      'status': 'Disponible',
    };
    if (barcode != null) m['barcode'] = barcode;
    return LibraryItem.fromMap(m);
  }

  Future<Map<String, dynamic>?> row(String code) async {
    final r = await db
        .query('library_items', where: 'code = ?', whereArgs: [code]);
    return r.isEmpty ? null : r.first;
  }

  Future<int> version(String code) async =>
      ((await row(code))!['row_version'] as num).toInt();

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('lib_rowver_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    db = await svc.database; // opens + creates the production schema
  });

  tearDownAll(() async {
    if (db.isOpen) await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('per-row optimistic concurrency token (TX-06)', () {
    test('a freshly added item starts at row_version 0', () async {
      await svc.addItem(item('V100'));
      expect(await version('V100'), 0);
    });

    test('an update carrying the matching expected version commits and '
        'advances the token', () async {
      await svc.addItem(item('V200', designation: 'Original'));
      expect(await version('V200'), 0);

      await svc.updateItem(item('V200', designation: 'Edited'),
          expectedVersion: 0);

      expect((await row('V200'))!['designation'], 'Edited');
      expect(await version('V200'), 1);
    });

    test('an update carrying a STALE expected version is refused and rolls '
        'back everything (no silent clobber)', () async {
      await svc.addItem(item('V300', designation: 'Real'));
      // Bump the row to version 1 via a legitimate write.
      await svc.updateItem(item('V300', designation: 'Real'),
          expectedVersion: 0);
      expect(await version('V300'), 1);

      // A second client that still believes the row is at version 0 tries to
      // overwrite it. The write must be refused, not applied.
      await expectLater(
        svc.updateItem(item('V300', designation: 'Clobber'),
            expectedVersion: 0),
        throwsA(isA<ConcurrentUpdateConflictException>()),
      );

      // The stored row is untouched: same designation AND same version, so the
      // concurrent edit did not win and no half-write landed.
      expect((await row('V300'))!['designation'], 'Real');
      expect(await version('V300'), 1);
    });

    test('the stale-version refusal is a typed conflict, not a raw '
        'DatabaseException (regression guard)', () async {
      await svc.addItem(item('V400'));
      await svc.updateItem(item('V400'), expectedVersion: 0); // -> v1
      Object? caught;
      try {
        await svc.updateItem(item('V400', designation: 'Bad'),
            expectedVersion: 0); // stale
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<ConcurrentUpdateConflictException>());
      expect(caught, isNot(isA<DatabaseException>()));
    });

    test('a null expected version is an unconditional (host/legacy) write '
        'that still advances the token', () async {
      await svc.addItem(item('V500', designation: 'V0'));
      expect(await version('V500'), 0);

      // Host path never sends a version -> today's behavior (always succeeds),
      // but the token climbs so a later optimistic check would catch staleness.
      await svc.updateItem(item('V500', designation: 'V1'));
      expect((await row('V500'))!['designation'], 'V1');
      expect(await version('V500'), 1);

      await svc.updateItem(item('V500', designation: 'V2'));
      expect((await row('V500'))!['designation'], 'V2');
      expect(await version('V500'), 2);

      // And an optimistic write against the now-stale version 1 is refused.
      await expectLater(
        svc.updateItem(item('V500', designation: 'Stale'), expectedVersion: 1),
        throwsA(isA<ConcurrentUpdateConflictException>()),
      );
      expect((await row('V500'))!['designation'], 'V2');
    });

    test('updating a row that no longer exists is refused, not created',
        () async {
      await expectLater(
        svc.updateItem(item('GONE', designation: 'ghost'), expectedVersion: 0),
        throwsA(isA<ConcurrentUpdateConflictException>()),
      );
      expect(await row('GONE'), isNull);
    });
  });

  // TX-06 opt-in (P9-9.46): a loan checkout/return rewrites the title's derived
  // status, so it MUST advance `row_version` too -- otherwise a client that read
  // the row before the loan would keep passing its optimistic check and
  // silently clobber the loan-derived status with a stale whole-row edit.
  group('loan writes advance the concurrency token (TX-06 opt-in)', () {
    final now = DateTime(2026, 1, 1, 12);
    Loan loanFor(String code) => LoanTransitions.checkOut(
          itemCode: code,
          memberId: '250001',
          memberName: 'Alice',
          itemTitle: 'Title',
          now: now,
        );

    test('a copy-level checkout bumps row_version so a pre-loan edit is refused',
        () async {
      await svc.addItem(item('L100')); // seeds physical copies -> v0
      final vBefore = await version('L100');
      expect(vBefore, 0);

      await svc.addLoan(loanFor('L100'));

      // The status re-derivation advanced the token: a client still holding
      // v0 can no longer overwrite the (now Emprunté) row.
      final vAfter = await version('L100');
      expect(vAfter, greaterThan(vBefore));
      await expectLater(
        svc.updateItem(item('L100', designation: 'Stale clobber'),
            expectedVersion: vBefore),
        throwsA(isA<ConcurrentUpdateConflictException>()),
      );
      expect((await row('L100'))!['designation'], 'Title',
          reason: 'the refused edit must not have landed');
    });

    test('a return also bumps the token, and a whole-row write against the '
        'fresh version still succeeds', () async {
      await svc.addItem(item('L200'));
      await svc.addLoan(loanFor('L200'));
      final active = (await svc.getLoans(activeOnly: true))
          .firstWhere((l) => l.itemCode == 'L200');

      await svc.updateLoan(
          LoanTransitions.returnLoan(active, when: now.add(const Duration(days: 2))));

      final vNow = await version('L200');
      // An edit carrying the CURRENT token is accepted (not locked out) and
      // advances it once more -- proving the bump does not wedge editing.
      await svc.updateItem(item('L200', designation: 'Renamed'),
          expectedVersion: vNow);
      expect((await row('L200'))!['designation'], 'Renamed');
      expect(await version('L200'), greaterThan(vNow));
    });
  });
}

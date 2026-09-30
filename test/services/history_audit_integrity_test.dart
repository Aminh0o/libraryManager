import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/services/database_service.dart';

/// DB-05: the `history` audit table has a fixed schema (id/timestamp/operation/
/// details/user) with an AUTOINCREMENT primary key. Before the fix,
/// `addHistoryEntry` inserted the caller's map RAW, so a client-supplied `id`
/// could collide with the sequence (ConstraintError) or an unknown column blow
/// up ("no such column") -- both 500s -- and a spoofed id could overwrite a row.
/// The repository now projects onto the known columns and lets the sequence
/// assign the id. This runs against a real file DB exactly as on a host.
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
    tmp = Directory.systemTemp.createTempSync('lib_histaudit_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    await svc.database; // opens + creates the production schema
  });

  tearDownAll(() async {
    final db = await svc.database;
    if (db.isOpen) await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<Map<String, dynamic>?> findByOperation(String op) async {
    final rows = await svc.getHistory(limit: 500);
    for (final r in rows) {
      if (r['operation'] == op) return r;
    }
    return null;
  }

  group('audit history integrity (DB-05 / Phase 9.7)', () {
    test(
      'an unknown column is dropped instead of throwing "no such column"',
      () async {
        // Without the whitelist this insert throws a DatabaseException, which the
        // server surfaces as a 500.
        await svc.addHistoryEntry({
          'operation': 'UNKNOWN_COL',
          'details': 'd',
          'user': 'u',
          'evil': 'should-be-ignored',
        });
        final row = await findByOperation('UNKNOWN_COL');
        expect(row, isNotNull);
        expect(row!['details'], 'd');
        expect(row.containsKey('evil'), isFalse);
      },
    );

    test(
      'a client-supplied id is ignored (never collides or overwrites)',
      () async {
        // Two entries claiming the SAME primary key: raw insert of the second
        // would violate the PK (ConstraintError -> 500). Stripping the id lets
        // the AUTOINCREMENT sequence assign distinct ids and both are kept.
        await svc.addHistoryEntry({
          'id': 999999,
          'operation': 'ID_CLAIM_A',
          'details': 'a',
          'user': 'u',
        });
        await svc.addHistoryEntry({
          'id': 999999,
          'operation': 'ID_CLAIM_B',
          'details': 'b',
          'user': 'u',
        });
        final a = await findByOperation('ID_CLAIM_A');
        final b = await findByOperation('ID_CLAIM_B');
        expect(a, isNotNull);
        expect(b, isNotNull);
        expect(a!['id'], isNot(b!['id']));
        expect(a['id'], isNot(999999));
      },
    );

    test('the known audit columns still round-trip', () async {
      await svc.addHistoryEntry({
        'timestamp': '2020-01-02T03:04:05.000',
        'operation': 'ROUND_TRIP',
        'details': 'hello',
        'user': 'Host',
      });
      final row = await findByOperation('ROUND_TRIP');
      expect(row, isNotNull);
      expect(row!['details'], 'hello');
      expect(row['user'], 'Host');
      expect(row['timestamp'], '2020-01-02T03:04:05.000');
    });
  });

  group('definition mutations are atomically audited (BE-05 / BE-09)', () {
    Future<bool> hasCodeDef(String prefix) async {
      final defs = await svc.getCodeDefinitions();
      return defs.any((d) => d['prefix'] == prefix);
    }

    test(
      'addCodeDefinition commits the row AND its audit line together',
      () async {
        await svc.addCodeDefinition(
          'ZZ',
          'Zzra',
          audit: {
            'timestamp': DateTime.now().toIso8601String(),
            'operation': 'ADD_VAR',
            'details': 'Code definition added: ZZ (Zzra)',
            'user': '10.0.0.5',
          },
        );
        expect(await hasCodeDef('ZZ'), isTrue);
        final logged = await findByOperation('ADD_VAR');
        expect(
          logged,
          isNotNull,
          reason: 'audit is in the same transaction as the insert',
        );
        expect(logged!['user'], '10.0.0.5');
      },
    );

    test(
      'a failing audit write rolls the definition insert back (atomic)',
      () async {
        // The audit row is inserted RAW (server-authored/trusted). A bogus column
        // makes the history insert throw, which must undo the definition insert
        // too -- proving write+audit commit or fail as one unit (TX-01 pattern).
        await expectLater(
          svc.addCodeDefinition(
            'ROLLME',
            'nope',
            audit: {
              'timestamp': DateTime.now().toIso8601String(),
              'operation': 'ADD_VAR',
              'details': 'should roll back',
              'user': 'u',
              'bogus': 'no-such-column',
            },
          ),
          throwsA(isA<DatabaseException>()),
        );
        expect(
          await hasCodeDef('ROLLME'),
          isFalse,
          reason: 'the definition must not survive a failed audit write',
        );
      },
    );
  });
}

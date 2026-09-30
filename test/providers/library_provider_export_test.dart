import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/services/repository.dart';
import 'package:library_manager/services/app_logger.dart';
import 'package:library_manager/services/database_service.dart';
import 'package:library_manager/config/app_info.dart';

/// Records getItems/countItems calls and applies the filters + limit/offset the
/// way the server does, so the test can prove the export reads the WHOLE
/// matching set rather than the cached page (Phase 7 / 7.3, FE-05 / BL-09).
class _ExportFakeRepo implements LibraryRepository {
  _ExportFakeRepo(this.all);

  final List<LibraryItem> all;
  final List<Map<String, Object?>> getItemCalls = [];
  final List<Map<String, Object?>> countCalls = [];

  List<LibraryItem> _match(String? s, String? st, String? ct) => all.where((i) {
    final ms =
        s == null ||
        s.isEmpty ||
        i.designation.toLowerCase().contains(s.toLowerCase()) ||
        i.code.toLowerCase().contains(s.toLowerCase());
    final mst = st == null || i.status == st;
    final mct = ct == null || i.codeType == ct;
    return ms && mst && mct;
  }).toList();

  @override
  Future<List<LibraryItem>> getItems({
    int limit = 1000,
    int offset = 0,
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) async {
    getItemCalls.add({
      'search': search,
      'status': status,
      'codeType': codeType,
      'limit': limit,
      'offset': offset,
    });
    return _match(search, status, codeType).skip(offset).take(limit).toList();
  }

  @override
  Future<int> countItems({
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) async {
    countCalls.add({'search': search, 'status': status, 'codeType': codeType});
    return _match(search, status, codeType).length;
  }

  @override
  Future<List<Map<String, dynamic>>> getCodeDefinitions() async => const [];

  @override
  Future<List<Map<String, dynamic>>> getAttributeDefinitions(
    String? type,
  ) async => const [];

  @override
  Future<Map<String, dynamic>> getStats() async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

String _statusFor(int i) =>
    i <= 40 ? 'Disponible' : (i <= 50 ? 'Emprunté' : 'Reliure');

LibraryItem _mk(int i, {String? designation}) => LibraryItem(
  code: i.toString().padLeft(4, '0'),
  codeType: i % 10 == 0 ? 'REV' : 'LIV',
  designation: designation ?? 'Book $i',
  quantite: 1,
  emplacement: 'R$i',
  taux: 10,
  emplacementStock: 'S$i',
  status: _statusFor(i),
);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

/// Stands in for a working desktop save dialog: [result] is the path the user
/// "picked", or null to simulate cancelling.
class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this.result);
  final String? result;
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async => result;
}

void main() {
  group('LibraryProvider CSV export spans the full set (Phase 7 / 7.3)', () {
    late List<LibraryItem> data;
    late _ExportFakeRepo repo;
    late LibraryProvider provider;

    setUp(() {
      data = [for (var i = 1; i <= 60; i++) _mk(i)];
      repo = _ExportFakeRepo(data);
      provider = LibraryProvider.forTesting(repository: repo);
    });

    test('exports EVERY item, not just the loaded page', () async {
      await provider.reload();
      // The on-screen list is one page (20)...
      expect(provider.items.length, 20);
      // ...but the export reads the whole filtered set from the server.
      final rows = await provider.itemsForExport();
      expect(rows.length, 60);
      expect(rows.last.code, '0060');
      // Fetched with a size equal to the server count, from offset 0.
      final call = repo.getItemCalls.last;
      expect(call['offset'], 0);
      expect(call['limit'], 60);
    });

    test('export respects the active filter', () async {
      provider.filterByStatus('Emprunté');
      await _settle();
      final rows = await provider.itemsForExport();
      expect(rows.length, 10);
      expect(rows.every((i) => i.status == 'Emprunté'), isTrue);
      final call = repo.getItemCalls.last;
      expect(call['status'], 'Emprunté');
      expect(call['limit'], 10);
    });

    test('export respects an active search', () async {
      final rows = await provider.itemsForExport();
      expect(rows.length, 60);

      // Narrow via a search term (mirrors what the UI search box sets).
      provider.search('Book 6');
      await Future<void>.delayed(const Duration(milliseconds: 450));
      final filtered = await provider.itemsForExport();
      // 'Book 6', 'Book 60'.. 'Book 69' are the substring matches in this set.
      expect(filtered.map((i) => i.designation), contains('Book 6'));
      expect(filtered.length, isNot(60));
      expect(repo.getItemCalls.last['search'], 'Book 6');
    });

    test('csvContent quotes fields that would shift columns (BL-09)', () {
      final tricky = LibraryItem(
        code: '0001',
        barcode: 'B,1"2',
        codeType: 'LIV',
        designation: 'Sold, 50% "off"',
        quantite: 2,
        emplacement: 'A\nB',
        taux: 3.5,
        emplacementStock: 'S1',
        status: 'Disponible',
      );
      final csv = provider.csvContent([tricky]);
      final lines = csv.trimRight().split('\n');
      expect(
        lines.first,
        'Code,Barre,Type,Designation,Quantite,Emplacement,Prix,Stock,Statut',
      );
      // Designation with a comma + embedded quotes is wrapped and doubled.
      expect(csv, contains('"Sold, 50% ""off"""'));
      // Barcode containing a comma and a quote is quoted too.
      expect(csv, contains('"B,1""2"'));
      // Multi-line emplacement is quoted so it does not create a fake row.
      expect(csv, contains('"A\nB"'));
      // Exactly one header + one data record worth of top-level newlines once
      // quoted fields are accounted for (the raw \n inside is protected).
      expect(lines.length, greaterThanOrEqualTo(2));
    });

    test('plain fields are left unquoted', () {
      final csv = provider.csvContent([_mk(1)]);
      expect(csv, contains('0001,,LIV,Book 1,1,R1,10.0,S1,Disponible'));
    });

    // NET-11 (P20): the whole-catalogue export now composes its text on a
    // worker isolate. These pins prove the off-isolate path cannot silently
    // diverge from the on-isolate one it replaced.
    group('buildInventoryCsvOffIsolate (NET-11)', () {
      List<List<String?>> cells(List<LibraryItem> items) => [
        for (final item in items)
          [
            item.code,
            item.barcode,
            item.codeType,
            item.designation,
            '${item.quantite}',
            item.emplacement,
            '${item.taux}',
            item.emplacementStock,
            item.status,
          ],
      ];

      test(
        'byte-identical to csvContent, quoting included (BL-09 preserved)',
        () async {
          final items = [
            _mk(1),
            LibraryItem(
              code: '0002',
              barcode: 'B,1"2',
              codeType: 'LIV',
              designation: 'Sold, 50% "off"',
              quantite: 2,
              emplacement: 'A\nB',
              taux: 3.5,
              emplacementStock: 'S1',
              status: 'Emprunt\u00e9',
            ),
          ];
          expect(
            await buildInventoryCsvOffIsolate(cells(items)),
            provider.csvContent(items),
          );
        },
      );

      test('builds a whole-catalogue export off-isolate', () async {
        final many = [for (int i = 1; i <= 2000; i++) _mk(i)];
        final csv = await buildInventoryCsvOffIsolate(cells(many));
        final lines = const LineSplitter().convert(csv);
        expect(
          lines.first,
          'Code,Barre,Type,Designation,Quantite,Emplacement,Prix,Stock,Statut',
        );
        // One line per record plus the header (LineSplitter emits no trailing
        // empty line for the final writeln terminator).
        expect(lines.length, many.length + 1);
        expect(csv, provider.csvContent(many));
      });
    });
  });

  group('LibraryProvider.exportDiagnostics (ARC-06)', () {
    late Directory tmp;
    late AppLogger savedLog;

    setUp(() {
      savedLog = appLog;
      tmp = Directory.systemTemp.createTempSync('lib_diag_');
      // Point the process-wide logger at a real temp file so the bundle has
      // something to collect (and so flush()/readLogContents() are exercised).
      initAppLogging(docsDir: tmp);
    });

    tearDown(() {
      appLog = savedLog;
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test(
      'admin bundle carries version + schema + mode + scrubbed log lines',
      () async {
        appLog.info('auth', 'diag-marker login password=hunter2supersecret ok');
        await appLog.flush();

        final chosen = p.join(tmp.path, 'picked_diagnostics.txt');
        FilePicker.platform = _FakeFilePicker(chosen);
        addTearDown(() => FilePicker.platform = _UnavailableFilePicker());

        final provider = LibraryProvider.forTesting(
          repository: _ExportFakeRepo(const []),
        );
        final path = await provider.exportDiagnostics();

        expect(path, chosen);
        final text = File(chosen).readAsStringSync();
        // Header carries the diagnostic context the plan requires.
        expect(text, contains('app_version: $kAppVersion'));
        expect(
          text,
          contains('db_version: ${DatabaseService.currentSchemaVersion}'),
        );
        expect(text, contains('mode: host'));
        // A real log line survived into the bundle...
        expect(text, contains('diag-marker'));
        // ...but the credential was scrubbed, never leaked verbatim.
        expect(text, isNot(contains('hunter2supersecret')));
        expect(text, contains('password=[redacted]'));
      },
    );

    test(
      'cancelling the save dialog writes nothing and returns null',
      () async {
        appLog.info('r', 'should-not-be-exported');
        await appLog.flush();
        FilePicker.platform = _FakeFilePicker(null); // user cancelled
        addTearDown(() => FilePicker.platform = _UnavailableFilePicker());

        final provider = LibraryProvider.forTesting(
          repository: _ExportFakeRepo(const []),
        );
        final path = await provider.exportDiagnostics();
        expect(path, isNull);
        // No diagnostics file was dropped anywhere under the temp dir.
        final strays = tmp
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (f) => p.basename(f.path).startsWith('library_diagnostics_'),
            );
        expect(strays, isEmpty);
      },
    );

    test('a non-admin is refused before anything is written', () async {
      final chosen = p.join(tmp.path, 'should_not_exist.txt');
      FilePicker.platform = _FakeFilePicker(chosen);
      addTearDown(() => FilePicker.platform = _UnavailableFilePicker());

      // isHost: false with a plain repository reads as viewer (not admin).
      final provider = LibraryProvider.forTesting(
        repository: _ExportFakeRepo(const []),
        isHost: false,
      );
      expect(provider.canAdminister, isFalse);
      await expectLater(
        provider.exportDiagnostics(),
        throwsA(isA<StateError>()),
      );
      expect(File(chosen).existsSync(), isFalse);
    });
  });
}

/// Simulates an unsupported context where the plugin has no OS handler, so
/// [FilePicker.saveFile] throws and the provider falls back to the Documents
/// path. Restored as the global platform between tests.
class _UnavailableFilePicker extends FilePicker {
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    throw UnimplementedError('saveFile() not implemented in test');
  }
}

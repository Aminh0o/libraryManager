import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:library_manager/domain/report_query.dart';
import 'package:library_manager/l10n/app_localizations.dart';
import 'package:library_manager/models/report.dart';
import 'package:library_manager/models/user_account.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/screens/reports_screen.dart';
import 'package:library_manager/services/api_contract.dart';
import 'package:library_manager/services/api_service.dart';
import 'package:library_manager/services/repository.dart';

// Phase 10.4b: the reports SURFACE. These tests drive the real screen against an
// injected repository that hands back a canned, SERVER-authored report, to pin
// that: (1) a read-only session is offered no report surface at all and the
// engine is never even asked; (2) a host runs the report and renders the server
// rows + summary verbatim (no client re-derivation); (3) a malformed date is
// refused locally before any request; (4) a windowless kind hides the dates;
// (5) Export CSV/PDF write the SAME report to disk (exercised against a real
// temp directory via a path_provider fake); and (6) a paired staff client runs
// the report over the real HTTP codec and a server-side (reversed-window) 400 is
// surfaced verbatim rather than pretended applied.

const _canned = Report(
  kind: ReportKind.circulation,
  title: 'Circulation',
  generatedAt: '2026-09-22T10:00:00',
  from: '2026-09-01',
  to: '2026-09-22',
  columns: ['Date', 'Borrowed', 'Returned'],
  rows: [['2026-09-20', '3', '1']],
  summary: {'Borrowed': '3', 'Returned': '1'},
);

/// Returns a canned report and records every ask, so a test can prove a session
/// that is offered no surface never reaches the engine, and that Run / a bad
/// date behave as designed.
class _ReportRepo implements LibraryRepository {
  _ReportRepo({this.report});
  final Report? report;
  int generateAttempts = 0;
  final List<Map<String, String?>> generateCalls = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  @override
  Future<Report> generateReport(
    ReportKind kind, {
    String? from,
    String? to,
  }) async {
    generateAttempts++;
    generateCalls.add({'kind': kind.storage, 'from': from, 'to': to});
    final r = report;
    if (r == null) throw StateError('no canned report');
    return r;
  }
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.documentsPath);
  final String documentsPath;
  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

/// A FilePicker handler that is present but whose `saveFile` throws -- exactly
/// what the provider sees when no real plugin is registered -- so it takes its
/// documented "unsupported -> fall back to Documents" branch.
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

/// A FilePicker standing in for a working desktop save dialog: [result] is the
/// path the user "picked", or null to simulate cancelling.
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
  }) async =>
      result;
}

Future<void> _pump(
  WidgetTester tester,
  LibraryRepository repo, {
  bool isHost = true,
  LibraryRepository? repositoryOverride,
}) async {
  tester.view.physicalSize = const Size(1280, 1024);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final provider = LibraryProvider.forTesting(
    repository: repositoryOverride ?? repo,
    isHost: isHost,
  );

  await tester.pumpWidget(
    ChangeNotifierProvider<LibraryProvider>.value(
      value: provider,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ReportsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A real [ApiService] whose transport is a faithful mini-server over the 10.4a
/// `/reports/<kind>` route (same strict window rule + role semantics), with the
/// session pinned to staff 'libby' -- so the client JSON codec and a server 400
/// are exercised for real rather than stubbed.
ApiService _staffClient(Report canned) {
  Future<http.Response> route(http.Request request) async {
    if (request.headers[apiVersionHeader] == null) {
      return http.Response('unauthorized', 401);
    }
    final path = request.url.path;
    final q = request.url.queryParameters;
    final match = RegExp(r'^/reports/([a-z]+)$').firstMatch(path);
    if (request.method == 'GET' && match != null) {
      final kind = ReportKind.tryParse(match.group(1));
      if (kind == null) {
        return http.Response(
          jsonEncode({'error': 'bad_request', 'message': 'unknown report kind'}),
          400,
        );
      }
      try {
        ReportQuery.window(kind, from: q['from'], to: q['to']);
      } on FormatException catch (e) {
        return http.Response(
          jsonEncode({'error': 'bad_request', 'message': e.message}),
          400,
        );
      }
      return http.Response(jsonEncode(canned.toMap()), 200);
    }
    return http.Response('not found', 404);
  }

  final api = ApiService(hostIp: '127.0.0.1', client: MockClient(route));
  api.sessionRole = UserRole.staff;
  api.sessionUsername = 'libby';
  return api;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a read-only (viewer) session is offered no report surface', (
    tester,
  ) async {
    final repo = _ReportRepo(report: _canned);
    await _pump(tester, repo, isHost: false);

    expect(find.text('Only staff can run reports.'), findsOneWidget);
    expect(find.byKey(const Key('reportRunButton')), findsNothing);
    // The engine is never asked for a session that cannot see reports.
    expect(repo.generateAttempts, 0);
  });

  testWidgets('a host runs a report and renders the server rows + summary', (
    tester,
  ) async {
    final repo = _ReportRepo(report: _canned);
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('reportRunButton')));
    await tester.pumpAndSettle();

    expect(repo.generateAttempts, 1);
    expect(repo.generateCalls.first['kind'], 'circulation');
    // Cells rendered verbatim from the server result.
    expect(find.text('2026-09-20'), findsOneWidget);
    expect(find.text('Borrowed: 3'), findsOneWidget);
    expect(find.text('Returned: 1'), findsOneWidget);
    expect(find.byKey(const Key('reportExportCsv')), findsOneWidget);
    expect(find.byKey(const Key('reportExportPdf')), findsOneWidget);
  });

  testWidgets('a malformed date is refused client-side before any request', (
    tester,
  ) async {
    final repo = _ReportRepo(report: _canned);
    await _pump(tester, repo);

    await tester.enterText(find.byKey(const Key('reportFromField')), 'not-a-date');
    await tester.tap(find.byKey(const Key('reportRunButton')));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid date (YYYY-MM-DD).'), findsOneWidget);
    expect(repo.generateAttempts, 0);
  });

  testWidgets('a windowless report hides the date window', (tester) async {
    final repo = _ReportRepo(report: _canned);
    await _pump(tester, repo);

    // circulation (default) is windowed -> dates shown.
    expect(find.byKey(const Key('reportFromField')), findsOneWidget);

    await tester.tap(find.byKey(const Key('reportKindField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Overdue items').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reportFromField')), findsNothing);
    expect(find.byKey(const Key('reportToField')), findsNothing);
  });

  testWidgets('a run report offers both export buttons', (tester) async {
    // The screen's job is to surface the export affordances over the SAME
    // server-authored report it rendered; the byte-writing itself is proven by
    // the pure builder tests + the provider tests below (real file IO cannot
    // run under the fake-async of a widget test -- the reason the inventory
    // export test also avoids it).
    final repo = _ReportRepo(report: _canned);
    await _pump(tester, repo);
    await tester.tap(find.byKey(const Key('reportRunButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reportExportCsv')), findsOneWidget);
    expect(find.byKey(const Key('reportExportPdf')), findsOneWidget);
  });

  test('provider.exportReportCsv writes the server report to a real file',
    () async {
      final tmp = Directory.systemTemp.createTempSync('lib_provider_csv_');
      PathProviderPlatform.instance = _FakePathProvider(tmp.path);
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      final provider = LibraryProvider.forTesting(
        repository: _ReportRepo(report: _canned),
        isHost: true,
      );
      final report = await provider.generateReport(ReportKind.circulation);
      final path = await provider.exportReportCsv(report);
      expect(path, endsWith('.csv'));
      final content = File(path!).readAsStringSync();
      expect(content, contains('Circulation'));
      expect(content, contains('Date,Borrowed,Returned'));
      expect(content, contains('2026-09-20,3,1'));
    });

  test('provider.exportReportPdf writes a real PDF file', () async {
    final tmp = Directory.systemTemp.createTempSync('lib_provider_pdf_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final provider = LibraryProvider.forTesting(
      repository: _ReportRepo(report: _canned),
      isHost: true,
    );
    final report = await provider.generateReport(ReportKind.circulation);
    final path = await provider.exportReportPdf(report);
    expect(path, endsWith('.pdf'));
    expect(String.fromCharCodes(File(path!).readAsBytesSync().take(4)), '%PDF');
  });

  test('save-as HONORS the path the OS dialog returns (BL-09 / 11b)',
      () async {
    final tmp = Directory.systemTemp.createTempSync('lib_provider_save_');
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final chosen = '${tmp.path}${Platform.pathSeparator}somewhere_else.csv';
    FilePicker.platform = _FakeFilePicker(chosen);
    addTearDown(() => FilePicker.platform = _UnavailableFilePicker());
    final provider = LibraryProvider.forTesting(
      repository: _ReportRepo(report: _canned),
      isHost: true,
    );
    final report = await provider.generateReport(ReportKind.circulation);
    final path = await provider.exportReportCsv(report);
    // The export lands exactly where the (simulated) dialog said, not in the
    // fallback Documents folder.
    expect(path, chosen);
    expect(File(chosen).existsSync(), isTrue);
    expect(File(chosen).readAsStringSync(), contains('Date,Borrowed,Returned'));
  });

  test('cancelling the save dialog writes NOTHING and returns null '
      '(no false success)', () async {
    final tmp = Directory.systemTemp.createTempSync('lib_provider_cancel_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    // A supported handler that returns null == the user dismissed the dialog.
    FilePicker.platform = _FakeFilePicker(null);
    addTearDown(() => FilePicker.platform = _UnavailableFilePicker());
    final provider = LibraryProvider.forTesting(
      repository: _ReportRepo(report: _canned),
      isHost: true,
    );
    final report = await provider.generateReport(ReportKind.circulation);
    final path = await provider.exportReportCsv(report);
    expect(path, isNull);
    // And nothing was written to the would-be fallback Documents folder.
    expect(
      tmp.listSync().whereType<File>().where((f) => f.path.endsWith('.csv')),
      isEmpty,
    );
  });

  testWidgets('a staff client runs the report over HTTP and sees the server rows',
    (tester) async {
      await _pump(
        tester,
        _ReportRepo(),
        isHost: false,
        repositoryOverride: _staffClient(_canned),
      );

      // staff (canWrite) -> the surface is offered.
      expect(find.byKey(const Key('reportRunButton')), findsOneWidget);
      await tester.tap(find.byKey(const Key('reportRunButton')));
      await tester.pumpAndSettle();

      expect(find.text('2026-09-20'), findsOneWidget);
      expect(find.text('Borrowed: 3'), findsOneWidget);
    });

  testWidgets('a server-side reversed-window refusal is surfaced verbatim', (
    tester,
  ) async {
    await _pump(
      tester,
      _ReportRepo(),
      isHost: false,
      repositoryOverride: _staffClient(_canned),
    );

    // Both dates are individually well-formed, so the client forwards them and
    // the SERVER owns the reversed-window refusal -- shown exactly as authored.
    await tester.enterText(find.byKey(const Key('reportFromField')), '2026-09-30');
    await tester.enterText(find.byKey(const Key('reportToField')), '2026-09-01');
    await tester.tap(find.byKey(const Key('reportRunButton')));
    await tester.pumpAndSettle();

    expect(find.textContaining('The start date is after the end date.'),
        findsOneWidget);
    // Nothing is pretended applied: no report rows are rendered.
    expect(find.text('2026-09-20'), findsNothing);
  });
}

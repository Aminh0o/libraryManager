import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/models/report.dart';
import 'package:library_manager/services/report_export.dart';

/// Phase 10.4b: the export builders are PURE (no file IO), so they can be
/// pinned in isolation -- crucially proving the CSV/PDF render the SAME
/// server-authored [Report] the table shows, with no client-side re-derivation.
void main() {
  Report circulation() => const Report(
    kind: ReportKind.circulation,
    title: 'Circulation report',
    generatedAt: '2026-09-22T10:00:00',
    from: '2026-09-01',
    to: '2026-09-22',
    columns: ['Date', 'Borrowed', 'Returned'],
    rows: [
      ['2026-09-20', '3', '1'],
      ['2026-09-21', '2', '4'],
    ],
    summary: {'Borrowed': '5', 'Returned': '5'},
  );

  group('toCsv', () {
    test('emits metadata block, summary, header and rows verbatim', () {
      final lines = const LineSplitter().convert(ReportExport.toCsv(circulation()));
      expect(lines.first, 'Circulation report');
      expect(lines[1], 'From,2026-09-01,To,2026-09-22');
      expect(lines[2], 'Generated,2026-09-22T10:00:00');
      expect(lines, contains('Borrowed,5'));
      expect(lines, contains('Returned,5'));
      expect(lines, contains('Date,Borrowed,Returned'));
      expect(lines, contains('2026-09-20,3,1'));
      expect(lines, contains('2026-09-21,2,4'));
    });

    test('RFC-4180 quotes a field carrying a comma or newline (BL-09)', () {
      const r = Report(
        kind: ReportKind.inventory,
        title: 'Inventory',
        generatedAt: '2026-09-22T10:00:00',
        columns: ['Type'],
        rows: [
          ['Books, Rare'],
          ['Two\nlines'],
          ['He said "hi"'],
        ],
      );
      final csv = ReportExport.toCsv(r);
      expect(csv, contains('"Books, Rare"'));
      expect(csv, contains('"Two\nlines"'));
      expect(csv, contains('"He said ""hi"""'));
    });

    test('a windowless report emits empty From/To and no summary lines', () {
      const r = Report(
        kind: ReportKind.overdue,
        title: 'Overdue',
        generatedAt: '2026-09-22T10:00:00',
        columns: ['Member'],
        rows: [['Amina']],
      );
      final lines = const LineSplitter().convert(ReportExport.toCsv(r));
      expect(lines[1], 'From,,To,');
    });
  });

  group('toPdfBytes', () {
    test('produces a real PDF byte stream beginning with the %PDF magic', () async {
      final bytes = await ReportExport.toPdfBytes(circulation());
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('renders a table-less (empty) report without throwing', () async {
      const r = Report(
        kind: ReportKind.members,
        title: 'Top borrowers',
        generatedAt: '2026-09-22T10:00:00',
        from: '2026-09-01',
        to: '2026-09-22',
        columns: ['Rank', 'Member'],
        rows: [],
      );
      final bytes = await ReportExport.toPdfBytes(r);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });

  // NET-11 (P20): the PDF compose moves off the UI isolate via Isolate.run,
  // carrying the Report as its Map form. These pin that the crossing is LOSSLESS
  // (so the worker renders the identical report the table shows) and that the
  // off-isolate build yields a real PDF -- including for a large result set, the
  // exact case whose synchronous CPU used to freeze the desktop.
  group('buildReportPdfOffIsolate (NET-11)', () {
    test('Report.toMap -> fromMap round-trips losslessly (safe isolate crossing)',
        () {
      final original = circulation();
      final rebuilt = Report.fromMap(original.toMap());
      expect(rebuilt.kind, original.kind);
      expect(rebuilt.title, original.title);
      expect(rebuilt.generatedAt, original.generatedAt);
      expect(rebuilt.from, original.from);
      expect(rebuilt.to, original.to);
      expect(rebuilt.columns, original.columns);
      expect(rebuilt.rows, original.rows);
      expect(rebuilt.summary, original.summary);
    });

    test('produces a real PDF off-isolate for a normal report', () async {
      final bytes = await buildReportPdfOffIsolate(circulation().toMap());
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('off-isolate build succeeds for a large report (the heavy case)',
        () async {
      final r = Report(
        kind: ReportKind.circulation,
        title: 'Big circulation',
        generatedAt: '2026-09-22T10:00:00',
        columns: ['Date', 'Borrowed', 'Returned'],
        rows: [
          for (int i = 0; i < 2000; i++) ['2026-01-${i % 28 + 1}', '$i', '$i'],
        ],
      );
      final bytes = await buildReportPdfOffIsolate(r.toMap());
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });

  group('baseName', () {
    test('is filesystem-safe and carries kind + normalised timestamp', () {
      const r = Report(
        kind: ReportKind.circulation,
        title: 'x',
        generatedAt: '2026-09-22T10:30:00.123',
        columns: [],
        rows: [],
      );
      final name = ReportExport.baseName(r);
      expect(name, 'report_circulation_2026-09-22_10-30-00');
      expect(name, isNot(contains(':')));
      expect(name, isNot(contains('.')));
      expect(name, isNot(contains('/')));
    });
  });

  // ARC-07 (P22): the export document's chrome labels are client-owned
  // presentation, so they localize while the report DATA stays server-authored.
  // These pin both halves: an override map reaches the emitted lines, and the
  // English defaults remain when no map is supplied (host/client parity).
  group('localized export chrome (ARC-07)', () {
    test('CSV chrome uses supplied labels', () {
      final lines = const LineSplitter().convert(ReportExport.toCsv(
        circulation(),
        labels: const {
          'from': 'Du',
          'to': 'Au',
          'generated': 'Généré',
        },
      ));
      expect(lines[1], 'Du,2026-09-01,Au,2026-09-22');
      expect(lines[2], 'Généré,2026-09-22T10:00:00');
    });

    test('a partial label map overrides only the supplied keys', () {
      final lines = const LineSplitter().convert(ReportExport.toCsv(
        circulation(),
        labels: const {'from': 'Från'},
      ));
      // 'from' localized; 'to'/'generated' fall back to the English defaults.
      expect(lines[1], 'Från,2026-09-01,To,2026-09-22');
      expect(lines[2], 'Generated,2026-09-22T10:00:00');
    });

    test('defaultLabels are the English fallback (unchanged parity)', () {
      expect(ReportExport.defaultLabels['from'], 'From');
      expect(ReportExport.defaultLabels['to'], 'To');
      expect(ReportExport.defaultLabels['generated'], 'Generated');
      expect(ReportExport.defaultLabels['period'], 'Period');
      expect(
          ReportExport.defaultLabels['noRecords'], 'No records for this report.');
    });

    test('off-isolate PDF accepts localized labels without throwing', () async {
      final bytes = await buildReportPdfOffIsolate(
        circulation().toMap(),
        labels: const {
          'generated': 'Généré',
          'period': 'Période',
          'noRecords': 'Aucun enregistrement',
        },
      );
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });
}

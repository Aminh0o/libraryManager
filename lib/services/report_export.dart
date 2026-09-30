import 'dart:isolate';

import 'package:csv/csv.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/report.dart';

/// NET-11 (P20): compose the report PDF OFF the UI isolate. For a large result
/// set, `package:pdf`'s table layout + byte encoding is pure, synchronous CPU
/// with no `BuildContext` and no asset-font loading (the built-in Helvetica face
/// is used), so it is safe to move off-thread exactly as the Excel import decode
/// was (Phase 11a). A custom object is not guaranteed transferable across an
/// isolate boundary, so the [Report] crosses as its plain [Map] form and is
/// rebuilt inside the worker -- `Report.fromMap`/`toMap` is lossless for the all-
/// string cell data a server-authored report carries, so the isolate renders the
/// identical report and the on-screen table and exported file still cannot
/// disagree. Falls back to nothing here: the caller awaits the byte list.
Future<List<int>> buildReportPdfOffIsolate(
  Map<String, dynamic> reportMap, {
  Map<String, String>? labels,
}) => Isolate.run(
  () => ReportExport.toPdfBytes(Report.fromMap(reportMap), labels: labels),
);

/// Pure, side-effect-free rendering of a computed [Report] to an exportable
/// document (Phase 10.4b). These are deliberately free of file/IO and of
/// `path_provider` so they can be unit-tested in isolation, and so the on-screen
/// table and the exported file can NEVER disagree -- both render the SAME
/// server-authored [Report] (the client re-derives nothing). This finally puts
/// the long-declared-but-unused `pdf` and `csv` dependencies to work (ARC-04).
class ReportExport {
  const ReportExport._();

  /// ARC-07 (P22): the export DOCUMENT chrome (a title block, the window /
  /// generation labels, the empty-state line) is client-owned presentation, not
  /// server-authored data -- so it can be localized without breaking the host/
  /// client "identical report" invariant (the DATA still comes from the same
  /// [Report]). Callers pass an already-localized label map (built where a
  /// `BuildContext` is available); these English values are the default so the
  /// pure functions stay independently testable and every existing caller is
  /// unchanged. Merged value-by-value so a partial map only overrides what it
  /// supplies.
  static const Map<String, String> defaultLabels = {
    'from': 'From',
    'to': 'To',
    'generated': 'Generated',
    'period': 'Period',
    'noRecords': 'No records for this report.',
  };

  static Map<String, String> _labels(Map<String, String>? overrides) => {
    ...defaultLabels,
    ...?overrides,
  };

  /// RFC-4180 CSV via `package:csv`. A short metadata block (title / window /
  /// generated) precedes the summary, then the header + data rows -- every line
  /// drawn from the SAME server-authored [Report]. The converter quotes any
  /// field carrying a comma, quote or line break, so a designation like
  /// `Sold, 50%` cannot shift the columns (the same BL-09 discipline the
  /// inventory export upholds).
  static String toCsv(Report r, {Map<String, String>? labels}) {
    final L = _labels(labels);
    final rows = <List<String>>[
      [r.title],
      [L['from']!, r.from ?? '', L['to']!, r.to ?? ''],
      [L['generated']!, r.generatedAt],
      const <String>[],
    ];
    if (r.summary.isNotEmpty) {
      for (final e in r.summary.entries) {
        rows.add([e.key, e.value]);
      }
      rows.add(const <String>[]);
    }
    rows.add(r.columns);
    rows.addAll(r.rows);
    return const ListToCsvConverter().convert(rows);
  }

  /// A landscape A4 PDF: a title, the effective window + generation stamp, the
  /// summary figures, then the report table. Returns raw bytes so the caller
  /// decides where to write them (keeps this pure and testable).
  static Future<List<int>> toPdfBytes(
    Report r, {
    Map<String, String>? labels,
  }) async {
    final L = _labels(labels);
    final doc = pw.Document(title: r.title, creator: 'Library Manager');
    final window = r.from == null && r.to == null
        ? null
        : '${r.from ?? '-'}  to  ${r.to ?? '-'}';

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              r.title,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              '${L['generated']}: ${r.generatedAt}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            if (window != null)
              pw.Text(
                '${L['period']}: $window',
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey700,
                ),
              ),
            pw.SizedBox(height: 12),
            if (r.summary.isNotEmpty)
              pw.Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in r.summary.entries)
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.blueGrey),
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Text(
                        '${e.key}: ${e.value}',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ),
                ],
              ),
            pw.SizedBox(height: 16),
            if (r.rows.isEmpty)
              pw.Text(L['noRecords']!, style: const pw.TextStyle(fontSize: 11))
            else
              pw.TableHelper.fromTextArray(
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.blueGrey50,
                ),
                headerStyle: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
                cellStyle: const pw.TextStyle(fontSize: 10),
                headers: r.columns,
                data: r.rows,
              ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  /// A suggested, filesystem-safe base name carrying the kind + window so an
  /// exported file is self-describing (no path separators, no odd characters).
  static String baseName(Report r) {
    final stamp = r.generatedAt
        .replaceAll(':', '-')
        .split('.')
        .first
        .replaceAll('T', '_');
    final safe = r.kind.storage.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return 'report_${safe}_$stamp';
  }
}

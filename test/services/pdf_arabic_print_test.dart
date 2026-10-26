import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show ByteData;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:library_manager/models/report.dart';
import 'package:library_manager/services/circulation_documents.dart';
import 'package:library_manager/services/pdf_fonts.dart';
import 'package:library_manager/services/receipt_payload.dart';
import 'package:library_manager/services/report_export.dart';

// DEF-04 (Arabic printing): the product's PDFs used the built-in Base-14
// Helvetica face, which has no Arabic glyphs and performs no shaping — an
// Arabic member name or title printed as disconnected latin junk (exactly
// the owner's complaint). The fix bundles IBMPlexSansArabic (SIL OFL 1.1)
// and routes every document through it; package:pdf shapes Arabic inside
// its TTF renderer. These tests exercise the shared service and both
// document builders from the real on-disk asset bytes.

/// Loads the same TTF files the installer bundles, straight from disk —
/// deterministic and free of any asset-bundle/binding dependency.
Future<({ByteData regular, ByteData bold})> diskFonts() async => (
  regular: await PdfPrintFonts.loadFromFile(PdfPrintFonts.regularAsset),
  bold: await PdfPrintFonts.loadFromFile(PdfPrintFonts.boldAsset),
);

String pdfText(List<int> bytes) => latin1.decode(bytes, allowInvalid: true);

CirculationSlip arabicSlip() => const CirculationSlip(
  docType: ReceiptDocType.loan,
  title: 'إيصال صرف',
  profileName: 'أمينة بوعلام',
  status: 'نشط',
  lines: [
    (label: 'العضو', value: 'M-0042'),
    (label: 'الاستعارة', value: 'L-1001'),
  ],
  items: ['مئة عام من العزلة — غابرييل غارثيا ماركيز', 'المطلع'],
  notes: ['أعد الكتب في الموعد المحدد'],
  generatedAt: '2026-10-19 12:00',
);

Report arabicReport() => Report(
  kind: ReportKind.circulation,
  title: 'تقرير الدوران',
  generatedAt: '2026-10-19 12:00',
  columns: const ['العنوان', 'الحالة'],
  rows: const [
    ['مئة عام من العزلة', 'مصرّف'],
    ['المطلع', 'متاح'],
  ],
  summary: const {'إجمالي': '2'},
);

void main() {
  group('PdfPrintFonts (DEF-04)', () {
    test('Helvetica mangles Arabic — the reported defect, pinned', () async {
      // package:pdf loudly refuses non-Latin-1 on the Base-14 faces. That
      // warning IS the defect the owner saw on paper: with the old default
      // theme every Arabic slip/report hit it. Capture proves the failure
      // mode is real, not invented.
      final logs = <String>[];
      await runZoned(
        () => ReportExport.toPdfBytes(arabicReport()),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => logs.add(line),
        ),
      );
      expect(
        logs.any((l) => l.contains('no Unicode support')),
        isTrue,
        reason: 'Helvetica was expected to reject the Arabic report',
      );
    });

    test('the bundled face removes the Unicode failure entirely', () async {
      final fonts = await diskFonts();
      final logs = <String>[];
      await runZoned(
        () => ReportExport.toPdfBytes(arabicReport(), fonts: fonts),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => logs.add(line),
        ),
      );
      expect(
        logs.where((l) => l.contains('no Unicode support')),
        isEmpty,
        reason: 'the TTF face must cover Arabic with no fallback warning',
      );
      expect(
        pdfText(await ReportExport.toPdfBytes(arabicReport(), fonts: fonts)),
        contains('IBMPlexSansArabic'),
      );
    });

    test(
      'theme() degrades to null when the loader cannot read the faces',
      () async {
        PdfPrintFonts.clearCacheForTesting();
        final theme = await PdfPrintFonts.theme(
          loader: (key) async => throw StateError('no bundle'),
        );
        expect(theme, isNull);
        PdfPrintFonts.clearCacheForTesting();
      },
    );

    test('theme() builds a TTF theme from injected bytes', () async {
      final fonts = await diskFonts();
      final theme = await PdfPrintFonts.theme(
        loader: (key) async =>
            key == PdfPrintFonts.regularAsset ? fonts.regular : fonts.bold,
      );
      expect(theme, isNotNull);
      // The theme's default style must carry the embedded TTF face, not
      // the Base-14 fallback.
      expect(theme!.defaultTextStyle.font, isA<pw.TtfFont>());
    });
  });

  group('circulation slips print Arabic (DEF-04)', () {
    test(
      'with an explicit font, the PDF embeds the face, not Helvetica',
      () async {
        final fonts = await diskFonts();
        final bytes = await CirculationDocuments.build(
          arabicSlip(),
          font: pw.Font.ttf(fonts.regular),
          fontBold: pw.Font.ttf(fonts.bold),
        );
        final text = pdfText(bytes);
        expect(text, startsWith('%PDF'));
        expect(text, contains('IBMPlexSansArabic'));
      },
    );

    test(
      'the degrade path (no readable face) still produces a printable PDF',
      () async {
        // Helvetica fallback must never block a print: build with no theme
        // injection on a machine where the bundle cannot be read.
        PdfPrintFonts.clearCacheForTesting();
        final bytes = await ReportExport.toPdfBytes(arabicReport());
        expect(pdfText(bytes), startsWith('%PDF'));
        expect(pdfText(bytes), contains('Helvetica'));
        PdfPrintFonts.clearCacheForTesting();
      },
    );
  });

  group('report PDFs print Arabic (DEF-04)', () {
    test(
      'toPdfBytes with fonts embeds the face; without, stays Helvetica',
      () async {
        final fonts = await diskFonts();
        final withFace = await ReportExport.toPdfBytes(
          arabicReport(),
          fonts: fonts,
        );
        final plain = await ReportExport.toPdfBytes(arabicReport());
        expect(pdfText(withFace), contains('IBMPlexSansArabic'));
        expect(pdfText(plain), contains('Helvetica'));
        expect(pdfText(plain), isNot(contains('IBMPlexSansArabic')));
      },
    );

    test(
      'buildReportPdfOffIsolate carries the fonts across the isolate',
      () async {
        final fonts = await diskFonts();
        final bytes = await buildReportPdfOffIsolate(
          arabicReport().toMap(),
          fonts: fonts,
        );
        final text = pdfText(bytes);
        expect(text, startsWith('%PDF'));
        // The worker isolate received plain ByteData (never rootBundle) and
        // embedded the face: this is the packaged-app path, end to end.
        expect(text, contains('IBMPlexSansArabic'));
      },
    );
  });

  group('member id caption is localized (Phase 3)', () {
    test(
      'all three ARB catalogues carry memberIdCaption with the {id} placeholder',
      () {
        // Key/placeholder parity is enforced generically by
        // test/l10n/l10n_parity_test.dart; this pins the specific key that
        // replaced the hard-coded English "ID:" caption on the member profile
        // so it cannot silently regress.
        for (final file in const [
          'lib/l10n/app_en.arb',
          'lib/l10n/app_fr.arb',
          'lib/l10n/app_ar.arb',
        ]) {
          final json =
              jsonDecode(File(file).readAsStringSync()) as Map<String, dynamic>;
          final value = json['memberIdCaption'];
          expect(value, isA<String>(), reason: '$file lacks memberIdCaption');
          expect(
            (value as String).contains('{id}'),
            isTrue,
            reason: '$file memberIdCaption lost its {id} placeholder',
          );
        }
      },
    );
  });
}

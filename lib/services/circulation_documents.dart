import 'package:barcode/barcode.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_fonts.dart';
import 'receipt_payload.dart';

/// Commercial hardening §6.12: a coherent, permission-checked document service
/// for the circulation printouts the product promises (loan / return / renewal
/// receipts, hold tickets, member cards). It is deliberately:
///
///  * **Pure & side-effect-free** (no IO, no `BuildContext`, no provider) so the
///    exact bytes are unit-testable and a printer failure can never roll back or
///    duplicate a committed transaction (§274). The caller writes the returned
///    bytes to disk / hands them to the print pipeline.
///  * **Fed authoritative, pre-formatted strings** (like `ReportExport`): the
///    screen formats dates/labels once through `appDate` + `AppLocalizations`
///    and passes the same values the UI shows, so the on-screen record, the
///    printed slip and the saved PDF cannot disagree (§263).
///  * **Privacy-conscious**: a slip carries only what the selected document
///    needs (§255/§259). The printed QR resolves to an opaque record reference
///    ([ReceiptPayload]) — never a name, contact detail, balance, token or the
///    LAN pairing secret. Nothing here performs a mutation.
///
/// Fonts: DEF-04 (Arabic printing). Unless the caller supplies its own face,
/// the document is built with the bundled IBMPlexSansArabic theme from
/// [PdfPrintFonts] — one OFL family covering Latin-1 accents *and* Arabic,
/// which `package:pdf` shapes correctly through its TTF renderer. The
/// built-in Helvetica it used before has no Arabic glyphs and no shaping, so
/// Arabic names/titles printed as garbage. If the face is somehow unreadable
/// the document still prints in Helvetica — degraded, never blocked.

/// The library's own identity block printed in the receipt header/footer
/// (§255). All fields are caller-supplied and optional; nothing is invented.
class LibraryIdentity {
  const LibraryIdentity({
    required this.name,
    this.contact = const <String>[],
    this.footer,
  });

  final String name;
  final List<String> contact;
  final String? footer;
}

/// One label/value line on a slip (e.g. ("Due date", "12 Oct 2026")).
typedef SlipLine = ({String label, String value});

/// A fully-prepared circulation document. Build one from an authoritative
/// record and pass it to [CirculationDocuments.build].
class CirculationSlip {
  const CirculationSlip({
    required this.docType,
    required this.title,
    required this.generatedAt,
    this.reference,
    this.profileName,
    this.status,
    this.lines = const <SlipLine>[],
    this.items = const <String>[],
    this.notes = const <String>[],
    this.codePayload,
    this.barcodeValue,
    this.reprint = false,
    this.reprintLabel,
  });

  final ReceiptDocType docType;

  /// Localized document title, e.g. "Loan receipt".
  final String title;

  /// Formatted issue/print timestamp shown in the header.
  final String generatedAt;

  /// Human-readable printed reference (loan/hold/card id). This is displayed
  /// text; the machine-readable code, when present, comes from [codePayload].
  final String? reference;

  /// Member display name — include ONLY when the chosen privacy mode allows it.
  final String? profileName;

  /// Derived state line, e.g. "Active", "Returned", "Ready for pickup".
  final String? status;

  /// Field rows (member id, copy id, dates, ...).
  final List<SlipLine> lines;

  /// Borrowed/returned item titles (one per physical copy).
  final List<String> items;

  /// Instruction / return-policy bullets and any short privacy footer.
  final List<String> notes;

  /// Pre-built printed-code payload from [encodeReceiptPayload]. Optional: a
  /// slip without a stable opaque id simply omits the QR.
  final String? codePayload;

  /// A Code-128 value (e.g. the copy or card barcode) rendered under the QR.
  final String? barcodeValue;

  /// True when this is a reprint; renders a clear badge so an audit reader can
  /// tell a duplicate slip from an original WITHOUT altering the transaction.
  final bool reprint;

  final String? reprintLabel;
}

class CirculationDocuments {
  const CirculationDocuments._();

  /// A compact portrait page (~A6) suited to desk receipts; callers may pass a
  /// thermal-strip or A4 format via [page] where a real printer is configured.
  static const PdfPageFormat defaultPageFormat = PdfPageFormat.a6;

  static bool _isArabicText(String text) {
    return RegExp(
      r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]',
    ).hasMatch(text);
  }

  static bool _isRtl(CirculationSlip slip, LibraryIdentity? library) {
    if (_isArabicText(slip.title)) return true;
    if (slip.profileName != null && _isArabicText(slip.profileName!)) {
      return true;
    }
    if (slip.status != null && _isArabicText(slip.status!)) return true;
    for (final l in slip.lines) {
      if (_isArabicText(l.label) || _isArabicText(l.value)) return true;
    }
    for (final it in slip.items) {
      if (_isArabicText(it)) return true;
    }
    if (library != null && _isArabicText(library.name)) return true;
    return false;
  }

  /// Renders [slip] to PDF bytes. Pure: performs no file or printer IO and never
  /// mutates any record, so it is safe to call for a preview, a save, or a
  /// reprint of an already-committed transaction.
  static Future<List<int>> build(
    CirculationSlip slip, {
    LibraryIdentity? library,
    PdfPageFormat page = defaultPageFormat,
    pw.Font? font,
    pw.Font? fontBold,
  }) async {
    // DEF-04: caller-supplied face wins; otherwise the bundled Arabic-capable
    // print theme (root isolate — this builder is never spawned off-thread).
    final pw.ThemeData? theme = font != null
        ? pw.ThemeData.withFont(base: font, bold: fontBold)
        : await PdfPrintFonts.theme();

    final isRtl = _isRtl(slip, library);
    final memberLabel = isRtl ? 'المستعير' : 'Member';
    final refLabel = isRtl ? 'المرجع' : 'Reference';
    final statusLabel = isRtl ? 'الحالة' : 'Status';
    final itemHeader = isRtl ? 'العنوان / المادة' : 'Item';

    final doc = pw.Document(
      title: slip.title,
      author: library?.name ?? 'Library Manager',
      creator: 'Library Manager',
      theme: theme,
    );

    doc.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: page,
          margin: const pw.EdgeInsets.all(18),
          theme: theme,
          textDirection: isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        ),
        build: (context) => pw.Column(
          crossAxisAlignment: isRtl
              ? pw.CrossAxisAlignment.end
              : pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            _header(slip, library, isRtl: isRtl),
            pw.SizedBox(height: 8),
            if (slip.profileName != null && slip.profileName!.isNotEmpty)
              _kv(memberLabel, slip.profileName!, isRtl: isRtl),
            if (slip.reference != null && slip.reference!.isNotEmpty)
              _kv(refLabel, slip.reference!, isRtl: isRtl),
            if (slip.status != null && slip.status!.isNotEmpty)
              _kv(statusLabel, slip.status!, isRtl: isRtl),
            for (final l in slip.lines) _kv(l.label, l.value, isRtl: isRtl),
            if (slip.items.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              _itemsTable(slip.items, headerTitle: itemHeader, isRtl: isRtl),
            ],
            if (slip.notes.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              for (final n in slip.notes)
                pw.Text(
                  isRtl ? '$n •' : '• $n',
                  style: const pw.TextStyle(fontSize: 8),
                  textDirection: isRtl
                      ? pw.TextDirection.rtl
                      : pw.TextDirection.ltr,
                ),
            ],
            pw.Spacer(),
            pw.SizedBox(height: 8),
            _codes(slip),
            pw.SizedBox(height: 6),
            pw.Text(
              slip.generatedAt,
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
              textDirection: isRtl
                  ? pw.TextDirection.rtl
                  : pw.TextDirection.ltr,
            ),
            if (library?.footer != null && library!.footer!.isNotEmpty)
              pw.Text(
                library.footer!,
                style: const pw.TextStyle(
                  fontSize: 7,
                  color: PdfColors.grey700,
                ),
                textDirection: isRtl
                    ? pw.TextDirection.rtl
                    : pw.TextDirection.ltr,
              ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  static pw.Widget _header(
    CirculationSlip slip,
    LibraryIdentity? library, {
    bool isRtl = false,
  }) {
    final row = pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: isRtl
                ? pw.CrossAxisAlignment.end
                : pw.CrossAxisAlignment.start,
            children: [
              if (library != null)
                pw.Text(
                  library.name,
                  textDirection: isRtl
                      ? pw.TextDirection.rtl
                      : pw.TextDirection.ltr,
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              if (library != null)
                for (final c in library.contact)
                  pw.Text(
                    c,
                    textDirection: isRtl
                        ? pw.TextDirection.rtl
                        : pw.TextDirection.ltr,
                    style: const pw.TextStyle(fontSize: 7),
                  ),
              pw.SizedBox(height: 4),
              pw.Text(
                slip.title,
                textDirection: isRtl
                    ? pw.TextDirection.rtl
                    : pw.TextDirection.ltr,
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        if (slip.reprint)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.red),
              borderRadius: pw.BorderRadius.circular(3),
            ),
            child: pw.Text(
              slip.reprintLabel ?? (isRtl ? 'نسخة مكررة' : 'REPRINT'),
              textDirection: isRtl
                  ? pw.TextDirection.rtl
                  : pw.TextDirection.ltr,
              style: pw.TextStyle(
                fontSize: 8,
                color: PdfColors.red,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
      ],
    );
    return pw.Directionality(
      textDirection: isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      child: row,
    );
  }

  static pw.Widget _kv(String label, String value, {bool isRtl = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Directionality(
        textDirection: isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        child: pw.RichText(
          text: pw.TextSpan(
            children: [
              pw.TextSpan(
                text: '$label: ',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.TextSpan(text: value, style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ),
      ),
    );
  }

  static pw.Widget _itemsTable(
    List<String> items, {
    String headerTitle = 'Item',
    bool isRtl = false,
  }) {
    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellAlignment: isRtl ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      headerAlignment: isRtl
          ? pw.Alignment.centerRight
          : pw.Alignment.centerLeft,
      headers: <String>[headerTitle],
      data: <List<String>>[
        for (final i in items) <String>[i],
      ],
    );
  }

  static pw.Widget _codes(CirculationSlip slip) {
    final hasQr = slip.codePayload != null && slip.codePayload!.isNotEmpty;
    final hasBar = slip.barcodeValue != null && slip.barcodeValue!.isNotEmpty;
    if (!hasQr && !hasBar) return pw.SizedBox.shrink();

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        if (hasQr)
          pw.BarcodeWidget(
            barcode: Barcode.qrCode(
              errorCorrectLevel: BarcodeQRCorrectionLevel.medium,
            ),
            data: slip.codePayload!,
            width: 60,
            height: 60,
            drawText: false,
          )
        else
          pw.SizedBox.shrink(),
        if (hasBar)
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.BarcodeWidget(
                barcode: Barcode.code128(),
                data: slip.barcodeValue!,
                width: 140,
                height: 32,
                drawText: true,
                textStyle: const pw.TextStyle(fontSize: 8),
              ),
            ],
          )
        else
          pw.SizedBox.shrink(),
      ],
    );
  }
}

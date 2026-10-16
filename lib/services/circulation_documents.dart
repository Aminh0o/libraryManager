import 'package:barcode/barcode.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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
/// Fonts: the built-in Helvetica face is used (as the existing report PDF does).
/// It covers Latin-1 (English, French accents) but does **not** shape Arabic —
/// print-side RTL/Arabic is therefore an explicitly disclosed limitation rather
/// than a silent claim (§272: on-screen RTL ≠ print RTL).

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
    final doc = pw.Document(
      title: slip.title,
      author: library?.name ?? 'Library Manager',
      creator: 'Library Manager',
      theme: font != null
          ? pw.ThemeData.withFont(base: font, bold: fontBold)
          : null,
    );

    doc.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: page,
          margin: const pw.EdgeInsets.all(18),
          theme: font != null
              ? pw.ThemeData.withFont(base: font, bold: fontBold)
              : null,
        ),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            _header(slip, library),
            pw.SizedBox(height: 8),
            if (slip.profileName != null && slip.profileName!.isNotEmpty)
              _kv('Member', slip.profileName!),
            if (slip.reference != null && slip.reference!.isNotEmpty)
              _kv('Reference', slip.reference!),
            if (slip.status != null && slip.status!.isNotEmpty)
              _kv('Status', slip.status!),
            for (final l in slip.lines) _kv(l.label, l.value),
            if (slip.items.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              _itemsTable(slip.items),
            ],
            if (slip.notes.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              for (final n in slip.notes)
                pw.Text('- $n', style: const pw.TextStyle(fontSize: 8)),
            ],
            pw.Spacer(),
            pw.SizedBox(height: 8),
            _codes(slip),
            pw.SizedBox(height: 6),
            pw.Text(
              slip.generatedAt,
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
            ),
            if (library?.footer != null && library!.footer!.isNotEmpty)
              pw.Text(
                library.footer!,
                style: const pw.TextStyle(
                  fontSize: 7,
                  color: PdfColors.grey700,
                ),
              ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  static pw.Widget _header(CirculationSlip slip, LibraryIdentity? library) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (library != null)
                pw.Text(
                  library.name,
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              if (library != null)
                for (final c in library.contact)
                  pw.Text(c, style: const pw.TextStyle(fontSize: 7)),
              pw.SizedBox(height: 4),
              pw.Text(
                slip.title,
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
              slip.reprintLabel ?? 'REPRINT',
              style: pw.TextStyle(
                fontSize: 8,
                color: PdfColors.red,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  static pw.Widget _kv(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: '$label: ',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
            pw.TextSpan(text: value, style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      ),
    );
  }

  static pw.Widget _itemsTable(List<String> items) {
    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 8),
      headers: const <String>['Item'],
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

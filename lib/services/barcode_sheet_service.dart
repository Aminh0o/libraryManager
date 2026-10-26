import 'dart:typed_data';
import 'package:barcode/barcode.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/library_item.dart';
import 'pdf_fonts.dart';

/// Label data entry for printing barcode stickers.
class BarcodeLabelData {
  final String title;
  final String? author;
  final String? location;
  final String barcode;

  const BarcodeLabelData({
    required this.title,
    this.author,
    this.location,
    required this.barcode,
  });

  factory BarcodeLabelData.fromItem(
    LibraryItem item, {
    String? specificBarcode,
  }) {
    final code =
        specificBarcode ??
        (item.barcode != null && item.barcode!.isNotEmpty
            ? item.barcode!
            : item.code);
    return BarcodeLabelData(
      title: item.designation,
      author: item.author,
      location: item.emplacement.isNotEmpty
          ? item.emplacement
          : item.emplacementStock,
      barcode: code,
    );
  }
}

/// Service to generate standard A4 sheet barcode label printouts
/// (3 columns x 8 rows = 24 labels per page) for sticking on physical books and spines.
class BarcodeSheetService {
  /// Generates printable PDF bytes for [labels] on A4 pages.
  static Future<Uint8List> generateSheet(
    List<BarcodeLabelData> labels, {
    String? libraryName,
  }) async {
    final doc = pw.Document(theme: await PdfPrintFonts.theme());

    // 24 labels per A4 page (3 columns x 8 rows)
    const labelsPerPage = 24;
    final totalPages = (labels.length / labelsPerPage).ceil();

    for (
      var pageIdx = 0;
      pageIdx < (totalPages > 0 ? totalPages : 1);
      pageIdx++
    ) {
      final startIndex = pageIdx * labelsPerPage;
      final pageLabels = labels.skip(startIndex).take(labelsPerPage).toList();

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          build: (pw.Context context) {
            return pw.GridView(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 2.1,
              children: [
                for (final label in pageLabels)
                  pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: PdfColors.grey400,
                        width: 0.5,
                      ),
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(4),
                      ),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          label.title,
                          maxLines: 1,
                          overflow: pw.TextOverflow.clip,
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                        if (label.location != null &&
                            label.location!.isNotEmpty)
                          pw.Text(
                            label.location!,
                            style: const pw.TextStyle(
                              fontSize: 7,
                              color: PdfColors.grey700,
                            ),
                          ),
                        pw.SizedBox(height: 2),
                        pw.Expanded(
                          child: pw.BarcodeWidget(
                            barcode: Barcode.code128(),
                            data: label.barcode,
                            drawText: true,
                            textStyle: const pw.TextStyle(fontSize: 7),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      );
    }

    return doc.save();
  }
}

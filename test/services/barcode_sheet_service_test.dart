import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/services/barcode_sheet_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BarcodeSheetService', () {
    test(
      'generateSheet creates a valid non-empty PDF binary with header',
      () async {
        final item = LibraryItem(
          code: 'BK-100',
          codeType: 'LIV',
          designation: 'Introduction to Algorithms',
          quantite: 5,
          emplacement: 'Shelf A1',
          taux: 4500.0,
          emplacementStock: 'Stock Room B',
          status: 'Disponible',
          author: 'Cormen, Leiserson, Rivest, Stein',
          barcode: '9780262033848',
        );

        final labels = [
          BarcodeLabelData.fromItem(item),
          BarcodeLabelData.fromItem(item, specificBarcode: 'COPY-001'),
          BarcodeLabelData.fromItem(item, specificBarcode: 'COPY-002'),
        ];

        final pdfBytes = await BarcodeSheetService.generateSheet(labels);
        expect(pdfBytes, isNotNull);
        expect(pdfBytes.length, greaterThan(100));

        // Standard PDF magic header check '%PDF-'
        final header = String.fromCharCodes(pdfBytes.take(5));
        expect(header, equals('%PDF-'));
      },
    );
  });
}

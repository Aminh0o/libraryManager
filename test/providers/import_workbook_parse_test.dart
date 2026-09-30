import 'dart:isolate';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/providers/library_provider.dart';

/// NET-11 guard. The workbook decode + every-row parse used to run synchronously
/// on the UI isolate and froze the window on a large import. It now runs via
/// `Isolate.run(() => parseImportWorkbook(bytes))` inside
/// `LibraryProvider.importItemsFromExcel`. These tests pin that the off-thread
/// parser produces EXACTLY the same `LibraryItem`s the old inline loop did, so
/// the freeze fix cannot silently change import behaviour.
Uint8List _workbookBytes(List<List<CellValue?>> rows) {
  final excel = Excel.createExcel();
  final sheet = excel['Sheet1'];
  for (final r in rows) {
    sheet.appendRow(r);
  }
  return Uint8List.fromList(excel.encode()!);
}

CellValue? _t(String s) => TextCellValue(s);

void main() {
  // Column layout the parser expects:
  // 0 Code, 1 Type, 2 Designation, 3 Quantite, 4 Emplacement,
  // 5 Prix, 6 Stock, 7 Statut, 8 Barcode.
  final header = <CellValue?>[
    _t('Code'), _t('Type'), _t('Designation'), _t('Quantite'),
    _t('Emplacement'), _t('Prix'), _t('Stock'), _t('Statut'), _t('Barcode'),
  ];

  test('parseImportWorkbook maps data rows to LibraryItems (header skipped)', () {
    final bytes = _workbookBytes([
      header,
      <CellValue?>[
        _t('0001'), _t('LIV'), _t('Book One'), IntCellValue(3),
        _t('A1'), DoubleCellValue(10.5), _t('S1'), _t('Disponible'), _t('9781'),
      ],
      <CellValue?>[
        _t('0002'), _t('REV'), _t('Journal, Two'), IntCellValue(1),
        _t('B2'), DoubleCellValue(0), _t('S2'), _t('Emprunté'), _t(''),
      ],
    ]);

    final items = parseImportWorkbook(bytes);

    expect(items, hasLength(2));
    final a = items.first;
    expect(a, isA<LibraryItem>());
    expect(a.code, '0001');
    expect(a.codeType, 'LIV');
    expect(a.designation, 'Book One');
    expect(a.quantite, 3);
    expect(a.emplacement, 'A1');
    expect(a.taux, 10.5);
    expect(a.emplacementStock, 'S1');
    expect(a.status, 'Disponible');
    expect(a.barcode, '9781');
    // A designation containing a comma survives untouched (no CSV-style split).
    expect(items[1].designation, 'Journal, Two');
    expect(items[1].status, 'Emprunté');
  });

  test('a workbook with only a header row yields no items', () {
    final bytes = _workbookBytes([header]);
    expect(parseImportWorkbook(bytes), isEmpty);
  });

  test('off-isolate parse returns an identical result to the on-thread parse',
      () async {
    final bytes = _workbookBytes([
      header,
      <CellValue?>[
        _t('0005'), _t('THE'), _t('Thesis Five'), IntCellValue(7),
        _t('C3'), DoubleCellValue(12.25), _t('S3'), _t('Réservé'), _t('9999'),
      ],
      <CellValue?>[
        _t('0006'), _t('MEM'), _t('Memo Six'), IntCellValue(2),
        _t('D4'), DoubleCellValue(3.0), _t('S4'), _t('Endommagé'), _t('8888'),
      ],
    ]);

    final sync = parseImportWorkbook(bytes);
    // This is exactly the call importItemsFromExcel now makes.
    final offThread = await Isolate.run(
      () => parseImportWorkbook(bytes),
      debugName: 'excel-import',
    );

    expect(offThread, hasLength(sync.length));
    for (var i = 0; i < sync.length; i++) {
      final s = sync[i];
      final r = offThread[i];
      expect(r.code, s.code);
      expect(r.codeType, s.codeType);
      expect(r.designation, s.designation);
      expect(r.quantite, s.quantite);
      expect(r.emplacement, s.emplacement);
      expect(r.taux, s.taux);
      expect(r.emplacementStock, s.emplacementStock);
      expect(r.status, s.status);
      expect(r.barcode, s.barcode);
    }
  });
}

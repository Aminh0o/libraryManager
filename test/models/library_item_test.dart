import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/models/library_item.dart';

/// Phase 6 (schema v24): the title enrichment fields must round-trip through
/// the DB map, stay NULL-tolerant for legacy rows, and survive whole-row
/// rebuilds (copyWith) -- the same rebuild-safety rule the member row follows.
void main() {
  LibraryItem base() => LibraryItem(
    code: '0500',
    codeType: 'LIV',
    designation: 'Dune',
    quantite: 2,
    emplacement: 'A1',
    taux: 15.5,
    emplacementStock: 'S1',
    barcode: 'ISBN-978',
  );

  group('LibraryItem v24 enrichment', () {
    test('toMap/fromMap round-trips every enrichment field', () {
      final item = LibraryItem(
        code: '0500',
        codeType: 'LIV',
        designation: 'Dune',
        quantite: 2,
        emplacement: 'A1',
        taux: 15.5,
        emplacementStock: 'S1',
        barcode: 'ISBN-978',
        rowVersion: 4,
        author: 'Frank Herbert',
        category: 'Science Fiction',
        description: 'Arrakis, the spice planet.',
        language: 'English',
        publisher: 'Chive Press',
        year: 1965,
        coverPath: r'C:\x\covers\0500.jpg',
      );
      final back = LibraryItem.fromMap(item.toMap());
      expect(back.author, 'Frank Herbert');
      expect(back.category, 'Science Fiction');
      expect(back.description, 'Arrakis, the spice planet.');
      expect(back.language, 'English');
      expect(back.publisher, 'Chive Press');
      expect(back.year, 1965);
      expect(back.coverPath, item.coverPath);
      expect(back.rowVersion, 4);
      // The pre-v24 core survived too -- enrichment never displaces it.
      expect(back.designation, 'Dune');
      expect(back.barcode, 'ISBN-978');
      expect(back.status, 'Disponible');
    });

    test('a legacy pre-v24 row reads with every enrichment field null', () {
      final legacy = LibraryItem.fromMap(base().toMap());
      expect(legacy.author, isNull);
      expect(legacy.category, isNull);
      expect(legacy.description, isNull);
      expect(legacy.language, isNull);
      expect(legacy.publisher, isNull);
      expect(legacy.year, isNull);
      expect(legacy.coverPath, isNull);
      expect(legacy.toMap()['author'], isNull);
    });

    test('copyWith changes one facet and keeps every other field', () {
      final item = LibraryItem(
        code: '0500',
        codeType: 'LIV',
        designation: 'Dune',
        quantite: 2,
        emplacement: 'A1',
        taux: 15.5,
        emplacementStock: 'S1',
        status: 'Emprunté',
        rowVersion: 7,
        author: 'Frank Herbert',
        year: 1965,
        coverPath: 'c.jpg',
      );
      final settled = item.copyWith(status: 'Disponible');
      expect(settled.status, 'Disponible');
      expect(settled.rowVersion, 7);
      expect(settled.author, 'Frank Herbert');
      expect(settled.year, 1965);
      expect(settled.coverPath, 'c.jpg');
      expect(settled.quantite, 2);
      expect(settled.taux, 15.5);
    });

    test('fromMap keeps an integer year and reads null for a missing one', () {
      final m = LibraryItem.fromMap({...base().toMap(), 'year': 1965});
      expect(m.year, 1965);
      final junk = LibraryItem.fromMap({...base().toMap(), 'year': null});
      expect(junk.year, isNull);
    });
  });
}

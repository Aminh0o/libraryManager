import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/domain/copy_ledger.dart';
import 'package:library_manager/models/item_copy.dart';

ItemCopy copy(int id, {String state = 'Disponible', String? barcode}) =>
    ItemCopy(id: id, itemCode: '0001', state: state, barcode: barcode);

void main() {
  group('CopyState', () {
    test('storage reuses the seeded French vocabulary', () {
      expect(CopyState.available.storage, 'Disponible');
      expect(CopyState.onLoan.storage, 'Emprunté');
      expect(CopyState.maintenance.storage, 'En Réparation');
      expect(CopyState.lost.storage, 'Perdu');
      expect(CopyState.archived.storage, 'Archivé');
    });

    test('parse is tolerant of unknown/legacy values -> available', () {
      expect(CopyState.parse('Emprunté'), CopyState.onLoan);
      expect(CopyState.parse('bogus'), CopyState.available);
      expect(CopyState.parse(null), CopyState.available);
    });
  });

  group('ItemCopy map round-trip', () {
    test('toMap/fromMap preserves fields', () {
      final c = ItemCopy(
        id: 7,
        itemCode: '0001',
        barcode: '978-1',
        state: 'Emprunté',
        note: 'water damage',
        acquiredAt: '2026-01-01T00:00:00.000',
      );
      final back = ItemCopy.fromMap(c.toMap());
      expect(back.id, 7);
      expect(back.itemCode, '0001');
      expect(back.barcode, '978-1');
      expect(back.state, 'Emprunté');
      expect(back.note, 'water damage');
      expect(back.acquiredAt, '2026-01-01T00:00:00.000');
      expect(back.isOnLoan, isTrue);
    });

    test('fromMap defaults missing state to available', () {
      final back = ItemCopy.fromMap({'item_code': '0001'});
      expect(back.isAvailable, isTrue);
    });
  });

  group('counts & availability', () {
    test('available/onLoan/total', () {
      final copies = [
        copy(1),
        copy(2, state: 'Emprunté'),
        copy(3, state: 'Emprunté'),
        copy(4, state: 'Perdu'),
      ];
      expect(CopyLedger.total(copies), 4);
      expect(CopyLedger.availableCount(copies), 1);
      expect(CopyLedger.onLoanCount(copies), 2);
    });

    test('findAvailable returns an available copy or null', () {
      expect(CopyLedger.findAvailable([copy(1), copy(2)])?.id, 1);
      expect(
        CopyLedger.findAvailable([copy(1, state: 'Emprunté')]),
        isNull,
      );
      expect(CopyLedger.findAvailable([]), isNull);
    });
  });

  group('checkout (copy-level, BL-01 complement)', () {
    test('marks the chosen copy on loan and leaves others untouched', () {
      final copies = [copy(1), copy(2)];
      final after = CopyLedger.checkout(copies, 2);
      expect(after.firstWhere((c) => c.id == 2).isOnLoan, isTrue);
      expect(after.firstWhere((c) => c.id == 1).isAvailable, isTrue);
      expect(CopyLedger.availableCount(after), 1);
    });

    test('does not mutate the input list (pure)', () {
      final copies = [copy(1)];
      CopyLedger.checkout(copies, 1);
      expect(copies.single.isAvailable, isTrue);
    });

    test('throws on an unknown copy', () {
      expect(() => CopyLedger.checkout([copy(1)], 99), throwsStateError);
    });

    test('throws when checking out an already-out copy (no double-checkout)',
        () {
      expect(
        () => CopyLedger.checkout([copy(1, state: 'Emprunté')], 1),
        throwsStateError,
      );
    });
  });

  group('returnCopy', () {
    test('marks an on-loan copy available', () {
      final after =
          CopyLedger.returnCopy([copy(1, state: 'Emprunté')], 1);
      expect(after.single.isAvailable, isTrue);
    });

    test('throws when returning a copy that is not on loan', () {
      expect(
        () => CopyLedger.returnCopy([copy(1)], 1),
        throwsStateError,
      );
    });

    test('throws on an unknown copy', () {
      expect(
        () => CopyLedger.returnCopy([copy(1, state: 'Emprunté')], 42),
        throwsStateError,
      );
    });
  });

  group('deriveTitleStatus (fixes DB-02 impossible states)', () {
    test('a title with any available copy is Disponible even if others out', () {
      final copies = [copy(1), copy(2, state: 'Emprunté')];
      expect(CopyLedger.deriveTitleStatus(copies), 'Disponible');
    });

    test('all copies out -> Emprunté', () {
      final copies = [copy(1, state: 'Emprunté'), copy(2, state: 'Emprunté')];
      expect(CopyLedger.deriveTitleStatus(copies), 'Emprunté');
    });

    test('empty ledger -> Disponible (legacy titles stay visible)', () {
      expect(CopyLedger.deriveTitleStatus([]), 'Disponible');
    });

    test('none available, no loans: maintenance beats archived beats lost', () {
      expect(
        CopyLedger.deriveTitleStatus(
            [copy(1, state: 'Perdu'), copy(2, state: 'En Réparation')]),
        'En Réparation',
      );
      expect(
        CopyLedger.deriveTitleStatus(
            [copy(1, state: 'Perdu'), copy(2, state: 'Archivé')]),
        'Archivé',
      );
      expect(
        CopyLedger.deriveTitleStatus([copy(1, state: 'Perdu')]),
        'Perdu',
      );
    });
  });

  group('findByBarcode (BL-03 resolution)', () {
    test('matches a per-copy barcode', () {
      final copies = [copy(1, barcode: 'A'), copy(2, barcode: 'B')];
      expect(CopyLedger.findByBarcode(copies, 'B')?.id, 2);
    });

    test('returns null when no copy matches', () {
      final copies = [copy(1, barcode: 'A')];
      expect(CopyLedger.findByBarcode(copies, 'Z'), isNull);
    });
  });
}

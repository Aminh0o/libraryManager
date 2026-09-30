import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/models/item_copy.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/domain/copy_ledger.dart';
import 'package:library_manager/screens/home_screen.dart';

// BL-05 (filter leg): the inventory status FILTER used to UNION the four
// hardcoded ItemStatus values with whatever raw STATUS strings happened to live
// in the DB. That let a value the copy rollup can NEVER produce (e.g. the stale
// ItemStatus 'Endommagé', or an arbitrary imported string) become a selectable
// filter that silently matched nothing -- and it OMITTED derivable states
// ('En Réparation', 'Perdu', 'Archivé'). Now the filter offers EXACTLY the
// canonical copy-derived vocabulary (CopyState.titleStatusVocabulary), which is
// precisely the set CopyLedger.deriveTitleStatus can emit.
void main() {
  group('statusFilterOptions (BL-05 canonical vocabulary)', () {
    test('returns exactly the copy-derived vocabulary, in enum order', () {
      expect(
        statusFilterOptions(),
        CopyState.values.map((s) => s.storage).toList(),
      );
    });

    test('every offered value is one the rollup can actually produce', () {
      // For each canonical status there is a copy ledger that derives to it, so
      // no filter option can ever match zero rows by construction.
      ItemCopy c(CopyState s) => ItemCopy(itemCode: 'X', state: s.storage);
      final derivable = {
        for (final s in CopyState.values) CopyLedger.deriveTitleStatus([c(s)]),
        // An empty ledger also derives to Disponible (documented behavior).
        CopyLedger.deriveTitleStatus(const []),
      };
      for (final opt in statusFilterOptions()) {
        expect(
          derivable,
          contains(opt),
          reason: 'filter offers "$opt" but the rollup can never produce it',
        );
      }
    });

    test('drops the non-derivable legacy ItemStatus value Endommagé', () {
      // 'Endommagé' was selectable under the old union but no CopyState derives
      // to it, so it must no longer appear.
      expect(ItemStatus.all, contains('Endommagé')); // sanity: it exists there
      expect(statusFilterOptions(), isNot(contains('Endommagé')));
    });

    test('adds the derivable states the old canonical set omitted', () {
      // The prior ItemStatus.all omitted these even though copies DO derive to
      // them; the narrowed vocabulary now includes them.
      expect(ItemStatus.all, isNot(contains('En Réparation')));
      expect(
        statusFilterOptions(),
        containsAll(['En Réparation', 'Perdu', 'Archivé']),
      );
    });

    test('is a closed set (no arbitrary DB string can be appended)', () {
      // The signature takes no argument, so the filter can never be widened by
      // stray catalogue values, and the vocabulary carries no duplicates.
      expect(
        statusFilterOptions().toSet().length,
        statusFilterOptions().length,
        reason: 'vocabulary must not contain duplicates',
      );
    });
  });
}

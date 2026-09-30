import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/services/repository.dart';

/// Paginating in-memory repo: serves the whole catalogue through the same
/// limit/offset contract the server uses, and applies real add/update/delete so
/// the post-mutation refresh re-reads an accurate window.
class _PagedRepo implements LibraryRepository {
  _PagedRepo(this.data);

  final List<LibraryItem> data;
  final List<Map<String, Object?>> itemCalls = [];

  @override
  Future<List<LibraryItem>> getItems({
    int limit = 1000,
    int offset = 0,
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) async {
    itemCalls.add({'limit': limit, 'offset': offset});
    return data.skip(offset).take(limit).toList();
  }

  @override
  Future<int> countItems({
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) async => data.length;

  @override
  Future<void> addItem(LibraryItem item, {Map<String, dynamic>? audit}) async {
    data.add(item);
    data.sort((a, b) => a.code.compareTo(b.code));
  }

  @override
  Future<void> updateItem(
    LibraryItem item, {
    Map<String, dynamic>? audit,
    int? expectedVersion,
  }) async {
    final i = data.indexWhere((e) => e.code == item.code);
    if (i >= 0) data[i] = item;
  }

  @override
  Future<void> deleteItem(String code, {Map<String, dynamic>? audit}) async {
    data.removeWhere((e) => e.code == code);
  }

  @override
  Future<List<Map<String, dynamic>>> getCodeDefinitions() async => const [];

  @override
  Future<List<Map<String, dynamic>>> getAttributeDefinitions(
    String? type,
  ) async => const [];

  @override
  Future<Map<String, dynamic>> getStats() async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

LibraryItem _mk(int i) => LibraryItem(
  code: i.toString().padLeft(4, '0'),
  codeType: 'LIV',
  designation: 'Book $i',
  quantite: 1,
  emplacement: 'R$i',
  taux: 10,
  emplacementStock: 'S$i',
  status: 'Disponible',
);

void main() {
  group('LibraryProvider post-mutation window (FE2-13)', () {
    late List<LibraryItem> data;
    late _PagedRepo repo;
    late LibraryProvider provider;

    setUp(() {
      data = [for (var i = 1; i <= 100; i++) _mk(i)];
      repo = _PagedRepo(data);
      provider = LibraryProvider.forTesting(repository: repo);
    });

    test('baseline: a plain refresh still shows exactly one page', () async {
      await provider.reload();
      expect(provider.items.length, 20);
      expect(provider.inventoryPage, 1);
    });

    test(
      'an EDIT keeps the scrolled window instead of collapsing to page 1',
      () async {
        await provider.reload();
        await provider.loadMoreItems();
        await provider.loadMoreItems();
        expect(provider.items.length, 60); // 3 pages loaded
        expect(provider.hasMoreInventory, isTrue);

        final last = provider.items.last; // code 0060
        await provider.updateItem(
          LibraryItem(
            code: last.code,
            barcode: last.barcode,
            codeType: last.codeType,
            designation: 'EDITED',
            quantite: last.quantite,
            emplacement: last.emplacement,
            taux: last.taux,
            emplacementStock: last.emplacementStock,
            status: last.status,
          ),
        );

        // The operator must still see all 60 rows, not be dumped back to 20.
        expect(provider.items.length, 60);
        expect(provider.inventoryPage, 3);
        expect(provider.hasMoreInventory, isTrue);
        // The edit is reflected, and the refresh re-read the whole window in one
        // query from offset 0 (not a page-1 collapse).
        expect(
          provider.items.any(
            (i) => i.code == '0060' && i.designation == 'EDITED',
          ),
          isTrue,
        );
        expect(repo.itemCalls.last['offset'], 0);
        expect(repo.itemCalls.last['limit'], 60);
      },
    );

    test(
      'after a mutation, loadMore continues from the correct offset',
      () async {
        await provider.reload();
        await provider.loadMoreItems();
        await provider.loadMoreItems();
        await provider.deleteItem('0001'); // window preserved (keepWindow)
        expect(provider.items.length, 60);

        repo.itemCalls.clear();
        await provider.loadMoreItems();
        // Must fetch the 4th page at offset 60, not re-read page 2.
        expect(repo.itemCalls.last['offset'], 60);
        expect(provider.items.length, 80);
      },
    );

    test('a DELETE keeps the window and reflects the removal', () async {
      await provider.reload();
      await provider.loadMoreItems();
      await provider.loadMoreItems();
      expect(provider.items.length, 60);

      await provider.deleteItem('0001');
      expect(provider.items.length, 60); // still 3 pages, now codes 0002..0061
      expect(provider.items.first.code, '0002');
      expect(provider.items.any((i) => i.code == '0001'), isFalse);
    });
  });
}

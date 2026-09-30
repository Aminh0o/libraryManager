import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/services/repository.dart';

/// In-memory [LibraryRepository] that applies the search / status / codeType
/// filters and limit / offset exactly like the server is expected to, and
/// records every call so the test can assert the provider DELEGATES the query
/// (Phase 7 / 7.2) rather than filtering a cached page in memory.
class _FakeRepo implements LibraryRepository {
  _FakeRepo(this.all);

  final List<LibraryItem> all;
  final List<Map<String, Object?>> getItemCalls = [];
  final List<Map<String, Object?>> countCalls = [];

  List<LibraryItem> _match(String? s, String? st, String? ct) => all.where((i) {
    final ms =
        s == null ||
        s.isEmpty ||
        i.designation.toLowerCase().contains(s.toLowerCase()) ||
        i.code.toLowerCase().contains(s.toLowerCase()) ||
        (i.barcode?.toLowerCase().contains(s.toLowerCase()) ?? false) ||
        i.emplacement.toLowerCase().contains(s.toLowerCase());
    final mst = st == null || i.status == st;
    final mct = ct == null || i.codeType == ct;
    return ms && mst && mct;
  }).toList();

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
    getItemCalls.add({
      'search': search,
      'status': status,
      'codeType': codeType,
      'limit': limit,
      'offset': offset,
    });
    return _match(search, status, codeType).skip(offset).take(limit).toList();
  }

  @override
  Future<int> countItems({
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) async {
    countCalls.add({'search': search, 'status': status, 'codeType': codeType});
    return _match(search, status, codeType).length;
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

String _statusFor(int i) =>
    i <= 40 ? 'Disponible' : (i <= 50 ? 'Emprunté' : 'Reliure');

LibraryItem _mk(int i) => LibraryItem(
  code: i.toString().padLeft(4, '0'),
  codeType: i % 10 == 0 ? 'REV' : 'LIV',
  designation: 'Book $i',
  quantite: 1,
  emplacement: 'R$i',
  taux: 10,
  emplacementStock: 'S$i',
  status: _statusFor(i),
);

/// Long enough for a microtask-resolved fake load to finish.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

/// Longer than the provider's 300 ms search debounce.
Future<void> _settleSearch() =>
    Future<void>.delayed(const Duration(milliseconds: 450));

void main() {
  group('LibraryProvider server-driven items (Phase 7 / 7.2)', () {
    late List<LibraryItem> data;
    late _FakeRepo repo;
    late LibraryProvider provider;

    setUp(() {
      data = [for (var i = 1; i <= 60; i++) _mk(i)];
      repo = _FakeRepo(data);
      provider = LibraryProvider.forTesting(repository: repo);
    });

    test('loads one page and reports hasMore from the server count', () async {
      await provider.reload();
      expect(provider.items.length, 20);
      expect(provider.hasMoreInventory, isTrue);
      expect(repo.getItemCalls.last['offset'], 0);
      expect(repo.getItemCalls.last['limit'], provider.pageSize);
      // No filters -> the repository is asked for the unfiltered window.
      expect(repo.getItemCalls.last['search'], isNull);
      expect(repo.getItemCalls.last['status'], isNull);
      expect(repo.getItemCalls.last['codeType'], isNull);
    });

    test('loadMoreItems accumulates pages across the WHOLE catalogue', () async {
      await provider.reload();
      await provider.loadMoreItems();
      await provider.loadMoreItems();

      expect(provider.items.length, 60);
      expect(provider.items.last.code, '0060');
      expect(provider.hasMoreInventory, isFalse);
      // Count-based hasMore means exactly three fetches, no spurious 4th empty
      // page (offsets 0/20/40).
      expect(repo.getItemCalls.map((c) => c['offset']).toList(), [0, 20, 40]);
    });

    test('search delegates to the repository and is debounced', () async {
      provider.search('Book 60');
      // Nothing fires synchronously — the debounce is still pending.
      expect(repo.getItemCalls, isEmpty);
      await _settleSearch();

      expect(repo.getItemCalls.last['search'], 'Book 60');
      expect(provider.items.length, 1);
      expect(provider.items.single.designation, 'Book 60');
    });

    test('filterByStatus re-queries from offset 0 with the status', () async {
      provider.filterByStatus('Emprunté');
      await _settle();

      final call = repo.getItemCalls.last;
      expect(call['status'], 'Emprunté');
      expect(call['offset'], 0);
      // 41..50 => 10 items, all matching the status filter.
      expect(provider.items.length, 10);
      expect(provider.items.every((i) => i.status == 'Emprunté'), isTrue);
      expect(provider.hasMoreInventory, isFalse);
      // The count call carries the SAME filter, so page + total agree.
      expect(repo.countCalls.last['status'], 'Emprunté');
    });

    test('filterByCodeType delegates the codeType to the server', () async {
      provider.filterByCodeType('REV');
      await _settle();

      expect(repo.getItemCalls.last['codeType'], 'REV');
      // codes 10/20/.../60 => 6 REV items.
      expect(provider.items.length, 6);
      expect(provider.items.every((i) => i.codeType == 'REV'), isTrue);
    });

    test('clearFilters resets to the unfiltered first page', () async {
      provider.filterByStatus('Reliure');
      await _settle();
      expect(provider.items.length, 10);

      provider.clearFilters();
      await _settle();

      final call = repo.getItemCalls.last;
      expect(call['status'], isNull);
      expect(call['search'], isNull);
      expect(call['codeType'], isNull);
      expect(call['offset'], 0);
      expect(provider.items.length, 20);
    });
  });
}

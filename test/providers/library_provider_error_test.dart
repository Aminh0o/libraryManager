import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/services/repository.dart';

/// A repository whose item load always fails, to exercise the failed-load path.
class _ThrowingRepo implements LibraryRepository {
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
    throw StateError('database is down');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// FE2-12: a failed load used to store the raw string `'Erreur de chargement:
/// $e'` and show it verbatim in the dashboard banner. The provider now keeps the
/// error OBJECT (and a non-descriptive sentinel in `errorMessage`) so the UI can
/// render a localized category instead of leaking the exception text.
void main() {
  test(
    'a failed load records the error object without a raw message',
    () async {
      final provider = LibraryProvider.forTesting(
        repository: _ThrowingRepo(),
        isHost: true,
      );

      await provider.reload();

      expect(provider.errorMessage, isNotNull); // "has error" flag still set
      expect(provider.errorMessage, isNot(contains('database is down')));
      expect(provider.errorMessage, isNot(contains('Erreur')));
      expect(provider.loadError, isA<StateError>()); // the UI classifies this
    },
  );
}

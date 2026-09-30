import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:library_manager/l10n/app_localizations.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/screens/item_details_screen.dart';
import 'package:library_manager/services/repository.dart';

// FE2-14: opening an item's details used to fabricate a fake 'Unknown' profile
// whenever the record was not in the loaded list (deleted from another client,
// or swapped by a restore). The operator saw a plausible-looking page for a row
// that no longer exists -- and could Edit the phantom. The screen must instead
// show an explicit "not found" state, while still rendering a real record.
class _FakeRepo implements LibraryRepository {
  _FakeRepo(this.items);

  final List<LibraryItem> items;

  @override
  Future<List<LibraryItem>> getItems({
    int limit = 1000,
    int offset = 0,
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) async =>
      items;

  @override
  Future<int> countItems(
          {String? search, String? status, String? codeType,
    String? sort,
    bool ascending = true,
  }) async =>
      items.length;

  @override
  Future<List<Map<String, dynamic>>> getCodeDefinitions() async => const [];

  @override
  Future<List<Map<String, dynamic>>> getAttributeDefinitions(String? type) async =>
      const [];

  @override
  Future<Map<String, dynamic>> getStats() async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

LibraryItem _item(String code, {String designation = 'Real Book'}) => LibraryItem(
      code: code,
      codeType: 'LIV',
      designation: designation,
      quantite: 3,
      emplacement: 'A1',
      taux: 12.5,
      emplacementStock: 'S1',
      status: 'Disponible',
    );

Widget _app(LibraryProvider provider, String code) =>
    ChangeNotifierProvider<LibraryProvider>.value(
      value: provider,
      child: MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ItemDetailsScreen(itemCode: code),
      ),
    );

void main() {
  testWidgets('a vanished record shows an explicit NOT-FOUND state, no ghost (FE2-14)',
      (tester) async {
    // The catalogue holds only 0001, but the operator opened 9999 (deleted
    // elsewhere since the list was rendered).
    final provider = LibraryProvider.forTesting(
        repository: _FakeRepo([_item('0001')]), isHost: true);
    await provider.reload();

    await tester.pumpWidget(_app(provider, '9999'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('itemMissingState')), findsOneWidget);
    expect(find.text('Article non trouvé'), findsOneWidget);
    expect(find.textContaining('9999'), findsOneWidget,
        reason: 'the missing record must be named so the operator knows what vanished');

    // The old fabricated profile must be gone entirely.
    expect(find.text('Unknown'), findsNothing,
        reason: 'no fake designation may be rendered');
    expect(find.byIcon(Icons.edit), findsNothing,
        reason: 'a phantom record must not offer an Edit action');
  });

  testWidgets('an existing record still renders its real profile (FE2-14)',
      (tester) async {
    final provider = LibraryProvider.forTesting(
        repository: _FakeRepo([_item('0001', designation: 'Real Book')]),
        isHost: true);
    await provider.reload();

    await tester.pumpWidget(_app(provider, '0001'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('itemMissingState')), findsNothing);
    expect(find.text('Article non trouvé'), findsNothing);
    expect(find.text('Real Book'), findsOneWidget);
    expect(find.text('Unknown'), findsNothing);
  });

  // Phase 12: a title's status is the copy rollup (BL-05), so the per-copy
  // condition ledger lives on the Item Details screen and is HOST-ONLY. The
  // _FakeRepo is not a DatabaseService, so loadCopies() yields an empty list
  // and the card renders its empty state -- but the point here is purely the
  // permission gate: the card is mounted for the host and never for a client.
  testWidgets('the HOST sees the per-copy ledger card (Phase 12)',
      (tester) async {
    final provider = LibraryProvider.forTesting(
        repository: _FakeRepo([_item('0001')]), isHost: true);
    await provider.reload();

    await tester.pumpWidget(_app(provider, '0001'));
    await tester.pumpAndSettle();

    expect(find.text('Exemplaires'), findsOneWidget,
        reason: 'the host owns the copy ledger and must be able to edit it');
  });

  testWidgets('a CLIENT does not see the copy card (host-only, Phase 12)',
      (tester) async {
    final provider = LibraryProvider.forTesting(
        repository: _FakeRepo([_item('0001')]), isHost: false);
    await provider.reload();

    await tester.pumpWidget(_app(provider, '0001'));
    await tester.pumpAndSettle();

    expect(find.text('Exemplaires'), findsNothing,
        reason: 'copy management is host-only; a client sees a read-only '
            'profile');
  });

  // Phase 13: the host copy card carries the add / remove / barcode controls.
  // With the empty _FakeRepo the list itself renders its empty state, but the
  // header "add copy" affordance is present for the host and absent for a
  // client (the whole card is gone for a client, so no control leaks).
  testWidgets('the HOST copy card offers the add-copy affordance (Phase 13)',
      (tester) async {
    final provider = LibraryProvider.forTesting(
        repository: _FakeRepo([_item('0001')]), isHost: true);
    await provider.reload();

    await tester.pumpWidget(_app(provider, '0001'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.add_circle_outline), findsOneWidget,
        reason: 'the host can grow the physical set from the card');
  });

  testWidgets('a CLIENT gets no copy-add affordance (host-only, Phase 13)',
      (tester) async {
    final provider = LibraryProvider.forTesting(
        repository: _FakeRepo([_item('0001')]), isHost: false);
    await provider.reload();

    await tester.pumpWidget(_app(provider, '0001'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.add_circle_outline), findsNothing);
  });
}

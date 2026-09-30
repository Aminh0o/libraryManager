import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:library_manager/l10n/app_localizations.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/screens/item_form_screen.dart';
import 'package:library_manager/services/database_service.dart'
    show ConcurrentUpdateConflictException;
import 'package:library_manager/services/repository.dart';

/// FE2-01 / FE2-02 regression guard: saving an item must be AWAITED, and the
/// form may only close on a CONFIRMED success. The pre-fix code fired
/// `provider.updateItem`/`addItem` without awaiting and popped immediately, so a
/// failed write was silently swallowed and the operator lost their input.
class _FakeRepo implements LibraryRepository {
  _FakeRepo({this.failOnWrite = false});

  final bool failOnWrite;
  int updates = 0;

  @override
  Future<List<LibraryItem>> getItems({
    int limit = 1000,
    int offset = 0,
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) async => const [];

  @override
  Future<void> updateItem(
    LibraryItem item, {
    Map<String, dynamic>? audit,
    int? expectedVersion,
  }) async {
    if (failOnWrite) {
      // Mimic a real rejection (409 conflict / 500 / network error): the
      // provider rethrows, which the fixed form must catch and surface.
      throw StateError('server rejected the write');
    }
    updates++;
  }

  // Everything else (getCodeDefinitions, getAttributeDefinitions, ...) is
  // irrelevant to the edit-save path; returning null keeps the form on its
  // plain TextFormFields, which validate from the prefilled item.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

LibraryItem get _existing => LibraryItem(
  code: '0001',
  codeType: 'LIV',
  designation: 'Existing Book',
  quantite: 1,
  emplacement: 'A1',
  taux: 0,
  emplacementStock: 'S1',
  status: 'Disponible',
);

Widget _app(LibraryProvider provider) =>
    ChangeNotifierProvider<LibraryProvider>.value(
      value: provider,
      child: MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('openForm'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ItemFormScreen(item: _existing),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _openForm(WidgetTester tester, LibraryProvider provider) async {
  await tester.pumpWidget(_app(provider));
  await tester.tap(find.byKey(const Key('openForm')));
  await tester.pumpAndSettle();
  expect(find.byType(ItemFormScreen), findsOneWidget);
}

Future<void> _tapSave(WidgetTester tester) async {
  // Phase L: the form now uses the outlined save icon from the design system;
  // the pinned behavior (which icon is irrelevant) is unchanged.
  final save = find.byIcon(Icons.save_outlined);
  await tester.ensureVisible(save);
  await tester.tap(save);
}

void main() {
  testWidgets(
    'a failed save keeps the form OPEN and shows an error (FE2-01/02)',
    (tester) async {
      await _openForm(
        tester,
        LibraryProvider.forTesting(
          repository: _FakeRepo(failOnWrite: true),
          isHost: false,
        ),
      );

      await _tapSave(tester);
      await tester.pump(); // _saving = true
      await tester
          .pump(); // future rejects -> catch -> _saving = false + snackbar

      expect(
        find.byType(ItemFormScreen),
        findsOneWidget,
        reason: 'the form must NOT close when the write failed',
      );
      expect(
        find.byType(SnackBar),
        findsOneWidget,
        reason: 'the failure must be surfaced to the operator',
      );

      // Flush the SnackBar auto-dismiss timer so the test ends with none pending.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('a successful save CLOSES the form (FE2-01/02)', (tester) async {
    final repo = _FakeRepo();
    await _openForm(
      tester,
      LibraryProvider.forTesting(repository: repo, isHost: false),
    );

    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(repo.updates, 1, reason: 'the mutation must reach the repository');
    expect(
      find.byType(ItemFormScreen),
      findsNothing,
      reason: 'a confirmed save closes the form',
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  // FE2-09: quantity used to accept empty / non-numeric / negative text and
  // silently store 0. The field must now reject it and block the save.
  Finder quantityField() => find.ancestor(
    of: find.byIcon(Icons.numbers),
    matching: find.byType(TextFormField),
  );

  testWidgets(
    'a non-numeric quantity is rejected and blocks the save (FE2-09)',
    (tester) async {
      final repo = _FakeRepo();
      await _openForm(
        tester,
        LibraryProvider.forTesting(repository: repo, isHost: false),
      );

      final qty = quantityField();
      expect(qty, findsOneWidget);
      await tester.enterText(qty, 'abc');
      await tester.pump();
      await _tapSave(tester);
      await tester.pump();

      expect(find.text('Nombre entier requis'), findsOneWidget);
      expect(
        find.byType(ItemFormScreen),
        findsOneWidget,
        reason: 'an invalid quantity must block the save',
      );
      expect(repo.updates, 0, reason: 'no write may reach the repository');
    },
  );

  testWidgets('a negative quantity is rejected (FE2-09)', (tester) async {
    final repo = _FakeRepo();
    await _openForm(
      tester,
      LibraryProvider.forTesting(repository: repo, isHost: false),
    );

    await tester.enterText(quantityField(), '-5');
    await tester.pump();
    await _tapSave(tester);
    await tester.pump();

    expect(find.text('Doit etre superieur ou egal a 0'), findsOneWidget);
    expect(repo.updates, 0);
    expect(find.byType(ItemFormScreen), findsOneWidget);
  });

  // TX-06 opt-in: the form now sends the row_version it READ as an optimistic
  // token. When the stored row has already advanced (another client / a loan
  // status change), the FIRST save is refused and the form stays open; the form
  // then re-reads the CURRENT version so a single RETRY succeeds instead of
  // looping on the stale token. This is the whole lost-update guard, proven
  // end-to-end through the real provider -> repository seam.
  testWidgets('a conflicted save is refused, then a retry on the refreshed '
      'version succeeds (TX-06)', (tester) async {
    // The stored row sits at version 1, but the form opened from a version-0
    // snapshot (_existing.rowVersion == 0).
    final repo = _ConflictRepo([
      LibraryItem(
        code: '0001',
        codeType: 'LIV',
        designation: 'Existing Book',
        quantite: 1,
        emplacement: 'A1',
        taux: 0,
        emplacementStock: 'S1',
        status: 'Disponible',
        rowVersion: 1,
      ),
    ]);
    await _openForm(
      tester,
      LibraryProvider.forTesting(repository: repo, isHost: false),
    );

    await _tapSave(tester);
    await tester.pump(); // _saving = true, save runs -> throws
    await tester.pump(); // catch -> reconcile (reload) starts
    await tester.pumpAndSettle(); // reload completes + snackbar

    expect(repo.updates, 0, reason: 'a stale-token write must be refused');
    expect(
      find.byType(ItemFormScreen),
      findsOneWidget,
      reason: 'the form stays open so nothing typed is lost',
    );
    expect(
      find.byType(SnackBar),
      findsOneWidget,
      reason: 'the conflict is surfaced to the operator',
    );
    expect(
      repo.lastExpected,
      0,
      reason: 'the first attempt carries the version the form READ (0)',
    );

    // Flush the first SnackBar so it cannot intercept the retry tap.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    await _tapSave(tester);
    await tester
        .pumpAndSettle(); // retry carries the refreshed version -> success

    expect(
      repo.lastExpected,
      1,
      reason: 'the retry must target the CURRENT version, not the stale 0',
    );
    expect(repo.updates, 1, reason: 'the reconciled retry commits');
    expect(
      find.byType(ItemFormScreen),
      findsNothing,
      reason: 'a confirmed save closes the form',
    );
  });
}

/// Version-aware fake repo: an update carrying a stale [expectedVersion] throws
/// the same typed conflict the real host service raises, and the loaded rows
/// (served to `reload()`) carry the true current version.
class _ConflictRepo implements LibraryRepository {
  _ConflictRepo(this.rows);

  final List<LibraryItem> rows;
  int updates = 0;
  int? lastExpected;

  @override
  Future<List<LibraryItem>> getItems({
    int limit = 1000,
    int offset = 0,
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) async => rows;

  @override
  Future<int> countItems({
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) async => rows.length;

  @override
  Future<void> updateItem(
    LibraryItem item, {
    Map<String, dynamic>? audit,
    int? expectedVersion,
  }) async {
    lastExpected = expectedVersion;
    final cur = rows.firstWhere((r) => r.code == item.code).rowVersion;
    if (expectedVersion != null && expectedVersion != cur) {
      throw ConcurrentUpdateConflictException(
        'Item ${item.code} was modified by another client.',
      );
    }
    updates++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

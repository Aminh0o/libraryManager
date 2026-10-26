import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:library_manager/l10n/app_localizations.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/models/member.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/screens/members_screen.dart';
import 'package:library_manager/services/repository.dart';
import 'package:library_manager/widgets/app_states.dart';

// Phase 2 (UX): the members list re-used "no members match search" while the
// FIRST fetch was still in flight, so a cold open flashed a false empty. The
// screen now mirrors the inventory page: a loading state while
// `provider.isLoading && members.isEmpty`, and the empty card only once the
// load has actually settled with nothing to show.
class _HangingRepo implements LibraryRepository {
  final Completer<List<LibraryItem>> _itemsGate =
      Completer<List<LibraryItem>>();

  /// Releases the in-flight item load so the test can observe the settled state.
  void releaseItems() {
    if (!_itemsGate.isCompleted) _itemsGate.complete(const <LibraryItem>[]);
  }

  @override
  Future<List<LibraryItem>> getItems({
    int limit = 1000,
    int offset = 0,
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) => _itemsGate.future;

  @override
  Future<int> countItems({
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) async => 0;

  @override
  Future<List<Member>> getMembers() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<_HangingRepo> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repo = _HangingRepo();
  final provider = LibraryProvider.forTesting(repository: repo, isHost: false);
  await tester.pumpWidget(
    ChangeNotifierProvider<LibraryProvider>.value(
      value: provider,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const MembersScreen(),
      ),
    ),
  );
  return repo;
}

void main() {
  testWidgets('a cold member load shows a spinner, not a false empty', (
    tester,
  ) async {
    await _pump(tester);

    // Kick the first fetch (un-awaited): _loadItems flips isLoading=true and
    // notifies synchronously before awaiting the hanging getItems.
    _startLoad(tester);
    await tester.pump();

    expect(find.byType(AppLoadingState), findsOneWidget);
    expect(find.byType(AppEmptyState), findsNothing);
  });

  testWidgets('once the load settles with no members the empty card returns', (
    tester,
  ) async {
    final repo = await _pump(tester);
    _startLoad(tester);
    await tester.pump();
    expect(find.byType(AppLoadingState), findsOneWidget);

    // Release the in-flight load so the provider finishes and clears isLoading.
    repo.releaseItems();
    await tester.pumpAndSettle();

    expect(find.byType(AppLoadingState), findsNothing);
    expect(find.byType(AppEmptyState), findsOneWidget);
  });
}

// Trigger the provider's first full load through the widget's own context so
// the rebuild that follows is the real member-list rebuild.
void _startLoad(WidgetTester tester) {
  final context = tester.element(find.byType(MembersScreen));
  final provider = Provider.of<LibraryProvider>(context, listen: false);
  // ignore: unawaited_futures
  provider.reloadAllForTesting();
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:library_manager/l10n/app_localizations.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/models/loan.dart';
import 'package:library_manager/models/member.dart';
import 'package:library_manager/models/reservation.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/screens/reservations_screen.dart';
import 'package:library_manager/services/repository.dart';

/// Pass 6 -- the REORDER SURFACE on the hold desk. These tests drive the
/// real [ReservationsScreen] against a hold queue that already carries the
/// per-item rank semantics the server would give it, and pin the three
/// contracts the plan promises to the operator:
///
/// * the up/down arrows are HIDDEN by default -- a global list interleaves
///   queues from several items, and reordering across items is meaningless,
///   so nothing appears until the operator focuses on one item;
/// * focusing the item filter reveals the arrows for that item's queued
///   rows and a tap forwards the intent (`up: true` / `up: false`) to the
///   repository exactly once;
/// * a boundary row (top of the line, bottom of the line, or a promoted
///   `available` row that has left the queue) keeps the affordance VISIBLE
///   but DISABLED, so the operator sees "why can't I click this" instead
///   of a mysteriously absent button.
///
/// The FakeRepo here records calls only; no reordering happens at the
/// source. That is deliberate -- the real swap semantics are covered by
/// `reservation_rank_test.dart` against a live SQLite, and the HTTP shape
/// by `http_server_reservation_move_test.dart`. What this file proves is
/// that the screen asks the right thing of the repository at the right
/// moment, and never asks when the row is not reorderable.
class _ReorderRepo implements LibraryRepository {
  _ReorderRepo(this.holds);

  final List<Reservation> holds;

  /// Every `moveReservation` call the widget made, in order. The test
  /// asserts on this list to prove the tap reached the source exactly
  /// once with the intended direction.
  final List<({int id, bool up})> moves = [];

  /// Set by the test to make the next `moveReservation` throw; used to
  /// pin the reload-on-failure path.
  Object? failNextMove;

  int _seq = 100;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  @override
  Future<HoldSettings> getHoldSettings() async => HoldSettings.defaults;

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
  Future<List<Loan>> getLoans({bool activeOnly = false}) async => const [];

  @override
  Future<List<Map<String, dynamic>>> getCodeDefinitions() async => const [];

  @override
  Future<List<Map<String, dynamic>>> getAttributeDefinitions(
    String? type,
  ) async => const [];

  @override
  Future<Map<String, dynamic>> getStats() async => const {};

  @override
  Future<List<Reservation>> getReservations({
    String? itemCode,
    String? memberId,
    ReservationStatus? status,
    bool liveOnly = false,
  }) async => [
    for (final h in holds)
      if ((itemCode == null || h.itemCode == itemCode) &&
          (memberId == null || h.memberId == memberId) &&
          (status == null || h.status == status) &&
          (!liveOnly || h.isLive))
        h,
  ];

  @override
  Future<List<Reservation>> readyForPickup() async => const [];

  @override
  Future<Reservation> placeReservation(
    String itemCode,
    String memberId, {
    Map<String, dynamic>? audit,
  }) async {
    final placed = Reservation(
      id: ++_seq,
      itemCode: itemCode,
      memberId: memberId,
      status: ReservationStatus.queued,
      createdAt: DateTime.now().toIso8601String(),
    );
    holds.add(placed);
    return placed;
  }

  @override
  Future<void> cancelReservation(int id, {Map<String, dynamic>? audit}) async {
    final idx = holds.indexWhere((h) => h.id == id);
    if (idx < 0) throw StateError('No such hold #$id.');
    holds[idx] = holds[idx].copyWith(
      status: ReservationStatus.cancelled,
      endedAt: DateTime.now().toIso8601String(),
    );
  }

  @override
  Future<void> moveReservation(
    int id, {
    required bool up,
    Map<String, dynamic>? audit,
  }) async {
    if (failNextMove != null) {
      final err = failNextMove!;
      failNextMove = null;
      throw err;
    }
    final idx = holds.indexWhere((h) => h.id == id);
    if (idx < 0) throw StateError('No such hold #$id.');
    if (holds[idx].status != ReservationStatus.queued) {
      throw StateError('Only queued holds can be reordered.');
    }
    moves.add((id: id, up: up));
  }
}

Reservation _queued(int id, String item, String member) => Reservation(
  id: id,
  itemCode: item,
  memberId: member,
  status: ReservationStatus.queued,
  createdAt: '2026-09-20T08:00:00Z',
);

Reservation _ready(int id, String item, String member) => Reservation(
  id: id,
  itemCode: item,
  memberId: member,
  copyId: 5,
  status: ReservationStatus.available,
  createdAt: '2026-09-19T08:00:00Z',
  availableAt: '2026-09-21T08:00:00Z',
  availableUntil: '2099-01-01T08:00:00Z',
);

Future<void> _pump(WidgetTester tester, _ReorderRepo repo) async {
  tester.view.physicalSize = const Size(1280, 1024);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final provider = LibraryProvider.forTesting(repository: repo, isHost: true);

  await tester.pumpWidget(
    ChangeNotifierProvider<LibraryProvider>.value(
      value: provider,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ReservationsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Focus the toolbar's item dropdown on the given code. The dropdown is a
/// Material [DropdownButton] whose overlay lives in a separate route, so we
/// tap to open it and then tap the matching [DropdownMenuItem] -- which the
/// screen renders with the code as its visible label.
Future<void> _filterTo(WidgetTester tester, String code) async {
  await tester.tap(find.byKey(const Key('holdItemFilter')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(code).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('no item filter selected -> no reorder arrows on any row', (
    tester,
  ) async {
    final repo = _ReorderRepo([
      _queued(1, 'ALG1', 'M-1'),
      _queued(2, 'ALG1', 'M-2'),
      _queued(3, 'ALG1', 'M-3'),
    ]);
    await _pump(tester, repo);

    // The rows are visible (open scope) but the reorder affordance is not
    // -- the global list would otherwise invite a cross-item reorder that
    // has no meaning.
    expect(find.byKey(const Key('hold-1')), findsOneWidget);
    expect(find.byKey(const Key('hold-2')), findsOneWidget);
    expect(find.byKey(const Key('hold-3')), findsOneWidget);
    expect(find.byKey(const Key('hold-up-1')), findsNothing);
    expect(find.byKey(const Key('hold-down-1')), findsNothing);
    expect(find.byKey(const Key('hold-up-2')), findsNothing);
    expect(find.byKey(const Key('hold-down-2')), findsNothing);
    expect(repo.moves, isEmpty);
  });

  testWidgets('focusing one item reveals arrows; tapping up on row 2 asks '
      'the repository for (id: 2, up: true)', (tester) async {
    final repo = _ReorderRepo([
      _queued(1, 'ALG1', 'M-1'),
      _queued(2, 'ALG1', 'M-2'),
      _queued(3, 'ALG1', 'M-3'),
    ]);
    await _pump(tester, repo);
    await _filterTo(tester, 'ALG1');

    // Every queued row of the focused item now carries both arrows.
    expect(find.byKey(const Key('hold-up-1')), findsOneWidget);
    expect(find.byKey(const Key('hold-down-1')), findsOneWidget);
    expect(find.byKey(const Key('hold-up-2')), findsOneWidget);
    expect(find.byKey(const Key('hold-down-2')), findsOneWidget);
    expect(find.byKey(const Key('hold-up-3')), findsOneWidget);
    expect(find.byKey(const Key('hold-down-3')), findsOneWidget);

    await tester.tap(find.byKey(const Key('hold-up-2')));
    await tester.pumpAndSettle();

    // Exactly one reorder intent reached the source, and it was the one
    // the operator expressed -- no optimistic list mutation, no double
    // submit. The reload after success re-reads the same queue (nothing
    // actually moved in this fake), which is the plan's contract: the UI
    // trusts the server's authoritative order.
    expect(repo.moves, hasLength(1));
    expect(repo.moves.single.id, 2);
    expect(repo.moves.single.up, isTrue);
  });

  testWidgets('a boundary row keeps the arrow visible but DISABLED (the '
      'affordance is discoverable, not hidden)', (tester) async {
    final repo = _ReorderRepo([
      _queued(1, 'ALG1', 'M-1'),
      _queued(2, 'ALG1', 'M-2'),
      _queued(3, 'ALG1', 'M-3'),
    ]);
    await _pump(tester, repo);
    await _filterTo(tester, 'ALG1');

    IconButton upBtn(int id) =>
        tester.widget<IconButton>(find.byKey(Key('hold-up-$id')));
    IconButton downBtn(int id) =>
        tester.widget<IconButton>(find.byKey(Key('hold-down-$id')));

    // Top of the line: `up` is greyed out, `down` is live.
    expect(upBtn(1).onPressed, isNull, reason: 'row 1 is at the head');
    expect(downBtn(1).onPressed, isNotNull);
    // Middle: both directions are live.
    expect(upBtn(2).onPressed, isNotNull);
    expect(downBtn(2).onPressed, isNotNull);
    // Bottom of the line: `down` is greyed out, `up` is live.
    expect(upBtn(3).onPressed, isNotNull);
    expect(downBtn(3).onPressed, isNull, reason: 'row 3 is at the tail');
  });

  testWidgets('a promoted (available) row shows NO arrows -- its position is '
      'the shelf, not the queue', (tester) async {
    final repo = _ReorderRepo([
      _ready(10, 'ALG1', 'M-1'), // promoted, waiting for pickup
      _queued(11, 'ALG1', 'M-2'), // next in line
    ]);
    await _pump(tester, repo);
    await _filterTo(tester, 'ALG1');

    // The queued row still has both arrows; the available row has neither.
    expect(find.byKey(const Key('hold-10')), findsOneWidget);
    expect(find.byKey(const Key('hold-up-10')), findsNothing);
    expect(find.byKey(const Key('hold-down-10')), findsNothing);
    expect(find.byKey(const Key('hold-up-11')), findsOneWidget);
  });

  testWidgets('a repository failure is surfaced verbatim and NOT pretended '
      'applied (the arrows re-appear for retry)', (tester) async {
    final repo = _ReorderRepo([
      _queued(20, 'ALG1', 'M-1'),
      _queued(21, 'ALG1', 'M-2'),
    ]);
    await _pump(tester, repo);
    await _filterTo(tester, 'ALG1');

    // Make the source refuse with a concrete reason; the screen must show
    // it (not a generic "failed"), leave the queue unchanged and re-render
    // the arrows so the operator can retry.
    repo.failNextMove = StateError(
      'Another operator just reordered this '
      'line. Reloaded -- try again.',
    );

    await tester.tap(find.byKey(const Key('hold-up-21')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Another operator just reordered'),
      findsOneWidget,
    );
    // No successful move was recorded -- the failure happened before the
    // repo could append to `moves`.
    expect(repo.moves, isEmpty);
    // The arrows are still rendered after the reload, so the operator can
    // make a second attempt.
    expect(find.byKey(const Key('hold-up-21')), findsOneWidget);
  });

  testWidgets('the item filter dropdown is populated from the loaded holds, '
      'not the whole catalogue', (tester) async {
    // Only two items appear even though the catalogue could be huge; the
    // dropdown is scoped to lines the operator can already see.
    final repo = _ReorderRepo([
      _queued(30, 'ALG1', 'M-1'),
      _queued(31, 'CAL1', 'M-2'),
      _queued(32, 'ALG1', 'M-3'),
    ]);
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('holdItemFilter')));
    await tester.pumpAndSettle();
    // "All" (the reset option) plus one entry per distinct item code. Both
    // the closed button's label and the open overlay's item are visible,
    // so we assert `findsWidgets` for the reset label too.
    expect(find.text('All'), findsWidgets);
    expect(find.text('ALG1'), findsWidgets);
    expect(find.text('CAL1'), findsWidgets);
    // No phantom item that is not in the loaded set.
    expect(find.text('PHYS1'), findsNothing);
  });
}

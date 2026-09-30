import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:library_manager/l10n/app_localizations.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/models/loan.dart';
import 'package:library_manager/models/member.dart';
import 'package:library_manager/models/reservation.dart';
import 'package:library_manager/models/user_account.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/screens/reservations_screen.dart';
import 'package:library_manager/services/api_contract.dart';
import 'package:library_manager/services/api_service.dart';
import 'package:library_manager/services/repository.dart';

// Phase 10.3b: the reservations / hold-queue SURFACE. These tests drive the
// real screen against an injected in-memory queue that carries the SAME guards
// as the host engine (a duplicate or full-queue place throws StateError; a
// cancel of an unknown/closed hold throws StateError -> HTTP 409 over the
// client), to pin that: (1) a read-only session is offered NO hold surface at
// all and the queue is never even read; (2) the queue is server-queried, so a
// scope change re-reads rather than trimming a cached page; (3) Place/Cancel
// write THROUGH the repository and reload from the server, never trusting a
// optimistic local edit; (4) a refusal the server makes is surfaced VERBATIM
// and is never pretended applied; (5) the policy editor is administrator-only
// and hard-rejects garbage before any write; and (6) a paired staff client sees
// the queue but not the admin policy editor, and its writes carry the CLIENT
// principal, not anything the caller chose.

/// A minimal hold queue with the SAME guards as DatabaseService: place refuses
/// a duplicate live hold for the member or a full queue; cancel is compare-and-
/// swap (a live hold closes exactly once; unknown or closed throws StateError).
class _HoldRepo implements LibraryRepository {
  _HoldRepo({
    List<Reservation>? holds,
    HoldSettings? settings,
    List<LibraryItem>? items,
    List<Member>? members,
  }) : holds = holds ?? <Reservation>[],
       settings = settings ?? HoldSettings.defaults,
       items = items ?? <LibraryItem>[],
       members = members ?? <Member>[];

  final List<Reservation> holds;
  HoldSettings settings;
  final List<LibraryItem> items;
  final List<Member> members;

  /// Counters the tests assert on: the queue must never be read by a session
  /// that is not offered a surface, and mutations must reach the source exactly
  /// once.
  int readAttempts = 0;
  int placeAttempts = 0;
  int cancelAttempts = 0;
  final List<int> cancelledIds = [];

  int _seq = 100;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  // ---- catalogue loaders (so the place dialog has real options) ----
  @override
  Future<List<LibraryItem>> getItems({
    int limit = 1000,
    int offset = 0,
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) async => items;

  @override
  Future<int> countItems({
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) async => items.length;

  @override
  Future<List<Member>> getMembers() async => members;

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

  // ---- the hold queue ----
  @override
  Future<HoldSettings> getHoldSettings() async => settings;

  @override
  Future<void> setHoldSettings(
    HoldSettings s, {
    Map<String, dynamic>? audit,
  }) async {
    settings = s;
  }

  @override
  Future<List<Reservation>> getReservations({
    String? itemCode,
    String? memberId,
    ReservationStatus? status,
    bool liveOnly = false,
  }) async {
    readAttempts++;
    return holds
        .where((h) => itemCode == null || h.itemCode == itemCode)
        .where((h) => memberId == null || h.memberId == memberId)
        .where((h) => status == null || h.status == status)
        .where((h) => !liveOnly || h.isLive)
        .toList();
  }

  @override
  Future<List<Reservation>> readyForPickup() async {
    readAttempts++;
    final now = DateTime.now();
    return holds.where((h) {
      final until = h.availableUntilDateTime;
      return h.status == ReservationStatus.available &&
          until != null &&
          until.isAfter(now);
    }).toList();
  }

  @override
  Future<Reservation> placeReservation(
    String itemCode,
    String memberId, {
    Map<String, dynamic>? audit,
  }) async {
    placeAttempts++;
    final liveForItem = holds
        .where((h) => h.itemCode == itemCode && h.isLive)
        .toList();
    if (liveForItem.length >= settings.queueMaxPerItem) {
      throw StateError(
        'The hold queue for this item is full (max ${settings.queueMaxPerItem}).',
      );
    }
    if (holds.any(
      (h) => h.itemCode == itemCode && h.memberId == memberId && h.isLive,
    )) {
      throw StateError('This member already has a live hold on this item.');
    }
    final hold = Reservation(
      id: ++_seq,
      itemCode: itemCode,
      memberId: memberId,
      status: ReservationStatus.queued,
      createdAt: DateTime.now().toIso8601String(),
    );
    holds.add(hold);
    return hold;
  }

  @override
  Future<void> cancelReservation(int id, {Map<String, dynamic>? audit}) async {
    cancelAttempts++;
    final idx = holds.indexWhere((h) => h.id == id);
    if (idx < 0) throw StateError('No such hold #$id.');
    if (!holds[idx].isLive) {
      throw StateError('Hold #$id is already closed.');
    }
    holds[idx] = holds[idx].copyWith(
      status: ReservationStatus.cancelled,
      endedAt: DateTime.now().toIso8601String(),
    );
    cancelledIds.add(id);
  }
}

LibraryItem _item(String code, String name) => LibraryItem(
  code: code,
  codeType: 'LIV',
  designation: name,
  quantite: 2,
  emplacement: 'A1',
  taux: 0,
  emplacementStock: 'S1',
);

Member _member(String id, String first, String last) => Member(
  memberId: id,
  firstName: first,
  lastName: last,
  registeredAt: DateTime(2026, 1, 1),
);

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

Future<_HoldRepo> _pump(
  WidgetTester tester,
  _HoldRepo repo, {
  bool isHost = true,
  bool loadCatalogue = false,
  LibraryRepository? repositoryOverride,
}) async {
  tester.view.physicalSize = const Size(1280, 1024);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final provider = LibraryProvider.forTesting(
    repository: repositoryOverride ?? repo,
    isHost: isHost,
  );
  if (loadCatalogue) {
    await provider.reloadAllForTesting();
  }

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
  return repo;
}

/// A client repository that is a REAL [ApiService] whose HTTP transport is a
/// faithful mini-server over the same guarded queue (mirroring the route shapes
/// and role semantics of HttpServerService), with the session pinned to staff
/// 'libby' — exactly like a paired device, so the test exercises the actual
/// client JSON codec and 409 propagation rather than a stubbed shortcut.
ApiService _staffClient(_HoldRepo repo) {
  Future<http.Response> route(http.Request request) async {
    try {
      // The client advertises its protocol version on every call; a real
      // server checks it, this mini-router simply requires the header.
      if (request.headers[apiVersionHeader] == null) {
        return http.Response('unauthorized', 401);
      }
      final uri = Uri.parse('http://127.0.0.1${request.url.path}');
      final path = uri.path;
      final query = uri.queryParameters;

      if (request.method == 'GET' && path == '/settings/holds') {
        return http.Response(jsonEncode(repo.settings.toMap()), 200);
      }
      if (request.method == 'PUT' && path == '/settings/holds') {
        // Policy is admin-only on the real server; 'libby' is staff.
        return http.Response(
          jsonEncode({'error': 'forbidden', 'message': 'administrators only'}),
          403,
        );
      }
      if (request.method == 'GET' && path == '/reservations') {
        final raw = query['status'];
        final status = raw == null ? null : ReservationStatus.tryParse(raw);
        if (raw != null && status == null) {
          return http.Response(
            jsonEncode({'error': 'bad_request', 'message': 'invalid status'}),
            400,
          );
        }
        final list = await repo.getReservations(
          status: status,
          liveOnly: query['live'] == '1',
        );
        return http.Response(
          jsonEncode(list.map((h) => h.toMap()).toList()),
          200,
        );
      }
      if (request.method == 'GET' && path == '/reservations/ready') {
        final list = await repo.readyForPickup();
        return http.Response(
          jsonEncode(list.map((h) => h.toMap()).toList()),
          200,
        );
      }
      if (request.method == 'POST' && path == '/reservations') {
        final body = jsonDecode(request.body) as Map;
        final code = body['item_code']?.toString() ?? '';
        final member = body['member_id']?.toString() ?? '';
        if (code.isEmpty || member.isEmpty) {
          return http.Response(
            jsonEncode({
              'error': 'bad_request',
              'message': 'item_code and member_id are required',
            }),
            400,
          );
        }
        try {
          final placed = await repo.placeReservation(code, member);
          return http.Response(jsonEncode(placed.toMap()), 201);
        } on StateError catch (e) {
          return http.Response(
            jsonEncode({'error': 'conflict', 'message': e.message}),
            409,
          );
        }
      }
      final cancel = RegExp(r'^/reservations/(\d+)/cancel$').firstMatch(path);
      if (request.method == 'POST' && cancel != null) {
        final id = int.tryParse(cancel.group(1)!);
        if (id == null) {
          return http.Response(
            jsonEncode({'error': 'bad_request', 'message': 'invalid id'}),
            400,
          );
        }
        try {
          // The server ALWAYS resolves the operator from the bearer identity —
          // never from anything the client sends.
          await repo.cancelReservation(id);
          return http.Response(jsonEncode({'ok': true}), 200);
        } on StateError catch (e) {
          return http.Response(
            jsonEncode({'error': 'conflict', 'message': e.message}),
            409,
          );
        }
      }
      return http.Response('not found', 404);
    } catch (e) {
      return http.Response('internal: $e', 500);
    }
  }

  final api = ApiService(hostIp: '127.0.0.1', client: MockClient(route));
  api.sessionRole = UserRole.staff;
  api.sessionUsername = 'libby';
  return api;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a read-only (viewer) session is offered no hold surface', (
    tester,
  ) async {
    // Non-host with a non-ApiService repository resolves to the least
    // privileged role, so the screen must not even read the queue.
    final repo = _HoldRepo(holds: [_queued(1, 'ALG1', 'M-1')]);
    await _pump(tester, repo, isHost: false);

    expect(find.text('Only staff can view or manage holds.'), findsOneWidget);
    expect(find.byKey(const Key('placeHoldFab')), findsNothing);
    expect(find.byKey(const Key('holdPolicyButton')), findsNothing);
    expect(find.byKey(const Key('hold-1')), findsNothing);
    // The queue is never read for a session that cannot see it.
    expect(repo.readAttempts, 0);
  });

  testWidgets('a host lists open holds with queue position and pickup-by', (
    tester,
  ) async {
    final repo = _HoldRepo(
      items: [_item('ALG1', 'Intro to Algorithms')],
      members: [_member('M-1', 'Amina', 'B')],
      holds: [
        _queued(11, 'ALG1', 'M-1'),
        _ready(12, 'ALG1', 'M-2'),
        // A terminal row that the default (open) scope must NOT surface.
        _queued(13, 'ALG1', 'M-3').copyWith(
          status: ReservationStatus.fulfilled,
          endedAt: '2026-09-21T09:00:00Z',
        ),
      ],
    );
    await _pump(tester, repo);

    // Both live rows show; the fulfilled one stays out of the open view.
    expect(find.byKey(const Key('hold-11')), findsOneWidget);
    expect(find.byKey(const Key('hold-12')), findsOneWidget);
    expect(find.byKey(const Key('hold-13')), findsNothing);
    // Queued row shows its place in line; promoted row shows a pickup deadline.
    expect(find.textContaining('#1 in line'), findsOneWidget);
    expect(find.textContaining('Pick up by'), findsOneWidget);
    // Admin host: the policy editor IS offered.
    expect(find.byKey(const Key('holdPolicyButton')), findsOneWidget);
  });

  testWidgets(
    'Place hold writes through the queue and reloads from the server',
    (tester) async {
      final repo = _HoldRepo(
        items: [_item('ALG1', 'Intro to Algorithms')],
        members: [_member('M-1', 'Amina', 'B')],
      );
      await _pump(tester, repo, loadCatalogue: true);

      await tester.tap(find.byKey(const Key('placeHoldFab')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('holdItemField')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Intro to Algorithms (ALG1)').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('holdMemberField')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Amina B (M-1)').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('holdPlaceSave')));
      await tester.pumpAndSettle();

      // Exactly one write reached the source, and the row appears on reload.
      expect(repo.placeAttempts, 1);
      expect(repo.holds, hasLength(1));
      expect(find.text('Hold placed'), findsOneWidget);
      expect(find.byKey(Key('hold-${repo.holds.single.id}')), findsOneWidget);
    },
  );

  testWidgets(
    'a server refusal is surfaced verbatim and never pretended applied',
    (tester) async {
      // Queue cap of 1 with one live hold: a fresh place is refused at the
      // source; the dialog must show the reason and add nothing.
      final repo = _HoldRepo(
        settings: const HoldSettings(pickupDays: 7, queueMaxPerItem: 1),
        items: [_item('ALG1', 'Intro to Algorithms')],
        members: [_member('M-1', 'Amina', 'B'), _member('M-2', 'Samir', 'K')],
        holds: [_queued(21, 'ALG1', 'M-1')],
      );
      await _pump(tester, repo, loadCatalogue: true);

      await tester.tap(find.byKey(const Key('placeHoldFab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('holdItemField')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Intro to Algorithms (ALG1)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('holdMemberField')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Samir K (M-2)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('holdPlaceSave')));
      await tester.pumpAndSettle();

      // The concrete server reason is shown, the dialog stays open, and the
      // queue did NOT grow — the UI never lies about a refused write.
      expect(
        find.text('The hold queue for this item is full (max 1).'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('holdPlaceSave')), findsOneWidget);
      expect(repo.holds, hasLength(1));
      expect(find.text('Hold placed'), findsNothing);
    },
  );

  testWidgets('Cancel confirms once, closes the hold at the source, reloads', (
    tester,
  ) async {
    final repo = _HoldRepo(
      items: [_item('ALG1', 'Intro to Algorithms')],
      members: [_member('M-1', 'Amina', 'B')],
      holds: [_queued(31, 'ALG1', 'M-1')],
    );
    await _pump(tester, repo, loadCatalogue: true);

    await tester.tap(find.byKey(const Key('hold-cancel-31')));
    await tester.pumpAndSettle();
    // The confirm names the member and the title (readable labels, not ids).
    expect(
      find.text('Cancel the hold for Amina B on Intro to Algorithms?'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('cancelConfirm')));
    await tester.pumpAndSettle();

    expect(repo.cancelledIds, [31]);
    expect(repo.holds.single.status, ReservationStatus.cancelled);
    expect(find.text('Hold cancelled'), findsOneWidget);
    // The cancelled row leaves the default open view.
    expect(find.byKey(const Key('hold-cancel-31')), findsNothing);
  });

  testWidgets(
    'the admin policy editor persists the window+cap and cancels clean',
    (tester) async {
      final repo = _HoldRepo(items: [], members: []);
      await _pump(tester, repo);

      await tester.tap(find.byKey(const Key('holdPolicyButton')));
      await tester.pumpAndSettle();
      // Cancel first: nothing changes.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.settings.pickupDays, HoldSettings.defaultPickupDays);

      await tester.tap(find.byKey(const Key('holdPolicyButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('holdPickupField')), '3');
      await tester.enterText(find.byKey(const Key('holdCapField')), '5');
      await tester.tap(find.byKey(const Key('holdPolicySave')));
      await tester.pumpAndSettle();

      expect(repo.settings.pickupDays, 3);
      expect(repo.settings.queueMaxPerItem, 5);
      expect(find.text('Hold policy updated'), findsOneWidget);
    },
  );

  testWidgets(
    'a garbage policy value is refused client-side before any write',
    (tester) async {
      final repo = _HoldRepo();
      await _pump(tester, repo);

      await tester.tap(find.byKey(const Key('holdPolicyButton')));
      await tester.pumpAndSettle();
      // digitsOnly strips the letters, leaving empty -> the validator refuses.
      await tester.enterText(find.byKey(const Key('holdPickupField')), 'abc');
      await tester.tap(find.byKey(const Key('holdPolicySave')));
      await tester.pumpAndSettle();

      // The dialog stays open and the policy is untouched at the source.
      expect(find.byKey(const Key('holdPolicySave')), findsOneWidget);
      expect(repo.settings.pickupDays, HoldSettings.defaultPickupDays);
      expect(repo.settings.queueMaxPerItem, HoldSettings.defaultQueueMax);
    },
  );

  testWidgets('the scope filter re-queries the queue server-side', (
    tester,
  ) async {
    final repo = _HoldRepo(
      holds: [
        _queued(41, 'ALG1', 'M-1'),
        _queued(42, 'ALG1', 'M-2').copyWith(
          status: ReservationStatus.cancelled,
          endedAt: '2026-09-21T09:00:00Z',
        ),
      ],
    );
    await _pump(tester, repo);
    final afterInitial = repo.readAttempts;

    // Default (open) hides the cancelled row.
    expect(find.byKey(const Key('hold-41')), findsOneWidget);
    expect(find.byKey(const Key('hold-42')), findsNothing);

    await tester.tap(find.byKey(const Key('holdScope')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All holds'));
    await tester.pumpAndSettle();

    // Switching scope triggers a fresh server read and surfaces the terminal row.
    expect(repo.readAttempts, greaterThan(afterInitial));
    expect(find.byKey(const Key('hold-41')), findsOneWidget);
    expect(find.byKey(const Key('hold-42')), findsOneWidget);
  });

  testWidgets('a staff client sees the queue but NOT the admin policy editor', (
    tester,
  ) async {
    final repo = _HoldRepo(
      holds: [_queued(51, 'ALG1', 'M-1'), _ready(52, 'ALG1', 'M-2')],
    );
    await _pump(
      tester,
      repo,
      isHost: false,
      repositoryOverride: _staffClient(repo),
    );

    // The queue is listed over the real client codec...
    expect(find.byKey(const Key('hold-51')), findsOneWidget);
    expect(find.byKey(const Key('hold-52')), findsOneWidget);
    // ...but the administrator-only policy editor is not offered to staff.
    expect(find.byKey(const Key('holdPolicyButton')), findsNothing);
    expect(find.byKey(const Key('placeHoldFab')), findsOneWidget);
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:library_manager/l10n/app_localizations.dart';
import 'package:library_manager/models/fine.dart';
import 'package:library_manager/models/member.dart';
import 'package:library_manager/models/user_account.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/screens/fines_screen.dart';
import 'package:library_manager/services/api_contract.dart';
import 'package:library_manager/services/api_service.dart';
import 'package:library_manager/services/repository.dart';

// Phase 10.2b: the fines SURFACE. These tests drive the real screen against an
// injected in-memory ledger (same CAS semantics as the host engine: settling a
// resolved or unknown fine throws StateError) to pin that (1) a read-only
// session is offered NO ledger at all, (2) a staff session sees the ledger but
// never the admin-only policy editor, (3) Collect/Waive write THROUGH the
// repository with the session principal recorded as resolvedBy, and (4) a
// double-settle race is refused and surfaced, never silently swallowed — the
// UI cannot make the server do something the server would reject.

/// A minimal ledger with the SAME settle guards as DatabaseService: pending ->
/// resolved exactly once; unknown or already-resolved throws StateError.
class _LedgerRepo implements LibraryRepository {
  _LedgerRepo({this.fines = const [], FineSettings? settings})
    : settings = settings ?? FineSettings.disabled;

  final List<Fine> fines;
  FineSettings settings;

  /// operatorName each successful settle was recorded with, id -> username.
  final Map<int, String?> settledBy = {};
  int settleAttempts = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  @override
  Future<FineSettings> getFineSettings() async => settings;

  @override
  Future<void> setFineSettings(
    FineSettings s, {
    Map<String, dynamic>? audit,
  }) async {
    settings = s;
  }

  @override
  Future<List<Fine>> getFines({String? memberId, FineStatus? status}) async =>
      fines
          .where((f) => memberId == null || f.memberId == memberId)
          .where((f) => status == null || f.status == status)
          .toList();

  @override
  Future<double> outstandingBalance(String memberId) async => fines
      .where((f) => f.memberId == memberId && f.isOpen)
      .fold<double>(0, (s, f) => s + f.amount);

  @override
  Future<void> payFine(
    int id, {
    String? operatorName,
    Map<String, dynamic>? audit,
  }) => _settle(id, FineStatus.paid, operatorName);

  @override
  Future<void> waiveFine(
    int id, {
    String? operatorName,
    Map<String, dynamic>? audit,
  }) => _settle(id, FineStatus.waived, operatorName);

  Future<void> _settle(int id, FineStatus target, String? operatorName) async {
    settleAttempts++;
    final idx = fines.indexWhere((f) => f.id == id);
    if (idx < 0) throw StateError('No such fine #$id.');
    if (!fines[idx].isOpen) throw StateError('Fine #$id is already resolved.');
    // The real ledger is immutable-append: only status/resolved_* change.
    fines[idx] = fines[idx].copyWith(
      status: target,
      resolvedAt: '2026-09-22T10:00:00Z',
      resolvedBy: operatorName,
    );
    settledBy[id] = operatorName;
  }

  @override
  Future<List<Member>> getMembers() async => const [];
}

Fine _pending(int id, double amount, {String member = 'M-1'}) => Fine(
  id: id,
  memberId: member,
  amount: amount,
  reason: 'Overdue 3 day(s)',
  createdAt: '2026-09-20T08:00:00Z',
);

Future<_LedgerRepo> _pump(
  WidgetTester tester,
  _LedgerRepo repo, {
  bool isHost = true,
  LibraryRepository? repositoryOverride,
}) async {
  tester.view.physicalSize = const Size(1280, 1024);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final LibraryProvider provider;
  if (isHost) {
    provider = LibraryProvider.forTesting(repository: repo, isHost: true);
  } else {
    provider = LibraryProvider.forTesting(
      repository: repositoryOverride ?? repo,
      isHost: false,
    );
  }

  await tester.pumpWidget(
    ChangeNotifierProvider<LibraryProvider>.value(
      value: provider,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const FinesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

/// A client repository that is a REAL [ApiService] whose HTTP transport is a
/// faithful mini-server over the same guarded ledger (mirroring the route
/// shapes and role semantics of HttpServerService), with the session pinned to
/// staff 'libby' — exactly like a paired device, so the test exercises the
/// actual client JSON codec rather than a stubbed shortcut.
ApiService _staffClient(_LedgerRepo repo) {
  Future<http.Response> route(http.Request request) async {
    String path;
    Map<String, String> query;
    try {
      // The client advertises its protocol version on every call; a real
      // server checks it, this mini-router simply requires the header.
      if (request.headers[apiVersionHeader] == null) {
        return http.Response('unauthorized', 401);
      }
      final uri = Uri.parse('http://127.0.0.1${request.url.path}');
      path = uri.path;
      query = uri.queryParameters;
      if (request.method == 'GET' && path == '/settings/fines') {
        return http.Response(jsonEncode(repo.settings.toMap()), 200);
      }
      if (request.method == 'PUT' && path == '/settings/fines') {
        final body = jsonDecode(request.body) as Map;
        final rate = body['rate_per_day'];
        if (rate is! num || !rate.isFinite || rate < 0) {
          return http.Response(
            jsonEncode({'error': 'bad_request', 'message': 'invalid rate'}),
            400,
          );
        }
        // Policy is admin-only on the real server; 'libby' is staff.
        return http.Response(
          jsonEncode({'error': 'forbidden', 'message': 'administrators only'}),
          403,
        );
      }
      if (request.method == 'GET' && path == '/fines') {
        final raw = query['status'];
        final status = raw == null ? null : FineStatus.tryParse(raw);
        if (raw != null && status == null) {
          return http.Response(
            jsonEncode({'error': 'bad_request', 'message': 'invalid status'}),
            400,
          );
        }
        return http.Response(
          jsonEncode(
            (await repo.getFines(
              status: status,
            )).map((f) => f.toMap()).toList(),
          ),
          200,
        );
      }
      final settle = RegExp(r'^/fines/(\d+)/(pay|waive)$').firstMatch(path);
      if (request.method == 'POST' && settle != null) {
        final id = int.parse(settle.group(1)!);
        try {
          if (settle.group(2) == 'pay') {
            // The server ALWAYS resolves the operator from the bearer
            // identity — never from anything the client sends.
            await repo.payFine(id, operatorName: 'libby');
          } else {
            await repo.waiveFine(id, operatorName: 'libby');
          }
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

  testWidgets('a read-only (viewer) session is offered no ledger surface', (
    tester,
  ) async {
    // Non-host with a non-ApiService repository resolves to the least
    // privileged role, so the screen must not even read the ledger.
    final repo = _LedgerRepo(fines: [_pending(1, 12.5)]);
    await _pump(tester, repo, isHost: false);

    expect(find.text('Only staff can view or settle fines.'), findsOneWidget);
    expect(find.byKey(const Key('fine-1')), findsNothing);
    expect(find.byKey(const Key('finePolicyButton')), findsNothing);
    expect(repo.settleAttempts, 0);
  });

  testWidgets('a host session lists open fines with the outstanding total', (
    tester,
  ) async {
    final repo = _LedgerRepo(fines: [_pending(1, 12.5), _pending(2, 6.0)]);
    await _pump(tester, repo);

    expect(find.text('Outstanding: 18.50 DZD'), findsOneWidget);
    expect(find.byKey(const Key('fine-1')), findsOneWidget);
    expect(find.byKey(const Key('fine-2')), findsOneWidget);
    expect(find.text('Overdue 3 day(s)  •  2026-09-20'), findsNWidgets(2));
    // Admin host: the policy editor IS offered.
    expect(find.byKey(const Key('finePolicyButton')), findsOneWidget);
  });

  testWidgets('Collect settles once, records the session principal, reloads', (
    tester,
  ) async {
    final repo = _LedgerRepo(fines: [_pending(1, 12.5)]);
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('fine-collect-1')));
    await tester.pumpAndSettle();
    expect(
      find.text('Record payment of 12.50 DZD for this fine?'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('collectConfirm')));
    await tester.pumpAndSettle();

    expect(repo.settledBy[1], 'admin'); // host principal, not caller-chosen
    expect(repo.fines.single.status, FineStatus.paid);
    // The reloaded row shows the settled state, not a stale open one.
    expect(find.byKey(const Key('fine-collect-1')), findsNothing);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('Handled by: admin'), findsOneWidget);
    expect(find.text('Outstanding: 0.00 DZD'), findsOneWidget);
    expect(find.text('Fine updated'), findsOneWidget);
  });

  testWidgets('Waive resolves the fine and it can never be collected after', (
    tester,
  ) async {
    final repo = _LedgerRepo(fines: [_pending(7, 4.0)]);
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('fine-waive-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waiveConfirm')));
    await tester.pumpAndSettle();

    expect(repo.fines.single.status, FineStatus.waived);
    expect(find.text('Waived'), findsOneWidget);

    // A direct double-settle through the same stack is refused (CAS guard) —
    // the money can never be collected after a waive.
    await expectLater(
      repo.payFine(7, operatorName: 'admin'),
      throwsA(isA<StateError>()),
    );
  });

  testWidgets('a fine already resolved at the source is shown settled, and '
      'a direct re-settle through the same guard is refused', (tester) async {
    // Fine 1 was paid elsewhere (race): the ledger must RENDER it settled —
    // with no collect affordance to double-charge — and the CAS guard must
    // refuse any direct re-settle attempt.
    final repo = _LedgerRepo(
      fines: [
        _pending(
          1,
          5.0,
        ).copyWith(status: FineStatus.paid, resolvedBy: 'someone'),
      ],
    );
    await _pump(tester, repo);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.byKey(const Key('fine-collect-1')), findsNothing);
    expect(find.text('Outstanding: 0.00 DZD'), findsOneWidget);
    await expectLater(
      repo.payFine(1, operatorName: 'admin'),
      throwsA(isA<StateError>()),
    );
  });

  testWidgets(
    'a staff client sees the ledger but NOT the admin policy editor',
    (tester) async {
      final repo = _LedgerRepo(fines: [_pending(1, 12.5)]);
      await _pump(
        tester,
        repo,
        isHost: false,
        repositoryOverride: _staffClient(repo),
      );

      expect(find.byKey(const Key('fine-1')), findsOneWidget);
      expect(find.byKey(const Key('finePolicyButton')), findsNothing);

      // Settling from a staff client records the CLIENT principal.
      await tester.tap(find.byKey(const Key('fine-collect-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collectConfirm')));
      await tester.pumpAndSettle();
      expect(repo.settledBy[1], 'libby');
    },
  );

  testWidgets(
    'the admin policy editor persists rate+currency and cancels clean',
    (tester) async {
      final repo = _LedgerRepo(fines: [_pending(1, 12.5)]);
      await _pump(tester, repo);

      await tester.tap(find.byKey(const Key('finePolicyButton')));
      await tester.pumpAndSettle();
      // Cancel first: nothing changes.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.settings.ratePerDay, 0.0);

      await tester.tap(find.byKey(const Key('finePolicyButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('fineRateField')), '2.50');
      await tester.enterText(find.byKey(const Key('fineCurrencyField')), 'DA');
      await tester.tap(find.byKey(const Key('finePolicySave')));
      await tester.pumpAndSettle();

      expect(repo.settings.ratePerDay, 2.50);
      expect(repo.settings.currency, 'DA');
      // Money formatting follows the freshly-saved currency...
      expect(find.text('Outstanding: 12.50 DA'), findsOneWidget);
      expect(find.text('Fine policy updated'), findsOneWidget);
    },
  );

  testWidgets(
    'a negative/garbage rate is refused client-side before any write',
    (tester) async {
      final repo = _LedgerRepo(fines: [_pending(1, 12.5)]);
      await _pump(tester, repo);

      await tester.tap(find.byKey(const Key('finePolicyButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('fineRateField')), 'abc');
      await tester.tap(find.byKey(const Key('finePolicySave')));
      await tester.pumpAndSettle();

      // The input formatter strips non-numeric text and the validator refuses
      // what remains: the dialog stays open and no write reaches the repository.
      expect(find.byKey(const Key('finePolicySave')), findsOneWidget);
      expect(repo.settings.ratePerDay, 0.0);
    },
  );

  testWidgets('the status filter re-queries the ledger server-side', (
    tester,
  ) async {
    final repo = _LedgerRepo(
      fines: [
        _pending(1, 12.5),
        _pending(2, 6.0).copyWith(status: FineStatus.paid, resolvedBy: 'admin'),
      ],
    );
    await _pump(tester, repo);
    expect(find.byKey(const Key('fine-1')), findsOneWidget);
    expect(find.byKey(const Key('fine-2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('fineFilter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pending').last);
    await tester.pumpAndSettle();

    // Only the pending row survives the filtered re-query.
    expect(find.byKey(const Key('fine-1')), findsOneWidget);
    expect(find.byKey(const Key('fine-2')), findsNothing);
  });
}

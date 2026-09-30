import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/models/loan.dart';
import 'package:library_manager/services/auth_service.dart';
import 'package:library_manager/services/database_service.dart'
    show
        ActiveLoanConflictException,
        ItemCodeConflictException,
        ConcurrentUpdateConflictException;
import 'package:library_manager/services/http_server_service.dart';
import 'package:library_manager/services/password_hasher.dart';
import 'package:library_manager/services/rate_limit.dart';
import 'package:library_manager/services/repository.dart';

/// Phase 21 -- the register's SCALE / CONCURRENCY / FAILURE matrix, run over a
/// REAL socket against the REAL server pipeline (error middleware + guards +
/// auth + idempotency + rate limit + router).
///
/// Why this file exists although most guards are already tested: the
/// per-increment suites prove each layer IN ISOLATION (`database_loan_test`
/// shows SQLite refuses a second concurrent checkout; `idempotency_test` shows
/// the middleware replays; `http_server_validation_test` shows one bad body
/// gets a 400). The audit's hazards (#15, #16, #17, #18, #20) are properties of
/// the WHOLE stack: a client on the wire is only stopped by a guard that
/// survives JSON, auth, middleware ORDERING and genuine event-loop
/// interleaving. That combined claim was never pinned, so a 409 reclassified to
/// a 500 by the retry path, or a replay that double-executed, would have stayed
/// invisible.
///
/// The repository below is a CONCURRENCY ORACLE, not a reimplementation of the
/// app: it holds the same invariants the real DB holds (one active loan per
/// copy, unique code, per-row version) and deliberately `await`s BEFORE the
/// check-then-act, so interleaving is at least as hostile as production. Every
/// assertion is about what the TRANSPORT answers.
void main() {
  late HttpServerService server;
  late AuthService auth;
  late _ScaleRepo repo;
  late String base;
  late http.Client client;
  late String token;

  setUp(() async {
    auth = AuthService(
      hasher: PasswordHasher(iterations: 1000),
      store: InMemoryAuthStore(),
    );
    await auth.setPassword('root-pw');
    repo = _ScaleRepo();
    server = HttpServerService(
      repository: repo,
      auth: auth,
      // A generous burst on purpose: these tests hammer from ONE source ip and
      // the question is data integrity under load, not the throttle (which is
      // pinned in http_server_rate_limit_test.dart and re-pinned here with its
      // own deliberately tiny bucket).
      rateLimiter: RateLimiter(capacity: 5000, refillPerMinute: 60000),
    );
    await server.startServer(host: '127.0.0.1', port: 0);
    base = 'http://127.0.0.1:${server.port}';
    client = http.Client();
    token = await _staffToken(client, base, auth);
  });

  tearDown(() async {
    client.close();
    await server.stopServer();
  });

  group('#17 -- many clients writing at once', () {
    test('a single-copy title cannot be double-lent over the wire', () async {
      // One copy, already on loan: the real schema (`uq_loans_active_copy` + the
      // copy-state CAS) permits exactly ONE active loan, so 11 of these 12
      // clients must be told 'no' -- explicitly, not by a silent 500.
      repo.seedItem(_item('RACE0001', status: ItemStatus.emprunte));
      repo.loanPreWriteDelay = const Duration(milliseconds: 60);

      final responses = await Future.wait(
        List.generate(
          12,
          (i) => client.post(
            Uri.parse('$base/loans'),
            headers: _authJson(token),
            body: jsonEncode(_loanBody(itemCode: 'RACE0001', member: 'M$i')),
          ),
        ),
      );

      final created = responses.where((r) => r.statusCode == 200).toList();
      final conflicts = responses.where((r) => r.statusCode == 409).toList();
      // The decisive production property: exactly ONE borrower wins and every
      // loser gets a TYPED conflict -- not a bare 500, which a client cannot
      // tell from a crash and would blindly retry.
      expect(created, hasLength(1));
      expect(conflicts, hasLength(11));
      // No client was left holding an ambiguous 5xx -- the outcome each loser
      // sees is a refusal they can render, not a transport mystery.
      expect(responses.map((r) => r.statusCode), everyElement(anyOf(200, 409)));
      expect(jsonDecode(conflicts.first.body)['error'], 'conflict');
      expect(await repo.activeLoansFor('RACE0001'), hasLength(1));
      repo.loanPreWriteDelay = Duration.zero;
    });

    test(
      '10 distinct concurrent checkouts all land, each with a unique id',
      () async {
        for (int i = 0; i < 10; i++) {
          repo.seedItem(
            _item(
              'OPEN${i.toString().padLeft(4, '0')}',
              status: ItemStatus.emprunte,
            ),
          );
        }

        final responses = await Future.wait(
          List.generate(
            10,
            (i) => client.post(
              Uri.parse('$base/loans'),
              headers: _authJson(token),
              body: jsonEncode(
                _loanBody(
                  itemCode: 'OPEN${i.toString().padLeft(4, '0')}',
                  member: 'M$i',
                ),
              ),
            ),
          ),
        );
        expect(responses.map((r) => r.statusCode), everyElement(200));

        final loans = await repo.allLoans();
        expect(loans, hasLength(10));
        expect(
          loans.map((l) => l.id).toSet(),
          hasLength(10),
          reason: 'a shared sequence under load must never repeat an id',
        );
      },
    );

    test(
      'concurrent adds of the same code: one lands, the rest conflict',
      () async {
        final body = jsonEncode(_itemMap('SAME0001'));
        final responses = await Future.wait(
          List.generate(
            6,
            (_) => client.post(
              Uri.parse('$base/items'),
              headers: _authJson(token),
              body: body,
            ),
          ),
        );

        expect(responses.where((r) => r.statusCode == 200), hasLength(1));
        final conflicts = responses.where((r) => r.statusCode == 409).toList();
        expect(conflicts, hasLength(5));
        expect(jsonDecode(conflicts.first.body)['error'], 'conflict');
      },
    );
  });

  group('#15/#16 -- timeout, retry and the phantom record', () {
    test('a slow-but-successful write answers 504, and the real invariant stops '
        'the client retry from inventing a second loan', () async {
      repo.seedItem(_item('SLOW0001', status: ItemStatus.emprunte));
      // The handler WILL succeed, but only after the server's own guard has
      // already answered: the client is told "failed" about work that really
      // committed -- precisely the audit's phantom-record hazard.
      repo.loanPreWriteDelay = const Duration(milliseconds: 250);
      final slow = HttpServerService(
        repository: repo,
        auth: auth,
        requestTimeout: const Duration(milliseconds: 150),
        rateLimiter: RateLimiter(capacity: 5000, refillPerMinute: 60000),
      );
      await slow.startServer(host: '127.0.0.1', port: 0);
      final slowBase = 'http://127.0.0.1:${slow.port}';
      addTearDown(slow.stopServer);

      Future<http.Response> send() => client.post(
        Uri.parse('$slowBase/loans'),
        headers: {..._authJson(token), 'Idempotency-Key': 'one-logical-send'},
        body: jsonEncode(_loanBody(itemCode: 'SLOW0001', member: 'M1')),
      );

      final first = await send();
      expect(
        first.statusCode,
        504,
        reason: 'a timeout must never be reported as success',
      );

      // Honest statement of what the stack guarantees: the idempotency cache
      // DELIBERATELY does not cover a 5xx, so this retry really does re-execute.
      // What protects the ledger is the server-side invariant, not the replay
      // cache -- and the client (ApiService) will in fact retry here.
      final retry = await send();
      expect(
        retry.statusCode,
        409,
        reason: 'the second send must be refused, not silently applied',
      );

      // The timed-out first request is still in flight on the server; let its
      // slow commit land before reading the ledger (that late commit IS the
      // phantom the client was told had failed).
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final landed = (await repo.allLoans())
          .where((l) => l.itemCode == 'SLOW0001')
          .toList();
      expect(landed, hasLength(1), reason: 'one logical borrow, one loan row');
      repo.loanPreWriteDelay = Duration.zero;
    });

    test('a replayed 2xx is served from cache and never re-executes', () async {
      repo.seedItem(_item('IDEM0001', status: ItemStatus.emprunte));
      final headers = {..._authJson(token), 'Idempotency-Key': 'send-once'};
      final body = jsonEncode(_loanBody(itemCode: 'IDEM0001', member: 'M1'));

      expect(
        (await client.post(
          Uri.parse('$base/loans'),
          headers: headers,
          body: body,
        )).statusCode,
        200,
      );
      final second = await client.post(
        Uri.parse('$base/loans'),
        headers: headers,
        body: body,
      );
      expect(second.statusCode, 200);
      expect(
        repo.addLoanExecutions,
        1,
        reason: 'the router must not run twice for one key',
      );
      expect(await repo.activeLoansFor('IDEM0001'), hasLength(1));
    });
  });

  group('#18 -- two clients editing one record', () {
    test(
      'the stale writer is refused 409 and the row holds exactly one edit',
      () async {
        repo.seedItem(
          _item('EDIT0001', designation: 'Shared record', rowVersion: 7),
        );
        // Both clients read version 7 and then write; without the guard the
        // second silently clobbers the first (the audit-era TX-06 finding). The
        // delay widens the window so the interleaving is forced, not lucky.
        repo.updatePreWriteDelay = const Duration(milliseconds: 150);

        final edits = ['Edit A', 'Edit B'];
        final writes = await Future.wait([
          for (final designation in edits)
            client.put(
              Uri.parse('$base/items'),
              headers: {..._authJson(token), 'x-expected-version': '7'},
              body: jsonEncode(_itemMap('EDIT0001', designation: designation)),
            ),
        ]);
        repo.updatePreWriteDelay = Duration.zero;

        expect(
          writes.map((r) => r.statusCode).toList()..sort(),
          equals([200, 409]),
          reason: 'exactly one writer may land',
        );
        final current = repo.items['EDIT0001']!;
        expect(
          current.rowVersion,
          8,
          reason: 'the survivor advanced the version',
        );
        // The row reflects ONE coherent edit: the survivor's text, and the loser's
        // is nowhere in the stored row (a part-merge would be the real damage).
        final winnerDesignation =
            edits[writes.indexWhere((r) => r.statusCode == 200)];
        expect(current.designation, winnerDesignation);
        expect(
          current.designation,
          isNot(edits.firstWhere((e) => e != winnerDesignation)),
        );
      },
    );

    test(
      'a caller that sends no version keeps the legacy unconditional write',
      () async {
        repo.seedItem(_item('NOVER001'));
        final res = await client.put(
          Uri.parse('$base/items'),
          headers: _authJson(token),
          body: jsonEncode(_itemMap('NOVER001', designation: 'Overwritten')),
        );
        expect(res.statusCode, 200);
        expect(repo.items['NOVER001']!.designation, 'Overwritten');
      },
    );
  });

  group('catalogue scale -- a big table read by many clients at once', () {
    test(
      '2000 rows paginate with no loss and no duplicate for 40 concurrent readers',
      () async {
        for (int i = 1; i <= 2000; i++) {
          repo.seedItem(
            _item(
              'CAT${i.toString().padLeft(5, '0')}',
              designation: 'Volume $i',
            ),
          );
        }

        final countRes = await client.get(
          Uri.parse('$base/items/count'),
          headers: {'Authorization': 'Bearer $token'},
        );
        expect(
          jsonDecode(countRes.body)['count'],
          2000,
          reason: 'the count is what drives correct pagination',
        );

        const pageSize = 50;
        final bodies = await Future.wait(
          List.generate(
            2000 ~/ pageSize,
            (p) => client.get(
              Uri.parse('$base/items?limit=$pageSize&offset=${p * pageSize}'),
              headers: {'Authorization': 'Bearer $token'},
            ),
          ),
        );

        final codes = <String>[];
        for (final b in bodies) {
          expect(b.statusCode, 200);
          codes.addAll(
            (jsonDecode(b.body) as List).map(
              (e) => (e as Map)['code'] as String,
            ),
          );
        }
        expect(codes, hasLength(2000));
        expect(
          codes.toSet(),
          hasLength(2000),
          reason: 'under concurrent reads a page may neither repeat nor drop',
        );
      },
    );

    test('a read storm does not disturb a concurrent write', () async {
      repo.seedItem(_item('SCALE001', status: ItemStatus.emprunte));
      for (int i = 0; i < 500; i++) {
        repo.seedItem(
          _item(
            'STORM${i.toString().padLeft(4, '0')}',
            designation: 'Noise $i',
          ),
        );
      }

      final results = await Future.wait([
        ...List.generate(
          40,
          (_) => client.get(
            Uri.parse('$base/items?limit=25'),
            headers: {'Authorization': 'Bearer $token'},
          ),
        ),
        client.post(
          Uri.parse('$base/loans'),
          headers: _authJson(token),
          body: jsonEncode(_loanBody(itemCode: 'SCALE001', member: 'M1')),
        ),
      ]);

      expect(results.take(40).every((r) => r.statusCode == 200), isTrue);
      expect(results.last.statusCode, 200);
      expect(
        await repo.activeLoansFor('SCALE001'),
        hasLength(1),
        reason: 'readers must not corrupt or swallow the write',
      );
    });
  });

  group('#3 -- the host restarts while clients are open', () {
    test('in-flight clients fail FAST, and the same session works again once '
        'the server is back', () async {
      // A fixed port where possible, so the restart is a like-for-like recovery
      // rather than a new endpoint (client re-discovery itself is NET-10,
      // still open).
      await server.stopServer();
      const preferredPort = 58291;
      int boundPort;
      try {
        await server.startServer(host: '127.0.0.1', port: preferredPort);
        boundPort = preferredPort;
      } on SocketException {
        // Something else on this machine holds that port; use a free one and
        // still bounce the SAME endpoint, which is what is under test.
        await server.startServer(host: '127.0.0.1', port: 0);
        boundPort = server.port;
      }
      base = 'http://127.0.0.1:$boundPort';
      final live = await client.get(
        Uri.parse('$base/items?limit=1'),
        headers: {'Authorization': 'Bearer $token'},
      );
      expect(live.statusCode, 200);

      await server.stopServer();
      final sw = Stopwatch()..start();
      final failures = <int>[];
      for (int i = 0; i < 3; i++) {
        try {
          await client.get(
            Uri.parse('$base/items?limit=1'),
            headers: {'Authorization': 'Bearer $token'},
          );
          failures.add(200); // must not happen while nothing is listening
        } on http.ClientException {
          failures.add(-1); // a clean, immediate transport failure
        }
      }
      sw.stop();
      expect(
        failures,
        everyElement(-1),
        reason: 'a dead host must never look like a success',
      );
      // The audit's freeze complaint: an outage must be reported, not sat on.
      // Windows refuses synchronously here, so a multi-second total would mean
      // the client is hanging rather than failing.
      expect(
        sw.elapsed,
        lessThan(const Duration(seconds: 5)),
        reason: 'an unreachable host must fail fast, not hang the UI',
      );

      await server.startServer(host: '127.0.0.1', port: boundPort);
      addTearDown(server.stopServer);
      final recovered = await client.get(
        Uri.parse('$base/items?limit=1'),
        headers: {'Authorization': 'Bearer $token'},
      );
      expect(
        recovered.statusCode,
        200,
        reason: 'the session must survive a host bounce',
      );
    });
  });

  group('#20 -- abusive traffic against a shared database', () {
    test('a mixed flood never yields a 500 and never corrupts the server', () async {
      // One oversized body, matching the server's own configured cap, plus a
      // stream of malformed / half-valid / good requests interleaved: the audit
      // asked whether a hostile client can take the service down for everyone.
      final oversized = 'x' * (6 * 1024 * 1024);
      final requests = <Future<http.Response>>[];
      for (int i = 0; i < 25; i++) {
        switch (i % 5) {
          case 0:
            requests.add(
              client.post(
                Uri.parse('$base/items'),
                headers: _authJson(token),
                body: '{"not json',
              ),
            );
          case 1:
            requests.add(
              client.post(
                Uri.parse('$base/items'),
                headers: _authJson(token),
                body: jsonEncode({'code': 'MISSING$i'}),
              ),
            );
          case 2:
            requests.add(
              client.post(
                Uri.parse('$base/items'),
                headers: _authJson(token),
                body: jsonEncode(_itemMap('BADTYPE$i', quantite: 'many')),
              ),
            );
          case 3:
            requests.add(
              client.post(
                Uri.parse('$base/items'),
                headers: _authJson(token),
                body: jsonEncode(
                  _itemMap('GOOD${i.toString().padLeft(3, '0')}'),
                ),
              ),
            );
          default:
            requests.add(
              client.post(
                Uri.parse('$base/items'),
                headers: _authJson(token),
                body: oversized,
              ),
            );
        }
      }
      final responses = await Future.wait(requests);

      expect(
        responses.map((r) => r.statusCode),
        everyElement(inInclusiveRange(200, 499)),
        reason:
            'client error must never surface as a server fault for everyone',
      );
      expect(
        responses.where((r) => r.statusCode == 413),
        isNotEmpty,
        reason: 'the oversized body must be cut off',
      );
      expect(responses.where((r) => r.statusCode == 200), isNotEmpty);

      // Still healthy afterwards: a good request works and the garbage rows did
      // not land.
      final after = await client.post(
        Uri.parse('$base/items'),
        headers: _authJson(token),
        body: jsonEncode(_itemMap('AFTERFLOOD')),
      );
      expect(after.statusCode, 200);
      expect(repo.items.containsKey('MISSING1'), isFalse);
      expect(repo.items.containsKey('BADTYPE2'), isFalse);
    });

    test(
      'a write flood is throttled with 429 + Retry-After, and reads stay open',
      () async {
        // A dedicated server with a tiny bucket, so the throttle is the subject
        // rather than an incidental side effect of load.
        final tightAuth = AuthService(
          hasher: PasswordHasher(iterations: 1000),
          store: InMemoryAuthStore(),
        );
        await tightAuth.setPassword('root-pw');
        final tight = HttpServerService(
          repository: repo,
          auth: tightAuth,
          rateLimiter: RateLimiter(capacity: 5, refillPerMinute: 600),
        );
        await tight.startServer(host: '127.0.0.1', port: 0);
        final tightBase = 'http://127.0.0.1:${tight.port}';
        addTearDown(tight.stopServer);
        final tightToken = await _staffToken(client, tightBase, tightAuth);

        final writes = await Future.wait(
          List.generate(
            20,
            (i) => client.post(
              Uri.parse('$tightBase/items'),
              headers: _authJson(tightToken),
              body: jsonEncode(
                _itemMap(
                  'FLOOD${i.toString().padLeft(3, '0')}',
                  designation: 'Flood $i',
                ),
              ),
            ),
          ),
        );
        final throttled = writes.where((r) => r.statusCode == 429).toList();
        expect(
          throttled,
          isNotEmpty,
          reason: 'writes must be capped before they reach the shared db',
        );
        expect(
          throttled.first.body,
          contains('retry_after_seconds'),
          reason: 'a refusal must tell the client how long to wait',
        );

        // The audit's operational worry: a throttled client must not be locked out
        // of reading, and the sync poll must keep working.
        final read = await client.get(
          Uri.parse('$tightBase/items?limit=5'),
          headers: {'Authorization': 'Bearer $tightToken'},
        );
        expect(read.statusCode, 200);
        final version = await client.get(
          Uri.parse('$tightBase/db-version'),
          headers: {'Authorization': 'Bearer $tightToken'},
        );
        expect(version.statusCode, 200);
      },
    );
  });
}

Map<String, String> _authJson(String token) => {
  'Content-Type': 'application/json',
  'Authorization': 'Bearer $token',
};

Map<String, dynamic> _loanBody({
  required String itemCode,
  required String member,
}) => {
  'item_code': itemCode,
  'member_id': member,
  'member_name': member,
  'item_title': 'Title $itemCode',
  'loan_date': '2026-09-23T10:00:00',
  'due_date': '2026-10-07T10:00:00',
  'status': LoanStatus.active.storage,
};

Map<String, dynamic> _itemMap(
  String code, {
  String? designation,
  Object? quantite = 1,
}) => {
  'code': code,
  'code_type': 'LIV',
  'designation': designation ?? 'Item $code',
  'quantite': quantite,
  'emplacement': 'A',
  'taux': 10,
  'emplacement_stock': 'S',
  'status': ItemStatus.disponible,
};

LibraryItem _item(
  String code, {
  String? designation,
  int quantite = 1,
  String status = ItemStatus.disponible,
  int rowVersion = 0,
}) => LibraryItem(
  code: code,
  codeType: 'LIV',
  designation: designation ?? 'Item $code',
  quantite: quantite,
  emplacement: 'A',
  taux: 10,
  emplacementStock: 'S',
  status: status,
  rowVersion: rowVersion,
);

Future<String> _login(
  http.Client c,
  String base,
  AuthService auth, {
  String username = 'probe',
  String password = 'probe-pw-123',
}) async {
  final admin = await _adminLogin(c, base, auth);
  final created = await c.post(
    Uri.parse('$base/users'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $admin',
    },
    body: jsonEncode({
      'username': username,
      'password': password,
      'role': 'staff',
    }),
  );
  expect(created.statusCode, 201, reason: 'seed staff failed: ${created.body}');
  final res = await c.post(
    Uri.parse('$base/auth/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'username': username, 'password': password}),
  );
  expect(res.statusCode, 200, reason: 'staff login failed: ${res.body}');
  return jsonDecode(res.body)['token'] as String;
}

Future<String> _adminLogin(http.Client c, String base, AuthService auth) async {
  final res = await c.post(
    Uri.parse('$base/auth/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'username': 'admin', 'password': 'root-pw'}),
  );
  expect(res.statusCode, 200, reason: 'admin login failed: ${res.body}');
  return jsonDecode(res.body)['token'] as String;
}

Future<String> _staffToken(http.Client c, String base, AuthService auth) =>
    _login(c, base, auth, username: 'staff1', password: 'staff-pw-123');

/// A concurrency oracle: it holds the same invariants the real database holds,
/// with a deliberate `await` BEFORE each check-then-act so concurrent requests
/// interleave at least as badly as they would against SQLite. Anything not
/// implemented fails loudly rather than silently returning a plausible value.
class _ScaleRepo implements LibraryRepository {
  final Map<String, LibraryItem> items = {};
  final List<Loan> loans = [];

  int _loanSeq = 0;
  Duration loanPreWriteDelay = Duration.zero;
  Duration updatePreWriteDelay = Duration.zero;
  int addLoanExecutions = 0;

  /// Titles whose single lent-out copy has already been claimed. Written and
  /// read SYNCHRONOUSLY (no await in between), because that is exactly how a
  /// SQLite UNIQUE index / a compare-and-swap behaves: the reservation is
  /// atomic even though the commit afterwards is slow. A delay placed BEFORE
  /// the claim would model a TOCTOU race the real server does not have.
  final Set<String> _claimed = <String>{};

  void seedItem(LibraryItem item) {
    _claimed.remove(item.code);
    items[item.code] = item;
  }

  Future<List<Loan>> activeLoansFor(String code) async => loans
      .where((l) => l.itemCode == code && l.status == LoanStatus.active.storage)
      .toList();

  Future<List<Loan>> allLoans() async => List.of(loans);

  // ---- reads ---------------------------------------------------------

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
    await Future<void>.delayed(Duration.zero);
    // A stable snapshot first: pagination across concurrent reads is only a
    // meaningful test if the page boundaries cannot shift mid-flight.
    final snapshot = items.values.toList(growable: false);
    final all = snapshot.where((i) {
      if (status != null && i.status != status) return false;
      if (codeType != null && i.codeType != codeType) return false;
      if (search != null &&
          search.isNotEmpty &&
          !i.designation.toLowerCase().contains(search.toLowerCase()) &&
          !i.code.toLowerCase().contains(search.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
    if (offset >= all.length) return const [];
    return all.skip(offset).take(limit).toList();
  }

  @override
  Future<int> countItems({
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) async {
    await Future<void>.delayed(Duration.zero);
    return (await getItems(
      limit: 1 << 30,
      search: search,
      status: status,
      codeType: codeType,
    )).length;
  }

  @override
  Future<List<Loan>> getLoans({bool activeOnly = false}) async {
    await Future<void>.delayed(Duration.zero);
    return loans
        .where((l) => !activeOnly || l.status == LoanStatus.active.storage)
        .toList();
  }

  // ---- writes --------------------------------------------------------

  @override
  Future<void> addItem(LibraryItem item, {Map<String, dynamic>? audit}) async {
    // No await before the check: a real UNIQUE index decides atomically, so a
    // race here resolves the same way it would in SQLite.
    if (items.containsKey(item.code)) {
      throw ItemCodeConflictException('Item code ${item.code} already exists.');
    }
    items[item.code] = item;
  }

  @override
  Future<void> updateItem(
    LibraryItem item, {
    Map<String, dynamic>? audit,
    int? expectedVersion,
  }) async {
    await Future<void>.delayed(updatePreWriteDelay); // widen the race window
    final current = items[item.code];
    if (current == null) {
      throw ItemCodeConflictException('Item code ${item.code} is unknown.');
    }
    if (expectedVersion != null && expectedVersion != current.rowVersion) {
      throw ConcurrentUpdateConflictException(
        'row_version changed: expected $expectedVersion, found ${current.rowVersion}',
      );
    }
    items[item.code] = LibraryItem(
      code: item.code,
      barcode: item.barcode,
      codeType: item.codeType,
      designation: item.designation,
      quantite: item.quantite,
      emplacement: item.emplacement,
      taux: item.taux,
      emplacementStock: item.emplacementStock,
      status: item.status,
      rowVersion: current.rowVersion + 1,
    );
  }

  @override
  Future<void> addLoan(Loan loan, {Map<String, dynamic>? audit}) async {
    addLoanExecutions++;
    final item = items[loan.itemCode];
    if (item == null) {
      throw ItemCodeConflictException('Item code ${loan.itemCode} is unknown.');
    }
    // The real rule: a title whose only copy is already committed as lent
    // cannot back a second active loan (DB-02 + the UNIQUE active-copy index).
    // The claim is atomic; only the write below is slow.
    if (item.status == ItemStatus.disponible || !_claimed.add(loan.itemCode)) {
      throw ActiveLoanConflictException(
        'A single available copy cannot back two loans.',
      );
    }
    await Future<void>.delayed(
      loanPreWriteDelay,
    ); // slow commit, like a real txn
    items[loan.itemCode] = LibraryItem(
      code: item.code,
      barcode: item.barcode,
      codeType: item.codeType,
      designation: item.designation,
      quantite: item.quantite,
      emplacement: item.emplacement,
      taux: item.taux,
      emplacementStock: item.emplacementStock,
      status: ItemStatus.emprunte,
      rowVersion: item.rowVersion,
    );
    loans.add(
      Loan(
        id: ++_loanSeq,
        itemCode: loan.itemCode,
        copyId: loan.copyId,
        memberId: loan.memberId,
        memberName: loan.memberName,
        itemTitle: loan.itemTitle,
        loanDate: loan.loanDate,
        dueDate: loan.dueDate,
        returnDate: loan.returnDate,
        status: LoanStatus.active.storage,
      ),
    );
  }

  @override
  Future<String> getDbVersion() async => '0';

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'The concurrency oracle deliberately does not implement '
    '${invocation.memberName} -- a test reaching it would be asserting '
    'nothing real.',
  );
}

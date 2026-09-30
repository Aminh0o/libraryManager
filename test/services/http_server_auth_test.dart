import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/models/loan.dart';
import 'package:library_manager/models/member.dart';
import 'package:library_manager/models/fine.dart';
import 'package:library_manager/models/reservation.dart';
import 'package:library_manager/models/report.dart';
import 'package:library_manager/services/auth_service.dart';
import 'package:library_manager/services/http_server_service.dart';
import 'package:library_manager/services/password_hasher.dart';
import 'package:library_manager/services/repository.dart';

/// In-memory [LibraryRepository] so the real server (router + auth middleware)
/// can be exercised over a socket without the SQLite/`path_provider` stack. The
/// auth behaviour under test happens entirely in the middleware, before any of
/// these methods are reached for unauthorized requests.
///
/// Exposed (not private) so the Phase 10.1 role-enforcement suite can drive the
/// same real server without duplicating a 70-line stub.
class FakeRepo implements LibraryRepository {
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
  Future<void> addItem(LibraryItem item, {Map<String, dynamic>? audit}) async {}
  @override
  Future<void> updateItem(
    LibraryItem item, {
    Map<String, dynamic>? audit,
    int? expectedVersion,
  }) async {}
  @override
  Future<void> deleteItem(String code, {Map<String, dynamic>? audit}) async {}
  @override
  Future<List<Map<String, dynamic>>> getHistory({
    int limit = 20,
    int offset = 0,
    String? subject,
  }) async => const [];
  @override
  Future<void> addHistoryEntry(Map<String, dynamic> entry) async {}
  @override
  Future<LibraryItem?> getItemByBarcode(String barcode) async => null;
  @override
  Future<Map<String, dynamic>> getStats() async => const {'totalQuantity': 0};
  @override
  Future<List<Map<String, dynamic>>> getCodeDefinitions() async => const [];
  @override
  Future<void> addCodeDefinition(
    String prefix,
    String label, {
    Map<String, dynamic>? audit,
  }) async {}
  @override
  Future<void> updateCodeDefinition(
    String oldPrefix,
    String newPrefix,
    String label, {
    Map<String, dynamic>? audit,
  }) async {}
  @override
  Future<void> deleteCodeDefinition(
    String prefix, {
    Map<String, dynamic>? audit,
  }) async {}
  @override
  Future<List<Map<String, dynamic>>> getAttributeDefinitions(
    String? type,
  ) async => const [];
  @override
  Future<void> addAttributeDefinition(
    String type,
    String value, {
    Map<String, dynamic>? audit,
  }) async {}
  @override
  Future<void> deleteAttributeDefinition(
    int id, {
    Map<String, dynamic>? audit,
  }) async {}
  @override
  Future<List<Member>> getMembers() async => const [];
  @override
  Future<void> addMember(Member member, {Map<String, dynamic>? audit}) async {}
  @override
  Future<void> updateMember(
    Member member, {
    Map<String, dynamic>? audit,
    int? expectedVersion,
  }) async {}
  @override
  Future<void> deleteMember(
    String memberId, {
    Map<String, dynamic>? audit,
  }) async {}
  @override
  Future<List<Loan>> getLoans({bool activeOnly = false}) async => const [];
  @override
  Future<void> addLoan(Loan loan, {Map<String, dynamic>? audit}) async {}
  @override
  Future<void> updateLoan(Loan loan, {Map<String, dynamic>? audit}) async {}
  @override
  Future<Loan?> findActiveLoanByScan(String scanned) async => null;
  @override
  Future<String> getDbVersion() async => '1';
  @override
  Future<String> generateMemberID() async => 'AUTO';

  // --- Fines (Phase 10.2): a tiny IN-MEMORY ledger that mirrors the exact
  // compare-and-swap semantics of the SQLite engine (a settle only succeeds on
  // a still-pending row and records the authenticated operator as resolved_by),
  // so the ROUTE layer -- role gates, 409-on-double-settle, malformed-status
  // 400 -- can be driven over a real socket without the database stack.
  FineSettings _fineSettings = FineSettings.disabled;
  final List<Fine> _fines = [];
  int _fineSeq = 0;

  /// Test helper: append an OPEN fine and return its id.
  int seedFine(String memberId, double amount, {String? reason}) {
    final id = ++_fineSeq;
    _fines.insert(
      0,
      Fine(
        id: id,
        memberId: memberId,
        amount: amount,
        status: FineStatus.pending,
        reason: reason ?? 'seed',
        createdAt: DateTime.now().toIso8601String(),
      ),
    );
    return id;
  }

  @override
  Future<FineSettings> getFineSettings() async => _fineSettings;
  @override
  Future<void> setFineSettings(
    FineSettings settings, {
    Map<String, dynamic>? audit,
  }) async {
    _fineSettings = settings;
  }

  @override
  Future<List<Fine>> getFines({String? memberId, FineStatus? status}) async => [
    for (final f in _fines)
      if ((memberId == null || f.memberId == memberId) &&
          (status == null || f.status == status))
        f,
  ];

  @override
  Future<double> outstandingBalance(String memberId) => Future.value(
    _fines
        .where((f) => f.memberId == memberId && f.status == FineStatus.pending)
        .fold<double>(0, (s, f) => s + f.amount),
  );

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
    final idx = _fines.indexWhere((f) => f.id == id);
    if (idx < 0) throw StateError('No such fine #$id.');
    if (_fines[idx].status != FineStatus.pending) {
      throw StateError('Fine #$id is already resolved.');
    }
    _fines[idx] = _fines[idx].copyWith(
      status: target,
      resolvedAt: DateTime.now().toIso8601String(),
      resolvedBy: operatorName,
    );
  }

  // --- Reservations / hold queue (Phase 10.3): a tiny IN-MEMORY queue that
  // mirrors the queue/terminal semantics of the SQLite engine (a hold only
  // ever QUEUES here -- FakeRepo models no physical copies -- and a cancel only
  // succeeds on a still-live row), so the ROUTE layer (role gates, duplicate/
  // full-queue 409, malformed status/id 400) can be driven over a real socket
  // without the database stack.
  HoldSettings _holdSettings = HoldSettings.defaults;
  final List<Reservation> _holds = [];
  int _holdSeq = 0;

  /// Test helper: append a live hold and return its id.
  int seedHold(
    String itemCode,
    String memberId, {
    ReservationStatus status = ReservationStatus.queued,
    String? availableUntil,
  }) {
    final id = ++_holdSeq;
    _holds.add(
      Reservation(
        id: id,
        itemCode: itemCode,
        memberId: memberId,
        status: status,
        createdAt: DateTime.now().toIso8601String(),
        availableUntil: availableUntil,
      ),
    );
    return id;
  }

  @override
  Future<HoldSettings> getHoldSettings() async => _holdSettings;
  @override
  Future<void> setHoldSettings(
    HoldSettings settings, {
    Map<String, dynamic>? audit,
  }) async {
    _holdSettings = settings;
  }

  @override
  Future<Reservation> placeReservation(
    String itemCode,
    String memberId, {
    Map<String, dynamic>? audit,
  }) async {
    if (itemCode.isEmpty) throw StateError('Unknown item.');
    if (memberId.isEmpty) throw StateError('Unknown member.');
    final liveForItem = _holds
        .where((h) => h.itemCode == itemCode && h.isLive)
        .toList();
    if (liveForItem.any((h) => h.memberId == memberId)) {
      throw StateError('This member already has a live hold on this item.');
    }
    if (liveForItem.length >= _holdSettings.queueMaxPerItem) {
      throw StateError(
        'The hold queue for this item is full (max ${_holdSettings.queueMaxPerItem}).',
      );
    }
    final id = ++_holdSeq;
    final res = Reservation(
      id: id,
      itemCode: itemCode,
      memberId: memberId,
      status: ReservationStatus.queued,
      createdAt: DateTime.now().toIso8601String(),
    );
    _holds.add(res);
    return res;
  }

  @override
  Future<List<Reservation>> getReservations({
    String? itemCode,
    String? memberId,
    ReservationStatus? status,
    bool liveOnly = false,
  }) async => [
    for (final h in _holds)
      if ((itemCode == null || h.itemCode == itemCode) &&
          (memberId == null || h.memberId == memberId) &&
          (status == null || h.status == status) &&
          (!liveOnly || h.isLive))
        h,
  ];

  @override
  Future<List<Reservation>> readyForPickup() async {
    final now = DateTime.now();
    return [
      for (final h in _holds)
        if (h.status == ReservationStatus.available &&
            (h.availableUntilDateTime == null ||
                !now.isAfter(h.availableUntilDateTime!)))
          h,
    ];
  }

  @override
  Future<void> cancelReservation(int id, {Map<String, dynamic>? audit}) async {
    final idx = _holds.indexWhere((h) => h.id == id);
    if (idx < 0) throw StateError('No such hold #$id.');
    if (!_holds[idx].isLive) {
      throw StateError('Hold #$id is already closed.');
    }
    _holds[idx] = _holds[idx].copyWith(
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
    // Pass 6: minimal fake for the reorder route. Records what was asked;
    // the auth tests only care about 403 vs 200 vs 400.
    final idx = _holds.indexWhere((h) => h.id == id);
    if (idx < 0) throw StateError('No such hold #$id.');
    if (_holds[idx].status != ReservationStatus.queued) {
      throw StateError('Only queued holds can be reordered.');
    }
  }

  // Echoes the requested kind + window back as a trivial table so the report
  // ROUTE tests can assert the server's role gate, kind validation, and date
  // passthrough without the SQLite stack.
  @override
  Future<Report> generateReport(
    ReportKind kind, {
    String? from,
    String? to,
  }) async => Report(
    kind: kind,
    title: kind.storage,
    generatedAt: DateTime.now().toIso8601String(),
    from: from,
    to: to,
    columns: const ['Echo'],
    rows: [
      ['${from ?? ''}|${to ?? ''}'],
    ],
    summary: const {'ok': 'yes'},
  );
}

void main() {
  late HttpServerService server;
  late AuthService auth;
  late String base;
  late http.Client client;

  setUp(() async {
    auth = AuthService(
      hasher: PasswordHasher(iterations: 1000),
      store: InMemoryAuthStore(),
      maxFailedAttempts: 3,
      lockoutWindow: const Duration(seconds: 60),
    );
    server = HttpServerService(repository: FakeRepo(), auth: auth);
    await server.startServer(host: '127.0.0.1', port: 0);
    base = 'http://127.0.0.1:${server.port}';
    client = http.Client();
  });

  tearDown(() async {
    client.close();
    await server.stopServer();
  });

  Future<http.Response> get(String path, {String? token}) => client.get(
    Uri.parse('$base$path'),
    headers: token == null ? {} : {'Authorization': 'Bearer $token'},
  );

  Future<http.Response> postJson(String path, Map<String, dynamic> body) =>
      client.post(
        Uri.parse('$base$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

  test(
    'bootstrap: routes are open while no credential is configured',
    () async {
      final res = await get('/items');
      expect(res.statusCode, 200);
    },
  );

  test(
    'enforcement: guarded routes return 401 once a password exists',
    () async {
      await auth.setPassword('s3cr3t');
      final res = await get('/items');
      expect(res.statusCode, 401);
      expect(jsonDecode(res.body)['error'], 'unauthorized');
    },
  );

  test('writes are guarded too', () async {
    await auth.setPassword('s3cr3t');
    final res = await client.delete(Uri.parse('$base/items/0001'));
    expect(res.statusCode, 401);
  });

  test('login issues a token that authorizes guarded routes', () async {
    await auth.setPassword('s3cr3t');
    final login = await postJson('/auth/login', {
      'username': 'admin',
      'password': 's3cr3t',
    });
    expect(login.statusCode, 200);
    final token = jsonDecode(login.body)['token'] as String;
    expect(token, isNotEmpty);

    final ok = await get('/items', token: token);
    expect(ok.statusCode, 200);
  });

  test(
    'login route stays reachable while everything else is guarded',
    () async {
      await auth.setPassword('s3cr3t');
      // Wrong password → 401 from the login handler (invalid_credentials),
      // NOT the generic guard's 'unauthorized'.
      final res = await postJson('/auth/login', {
        'username': 'admin',
        'password': 'nope',
      });
      expect(res.statusCode, 401);
      expect(jsonDecode(res.body)['error'], 'invalid_credentials');
    },
  );

  test('brute force locks the source (429) after max attempts', () async {
    await auth.setPassword('s3cr3t');
    expect(
      (await postJson('/auth/login', {
        'username': 'admin',
        'password': 'bad',
      })).statusCode,
      401,
    );
    expect(
      (await postJson('/auth/login', {
        'username': 'admin',
        'password': 'bad',
      })).statusCode,
      401,
    );
    final locked = await postJson('/auth/login', {
      'username': 'admin',
      'password': 'bad',
    });
    expect(locked.statusCode, 429);
    expect(jsonDecode(locked.body)['error'], 'too_many_attempts');
  });

  test('malformed login body returns 400, never crashes', () async {
    await auth.setPassword('s3cr3t');
    final res = await client.post(
      Uri.parse('$base/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: '{not json',
    );
    expect(res.statusCode, 400);
  });

  test('db-version requires auth once enforced, works with token', () async {
    await auth.setPassword('s3cr3t');
    expect((await get('/db-version')).statusCode, 401);
    final token = await auth.issueToken();
    expect((await get('/db-version', token: token)).statusCode, 200);
  });
}

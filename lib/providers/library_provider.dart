import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:excel/excel.dart' as excel_pkg;
import 'package:file_picker/file_picker.dart';
import '../models/library_item.dart';
import '../models/item_copy.dart';
import '../models/code_definition.dart';
import '../models/attribute_definition.dart';
import '../models/member.dart';
import '../models/loan.dart';
import '../models/fine.dart';
import '../models/reservation.dart';
import '../models/chat_message.dart';
import '../models/report.dart';
import '../models/user_account.dart';
import '../domain/loan_transitions.dart';
import '../services/repository.dart';
import '../services/database_service.dart';
import '../services/api_service.dart';
import '../services/api_contract.dart';
import '../services/http_server_service.dart';
import '../services/auth_service.dart';
import '../services/sqflite_auth_store.dart';
import '../services/app_logger.dart';
import '../services/pairing_guard.dart';
import '../services/pairing_protocol.dart';
import '../services/report_export.dart';
import '../services/error_messages.dart';
import '../config/app_info.dart';
import '../config/network_config.dart';
import '../l10n/app_localizations.dart';

/// Tri-state LAN link health surfaced by [LibraryProvider.connectionStatus]
/// (NET-07). Previously the header was a binary green/red: a CLIENT that lost
/// the network kept showing a confident 'Connected' for the whole 12-second
/// give-up grace window, hiding the outage. `reconnecting` (amber) is reported
/// the moment a health probe fails while the link is still nominally up.
enum LanConnectionStatus { connected, reconnecting, disconnected }

/// WHICH host-side LAN-server failure is being reported (ARC-07). The provider
/// has no `BuildContext`, so it cannot build a localized string itself; it
/// records the KIND and the screen renders it in the session's language. Kept
/// separate from the raw diagnostic text so a translation change can never
/// break a caller that only wants to know whether the server is down.
enum LanServerErrorKind { notInitialized, startFailed }

class LibraryProvider with ChangeNotifier {
  List<LibraryItem> _items = [];
  List<Member> _members = [];
  List<Loan> _loans = [];
  List<CodeDefinition> _codeDefinitions = [];
  List<AttributeDefinition> _attributes = [];
  String _searchQuery = '';
  String? _statusFilter;
  String? _codeTypeFilter;
  bool _isLoading = false;
  String? _errorMessage;
  // FE2-12: the raw error OBJECT from a failed load, so the UI can render a
  // categorized/localized message (via describeError) instead of leaking the
  // string form of the exception. _errorMessage stays as the "has error" flag.
  Object? _loadError;
  Locale _locale = const Locale('fr'); // Default to French for Algeria

  // LAN Sync Settings
  bool _isHost = true;
  String _hostIp = '';
  // Port of the host's HTTP server the client connects to. Defaults to
  // [NetworkConfig.defaultHttpPort] but is learned from the pairing response and
  // persisted (NET-01).
  int _hostPort = NetworkConfig.defaultHttpPort;
  LibraryRepository? _repository;
  HttpServerService? _server;
  // Host-only server-side authentication (credential + issued tokens).
  AuthService? _auth;
  // Bearer token received during pairing, used by client-mode ApiService.
  String? _clientToken;
  Timer? _backupTimer;
  Timer? _healthTimer;
  Timer? _immediateBackupTimer;
  bool _healthCheckBusy = false;
  int _healthFailures = 0;
  DateTime? _lastHealthSuccessAt;

  // LAN Pairing (no-camera method)
  static const int _pairingUdpPort = NetworkConfig.defaultPairingUdpPort;
  RawDatagramSocket? _pairingSocket;
  Timer? _pairingExpiryTimer;
  String? _pairingCode;
  DateTime? _pairingCodeExpiresAt;

  /// Privilege granted to the session created when [pairingCode] is redeemed
  /// (Phase 10.1). The operator chooses it explicitly; it is NOT admin by
  /// default, so pairing can no longer be a silent route to full control.
  UserRole _pairingRole = UserRole.staff;
  String? _pairingAdvertisedIp;
  // Caps wrong pairing attempts per source IP so the 6-digit code space can't
  // be brute-forced for a code's lifetime (NET-02).
  final PairingGuard _pairingGuard = PairingGuard();

  @visibleForTesting
  PairingGuard get pairingGuardForTesting => _pairingGuard;

  bool _isConnected = true;
  // Set when the host's LAN server fails to bind a socket (BE-01). Kept
  // separate from [_errorMessage] (which data loads clear) so a bind failure is
  // not silently wiped by a successful local read.
  String? _serverError;
  LanServerErrorKind? _serverErrorKind;
  String _adminPassword = '';

  // Pagination State
  int _inventoryPage = 0;
  final int _pageSize = 20;
  bool _hasMoreInventory = true;
  // Core Workflow Recovery: server-side sort + total row count so the
  // inventory table can display an honest "Showing X-Y of Z" line and keep
  // the sort stable across pages.
  int _inventoryTotal = 0;
  String? _sortColumn;
  bool _sortAscending = true;
  // Debounces server-side search so typing doesn't fire a query per keystroke,
  // and a monotonic load token so a superseded (slow) query can never overwrite
  // a newer result (Phase 7 / FE-05).
  Timer? _searchDebounce;
  int _loadSeq = 0;

  List<Map<String, dynamic>> _history = [];
  int _historyPage = 0;
  bool _hasMoreHistory = true;
  // Pass 5: the active subject filter for the global history screen. Kept on
  // the provider so scroll-to-load-more pages 2..N stay scoped to the same
  // record the operator filtered on.
  String? _historySubject;
  String _lastDbVersion = '0';
  Map<String, dynamic> _stats = {};
  final Map<String, DateTime> _activeClients = {};
  // Phase 15: the last SUCCESSFUL backup, persisted per-host so the system-
  // health center can honestly report backup freshness (and go stale) across
  // restarts. Null means "never backed up" -- surfaced as such, never faked.
  DateTime? _lastBackupAt;

  // Phase 19: the local view of the LAN staff-chat transcript. On a host the
  // authoritative buffer lives in its own [HttpServerService]; on a client this
  // mirrors what the host returns per poll. [_chatCursor] is the highest id
  // already folded in, so a poll only ever fetches new messages.
  final List<ChatMessage> _chatMessages = [];
  int _chatCursor = 0;

  // Getters
  // The list is now filtered + paginated server-side, so `items` is simply the
  // current window of rows matching the active search/filters (Phase 7 / 7.2).
  List<LibraryItem> get items => _items;
  List<LibraryItem> get allItems => _items;
  // FE2-10: expose the ACTIVE search term so a scan started elsewhere (the
  // dashboard Quick Scan) can be reflected once the operator lands on the
  // inventory view. Read-only: mutations go through search()/clearFilters().
  String get searchQuery => _searchQuery;
  Locale get locale => _locale;
  bool get isHost => _isHost;
  String get hostIp => _hostIp;
  int get hostPort => _hostPort;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Object? get loadError => _loadError;
  String? get statusFilter => _statusFilter;
  String? get codeTypeFilter => _codeTypeFilter;
  bool get isConnected => _isConnected;

  /// Whether the embedded LAN server socket is actually listening (BE-01).
  bool get serverRunning => _server?.isRunning ?? false;

  /// Non-null when the host's LAN server failed to start, so a bind failure is
  /// surfaced (and diagnosable) instead of masquerading as "connected".
  ///
  /// ARC-07: pass the session's [AppLocalizations] to get the operator's own
  /// language. The provider has no `BuildContext`, so the raw French text is
  /// only the fallback for a non-UI consumer (logs, diagnostics) -- the screens
  /// always render the localized form, and `serverErrorKind` says WHICH failure
  /// it was without depending on a translation.
  String? serverError([AppLocalizations? l10n]) {
    final kind = _serverErrorKind;
    if (kind == null) return null;
    if (l10n != null) {
      return kind == LanServerErrorKind.notInitialized
          ? l10n.errServerNotInitialized
          : l10n.errServerStartFailed;
    }
    return _serverError;
  }

  /// Which LAN-server failure is being reported (null = none), independent of
  /// any translation.
  LanServerErrorKind? get serverErrorKind => _serverErrorKind;
  bool get hasAdminPassword => _adminPassword.isNotEmpty;

  /// LAN link health for the header indicator (NET-07). A host is LAN-local and
  /// simply up/down (its server bind state, reflected in [isConnected], BE-01);
  /// a CLIENT additionally reports `reconnecting` the instant a health probe
  /// fails but before the give-up grace window is exhausted, so a brief blip
  /// shows amber instead of a false green.
  LanConnectionStatus get connectionStatus {
    if (!_isConnected) return LanConnectionStatus.disconnected;
    if (!_isHost && _healthFailures > 0) {
      return LanConnectionStatus.reconnecting;
    }
    return LanConnectionStatus.connected;
  }

  List<CodeDefinition> get codeDefinitions => _codeDefinitions;
  List<AttributeDefinition> get attributes => _attributes;
  List<Member> get members => _members;
  List<Loan> get loans => _loans;
  List<Loan> get activeLoans => _loans.where((l) => !l.isReturned).toList();
  String? get pairingCode => _pairingCode;
  DateTime? get pairingCodeExpiresAt => _pairingCodeExpiresAt;
  UserRole get pairingRole => _pairingRole;

  List<String> get locations => _attributes
      .where((a) => a.type == 'LOCATION')
      .map((a) => a.value)
      .toList();
  List<String> get statuses =>
      _attributes.where((a) => a.type == 'STATUS').map((a) => a.value).toList();

  // Pagination & History Getters
  int get inventoryPage => _inventoryPage;
  bool get hasMoreInventory => _hasMoreInventory;
  int get inventoryTotal => _inventoryTotal;
  String? get sortColumn => _sortColumn;
  bool get sortAscending => _sortAscending;
  List<Map<String, dynamic>> get history => _history;
  bool get hasMoreHistory => _hasMoreHistory;
  int get pageSize => _pageSize;
  List<String> get activeClients => _activeClients.keys
      .where(
        (ip) => DateTime.now().difference(_activeClients[ip]!).inMinutes < 5,
      )
      .toList();

  /// When a backup last succeeded (host only), or null if never. Backs the
  /// system-health backup-freshness row.
  DateTime? get lastBackupAt => _lastBackupAt;

  /// The current LAN-chat transcript (oldest first). Ephemeral: never persisted.
  List<ChatMessage> get chatMessages => List.unmodifiable(_chatMessages);

  LibraryProvider() {
    _loadSettings();
  }

  /// Test-only constructor: injects a repository and skips the settings/server
  /// bootstrap, so the provider's query wiring can be unit-tested in isolation.
  @visibleForTesting
  LibraryProvider.forTesting({
    required LibraryRepository repository,
    bool isHost = true,
    AuthService? authService,
  }) {
    _repository = repository;
    _isHost = isHost;
    // FE2-11: tests inject an authoritative AuthService so the host unlock
    // gate's server-side verification can be exercised without a real DB.
    _auth = authService;
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isHost = prefs.getBool('isHost') ?? true;
    _hostIp = prefs.getString('hostIp') ?? '';
    _hostPort = prefs.getInt('hostPort') ?? NetworkConfig.defaultHttpPort;

    // Load saved locale
    final savedLocale = prefs.getString('locale') ?? 'fr';
    _locale = Locale(savedLocale);

    // Load admin password
    _adminPassword = prefs.getString('adminPassword') ?? '';
    // Client-mode pairing token (persisted so reconnects keep working).
    _clientToken = prefs.getString('clientToken');

    // Phase 15: restore the last successful backup time for the health view.
    final lastBackup = prefs.getString('lastBackupAt');
    if (lastBackup != null) _lastBackupAt = DateTime.tryParse(lastBackup);

    await _initRepository();
  }

  Future<String?> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );

      final privateAddresses = <String>[];
      final otherAddresses = <String>[];

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          final ip = addr.address;
          if (_isPrivateIpv4(ip)) {
            privateAddresses.add(ip);
          } else {
            otherAddresses.add(ip);
          }
        }
      }

      if (privateAddresses.isNotEmpty) return privateAddresses.first;
      if (otherAddresses.isNotEmpty) return otherAddresses.first;
    } catch (e) {
      appLog.warn('net', 'Error getting local IP', e);
    }
    return null;
  }

  bool _isPrivateIpv4(String ip) {
    if (ip.startsWith('10.')) return true;
    if (ip.startsWith('192.168.')) return true;
    final parts = ip.split('.');
    if (parts.length == 4) {
      final first = int.tryParse(parts[0]);
      final second = int.tryParse(parts[1]);
      if (first == 172 && second != null && second >= 16 && second <= 31) {
        return true;
      }
    }
    return false;
  }

  Future<void> _initRepository() async {
    if (_repository is ApiService) {
      try {
        (_repository as ApiService).close();
      } catch (e) {
        // RC-07: a client-close failure was silent; record it.
        appLog.warn('net', 'Failed to close ApiService client', e);
      }
    }

    if (!_isHost && _server != null) {
      try {
        await _server!.stopServer();
      } catch (e) {
        // RC-07: a failed LAN-server stop was silent; record it.
        appLog.warn('net', 'Failed to stop LAN server on mode switch', e);
      }
      _server = null;
      _auth = null;
    }

    if (_isHost) {
      _repository = DatabaseService();
      if (_server == null) {
        // Host owns the server-side credential store + issued tokens.
        _auth ??= AuthService(
          store: SqfliteAuthStore(() => DatabaseService().database),
        );
        _server = HttpServerService(auth: _auth);
      }

      await _ensurePairingSocket();
      // Start the LAN server and reflect the REAL listen state - never report
      // "connected" when the socket failed to bind (BE-01).
      await _startHostServer();
      _healthFailures = 0;
    } else {
      if (_hostIp.trim().isEmpty) {
        _repository = null;
        _isConnected = false;
        _healthFailures = 0;
      } else {
        _repository = ApiService(
          hostIp: _hostIp,
          port: _hostPort,
          authToken: _clientToken,
        );
        // A persisted token carries no role with it, so ask the host who it
        // belongs to before the UI renders this device's privileges.
        await _revalidateSession();
        _isConnected = false;
        _healthFailures = 0;
      }
      _server = null;
      _auth = null;

      _stopPairingSocket();
    }
    if (_isHost) {
      await _loadItems();
      await _loadMembers();
      await _loadLoans();
    } else {
      _items = [];
      _members = [];
      _loans = [];
      _stats = {};
      _errorMessage = null;
      _loadError = null;
      _isLoading = false;
      notifyListeners();
    }
    _startHealthCheck();

    // Start periodic backup if host
    if (_isHost) {
      _backupTimer?.cancel();
      _backupTimer = Timer.periodic(const Duration(minutes: 30), (timer) {
        backupData().catchError((e) => appLog.error('backup', 'Auto-backup failed', e));
      });
    } else {
      _backupTimer?.cancel();
    }
  }

  /// Starts the embedded LAN server (if not already up) and mirrors the actual
  /// socket state into [isConnected] / [serverError]. A failed bind (e.g. port
  /// 8080 already in use) no longer masquerades as "connected" (BE-01).
  Future<void> _startHostServer() async {
    final server = _server;
    if (server == null) {
      _isConnected = false;
      _serverErrorKind = LanServerErrorKind.notInitialized;
      _serverError = 'Aucun serveur LAN initialisé.';
      return;
    }
    if (server.isRunning) {
      _isConnected = true;
      _serverError = null;
      _serverErrorKind = null;
      return;
    }
    try {
      await server.startServer(onActivity: updateClientActivity);
      _isConnected = server.isRunning;
      _serverErrorKind =
          _isConnected ? null : LanServerErrorKind.startFailed;
      _serverError = _isConnected
          ? null
          : 'Le serveur LAN n\'a pas pu démarrer.';
    } catch (e) {
      _isConnected = false;
      _serverErrorKind = LanServerErrorKind.startFailed;
      // The caught error stays in the French, operator-facing log line: it is
      // diagnostic text for the persisted log, not a UI string (the UI reads
      // [serverError] with the session's localizations).
      _serverError =
          'Le serveur LAN n\'a pas pu démarrer '
          '(port ${NetworkConfig.defaultHttpPort} déjà utilisé ?) : $e';
      appLog.error('server', _serverError!);
    }
  }

  @visibleForTesting
  set serverForTesting(HttpServerService? server) => _server = server;

  @visibleForTesting
  Future<void> startHostServerForTesting() => _startHostServer();

  Future<void> _ensurePairingSocket() async {
    if (_pairingSocket != null) return;
    try {
      RawDatagramSocket socket;
      if (Platform.isWindows) {
        socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          _pairingUdpPort,
          reuseAddress: true,
        );
      } else {
        try {
          socket = await RawDatagramSocket.bind(
            InternetAddress.anyIPv4,
            _pairingUdpPort,
            reuseAddress: true,
            reusePort: true,
          );
        } catch (_) {
          socket = await RawDatagramSocket.bind(
            InternetAddress.anyIPv4,
            _pairingUdpPort,
            reuseAddress: true,
          );
        }
      }
      socket.broadcastEnabled = true;
      _pairingSocket = socket;

      socket.listen((event) async {
        if (event != RawSocketEvent.read) return;
        final dg = socket.receive();
        if (dg == null) return;

        final msg = String.fromCharCodes(dg.data);
        if (!msg.startsWith('LIB_PAIR_REQ:')) return;
        final rawReq = msg.substring('LIB_PAIR_REQ:'.length).trim();
        final digits = rawReq.replaceAll(RegExp(r'\D'), '');
        final reqCode = digits.isEmpty
            ? rawReq
            : (digits.length <= 6 ? digits.padLeft(6, '0') : digits);

        assert(() {
          debugPrint(
            'Pairing: received req from ${dg.address.address}:${dg.port} code=$reqCode',
          );
          return true;
        }());

        final currentCode = _pairingCode;
        final expiresAt = _pairingCodeExpiresAt;
        final advertisedIp = _pairingAdvertisedIp;

        // Throttle: drop requests from a source that has already exceeded its
        // wrong-code budget, before revealing anything about why (NET-02).
        final sourceIp = dg.address.address;
        if (!_pairingGuard.allowAttempt(sourceIp)) {
          assert(() {
            debugPrint('Pairing: dropping throttled REQ from $sourceIp');
            return true;
          }());
          return;
        }

        if (currentCode == null || expiresAt == null) return;
        if (DateTime.now().isAfter(expiresAt)) return;
        if (reqCode != currentCode) {
          _pairingGuard.recordFailure(sourceIp);
          return;
        }
        if (advertisedIp == null || advertisedIp.isEmpty) return;

        final expiresEpochMs = expiresAt.millisecondsSinceEpoch;
        // Issue a bearer token bound to this trusted exchange. The pairing code
        // is verified above, so possession of the out-of-band code is the
        // credential; the password never crosses the wire. The code is then
        // consumed (single-use) to prevent replay and duplicate issuance from
        // the client's repeated REQ datagrams.
        //
        // Phase 10.1: the token is now bound to a NAMED, role-limited account
        // created for this pairing (`device-<code>`), so the paired client is
        // least-privileged and the session is visible + revocable in the user
        // list. Only a bootstrap install (no credential configured) still
        // mints the historical unattributed admin token.
        final token = _auth != null
            ? await _issuePairingToken(currentCode, _pairingRole)
            : '';
        // Advertise the port the server ACTUALLY bound (not a hardcoded 8080)
        // so a client reaches it even when 8080 is taken/changed (NET-01).
        final resp = encodePairingResponse(
          code: currentCode,
          ip: advertisedIp,
          port: _server?.port ?? NetworkConfig.defaultHttpPort,
          expiresEpochMs: expiresEpochMs,
          token: token,
        );
        socket.send(resp.codeUnits, dg.address, dg.port);

        // Correct code: clear this source's failure budget (it proved it was
        // handed the out-of-band code) and consume the single-use code.
        _pairingGuard.recordSuccess(sourceIp);
        _pairingExpiryTimer?.cancel();
        _pairingCode = null;
        _pairingCodeExpiresAt = null;
        _pairingAdvertisedIp = null;
        notifyListeners();

        assert(() {
          debugPrint(
            'Pairing: sent resp to ${dg.address.address}:${dg.port} ip=$advertisedIp',
          );
          return true;
        }());
      });
    } catch (e) {
      appLog.error('pairing', 'Pairing UDP socket error', e);
    }
  }

  void _stopPairingSocket() {
    _pairingExpiryTimer?.cancel();
    _pairingExpiryTimer = null;
    _pairingCode = null;
    _pairingCodeExpiresAt = null;
    _pairingAdvertisedIp = null;
    _pairingGuard.clear();

    try {
      _pairingSocket?.close();
    } catch (e) {
      // RC-07: a pairing-socket close failure was silent; record it.
      appLog.warn('pairing', 'Failed to close pairing socket', e);
    }
    _pairingSocket = null;
  }

  /// Mints the bearer token for a redeemed pairing code.
  ///
  /// Creates a dedicated named account (`device-<6 digits>`, random secret the
  /// host itself never uses) at the operator-chosen [role] and returns a token
  /// bound to it. Consequences the operator can rely on:
  ///  - the paired device is NOT admin unless admin was explicitly chosen;
  ///  - it appears in the user list and deleting that account disconnects it;
  ///  - the legacy unattributed-admin token is only used while the install has
  ///    no credential at all (bootstrap), which is the pre-10.1 behavior.
  Future<String> _issuePairingToken(String code, UserRole role) async {
    final auth = _hostAuthService();
    if (!await auth.hasCredential()) return auth.issueToken();
    final username = 'device-$code';
    try {
      final secret = _generatePairingCode() + _generatePairingCode();
      await auth.addUser(username, secret, role);
    } on UserAdminException {
      // Astronomically unlikely (a 6-digit code reused within its window), and
      // failing closed to a read-only session beats failing open to admin.
      return auth.issueTokenFor(
        TokenPrincipal(username: username, role: UserRole.viewer),
      );
    }
    return auth.issueTokenFor(TokenPrincipal(username: username, role: role));
  }

  String _generatePairingCode() {
    final rnd = Random.secure();
    return rnd.nextInt(1000000).toString().padLeft(6, '0');
  }

  Future<String> startPairingCode({
    Duration validFor = const Duration(minutes: 5),
    UserRole role = UserRole.staff,
  }) async {
    if (!_isHost) {
      throw StateError('Pairing code can only be generated on the host');
    }

    await _ensurePairingSocket();
    if (_pairingSocket == null) {
      throw StateError(
        'Failed to start pairing service (UDP port $_pairingUdpPort)',
      );
    }
    _pairingExpiryTimer?.cancel();

    final ip = await getLocalIp();
    if (ip == null || ip.isEmpty) {
      throw StateError('No LAN IPv4 address found for pairing');
    }

    final code = _generatePairingCode();
    final expiresAt = DateTime.now().add(validFor);

    _pairingCode = code;
    _pairingCodeExpiresAt = expiresAt;
    _pairingAdvertisedIp = ip;
    _pairingRole = role;

    _pairingExpiryTimer = Timer(validFor, () {
      _pairingCode = null;
      _pairingCodeExpiresAt = null;
      _pairingAdvertisedIp = null;
      notifyListeners();
    });

    notifyListeners();
    return code;
  }

  Future<List<InternetAddress>> _getBroadcastAddresses() async {
    final result = <InternetAddress>{InternetAddress('255.255.255.255')};
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          final ip = addr.address;
          if (!_isPrivateIpv4(ip)) continue;
          final parts = ip.split('.');
          if (parts.length != 4) continue;
          result.add(
            InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'),
          );
        }
      }
    } catch (e) {
      appLog.warn('pairing', 'Error computing broadcast addresses', e);
    }
    return result.toList();
  }

  Future<String?> discoverHostIpByPairingCode(
    String code, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (_isHost) return null;

    final cleanedRaw = code.trim();
    final cleanedDigits = cleanedRaw.replaceAll(RegExp(r'\D'), '');
    final cleaned = cleanedDigits.isEmpty
        ? cleanedRaw
        : (cleanedDigits.length <= 6
              ? cleanedDigits.padLeft(6, '0')
              : cleanedDigits);
    if (cleaned.isEmpty) return null;

    RawDatagramSocket? socket;
    try {
      if (Platform.isWindows) {
        try {
          socket = await RawDatagramSocket.bind(
            InternetAddress.anyIPv4,
            _pairingUdpPort,
            reuseAddress: true,
          );
        } catch (_) {
          socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        }
      } else {
        try {
          socket = await RawDatagramSocket.bind(
            InternetAddress.anyIPv4,
            _pairingUdpPort,
            reuseAddress: true,
            reusePort: true,
          );
        } catch (_) {
          try {
            socket = await RawDatagramSocket.bind(
              InternetAddress.anyIPv4,
              _pairingUdpPort,
              reuseAddress: true,
            );
          } catch (_) {
            socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
          }
        }
      }
      socket.broadcastEnabled = true;

      final broadcastTargets = await _getBroadcastAddresses();
      final msg = 'LIB_PAIR_REQ:$cleaned';

      assert(() {
        debugPrint('Pairing discovery: code=$cleaned udpPort=$_pairingUdpPort');
        debugPrint(
          'Pairing discovery: broadcastTargets=${broadcastTargets.map((e) => e.address).toList()}',
        );
        return true;
      }());

      final completer = Completer<String?>();
      late StreamSubscription sub;

      sub = socket.listen((event) async {
        if (event != RawSocketEvent.read) return;
        final dg = socket!.receive();
        if (dg == null) return;

        final resp = String.fromCharCodes(dg.data);
        if (!resp.startsWith('LIB_PAIR_RESP:')) return;

        assert(() {
          debugPrint(
            'Pairing discovery: got resp from ${dg.address.address}:${dg.port}',
          );
          return true;
        }());

        final parsed = decodePairingResponse(
          resp,
          expectedCode: cleaned,
          now: DateTime.now(),
        );
        if (parsed == null) return;

        // Learn + persist the host's real bound port so this session and every
        // later reconnect dial the right port (NET-01). The optional token is
        // the bearer credential issued during pairing (clients never send the
        // admin password over the wire).
        _hostPort = parsed.port;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('hostPort', parsed.port);
        final tk = parsed.token;
        if (tk != null && tk.isNotEmpty) {
          _clientToken = tk;
          await prefs.setString('clientToken', tk);
        }

        if (!completer.isCompleted) {
          completer.complete(parsed.ip);
        }
      });

      for (var attempt = 0; attempt < 3; attempt++) {
        for (final addr in broadcastTargets) {
          socket.send(msg.codeUnits, addr, _pairingUdpPort);
        }
        await Future.delayed(const Duration(milliseconds: 250));
      }

      if (!completer.isCompleted) {
        final localIp = await getLocalIp();
        final parts = localIp?.split('.') ?? const <String>[];
        final canScan =
            localIp != null && _isPrivateIpv4(localIp) && parts.length == 4;
        if (canScan) {
          final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
          assert(() {
            debugPrint(
              'Pairing discovery: fallback unicast scan prefix=$prefix',
            );
            return true;
          }());
          for (var i = 1; i <= 254; i++) {
            if (completer.isCompleted) break;
            final candidate = '$prefix.$i';
            if (candidate == localIp) continue;
            socket.send(
              msg.codeUnits,
              InternetAddress(candidate),
              _pairingUdpPort,
            );
            if (i % 32 == 0) {
              await Future<void>.delayed(Duration.zero);
            }
          }
        }
      }

      final found = await completer.future.timeout(
        timeout,
        onTimeout: () => null,
      );
      await sub.cancel();
      return found;
    } catch (e) {
      appLog.warn('pairing', 'Pairing discovery error', e);
      return null;
    } finally {
      try {
        socket?.close();
      } catch (e) {
        // RC-07: a discovery-socket close failure was silent; record it.
        appLog.warn('pairing', 'Failed to close discovery socket', e);
      }
    }
  }

  /// The identity/role this DEVICE currently holds on the host (Phase 10.1).
  /// On the HOST it is always admin -- the local DatabaseService path is the
  /// operator's own machine and is not HTTP-guarded by design. On a CLIENT it is
  /// learned from the login response, or re-derived from `GET /auth/session`
  /// after a restart, and defaults to [UserRole.viewer] when unknown, so a
  /// client can never show more affordances than the server would honour.
  UserRole get sessionRole {
    if (_isHost) return UserRole.admin;
    final repo = _repository;
    return repo is ApiService ? repo.sessionRole : UserRole.viewer;
  }

  String? get sessionUsername {
    if (_isHost) return AuthService.adminUsername;
    final repo = _repository;
    return repo is ApiService ? repo.sessionUsername : null;
  }

  /// May this device mutate data? Drives every write affordance (add/edit
  /// item, borrow, return, member edits). SERVER ENFORCEMENT IS INDEPENDENT --
  /// a client that ignores this simply receives a 403.
  bool get canWrite => sessionRole.atLeast(UserRole.staff);

  /// May this device administer accounts and code/attribute vocabularies?
  bool get canAdminister => sessionRole.atLeast(UserRole.admin);

  bool get hasSession => sessionUsername != null;

  /// Client-mode: sign in to the host as a NAMED account (Phase 10.1) and keep
  /// the granted identity+role for role-aware UI. Returns null on rejection
  /// (wrong credentials -- or a lockout, which the host reports as 429 and this
  /// surfaces identically to a denial so accounts cannot be enumerated).
  Future<LoginSession?> loginUser({
    required String username,
    required String password,
  }) async {
    if (_isHost) return null;
    final repo = _repository;
    if (repo is! ApiService) return null;
    final session = await repo.login(username, password);
    if (session == null || !session.isValid) return null;
    _clientToken = session.token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('clientToken', session.token);
    notifyListeners();
    return session;
  }

  /// Re-derives this client's identity+role from its bearer token, so a
  /// restarted device that kept a persisted token still knows (and shows) the
  /// right privilege level. Silent on failure: the viewer default stands.
  Future<void> _revalidateSession() async {
    if (_isHost) return;
    final repo = _repository;
    if (repo is! ApiService) return;
    if (repo.authToken == null || repo.authToken!.isEmpty) return;
    try {
      final s = await repo.currentSession();
      if (s != null) {
        repo.sessionRole = s.role;
        repo.sessionUsername = s.username;
        notifyListeners();
      }
    } catch (_) {
      /* keep the least-privileged default */
    }
  }

  /// Client-mode: authenticate to the host with the admin password to obtain a
  /// bearer token, for manual-IP connections that skip the pairing code. The
  /// token is persisted so subsequent requests (and restarts) stay authorized.
  Future<bool> authenticateHost(String password) async {
    final s = await loginUser(
      username: AuthService.adminUsername,
      password: password,
    );
    return s != null;
  }

  /// Client-mode: forget this device's bearer credential and learned identity,
  /// returning it to a signed-out, least-privileged ([UserRole.viewer]) state so
  /// the UI hides write affordances immediately. The token still expires on the
  /// host on its own; this only clears what THIS device holds and persists.
  Future<void> signOut() async {
    if (_isHost) return;
    _clientToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('clientToken');
    final repo = _repository;
    if (repo is ApiService) {
      repo.authToken = null;
      repo.sessionRole = UserRole.viewer;
      repo.sessionUsername = null;
    }
    notifyListeners();
  }

  // ==========================================================================
  // User administration (Phase 10.1). The UI calls ONLY these; each one runs
  // on the HOST's authoritative AuthService when this device is the host, and
  // over the ADMIN-guarded HTTP surface when it is a client -- so the same
  // least-privilege rules apply from either side and no client can talk itself
  // into a higher role by editing its own UI state.
  // ==========================================================================

  Future<List<UserRecord>> listUsers() async {
    _requireAdmin();
    if (_isHost) return _hostAuthService().users();
    final repo = _repository;
    if (repo is! ApiService) {
      throw UserAdminException('Not connected to the library host.');
    }
    return repo.fetchUsers();
  }

  Future<void> createUser({
    required String username,
    required String password,
    required UserRole role,
  }) async {
    _requireAdmin();
    if (_isHost) {
      await _hostAuthService().addUser(username, password, role);
      return;
    }
    final repo = _repository;
    if (repo is! ApiService) {
      throw UserAdminException('Not connected to the library host.');
    }
    await repo.createUser(username: username, password: password, role: role);
  }

  Future<void> changeUserRole(String username, UserRole role) async {
    _requireAdmin();
    if (_isHost) {
      await _hostAuthService().changeUserRole(username, role);
      return;
    }
    final repo = _repository;
    if (repo is! ApiService) {
      throw UserAdminException('Not connected to the library host.');
    }
    await repo.setUserRole(username, role);
    await _revalidateSession();
  }

  Future<void> setUserPassword({
    required String username,
    required String password,
  }) async {
    _requireAdmin();
    if (_isHost) {
      await _hostAuthService().setUserPassword(username, password);
      return;
    }
    final repo = _repository;
    if (repo is! ApiService) {
      throw UserAdminException('Not connected to the library host.');
    }
    await repo.setUserPassword(username, password);
  }

  Future<void> removeUser(String username) async {
    _requireAdmin();
    if (_isHost) {
      await _hostAuthService().removeUser(username);
      return;
    }
    final repo = _repository;
    if (repo is! ApiService) {
      throw UserAdminException('Not connected to the library host.');
    }
    await repo.deleteUser(username);
    await _revalidateSession();
  }

  /// Client-side mirror of the server's admin requirement, so the UI can refuse
  /// up front instead of firing a request it knows will 403. This is USER-FACING
  /// convenience only; the ROUTE GUARD remains the actual enforcement point.
  void _requireAdmin() {
    if (!canAdminister) {
      throw UserAdminException(
        'Only an administrator can manage accounts and roles.',
      );
    }
  }

  // ==========================================================================
  // Fines & payments (Phase 10.2). MONEY RULES and role gates are enforced
  // SERVER-SIDE: the host accrues a fine inside the return transaction and
  // refuses a non-staff settle, and an already-resolved fine cannot be settled
  // twice. These client-side guards simply avoid firing a request the caller
  // already knows will be refused. Both host and remote client flow through the
  // SAME [LibraryRepository] seam (DatabaseService vs ApiService). The operator
  // recorded against a settlement is ALWAYS the current session principal
  // ([sessionUsername]) -- never a caller-supplied name -- so a payment can
  // never be attributed to someone else.
  // ==========================================================================

  /// The authenticated identity charged with a pay/waive, mirrored to the host
  /// repository for `resolved_by`; a client's server derives it from the token.
  String? get _fineOperator => hasSession ? sessionUsername : null;

  /// Least-privilege guard for staff-level fine actions (read the ledger,
  /// pay, waive) -- the client-side twin of the server's `staff` route gate.
  void _requireFineStaff() {
    if (!canWrite) {
      throw StateError('Only staff can view or settle fines.');
    }
  }

  /// Guard for authoring the fine POLICY, which the server reserves for admins.
  void _requireFineAdmin() {
    if (!canAdminister) {
      throw StateError('Only an administrator can change the fine policy.');
    }
  }

  Future<FineSettings> getFineSettings() async {
    _requireFineStaff();
    return _repository!.getFineSettings();
  }

  Future<void> setFineSettings(FineSettings settings) async {
    _requireFineAdmin();
    await _repository!.setFineSettings(
      settings,
      audit: _hostAudit(
        'FINE_SETTINGS',
        'Taux de retard: ${settings.ratePerDay} ${settings.currency}/jour',
      ),
    );
  }

  Future<List<Fine>> getFines({String? memberId, FineStatus? status}) async {
    _requireFineStaff();
    return _repository!.getFines(memberId: memberId, status: status);
  }

  /// Phase 15: an on-demand read of currently-active loans straight from the
  /// authoritative source (host DB or the LAN API), so the notification center
  /// reports a real overdue count for both host and client instead of trusting
  /// whatever is cached in the visible window.
  Future<List<Loan>> fetchActiveLoans() async {
    if (_repository == null) return const [];
    return _repository!.getLoans(activeOnly: true);
  }

  /// Phase 19: post a LAN-chat message. On the host this writes straight into
  /// its own in-process buffer (the same one clients read over HTTP); on a
  /// client it goes to the host's `/chat` route. Throws when there is no live
  /// channel (server stopped / not an API client) so the UI cannot claim a
  /// message was sent when it was not.
  Future<void> sendChatMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (_isHost) {
      final server = _server;
      if (server == null) {
        throw StateError('The LAN server is not running.');
      }
      server.postChatLocal(
        sessionUsername ?? AuthService.adminUsername,
        UserRole.admin.storage,
        trimmed,
      );
      await refreshChat();
      return;
    }
    final api = _repository;
    if (api is ApiService) {
      await api.sendChat(trimmed);
      await refreshChat();
    } else {
      throw StateError('Chat is unavailable on this device.');
    }
  }

  /// Phase 19: pull any chat messages newer than the cursor into the local
  /// view. Cheap and idempotent; the chat UI polls it on a timer while open.
  Future<void> refreshChat() async {
    var res = await _readChat();
    if (res == null) return;
    // The host's buffer is ephemeral; if its sequence has gone backwards the
    // host restarted, so drop the stale transcript rather than show a mix.
    if (res.latest < _chatCursor) {
      _chatMessages.clear();
      _chatCursor = 0;
      res = await _readChat();
      if (res == null) return;
    }
    if (res.messages.isEmpty && _chatCursor == res.latest) return;
    _chatMessages.addAll(res.messages);
    if (_chatMessages.length > 500) {
      _chatMessages.removeRange(0, _chatMessages.length - 500);
    }
    _chatCursor = res.latest;
    notifyListeners();
  }

  Future<({List<ChatMessage> messages, int latest})?> _readChat() async {
    if (_isHost) {
      final server = _server;
      if (server == null) return null;
      return server.chatSinceLocal(_chatCursor);
    }
    final api = _repository;
    if (api is ApiService) return api.fetchChat(_chatCursor);
    return null;
  }

  Future<double> outstandingBalance(String memberId) async {
    _requireFineStaff();
    return _repository!.outstandingBalance(memberId);
  }

  Future<void> payFine(int id) async {
    _requireFineStaff();
    await _repository!.payFine(
      id,
      operatorName: _fineOperator,
      audit: _hostAudit('FINE_PAY', 'Amende #$id payée'),
    );
  }

  Future<void> waiveFine(int id) async {
    _requireFineStaff();
    await _repository!.waiveFine(
      id,
      operatorName: _fineOperator,
      audit: _hostAudit('FINE_WAIVE', 'Amende #$id annulée'),
    );
  }

  // ==========================================================================
  // Reservations / hold queue (Phase 10.3). QUEUE RULES and role gates are
  // enforced SERVER-SIDE: the host owns the line, claims a copy only at
  // promotion, refuses a walk-up that would cut a promoted holder, and closes
  // an already-terminal hold with a 409. These client-side guards simply avoid
  // firing a request the caller already knows will be refused; both host and
  // remote client flow through the SAME [LibraryRepository] seam. Cancelling a
  // promoted hold releases its copy and promotes the next holder atomically.
  // ==========================================================================

  /// Least-privilege guard for staff-level hold actions (place/read/cancel a
  /// hold, view the ready shelf) -- the client-side twin of the server's
  /// `staff` route gate.
  void _requireHoldStaff() {
    if (!canWrite) {
      throw StateError('Only staff can manage holds.');
    }
  }

  /// Guard for authoring the hold POLICY, which the server reserves for admins.
  void _requireHoldAdmin() {
    if (!canAdminister) {
      throw StateError('Only an administrator can change the hold policy.');
    }
  }

  Future<HoldSettings> getHoldSettings() async {
    _requireHoldStaff();
    return _repository!.getHoldSettings();
  }

  Future<void> setHoldSettings(HoldSettings settings) async {
    _requireHoldAdmin();
    await _repository!.setHoldSettings(
      settings,
      audit: _hostAudit(
        'HOLD_SETTINGS',
        'Hold policy: pickup ${settings.pickupDays}d, queue cap ${settings.queueMaxPerItem}',
      ),
    );
  }

  Future<Reservation> placeReservation(
      String itemCode, String memberId) async {
    _requireHoldStaff();
    return _repository!.placeReservation(
      itemCode,
      memberId,
      audit: _hostAudit(
          'HOLD_PLACE', 'Hold placed: $memberId for $itemCode'),
    );
  }

  Future<List<Reservation>> getReservations({
    String? itemCode,
    String? memberId,
    ReservationStatus? status,
    bool liveOnly = false,
  }) async {
    _requireHoldStaff();
    return _repository!.getReservations(
      itemCode: itemCode,
      memberId: memberId,
      status: status,
      liveOnly: liveOnly,
    );
  }

  Future<List<Reservation>> readyForPickup() async {
    _requireHoldStaff();
    return _repository!.readyForPickup();
  }

  Future<void> cancelReservation(int id) async {
    _requireHoldStaff();
    await _repository!.cancelReservation(
      id,
      audit: _hostAudit('HOLD_CANCEL', 'Hold #$id cancelled'),
    );
  }

  /// Pass 6: swap a queued hold with its immediate neighbour in the same
  /// item's line. Same permission + audit-row shape as [cancelReservation];
  /// the [up] flag decides direction and the operation label. A boundary
  /// row is a no-op server-side (the swap sees no neighbour) and the audit
  /// line is skipped on no-ops so the trail never records a non-change.
  Future<void> moveReservation(int id, {required bool up}) async {
    _requireHoldStaff();
    await _repository!.moveReservation(
      id,
      up: up,
      audit: _hostAudit(
        up ? 'HOLD_MOVE_UP' : 'HOLD_MOVE_DOWN',
        'Hold #$id moved ${up ? 'up' : 'down'}',
      ),
    );
  }

  // ==========================================================================
  // Reports (Phase 10.4). READ-ONLY and computed SERVER-SIDE; the client-side
  // guard simply avoids a request the server would refuse with a 403. Host and
  // LAN client go through the SAME [LibraryRepository] seam, so both receive
  // byte-identical aggregates for the same kind + window.
  // ==========================================================================

  /// Least-privilege guard for reading a report -- the client-side twin of the
  /// server's `staff` route gate (a report exposes patron + financial data).
  void _requireReportStaff() {
    if (!canWrite) {
      throw StateError('Only staff can run reports.');
    }
  }

  Future<Report> generateReport(
    ReportKind kind, {
    String? from,
    String? to,
  }) async {
    _requireReportStaff();
    return _repository!.generateReport(kind, from: from, to: to);
  }

  /// Resolves where an export should be written (BL-09 / plan 11b). On a
  /// desktop with a working platform handler this lets the user choose the
  /// location; DISMISSING that dialog returns `null` so the caller writes
  /// NOTHING and reports no success (no false "Saved" message). When no OS
  /// handler is available (an unsupported platform, or a unit test where the
  /// plugin is not registered and `saveFile` throws), we fall back to the
  /// historical Documents path so behavior there is unchanged.
  Future<String?> _exportTargetPath(
      String fileName, List<String> extensions) async {
    String? chosen;
    var handlerAvailable = true;
    try {
      chosen = await FilePicker.platform.saveFile(
        dialogTitle: fileName,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: extensions,
      );
    } catch (_) {
      // LateInitializationError / UnimplementedError: no OS save dialog here.
      handlerAvailable = false;
    }
    if (handlerAvailable) {
      return chosen; // null => user cancelled; a path => honor it
    }
    final docsDir = await getApplicationDocumentsDirectory();
    return p.join(docsDir.path, fileName);
  }

  /// Writes a computed [Report] to CSV and returns the path, or `null` if the
  /// user cancelled the save dialog. The bytes come from the SAME server-
  /// authored [Report] the screen is showing (never re-derived on the client),
  /// and the export is gated by the same staff guard as the read (a report
  /// leaks patron + financial data).
  Future<String?> exportReportCsv(Report report,
      {Map<String, String>? labels}) async {
    _requireReportStaff();
    final csv = ReportExport.toCsv(report, labels: labels);
    final filePath = await _exportTargetPath(
        '${ReportExport.baseName(report)}.csv', const ['csv']);
    if (filePath == null) return null; // user cancelled -> nothing written
    await File(filePath).writeAsString(csv);
    return filePath;
  }

  /// Writes a computed [Report] to a landscape-A4 PDF and returns the path, or
  /// `null` if the user cancelled (finally exercising the declared `pdf`
  /// dependency, ARC-04). Same server-authored source + same staff gate as
  /// [exportReportCsv].
  Future<String?> exportReportPdf(Report report,
      {Map<String, String>? labels}) async {
    _requireReportStaff();
    // NET-11 (P20): build the PDF off the UI isolate so a large report cannot
    // freeze the desktop; the bytes are identical to a synchronous toPdfBytes.
    final bytes = await buildReportPdfOffIsolate(report.toMap(), labels: labels);
    final filePath = await _exportTargetPath(
        '${ReportExport.baseName(report)}.pdf', const ['pdf']);
    if (filePath == null) return null; // user cancelled -> nothing written
    await File(filePath).writeAsBytes(bytes);
    return filePath;
  }

  /// ARC-06: bundles a small, credential-free diagnostics report (app version,
  /// schema version, host/client mode, OS) plus the current + rotated log
  /// files (already secret-scrubbed by [AppLogger.readLogContents]) to a
  /// user-chosen path. Admin-gated: a diagnostics file can reveal internal
  /// paths and operation traces, so only an administering session may export
  /// it. Returns the written path, or `null` if the user cancelled the save
  /// dialog. Flushes the logger first so the newest lines are on disk.
  Future<String?> exportDiagnostics() async {
    if (!canAdminister) {
      throw StateError('Admin access required');
    }
    await appLog.flush();
    final logs = await appLog.readLogContents();
    final ts = DateTime.now().toUtc();
    final header = StringBuffer()
      ..writeln('Library Manager diagnostics')
      ..writeln('generated_utc: ${ts.toIso8601String()}')
      ..writeln('app_version: $kAppVersion')
      ..writeln('db_version: ${DatabaseService.currentSchemaVersion}')
      ..writeln('mode: ${_isHost ? 'host' : 'client'}')
      ..writeln('platform: ${Platform.operatingSystem} '
          '(${Platform.operatingSystemVersion})')
      ..writeln('dart_version: ${Platform.version}')
      ..writeln('--- log (${appLog.logFile?.path ?? 'no file sink'}) ---');
    final bundle = '${header.toString()}$logs';
    final fileName =
        'library_diagnostics_${ts.toIso8601String().replaceAll(':', '-')}.txt';
    final filePath = await _exportTargetPath(fileName, const ['txt']);
    if (filePath == null) return null; // user cancelled -> nothing written
    appLog.info('diagnostics', 'Exported diagnostics bundle');
    await File(filePath).writeAsString(bundle);
    return filePath;
  }

  Future<void> updateSettings(bool isHost, String hostIp, {int? port}) async {
    _isHost = isHost;
    _hostIp = hostIp;
    if (port != null) _hostPort = port;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isHost', isHost);
    await prefs.setString('hostIp', hostIp);
    await prefs.setInt('hostPort', _hostPort);

    await _initRepository();
    notifyListeners();
  }

  void setLocale(Locale locale) async {
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', locale.languageCode);
    notifyListeners();
  }

  // Password Management
  bool checkPassword(String password) {
    if (_adminPassword.isEmpty) return true; // No password set

    // Check if stored password is a SHA-256 hash (64 chars hex)
    final isHash =
        _adminPassword.length == 64 &&
        RegExp(r'^[a-f0-9]+$').hasMatch(_adminPassword);

    if (isHash) {
      final inputHash = sha256.convert(utf8.encode(password)).toString();
      return _adminPassword == inputHash;
    } else {
      // Temporary plain-text support for migration
      return _adminPassword == password;
    }
  }

  /// The host's server-side authentication service, created on first use. The
  /// app-wide singleton DB backs it, so it sees the same salted credential the
  /// running LAN server enforces.
  AuthService _hostAuthService() => _auth ??= AuthService(
    store: SqfliteAuthStore(() => DatabaseService().database),
  );

  /// Authoritative unlock for sensitive settings/admin actions (FE2-11).
  ///
  /// On the HOST this verifies against the SERVER-side salted credential, not
  /// the local SharedPreferences hash used by [checkPassword] — whose empty
  /// default let any operator on the host machine unlock reconfiguration,
  /// history, erase and reset without ever proving the admin password. When no
  /// credential has been configured yet the host runs bootstrap-open (matching
  /// the LAN API policy: nothing is protected until a password is set, so an
  /// unconfigured operator is never locked out). On a CLIENT the sensitive
  /// server-backed routes are already guarded by the bearer token, so the local
  /// gate is retained to avoid breaking pre-password reconnection.
  Future<bool> verifyAdminPassword(String password) async {
    if (!_isHost) return checkPassword(password);
    final auth = _hostAuthService();
    if (!await auth.enforcementActive()) {
      return true; // bootstrap: no password set
    }
    return auth.verifyPassword(password);
  }

  /// Whether an admin password is CURRENTLY enforced, i.e. whether changing it
  /// must first prove the existing one. On the HOST this reads the SERVER-side
  /// credential state (authoritative, FE2-11), so a host whose credential is set
  /// but whose LOCAL prefs copy is empty can no longer skip the old-password
  /// step. On a CLIENT it reflects the local gate. Bootstrap (no credential yet)
  /// reports false so first-time setup is never demanded an old password.
  Future<bool> passwordEnforcementActive() async {
    if (!_isHost) return _adminPassword.isNotEmpty;
    return _hostAuthService().enforcementActive();
  }

  Future<void> changePassword(String newPassword) async {
    final hashed = sha256.convert(utf8.encode(newPassword)).toString();
    _adminPassword = hashed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('adminPassword', hashed);

    // Server-side, salted PBKDF2 credential on the host. Setting a password is
    // what activates LAN-API authentication (SEC-01/NET-01); clearing it turns
    // enforcement back to bootstrap-open. The local prefs SHA-256 above is kept
    // only for the existing client-side UI confirmation gate (unchanged).
    if (_isHost) {
      try {
        _auth ??= AuthService(
          store: SqfliteAuthStore(() => DatabaseService().database),
        );
        if (newPassword.isEmpty) {
          await _auth!.reset();
        } else {
          await _auth!.setPassword(newPassword);
        }
      } catch (e) {
        appLog.error('auth', 'Server credential update failed', e);
      }
    }
    notifyListeners();
  }

  // Connectivity Health Check
  void _startHealthCheck() {
    _healthTimer?.cancel();
    final interval = _isHost
        ? const Duration(seconds: 1)
        : const Duration(seconds: 2);
    _healthTimer = Timer.periodic(interval, (timer) async {
      if (_healthCheckBusy) return;
      _healthCheckBusy = true;
      try {
        if (_isHost) {
          // Host is always LAN-local. Also watch for DB changes caused by clients.
          if (!_isConnected) {
            _isConnected = true;
            notifyListeners();
          }

          try {
            final repo = _repository;
            if (repo is DatabaseService) {
              final version = await repo.getDbVersion();
              if (_lastDbVersion != version) {
                _lastDbVersion = version;
                await _reloadAll();
              }
            }
          } catch (e) {
            appLog.warn('sync', 'Host db_version watch error', e);
          }
        } else {
          try {
            final repo = _repository;
            if (repo is! ApiService) {
              _onClientProbeFailure();
              return;
            }
            final api = repo;
            final version = await api.getDbVersion().timeout(
              const Duration(seconds: 3),
            );
            final wasDegraded = _healthFailures > 0;
            _healthFailures = 0;
            _lastHealthSuccessAt = DateTime.now();

            if (!_isConnected) {
              _isConnected = true;
              _lastDbVersion = version;
              await _reloadAll();
              notifyListeners();
            } else if (version != _lastDbVersion) {
              _lastDbVersion = version;
              await _reloadAll();
            } else if (wasDegraded) {
              // Recovered from the amber 'reconnecting' grace window with the
              // data unchanged, so no reload fired a notify; refresh the header.
              notifyListeners();
            }
          } catch (_) {
            _onClientProbeFailure();
          }
        }
      } finally {
        _healthCheckBusy = false;
      }
    });
  }

  /// Shared handling for a failed CLIENT health probe (NET-07). Counts the
  /// consecutive failure and only declares the link truly down once BOTH at
  /// least 3 failures AND the last success is older than the 12s grace window
  /// have elapsed. It always notifies, so [connectionStatus] can turn the
  /// header amber on the FIRST blip rather than holding a false green. The
  /// periodic timer and the test seam both run through here, so the production
  /// give-up rule is the exact code under test.
  void _onClientProbeFailure() {
    _healthFailures++;
    if (_isConnected) {
      final lastOk = _lastHealthSuccessAt;
      final tooOld =
          lastOk == null ||
          DateTime.now().difference(lastOk) > const Duration(seconds: 12);
      if (_healthFailures >= 3 && tooOld) {
        _isConnected = false;
      }
    }
    notifyListeners();
  }

  /// Test-only: drives the SAME client probe accounting the periodic health
  /// check uses, so the connected -> reconnecting -> (grace) -> disconnected
  /// transitions and the amber -> green recovery are provable without a real
  /// socket or the wall-clock grace delay.
  @visibleForTesting
  Future<void> clientProbeForTesting({
    required bool success,
    String? version,
  }) async {
    if (!success) {
      _onClientProbeFailure();
      return;
    }
    final wasDegraded = _healthFailures > 0;
    _healthFailures = 0;
    _lastHealthSuccessAt = DateTime.now();
    if (!_isConnected) {
      _isConnected = true;
      _lastDbVersion = version ?? _lastDbVersion;
      await _reloadAll();
    } else if (version != null && version != _lastDbVersion) {
      _lastDbVersion = version;
      await _reloadAll();
    } else if (wasDegraded) {
      notifyListeners();
    }
  }

  /// Test-only: back-date the last successful probe so the 12s give-up grace
  /// window can be expired deterministically.
  @visibleForTesting
  set lastHealthSuccessForTesting(DateTime? t) => _lastHealthSuccessAt = t;

  Future<void> _reloadAll() async {
    await _loadItems();
    await _loadMembers();
    await _loadLoans();
  }

  Future<void> _loadItems({bool more = false, bool keepWindow = false}) async {
    if (_repository == null) return;
    if (more && !_hasMoreInventory) return;

    // A post-mutation refresh (FE2-13) must NOT collapse the list back to the
    // first page: re-pull the SAME window the operator has already scrolled
    // through, so their row count and scroll position survive an add/edit/
    // delete. Any other load pulls exactly one page.
    int limit = _pageSize;
    if (keepWindow) {
      final pages = (_items.length + _pageSize - 1) ~/ _pageSize;
      limit = (pages < 1 ? 1 : pages) * _pageSize;
    }

    final seq = ++_loadSeq;
    _isLoading = true;
    _errorMessage = null;
    _loadError = null;
    if (!more) {
      _inventoryPage = 0;
      _items = [];
    }
    notifyListeners();

    // Search / filter / pagination are applied by the SERVER (Phase 7 / 7.2):
    // the same filters go to getItems AND countItems, so the page shown and the
    // "has more" decision agree over the WHOLE catalogue, not a cached page
    // (FE-05 / FE2-05).
    final search = _searchQuery.trim().isEmpty ? null : _searchQuery;
    try {
      final newItems = await _repository!.getItems(
        limit: limit,
        offset: _inventoryPage * _pageSize,
        search: search,
        status: _statusFilter,
        codeType: _codeTypeFilter,
        sort: _sortColumn,
        ascending: _sortAscending,
      );
      final total = await _repository!.countItems(
        search: search,
        status: _statusFilter,
        codeType: _codeTypeFilter,
      );
      _inventoryTotal = total;

      // A newer load (e.g. a fresh search) superseded this one — drop its
      // results so pages from different queries never interleave.
      if (seq != _loadSeq) return;

      if (more) {
        _items.addAll(newItems);
      } else {
        _items = newItems;
      }
      _hasMoreInventory = _items.length < total;
      // Keep `inventoryPage` as the 0-based index of the NEXT page so a later
      // loadMoreItems() continues exactly after the current window. Equivalent
      // to the previous `++` for one-page loads, and correct for the wider
      // keepWindow refresh (which loads several pages in one query).
      if (_hasMoreInventory) _inventoryPage = _items.length ~/ _pageSize;

      // Load code definitions
      final defs = await _repository!.getCodeDefinitions();
      _codeDefinitions = defs.map((d) => CodeDefinition.fromMap(d)).toList();

      // Load attribute definitions
      final attrDefs = await _repository!.getAttributeDefinitions(null);
      _attributes = attrDefs
          .map((a) => AttributeDefinition.fromMap(a))
          .toList();

      // Update Stats
      _stats = await _repository!.getStats();
    } catch (e) {
      _loadError = e;
      _errorMessage =
          'load-error'; // sentinel; dashboard localizes via describeError
      appLog.error('load', 'Load failed', e);
    } finally {
      if (seq == _loadSeq) _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreItems() => _loadItems(more: true);

  /// Core Workflow Recovery: read-only item lookup used by the command
  /// palette's global search. Runs a bounded query against the repository
  /// WITHOUT mutating [_searchQuery] or triggering a full `_loadItems`, so a
  /// user who opens Ctrl+K and presses Escape leaves no trace on the visible
  /// inventory. Errors collapse to an empty list -- the palette then shows
  /// only the navigation entries rather than throwing.
  Future<List<LibraryItem>> itemMatches(String query, {int limit = 6}) async {
    final repo = _repository;
    if (repo == null) return const [];
    final trimmed = query.trim();
    try {
      return await repo.getItems(
        limit: limit,
        offset: 0,
        search: trimmed.isEmpty ? null : trimmed,
      );
    } catch (_) {
      return const [];
    }
  }

  /// Core Workflow Recovery: change the inventory sort column / direction.
  /// Passing a null `column` clears the sort and reverts to the default
  /// (code_type, code) ordering. The change re-queries from the first page so
  /// the operator does not see an inconsistent tail of a stale window.
  Future<void> setSort(String? column, {bool? ascending}) async {
    final nextColumn = column;
    final nextAscending = ascending ??
        (nextColumn == _sortColumn ? !_sortAscending : true);
    if (_sortColumn == nextColumn && _sortAscending == nextAscending) return;
    _sortColumn = nextColumn;
    _sortAscending = nextAscending;
    await _loadItems();
  }

  // History Pagination
  Future<void> loadHistory({bool more = false, String? subject}) async {
    if (_repository == null) return;
    if (more && !_hasMoreHistory) return;

    // A subject change (including clearing) always resets to page 0 so the
    // operator never sees page 3 of the previous filter mixed with page 1 of
    // the new one.
    if (!more || subject != _historySubject) {
      _historySubject = subject;
      _historyPage = 0;
      _history = [];
    }

    try {
      final newHistory = await _repository!.getHistory(
        limit: _pageSize,
        offset: _historyPage * _pageSize,
        subject: _historySubject,
      );

      if (more && _historySubject == subject) {
        _history.addAll(newHistory);
      } else if (!more) {
        _history = newHistory;
      } else {
        // Subject changed mid-scroll: discard stale buffer and start over.
        _history = newHistory;
      }

      _hasMoreHistory = newHistory.length == _pageSize;
      if (_hasMoreHistory) _historyPage++;
      notifyListeners();
    } catch (e) {
      appLog.error('load', 'Error loading history', e);
    }
  }

  /// Last [limit] audit rows mentioning [code]. Read-only one-shot: no cached
  /// state, no notifyListeners, no page tracking. Errors swallow to `[]` so a
  /// transient failure hides the section rather than shouting a banner on an
  /// ancillary view (matches the dashboard Needs-Attention honest-omission
  /// pattern established in Pass 4).
  Future<List<Map<String, dynamic>>> itemHistory(
    String code, {
    int limit = 8,
  }) async {
    final repo = _repository;
    if (repo == null || code.isEmpty) return const [];
    try {
      return await repo.getHistory(limit: limit, offset: 0, subject: code);
    } catch (_) {
      return const [];
    }
  }

  /// Last [limit] audit rows mentioning [memberId]. Same read-only semantics
  /// as [itemHistory].
  Future<List<Map<String, dynamic>>> memberHistory(
    String memberId, {
    int limit = 8,
  }) async {
    final repo = _repository;
    if (repo == null || memberId.isEmpty) return const [];
    try {
      return await repo.getHistory(
        limit: limit,
        offset: 0,
        subject: memberId,
      );
    } catch (_) {
      return const [];
    }
  }

  /// Build the audit row for a **host** mutation so it can be written inside the
  /// mutation's own transaction (TX-01 / 5.2). Returns null for remote clients,
  /// whose audit the server records authoritatively (real client IP + clock).
  Map<String, dynamic>? _hostAudit(String operation, String details) {
    if (!_isHost) return null;
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'operation': operation,
      'details': details,
      'user': 'Host',
    };
  }

  void updateClientActivity(String clientIp) {
    _activeClients[clientIp] = DateTime.now();
    notifyListeners();
  }

  // Code Definition Management
  // Audit is written inside the mutation's own transaction (TX-01/5.2) via
  // `audit:` (host) or, for remote clients, authoritatively by the embedded
  // server (real client IP + clock) -- so a definition change can never commit
  // unlogged (BE-05/BE-09).
  Future<void> addCodeDefinition(String prefix, String label) async {
    if (_repository == null) return;
    await _repository!.addCodeDefinition(
      prefix,
      label,
      audit: _hostAudit('ADD_VAR', 'Variable ajoutée: $prefix ($label)'),
    );
    await reload();
    _triggerImmediateBackup();
  }

  Future<void> updateCodeDefinition(
    String oldPrefix,
    String newPrefix,
    String label,
  ) async {
    if (_repository == null) return;
    await _repository!.updateCodeDefinition(
      oldPrefix,
      newPrefix,
      label,
      audit: _hostAudit(
        'UPDATE_VAR',
        'Variable modifiée: $oldPrefix -> $newPrefix ($label)',
      ),
    );
    await reload();
    _triggerImmediateBackup();
  }

  Future<void> deleteCodeDefinition(String prefix) async {
    if (_repository == null) return;
    await _repository!.deleteCodeDefinition(
      prefix,
      audit: _hostAudit('DELETE_VAR', 'Variable supprimée: $prefix'),
    );
    await reload();
    _triggerImmediateBackup();
  }

  // Attribute Definition Management
  Future<void> addAttributeDefinition(String type, String value) async {
    if (_repository == null) return;
    await _repository!.addAttributeDefinition(
      type,
      value,
      audit: _hostAudit('ADD_ATTR', 'Attribut ajouté ($type): $value'),
    );
    await reload();
    _triggerImmediateBackup();
  }

  Future<void> deleteAttributeDefinition(int id) async {
    if (_repository == null) return;
    await _repository!.deleteAttributeDefinition(
      id,
      audit: _hostAudit('DELETE_ATTR', 'Attribut supprimé (ID: $id)'),
    );
    await reload();
    _triggerImmediateBackup();
  }

  void _triggerImmediateBackup() {
    if (_isHost) {
      _immediateBackupTimer?.cancel();
      _immediateBackupTimer = Timer(const Duration(seconds: 15), () {
        backupData().catchError(
          (e) => appLog.error('backup', 'Immediate backup failed', e),
        );
      });
    }
  }

  Future<void> reload() => _loadItems();

  /// Test seam: seeds items + members + loans from the injected repository so a
  /// `forTesting` provider can be populated without the full host bootstrap
  /// (FE2-15 active-loans UI test).
  @visibleForTesting
  Future<void> reloadAllForTesting() => _reloadAll();

  /// Sets the search term and re-queries the server, debounced so a burst of
  /// keystrokes fires a single search (Phase 7 / 7.2).
  void search(String query) {
    _searchQuery = query;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), _loadItems);
  }

  void filterByStatus(String? status) {
    _statusFilter = status;
    _loadItems();
  }

  void filterByCodeType(String? codeType) {
    _codeTypeFilter = codeType;
    _loadItems();
  }

  void clearFilters() {
    _statusFilter = null;
    _codeTypeFilter = null;
    _searchQuery = '';
    _searchDebounce?.cancel();
    _loadItems();
  }

  Future<LibraryItem?> findItemByBarcode(String barcode) async {
    if (_repository == null) return null;
    return await _repository!.getItemByBarcode(barcode);
  }

  /// Generate the next code for a given code type
  Future<String> generateNextCode(String codeType) async {
    if (_repository is DatabaseService) {
      return await (_repository as DatabaseService).generateNextCode(codeType);
    }
    // For client mode, generate based on local items
    final typeItems = _items.where((i) => i.codeType == codeType).toList();
    if (typeItems.isEmpty) return '0001';

    int maxCode = 0;
    for (final item in typeItems) {
      final parsed = int.tryParse(item.code) ?? 0;
      if (parsed > maxCode) maxCode = parsed;
    }
    return (maxCode + 1).toString().padLeft(4, '0');
  }

  Future<void> addItem(LibraryItem item) async {
    await _repository?.addItem(
      item,
      audit: _hostAudit(
        'ADD',
        'Ajout de ${item.fullCode}: ${item.designation}',
      ),
    );
    await _loadItems(keepWindow: true);
    _triggerImmediateBackup();
  }

  /// TX-06: [expectedVersion] is the `row_version` the UI READ with the row it
  /// is editing. The item form always supplies it, so a whole-row save that
  /// lost a race is refused (server 409 / typed conflict) instead of silently
  /// clobbering the newer row — including status changes written by the loan
  /// engine, which now advance the token too.
  Future<void> updateItem(LibraryItem item, {int? expectedVersion}) async {
    await _repository?.updateItem(
      item,
      audit: _hostAudit('UPDATE', 'Modification de ${item.fullCode}'),
      expectedVersion: expectedVersion,
    );
    await _loadItems(keepWindow: true);
    _triggerImmediateBackup();
  }

  Future<void> deleteItem(String code) async {
    await _repository?.deleteItem(
      code,
      audit: _hostAudit('DELETE', 'Suppression de $code'),
    );
    await _loadItems(keepWindow: true);
    _triggerImmediateBackup();
  }

  Future<void> updateItemStatus(LibraryItem item, String newStatus) async {
    final updatedItem = LibraryItem(
      code: item.code,
      barcode: item.barcode,
      codeType: item.codeType,
      designation: item.designation,
      quantite: item.quantite,
      emplacement: item.emplacement,
      taux: item.taux,
      emplacementStock: item.emplacementStock,
      status: newStatus,
    );
    await updateItem(updatedItem);
  }

  /// Phase 12: list a title's physical copies. Host-only — the copy ledger
  /// lives on the host and is deliberately NOT on the LibraryRepository seam,
  /// so a remote client gets an empty list (its Item Details screen never
  /// renders the copies card). Mirrors the `import`/`generateNextCode` cast
  /// pattern for host-only capabilities.
  Future<List<ItemCopy>> loadCopies(String itemCode) async {
    final repo = _repository;
    if (repo is DatabaseService) return repo.getCopies(itemCode);
    return const [];
  }

  /// Phase 12 / BL-05 follow-up: change one copy's physical condition. The
  /// DatabaseService validates the transition, CAS-guards against fighting a
  /// loan/hold, and re-derives the title status (bumping `row_version`), so we
  /// only need to refresh the visible window. Errors propagate to the caller.
  Future<void> setCopyCondition(
    String itemCode,
    int copyId,
    CopyState target,
  ) async {
    final repo = _repository;
    if (repo is! DatabaseService) {
      throw StateError('Copy management is host-only.');
    }
    await repo.setCopyCondition(
      copyId,
      target,
      audit: _hostAudit(
        'COPY_STATE',
        'Copie #$copyId de $itemCode -> ${target.storage}',
      ),
    );
    await _loadItems(keepWindow: true);
    _triggerImmediateBackup();
  }

  /// Phase 13: add one physical copy to a title (host-only). The data layer
  /// keeps `quantite` synced to the copy count and re-derives the title status;
  /// we refresh the visible window. Returns the new copy id.
  Future<int> addCopy(String itemCode) async {
    final repo = _repository;
    if (repo is! DatabaseService) {
      throw StateError('Copy management is host-only.');
    }
    final id = await repo.addCopyForItem(
      itemCode,
      audit: _hostAudit('COPY_ADD', "Ajout d'un exemplaire de $itemCode"),
    );
    await _loadItems(keepWindow: true);
    _triggerImmediateBackup();
    return id;
  }

  /// Phase 13: remove one physical copy (host-only). Refused when the copy is
  /// on loan / reserved or is the title's last copy; the resulting
  /// [CopyConflictException] surfaces as a localized conflict via
  /// [describeError].
  Future<void> removeCopy(String itemCode, int copyId) async {
    final repo = _repository;
    if (repo is! DatabaseService) {
      throw StateError('Copy management is host-only.');
    }
    await repo.removeCopy(
      copyId,
      audit: _hostAudit(
          'COPY_DEL', "Suppression de l'exemplaire #$copyId de $itemCode"),
    );
    await _loadItems(keepWindow: true);
    _triggerImmediateBackup();
  }

  /// Phase 13: set / clear one copy's per-copy barcode (host-only). A non-empty
  /// barcode colliding with another copy throws [BarcodeConflictException].
  Future<void> setCopyBarcode(
      String itemCode, int copyId, String? barcode) async {
    final repo = _repository;
    if (repo is! DatabaseService) {
      throw StateError('Copy management is host-only.');
    }
    await repo.setCopyBarcode(
      copyId,
      barcode,
      audit: _hostAudit('COPY_BARCODE', 'Exemplaire #$copyId de $itemCode'),
    );
    _triggerImmediateBackup();
  }

  // Statistics getters
  int get totalItems => _items.length;
  int get totalQuantity => _stats['totalQuantity'] ?? 0;
  double get totalValue => (_stats['totalValue'] ?? 0.0).toDouble();
  int get onLoanCount => _stats['onLoan'] ?? 0;

  int getCountByStatus(String status) =>
      _items.where((i) => i.status == status).length;
  int getCountByCodeType(String codeType) {
    if (_stats['typeDist'] == null) return 0;
    final dist = _stats['typeDist'] as Map;
    return dist[codeType] ?? 0;
  }

  Future<void> backupData() async {
    if (_repository is DatabaseService) {
      await (_repository as DatabaseService).createAutoBackup();
      // Phase 15: only a completed backup updates the health timestamp.
      final ts = DateTime.now();
      _lastBackupAt = ts;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastBackupAt', ts.toIso8601String());
      notifyListeners();
    } else {
      throw HostOnlyFeatureException('Backup');
    }
  }

  Future<void> restoreData(String path) async {
    if (_repository is DatabaseService) {
      final repo = _repository as DatabaseService;
      // Quiesce the LAN server around the close->copy->reopen so neither
      // in-flight nor new requests observe a swapped / partially-restored
      // database (DB-04). The reload reads the reopened local handle directly,
      // so it stays inside the window but is unaffected by the 503 gate.
      final server = _server;
      Future<void> work() async {
        await repo.restoreDatabase(path);
        await reload();
      }

      if (server != null && server.isRunning) {
        await server.withMaintenance(work);
      } else {
        await work();
      }
    } else {
      throw HostOnlyFeatureException('Restore');
    }
  }

  Future<void> clearAllData() async {
    if (_repository is DatabaseService) {
      final repo = _repository as DatabaseService;
      // Wipe quiesced too (DB-04): clients must not read a half-cleared
      // database or interleave writes mid-wipe.
      final server = _server;
      Future<void> work() async {
        await repo.clearAllData(
          audit: _hostAudit('WIPE', 'Effacement complet de la base de données'),
        );
        await _loadItems();
        _triggerImmediateBackup();
      }

      if (server != null && server.isRunning) {
        await server.withMaintenance(work);
      } else {
        await work();
      }
    } else {
      throw HostOnlyFeatureException('Wipe');
    }
  }

  Future<ImportResult> importItemsFromExcel(String filePath) async {
    if (_repository == null || !_isHost) {
      throw HostOnlyFeatureException('Import');
    }

    // NET-11: decoding a workbook and walking every row is pure CPU work that
    // used to run synchronously on the UI isolate, freezing the window for the
    // whole decode on a large import. Read the bytes with a non-blocking await,
    // then decode + parse OFF-THREAD. The DB batch stays on this isolate (the
    // sqflite ffi handle is isolate-local) and behavior is identical to the old
    // inline loop -- only *where* the parsing runs changed.
    final bytes = await File(filePath).readAsBytes();
    final itemsToImport = await Isolate.run(
      () => parseImportWorkbook(bytes),
      debugName: 'excel-import',
    );

    if (itemsToImport.isEmpty) {
      return ImportResult(inserted: 0, skippedCodes: []);
    }
    // FW-03: import never overwrites an existing catalogue row. The audit line
    // is written inside the import transaction (BE-09), and the version stamp
    // is atomic with the batch (RC-06). The typed result reports how many rows
    // were genuinely added vs skipped as already-present.
    final dbService = _repository as DatabaseService;
    final result = await dbService.batchInsertItems(
      itemsToImport,
      audit: _hostAudit(
        'IMPORT',
        '${itemsToImport.length} lignes analysees depuis Excel',
      ),
    );
    await reload();
    _triggerImmediateBackup();
    return result;
  }

  /// Exports the whole (filter-aware) inventory to CSV. Returns the written
  /// path, or `null` if the user cancelled the save dialog (BL-09 / 11b).
  Future<String?> exportToCsv() async {
    final rows = await itemsForExport();
    // NET-11 (P20): the row set is already fully resolved, but composing the
    // text for a whole catalogue is CPU work; do it off the UI isolate.
    final csv = await buildInventoryCsvOffIsolate([
      for (final item in rows)
        [
          item.code,
          item.barcode,
          item.codeType,
          item.designation,
          '${item.quantite}',
          item.emplacement,
          '${item.taux}',
          item.emplacementStock,
          item.status,
        ],
    ]);
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final filePath = await _exportTargetPath(
        'bibliotheque_export_$timestamp.csv', const ['csv']);
    if (filePath == null) return null; // user cancelled -> nothing written
    await File(filePath).writeAsString(csv);
    return filePath;
  }

  /// The full set of rows to export: EVERY item matching the current
  /// search/filter, fetched from the server (via `countItems` for the exact
  /// size, then one unpaginated read) — not just the loaded page
  /// (Phase 7 / 7.3, closes FE-05 / BL-09).
  @visibleForTesting
  Future<List<LibraryItem>> itemsForExport() async {
    final repo = _repository;
    if (repo == null) return List<LibraryItem>.of(_items);
    final search = _searchQuery.trim().isEmpty ? null : _searchQuery;
    final total = await repo.countItems(
      search: search,
      status: _statusFilter,
      codeType: _codeTypeFilter,
    );
    return await repo.getItems(
      limit: total,
      offset: 0,
      search: search,
      status: _statusFilter,
      codeType: _codeTypeFilter,
    );
  }

  /// Builds the CSV text, RFC-4180-quoting any field containing a comma,
  /// double-quote or newline so a designation like `Sold, 50%` can no longer
  /// shift the columns (BL-09).
  @visibleForTesting
  String csvContent(List<LibraryItem> items) {
    final buffer = StringBuffer();
    // CSV Header with French labels
    buffer.writeln(
      'Code,Barre,Type,Designation,Quantite,Emplacement,Prix,Stock,Statut',
    );
    for (final item in items) {
      buffer.writeln(
        [
          item.code,
          item.barcode ?? '',
          item.codeType,
          item.designation,
          '${item.quantite}',
          item.emplacement,
          '${item.taux}',
          item.emplacementStock,
          item.status,
        ].map(_csvField).join(','),
      );
    }
    return buffer.toString();
  }

  static String _csvField(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Exposes the RFC-4180 quoting rule to [buildInventoryCsvOffIsolate]: a
  /// top-level isolate entry point cannot reach a private instance member, and
  /// both paths MUST quote identically or the off-isolate export could silently
  /// differ from [csvContent].
  @visibleForTesting
  static String staticCsvField(String value) => _csvField(value);

  // Member Management
  Future<void> _loadMembers() async {
    if (_repository == null) return;
    try {
      _members = await _repository!.getMembers();
      notifyListeners();
    } catch (e) {
      appLog.error('load', 'Error loading members', e);
    }
  }

  Future<void> addMember(Member member) async {
    if (_repository == null) return;

    // Auto-generate member ID if using DatabaseService
    String finalMemberId = member.memberId;
    if (_repository is DatabaseService &&
        (member.memberId.isEmpty || member.memberId == 'AUTO')) {
      finalMemberId = await (_repository as DatabaseService).generateMemberID();
    }

    final memberWithId = Member(
      id: member.id,
      firstName: member.firstName,
      lastName: member.lastName,
      email: member.email,
      phone: member.phone,
      memberId: finalMemberId,
      registeredAt: member.registeredAt,
    );

    await _repository!.addMember(
      memberWithId,
      audit: _hostAudit('ADD_MEMBER', 'Ajout membre: ${memberWithId.fullName}'),
    );
    await _loadMembers();
    _triggerImmediateBackup();
  }

  /// TX-06: [expectedVersion] is the `row_version` the member dialog READ with
  /// the row it is editing. The dialog always supplies it on an edit, so a
  /// whole-row save that lost a race is refused (server 409 / typed conflict)
  /// instead of silently clobbering another client's newer change.
  Future<void> updateMember(Member member, {int? expectedVersion}) async {
    if (_repository == null) return;
    await _repository!.updateMember(
      member,
      audit: _hostAudit(
        'UPDATE_MEMBER',
        'Modification membre: ${member.fullName}',
      ),
      expectedVersion: expectedVersion,
    );
    await _loadMembers();
    _triggerImmediateBackup();
  }

  Future<void> deleteMember(String memberId) async {
    if (_repository == null) return;
    await _repository!.deleteMember(
      memberId,
      audit: _hostAudit('DEL_MEMBER', 'Suppression membre: $memberId'),
    );
    await _loadMembers();
    _triggerImmediateBackup();
  }

  // Loan Management
  Future<void> _loadLoans() async {
    if (_repository == null) return;
    try {
      _loans = await _repository!.getLoans();
      notifyListeners();
    } catch (e) {
      appLog.error('load', 'Error loading loans', e);
    }
  }

  Future<void> checkOutItem(
    LibraryItem item,
    Member member, {
    int durationDays = 15,
  }) async {
    if (_repository == null) return;

    // Check if item is available
    if (item.status != 'Disponible') {
      throw Exception('Cet article n\'est pas disponible.');
    }

    final loan = LoanTransitions.checkOut(
      itemCode: item.code,
      memberId: member.memberId,
      memberName: member.fullName,
      itemTitle: item.designation,
      now: DateTime.now(),
      durationDays: durationDays,
    );

    await _repository!.addLoan(
      loan,
      audit: _hostAudit(
        'CHECKOUT',
        'Emprunt: ${item.code} par ${member.fullName}',
      ),
    );
    await _loadLoans();
    await _loadItems(); // Refresh item status
    _triggerImmediateBackup();
  }

  Future<void> returnItem(String scanned) async {
    if (_repository == null) return;

    // BL-03: resolve the scanned/typed value (per-copy barcode / title ISBN /
    // item code) to the specific active loan server-side, so returning works
    // for anything a scanner produces and frees exactly the copy borrowed.
    final activeLoan = await _repository!.findActiveLoanByScan(scanned);
    if (activeLoan == null) {
      throw Exception('Aucun emprunt actif trouvé pour cet article.');
    }

    final returnedLoan = LoanTransitions.returnLoan(activeLoan);

    await _repository!.updateLoan(
      returnedLoan,
      audit: _hostAudit('CHECKIN', 'Retour: ${activeLoan.itemCode}'),
    );
    await _loadLoans();
    await _loadItems(); // Refresh item status
    _triggerImmediateBackup();
  }

  Future<void> renewLoan(Loan loan, {int additionalDays = 15}) async {
    if (_repository == null) return;

    // Canonical transition: throws if the loan is not active, so a returned
    // loan can never be "renewed" back to life (BL-02).
    final renewedLoan = LoanTransitions.renew(
      loan,
      additionalDays: additionalDays,
    );

    await _repository!.updateLoan(
      renewedLoan,
      audit: _hostAudit('RENEW', 'Renouvellement: ${loan.itemCode}'),
    );
    await _loadLoans();
  }

  @override
  void dispose() {
    _backupTimer?.cancel();
    _healthTimer?.cancel();
    _immediateBackupTimer?.cancel();
    _searchDebounce?.cancel();
    _stopPairingSocket();
    _healthCheckBusy = false;
    if (_repository is ApiService) {
      try {
        (_repository as ApiService).close();
      } catch (e) {
        // RC-07: a client-close failure during dispose was silent; record it.
        appLog.warn('net', 'Failed to close ApiService client on dispose', e);
      }
    }
    if (_server != null) {
      _server!.stopServer().catchError((e) {
        // RC-07: surface a failed server stop on dispose instead of swallowing.
        appLog.warn('net', 'Failed to stop LAN server on dispose', e);
      });
    }
    super.dispose();
  }
}

/// NET-11 (P20): builds the whole-inventory CSV text OFF the UI isolate.
/// [LibraryProvider.exportToCsv] resolves EVERY filter-matching row into
/// memory (Phase 7 / 7.3), so on a large catalogue the string composition was
/// the remaining synchronous CPU burst that could freeze the desktop. Only
/// plain values (String/int/double) cross the isolate boundary, so the rows are
/// carried as already-resolved cell lists; the output is byte-identical to the
/// on-isolate [LibraryProvider.csvContent] path. Pure top-level function -- no
/// provider/DB state -- which is what `Isolate.run` requires.
Future<String> buildInventoryCsvOffIsolate(List<List<String?>> rows) =>
    Isolate.run(() {
      final buffer = StringBuffer();
      buffer.writeln(
        'Code,Barre,Type,Designation,Quantite,Emplacement,Prix,Stock,Statut',
      );
      for (final cells in rows) {
        buffer.writeln(
          cells
              .map((c) => LibraryProvider.staticCsvField(c ?? ''))
              .join(','),
        );
      }
      return buffer.toString();
    });

/// NET-11: decodes an .xlsx workbook and maps every data row to a
/// [LibraryItem]. Runs OFF the UI isolate (see
/// [LibraryProvider.importItemsFromExcel]) so a large import no longer freezes
/// the window for the whole decode. Kept as a pure top-level function -- no
/// provider/DB state -- both because that is what `Isolate.run` requires and
/// because it makes the parsing independently testable. Column layout:
/// 0 Code, 1 Type, 2 Designation, 3 Quantite, 4 Emplacement, 5 Prix, 6 Stock,
/// 7 Statut, 8 Barcode.
@visibleForTesting
List<LibraryItem> parseImportWorkbook(Uint8List bytes) {
  final excel = excel_pkg.Excel.decodeBytes(bytes);
  final items = <LibraryItem>[];

  for (final table in excel.tables.keys) {
    final sheet = excel.tables[table]!;
    if (sheet.maxRows <= 1) continue; // Skip empty sheets or headers only

    for (var i = 1; i < sheet.maxRows; i++) {
      final row = sheet.rows[i];
      if (row.isEmpty || row.length < 3) continue;

      String? getString(int index) {
        if (index >= row.length || row[index] == null) return null;
        final value = row[index]!.value;
        if (value == null) return null;
        return value.toString().trim();
      }

      int getInt(int index) {
        final s = getString(index);
        if (s == null) return 0;
        return int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      }

      double getDouble(int index) {
        final s = getString(index);
        if (s == null) return 0.0;
        return double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
      }

      final code = getString(0);
      final type = getString(1) ?? 'LIV';
      final designation = getString(2);

      if (code == null || designation == null) continue;

      items.add(
        LibraryItem(
          code: code,
          barcode: getString(8), // Barcode at index 8
          codeType: type,
          designation: designation,
          quantite: getInt(3),
          emplacement: getString(4) ?? '',
          taux: getDouble(5),
          emplacementStock: getString(6) ?? '',
          status: getString(7) ?? ItemStatus.disponible,
        ),
      );
    }
  }
  return items;
}

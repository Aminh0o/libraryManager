import '../models/user_account.dart';
import 'password_hasher.dart';

/// Persistence seam for [AuthService] so the same auth core can run against an
/// in-memory store in tests and, later, against the SQLite `admin_credentials`
/// / `client_tokens` / `users` tables without any change to the logic here.
abstract class AuthStore {
  /// Returns the stored PBKDF2 credential string, or `null` when no password
  /// has been configured yet. This is the LEGACY shared-admin credential
  /// (pre-10.1): it remains the only credential on installs that never
  /// configured named users, and the bootstrap source for the `admin` account
  /// on upgrades (see addUser/changeUserRole docs on [AuthService]).
  Future<String?> loadCredential();
  Future<void> saveCredential(String hash);

  /// The set of currently-valid bearer tokens.
  Future<Set<String>> loadTokens();
  Future<void> saveTokens(Set<String> tokens);

  /// Named accounts (Phase 10.1): username -> (role, createdAt). Password
  /// hashes never cross this seam -- [AuthService] verifies against them via
  /// [verifyUserPassword]. Stores MUST derive an empty map (never throw) for
  /// a database that predates the `users` table.
  Future<Map<String, ({UserRole role, String? createdAt})>> listUsers();

  /// Inserts or replaces one named account with its PBKDF2 hash.
  Future<void> upsertUser(String username, String hash, UserRole role);

  /// The stored PBKDF2 hash for [username] (null when the account does not
  /// exist). Only [AuthService] ever sees this -- it never crosses the wire.
  Future<String?> userHash(String username);

  Future<void> removeUserRow(String username);

  /// Who each issued bearer token belongs to. A token ABSENT from the map is
  /// a pre-10.1 (or pairing-issued, host-delegated) token and [AuthService]
  /// treats it as [UserRole.admin] -- the privilege it always had -- so
  /// already-paired clients are never stranded by the upgrade.
  Future<Map<String, ({String username, UserRole role})>> loadTokenPrincipals();
  Future<void> saveTokenPrincipals(
    Map<String, ({String username, UserRole role})> principals,
  );
}

/// Default [AuthStore] used by tests and before server-side persistence ships.
class InMemoryAuthStore implements AuthStore {
  String? _credential;
  Set<String> _tokens = <String>{};
  final Map<String, ({UserRole role, String? createdAt})> _users = {};
  final Map<String, String> _userHashes = {};
  final Map<String, ({String username, UserRole role})> _principals = {};

  @override
  Future<String?> loadCredential() async => _credential;

  @override
  Future<void> saveCredential(String hash) async => _credential = hash;

  @override
  Future<Set<String>> loadTokens() async => Set<String>.from(_tokens);

  @override
  Future<void> saveTokens(Set<String> tokens) async =>
      _tokens = Set<String>.from(tokens);

  @override
  Future<Map<String, ({UserRole role, String? createdAt})>> listUsers() async =>
      Map.of(_users);

  @override
  Future<void> upsertUser(String username, String hash, UserRole role) async {
    _users[username] = (
      role: role,
      createdAt:
          _users[username]?.createdAt ?? DateTime.now().toIso8601String(),
    );
    _userHashes[username] = hash;
  }

  @override
  Future<String?> userHash(String username) async => _userHashes[username];

  @override
  Future<void> removeUserRow(String username) async {
    _users.remove(username);
    _userHashes.remove(username);
  }

  @override
  Future<Map<String, ({String username, UserRole role})>>
  loadTokenPrincipals() async => Map.of(_principals);

  @override
  Future<void> saveTokenPrincipals(
    Map<String, ({String username, UserRole role})> principals,
  ) async {
    _principals
      ..clear()
      ..addAll(principals);
  }

  /// Test seam: the PBKDF2 hash currently stored for [username] (null when
  /// absent) so tests can assert a hash was rotated without seeing passwords.
  String? debugUserHash(String username) => _userHashes[username];
}

/// Outcome of a login attempt. `invalidCredentials` intentionally does not
/// distinguish "no such user" from "wrong password" (SEC-03), and `locked`
/// means brute-force protection is temporarily refusing attempts.
enum AuthStatus { ok, invalidCredentials, locked }

class AuthResult {
  final AuthStatus status;
  final String? token;

  /// Who the minted token belongs to (Phase 10.1). Null only on non-success.
  final TokenPrincipal? principal;

  /// When [AuthStatus.locked], how long until attempts are accepted again.
  final Duration? retryAfter;

  const AuthResult._(
    this.status, {
    this.token,
    this.principal,
    this.retryAfter,
  });

  factory AuthResult.success(String token, {TokenPrincipal? principal}) =>
      AuthResult._(AuthStatus.ok, token: token, principal: principal);
  factory AuthResult.denied() => AuthResult._(AuthStatus.invalidCredentials);
  factory AuthResult.locked(Duration after) =>
      AuthResult._(AuthStatus.locked, retryAfter: after);

  bool get isSuccess => status == AuthStatus.ok;
}

/// Server-side authentication core: single admin credential, opaque bearer
/// tokens issued to trusted (paired) clients, and a per-source brute-force
/// throttle.
///
/// This is deliberately framework-free (no Flutter, SharedPreferences, socket
/// or database dependencies) so it is fully unit-testable and can be reused by
/// both the HTTP middleware and the pairing/credential wiring that ships in
/// the next increment. It replaces the previous client-only unsalted SHA-256
/// model (SEC-02 / SEC-03 / NET-01).
class AuthService {
  /// The system manages exactly one administrative account.
  static const String adminUsername = 'admin';

  final PasswordHasher _hasher;
  final AuthStore _store;

  /// Failed attempts tolerated within [lockoutWindow] before a source is
  /// locked out.
  final int maxFailedAttempts;
  final Duration lockoutWindow;

  /// Injectable clock so throttle behaviour is testable without real delays.
  final DateTime Function() _now;

  final Map<String, _Throttle> _throttle = {};
  Set<String> _tokens = <String>{};
  final Map<String, ({UserRole role, String? createdAt})> _users = {};
  final Map<String, ({String username, UserRole role})> _principals = {};
  bool _loaded = false;
  // Cached "is a credential configured?" so the auth middleware can decide to
  // enforce without a database read on every request.
  bool? _credentialPresent;

  AuthService({
    PasswordHasher? hasher,
    AuthStore? store,
    this.maxFailedAttempts = 5,
    this.lockoutWindow = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : _hasher = hasher ?? PasswordHasher(),
       _store = store ?? InMemoryAuthStore(),
       _now = now ?? DateTime.now;

  /// Loads persisted credential/tokens/users once. Safe to call repeatedly.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _tokens = await _store.loadTokens();
    _principals
      ..clear()
      ..addAll(await _store.loadTokenPrincipals());
    _users
      ..clear()
      ..addAll(await _store.listUsers());
    final stored = await _store.loadCredential();
    _credentialPresent = stored != null && stored.isNotEmpty;
    _loaded = true;
  }

  Future<void> _reload() async {
    _loaded = false;
    await ensureLoaded();
  }

  Future<String?> _credential() async {
    final stored = await _store.loadCredential();
    return (stored != null && stored.isNotEmpty) ? stored : null;
  }

  /// Whether an admin password has been configured (legacy credential OR any
  /// named account). When false, callers may choose to run in an unenforced
  /// bootstrap mode (no credential exists yet).
  Future<bool> hasCredential() async {
    await ensureLoaded();
    if (_users.isNotEmpty) return _credentialPresent = true;
    final stored = await _store.loadCredential();
    _credentialPresent = stored != null && stored.isNotEmpty;
    return _credentialPresent!;
  }

  /// Cheap, cache-backed check used by the auth middleware on each request to
  /// decide whether to enforce. Refreshed by [ensureLoaded]/[setPassword]/
  /// [reset]; does not hit the store after the first load.
  Future<bool> enforcementActive() async {
    if (_credentialPresent == null) await ensureLoaded();
    return _credentialPresent ?? false;
  }

  /// Sets (or replaces) the admin password, storing only a salted PBKDF2 hash.
  Future<void> setPassword(String password) async {
    await ensureLoaded();
    if (password.isEmpty) {
      throw ArgumentError('Password must not be empty');
    }
    await _store.saveCredential(_hasher.hash(password));
    _credentialPresent = true;
  }

  /// Clears the admin credential and all issued tokens (used by "erase data").
  Future<void> reset() async {
    await ensureLoaded();
    await _store.saveCredential('');
    _tokens = <String>{};
    await _store.saveTokens(_tokens);
    _credentialPresent = false;
    _throttle.clear();
  }

  /// Direct verification of the admin password, bypassing the throttle. Used
  /// for local confirmations (e.g. the host typing its own password to unlock
  /// a destructive action) where a source key is not meaningful.
  Future<bool> verifyPassword(String password) async {
    await ensureLoaded();
    final stored = await _store.loadCredential();
    if (stored == null || stored.isEmpty) return false;
    return _hasher.verify(password, stored);
  }

  /// Whether [token] is a currently-issued, un-revoked bearer token.
  Future<bool> isAuthorized(String? token) async {
    if (token == null || token.isEmpty) return false;
    await ensureLoaded();
    return _tokens.contains(token);
  }

  // ==========================================================================
  // Named accounts & roles (Phase 10.1)
  // ==========================================================================

  /// All loginable identities, public projection only (never a hash), sorted.
  /// A legacy-only install (shared `admin_credentials` row, no `users` row)
  /// surfaces as a synthesized 'admin'/[UserRole.admin] account so the UI and
  /// the last-admin guard always see at least one administrator.
  Future<List<UserRecord>> users() async {
    await ensureLoaded();
    final out = <UserRecord>[
      for (final e in _users.entries)
        UserRecord(
          username: e.key,
          role: e.value.role,
          createdAt: e.value.createdAt,
        ),
    ];
    if (_users['admin'] == null && await _credential() != null) {
      out.add(const UserRecord(username: adminUsername, role: UserRole.admin));
    }
    out.sort((a, b) => a.username.compareTo(b.username));
    return out;
  }

  Future<int> _adminCount() async {
    var n = _users.entries.where((e) => e.value.role == UserRole.admin).length;
    if (_users['admin'] == null && await _credential() != null) n++;
    return n;
  }

  /// Role attached to a freshly minted token. A token with NO recorded
  /// principal is a pre-10.1 legacy/pairing token and keeps the ADMIN right
  /// it always had (revoking it on upgrade would strand every paired client);
  /// least-privilege applies to tokens minted from now on.
  Future<TokenPrincipal> principalFor(String token) async {
    await ensureLoaded();
    final p = _principals[token];
    if (p != null) {
      return TokenPrincipal(username: p.username, role: p.role);
    }
    // Unattributed token: pre-10.1 shared/admin token -> keeps admin AND is
    // flagged non-named so route guards treat it as legacy (see TokenPrincipal).
    return const TokenPrincipal(
      username: adminUsername,
      role: UserRole.admin,
      isNamed: false,
    );
  }

  /// Authenticates [username]/[password] against the NAMED accounts first,
  /// falling back to the legacy shared-admin credential, and mints a token
  /// bound to the winner's identity+role. Brute-force throttling is per
  /// [sourceKey] exactly as before; failures never reveal whether the
  /// username exists (SEC-03).
  Future<AuthResult> login(
    String username,
    String password, {
    required String sourceKey,
  }) async {
    await ensureLoaded();
    // Accounts are stored normalized (lowercase) by addUser; login can arrive
    // as typed (client dialog, HTTP body), so normalize here too -- otherwise
    // 'Mary' would never match the stored 'mary' and a valid host-created
    // account would be rejected from a client PC.
    username = UserRecord.normalizeUsername(username);
    final now = _now();

    final entry = _throttle.putIfAbsent(sourceKey, () => _Throttle());
    if (entry.isLocked(now, lockoutWindow)) {
      return AuthResult.locked(entry.retryAfter(now, lockoutWindow));
    }

    final user = _users[username];
    var ok = false;
    var principal = const TokenPrincipal(
      username: adminUsername,
      role: UserRole.admin,
    );
    if (user != null) {
      if (await verifyUserPassword(username, password)) {
        ok = true;
        principal = TokenPrincipal(username: username, role: user.role);
      }
    } else if (username == adminUsername) {
      final stored = await _credential();
      if (stored != null && _hasher.verify(password, stored)) {
        ok = true;
        principal = const TokenPrincipal(
          username: adminUsername,
          role: UserRole.admin,
        );
      }
    }
    if (!ok) {
      final lockedNow = entry.recordFailure(
        now,
        maxAttempts: maxFailedAttempts,
        window: lockoutWindow,
      );
      if (lockedNow) {
        return AuthResult.locked(entry.retryAfter(now, lockoutWindow));
      }
      return AuthResult.denied();
    }

    entry.reset();
    final token = await issueTokenFor(principal);
    return AuthResult.success(token, principal: principal);
  }

  /// Verifies [password] against a named account's PBKDF2 hash. False for an
  /// unknown account or a synthesized legacy admin (which [verifyPassword]
  /// covers through the legacy credential path).
  Future<bool> verifyUserPassword(String username, String password) async {
    await ensureLoaded();
    username = UserRecord.normalizeUsername(username);
    if (!_users.containsKey(username)) return false;
    final hash = await _store.userHash(username);
    return hash != null && hash.isNotEmpty && _hasher.verify(password, hash);
  }

  /// Creates a named account. The username 'admin' is RESERVED: it is the
  /// legacy bootstrap identity whose credential lives in `admin_credentials`
  /// (managed by [setPassword]/[reset]); allowing a `users` row with the same
  /// name would create two credentials for one identity. Passwords for named
  /// accounts enforce [UserRecord.minPasswordLength].
  Future<UserRecord> addUser(
    String usernameRaw,
    String password,
    UserRole role,
  ) async {
    await ensureLoaded();
    final username = UserRecord.normalizeUsername(usernameRaw);
    if (!UserRecord.isValidUsername(username)) {
      throw UserAdminException(
        'Username must be 3-32 characters (letters, digits, . _ -), starting with a letter or digit.',
      );
    }
    if (username == adminUsername) {
      throw UserAdminException(
        'The username "admin" is reserved for the built-in administrator.',
      );
    }
    if (password.length < UserRecord.minPasswordLength) {
      throw UserAdminException(
        'Password must be at least ${UserRecord.minPasswordLength} characters.',
      );
    }
    if (_users.containsKey(username)) {
      throw UserAdminException('A user named "$username" already exists.');
    }
    await _store.upsertUser(username, _hasher.hash(password), role);
    await _reload();
    return UserRecord(
      username: username,
      role: role,
      createdAt: _users[username]?.createdAt,
    );
  }

  /// Deletes a named account and revokes every token belonging to it.
  Future<void> removeUser(String usernameRaw) async {
    await ensureLoaded();
    final username = UserRecord.normalizeUsername(usernameRaw);
    if (username == adminUsername && !_users.containsKey(adminUsername)) {
      throw UserAdminException(
        'The built-in administrator cannot be deleted (reset its password instead).',
      );
    }
    if (!_users.containsKey(username)) {
      throw UserAdminException('No such user "$username".');
    }
    if (_users[username]!.role == UserRole.admin && await _adminCount() <= 1) {
      throw UserAdminException('Refusing to remove the last administrator.');
    }
    await _store.removeUserRow(username);
    await _revokeTokensFor(username);
    await _reload();
  }

  /// Changes a role. A role change also updates every ALREADY-ISSUED token of
  /// that user, so a demotion takes effect on the client's next request
  /// rather than only after re-login (the stored principals map is the live
  /// authorization source). Refuses to demote the last administrator.
  Future<void> changeUserRole(String usernameRaw, UserRole role) async {
    await ensureLoaded();
    final username = UserRecord.normalizeUsername(usernameRaw);
    final current = _users[username];
    if (current == null) {
      throw UserAdminException(
        username == adminUsername
            ? 'The built-in administrator always keeps the admin role.'
            : 'No such user "$username".',
      );
    }
    if (current.role == UserRole.admin &&
        role != UserRole.admin &&
        await _adminCount() <= 1) {
      throw UserAdminException('Refusing to demote the last administrator.');
    }
    if (username == adminUsername && role != UserRole.admin) {
      throw UserAdminException(
        'The built-in administrator always keeps the admin role.',
      );
    }
    final hash = await _store.userHash(username);
    if (hash == null || hash.isEmpty) {
      throw UserAdminException(
        'Account "$username" has no password set (reset it first).',
      );
    }
    await _store.upsertUser(username, hash, role);
    for (final e in _principals.entries.toList()) {
      if (e.value.username == username) {
        _principals[e.key] = (username: username, role: role);
      }
    }
    await _store.saveTokenPrincipals(_principals);
    await _reload();
  }

  /// Rotates a named account's password. Changing an ADMIN's password revokes
  /// that user's tokens (the classic credential-compromise response); the
  /// legacy bootstrap path is different (setPassword) and keeps its historical
  /// no-revoke behavior for already-paired clients.
  Future<void> setUserPassword(String usernameRaw, String password) async {
    await ensureLoaded();
    final username = UserRecord.normalizeUsername(usernameRaw);
    if (password.length < UserRecord.minPasswordLength) {
      throw UserAdminException(
        'Password must be at least ${UserRecord.minPasswordLength} characters.',
      );
    }
    if (!_users.containsKey(username)) {
      throw UserAdminException(
        username == adminUsername
            ? 'The built-in administrator password is managed separately.'
            : 'No such user "$username".',
      );
    }
    await _store.upsertUser(
      username,
      _hasher.hash(password),
      _users[username]!.role,
    );
    if (_users[username]!.role == UserRole.admin) {
      await _revokeTokensFor(username);
    }
    await _reload();
  }

  Future<void> _revokeTokensFor(String username) async {
    final victims = _principals.entries
        .where((e) => e.value.username == username)
        .map((e) => e.key)
        .toList();
    if (victims.isEmpty) return;
    for (final t in victims) {
      _tokens.remove(t);
      _principals.remove(t);
    }
    await _store.saveTokens(_tokens);
    await _store.saveTokenPrincipals(_principals);
  }

  /// Mints a token bound to a specific identity+role ([issueToken]'s
  /// least-privilege successor).
  Future<String> issueTokenFor(TokenPrincipal principal) async {
    await ensureLoaded();
    final token = _hasher.generateToken();
    _tokens.add(token);
    _principals[token] = (username: principal.username, role: principal.role);
    await _store.saveTokens(_tokens);
    await _store.saveTokenPrincipals(_principals);
    return token;
  }

  /// Mints a token directly. Used by the trusted pairing exchange, which has
  /// already authenticated the peer out-of-band (via the short-lived pairing
  /// code) and therefore does not re-send the password over the wire. Keeps
  /// the historical ADMIN privilege (a token with no recorded principal
  /// resolves to admin in [principalFor]) so pre-10.1 pairings are unchanged;
  /// pairing with an explicit role is wired in a later 10.1 increment.
  Future<String> issueToken() async {
    await ensureLoaded();
    final token = _hasher.generateToken();
    _tokens.add(token);
    await _store.saveTokens(_tokens);
    return token;
  }

  Future<void> revokeToken(String token) async {
    await ensureLoaded();
    if (_tokens.remove(token)) {
      _principals.remove(token);
      await _store.saveTokens(_tokens);
      await _store.saveTokenPrincipals(_principals);
    }
  }

  /// Remaining failures before lockout for [sourceKey] (diagnostics/tests).
  int failuresFor(String sourceKey) => _throttle[sourceKey]?.failures ?? 0;
}

class _Throttle {
  int failures = 0;
  DateTime? _lastFailure;
  DateTime? _lockedUntil;

  /// Records a failed attempt. Returns true if this failure crossed the
  /// threshold and engaged a lockout until `now + window`.
  bool recordFailure(
    DateTime now, {
    required int maxAttempts,
    required Duration window,
  }) {
    failures++;
    _lastFailure = now;
    if (failures >= maxAttempts) {
      _lockedUntil = now.add(window);
      return true;
    }
    return false;
  }

  void reset() {
    failures = 0;
    _lastFailure = null;
    _lockedUntil = null;
  }

  bool isLocked(DateTime now, Duration window) {
    if (_lockedUntil != null && now.isBefore(_lockedUntil!)) return true;
    if (failures >= 0 &&
        _lastFailure != null &&
        now.difference(_lastFailure!) >= window) {
      // Window elapsed: clear the stale failure count.
      reset();
    }
    return false;
  }

  Duration retryAfter(DateTime now, Duration window) {
    if (_lockedUntil != null && now.isBefore(_lockedUntil!)) {
      return _lockedUntil!.difference(now);
    }
    return window;
  }
}

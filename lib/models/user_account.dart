/// Named application accounts and their authorization roles (Phase 10.1,
/// closes the `users/roles MISSING` row and the NET-02 "backend does not
/// distinguish authorities" residual).
///
/// Kept deliberately free of Flutter/SQL so the auth core, the shelf
/// middleware and unit tests all share one vocabulary:
///  - [UserRole.admin]  everything, incl. user management + destructive ops
///  - [UserRole.staff]  circulation + catalogue + members (day-job librarian)
///  - [UserRole.viewer] reads only (counter PC, training, public kiosk)
///
/// This is AUTHORIZATION (what a caller may do), layered on top of the
/// existing authentication (who the bearer token belongs to, SEC-01/02).
enum UserRole {
  admin('admin', rank: 3),
  staff('staff', rank: 2),
  viewer('viewer', rank: 1);

  const UserRole(this.storage, {required this.rank});

  /// Exact value stored in the `users.role` column.
  final String storage;

  /// Ordering: a route demanding [atLeast] passes for any role whose rank is
  /// greater than or equal to the demanded one. Ranks are spaced so an
  /// intermediate role can be inserted later without renumbering.
  final int rank;

  /// Parses a stored/persisted value. Unknown or missing values fall back to
  /// [UserRole.viewer] — the LEAST privileged role, so a corrupt row or a
  /// legacy writer that never set `role` can never escalate to admin.
  static UserRole parse(Object? value) => tryParse(value) ?? UserRole.viewer;

  /// STRICT parse for UNTRUSTED input (HTTP bodies, UI selections): returns
  /// null rather than guessing. [parse] must never be used for these, because
  /// its viewer fallback combined with a *write* path would turn a typo or a
  /// forged `role` value into a silent privilege change (e.g. "supervisour"
  /// falling through to admin on a role-change route).
  static UserRole? tryParse(Object? value) {
    final s = value?.toString();
    for (final r in UserRole.values) {
      if (r.storage == s) return r;
    }
    return null;
  }

  bool atLeast(UserRole minimum) => rank >= minimum.rank;
}

/// Thrown by user-administration operations for any invalid input or refused
/// state change (duplicate/unknown username, weak or malformed password, the
/// last-admin guard). Deliberately a [StateError] parent so a caller that only
/// catches generic errors still sees a refused mutation as an error, and the
/// HTTP layer can map it to a structured 4xx instead of a bare 500.
class UserAdminException extends StateError {
  UserAdminException(super.message);
}

/// One row of the `users` table. The PBKDF2 hash never leaves the server;
/// [toPublicMap] is the shape the API/UI may see.
class UserRecord {
  const UserRecord({
    required this.username,
    required this.role,
    this.createdAt,
  });

  final String username;
  final UserRole role;
  final String? createdAt;

  /// Username policy: 3-32 chars, letters/digits/dot/underscore/hyphen, must
  /// start with a letter or digit. Case-insensitive systems are simplified by
  /// storing the exact lowercase form; [normalize] enforces that.
  static final RegExp _namePattern = RegExp(r'^[a-z0-9][a-z0-9._-]{2,31}$');

  /// Minimum password length for NAMED accounts. (The legacy shared `admin`
  /// credential keeps its historical policy; new accounts must be stronger.)
  static const int minPasswordLength = 8;

  static String normalizeUsername(String raw) => raw.trim().toLowerCase();

  static bool isValidUsername(String username) =>
      _namePattern.hasMatch(username);

  /// The publicly-visible projection of this account (no hash, no metadata
  /// the client does not need).
  Map<String, dynamic> toPublicMap() => {
    'username': username,
    'role': role.storage,
    if (createdAt != null) 'created_at': createdAt,
  };
}

/// The authenticated identity behind a bearer token, resolved by
/// [AuthService.principalFor] and attached to every guarded request by the
/// auth middleware's request context.
class TokenPrincipal {
  const TokenPrincipal({
    required this.username,
    required this.role,
    this.isNamed = true,
  });

  final String username;
  final UserRole role;

  /// False for LEGACY principals: a pre-10.1 shared token, or a request that
  /// passed through the bootstrap-open path (no credential configured yet).
  /// Both keep the historical ALL-powerful behavior -- role gates apply only
  /// to tokens minted for named accounts, so upgrading a live install can
  /// never lock its own operator out.
  final bool isNamed;
}

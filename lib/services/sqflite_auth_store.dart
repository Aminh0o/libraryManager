import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/user_account.dart';
import 'auth_service.dart';

/// SQLite-backed [AuthStore] so the admin credential and issued bearer tokens
/// survive host restarts (the whole point of moving auth off the client,
/// SEC-02 / SEC-03 / NET-01).
///
/// It takes a `Future<Database> Function()` seam rather than the
/// [DatabaseService] singleton directly, so production can pass the app
/// database while tests can pass an in-memory ffi database — keeping this class
/// fully unit-testable without `path_provider`.
///
/// The table DDL is intentionally identical to the `version: 10` migration in
/// `database_service.dart`; [ensureSchema] is idempotent so it also works
/// against a freshly opened in-memory database in tests.
class SqfliteAuthStore implements AuthStore {
  static const String credentialId = 'admin';
  static const String credentialsTable = 'admin_credentials';
  static const String tokensTable = 'client_tokens';
  static const String usersTable = 'users';

  final Future<Database> Function() _database;

  SqfliteAuthStore(this._database);

  /// Creates the auth tables if absent. Safe to call on every startup.
  /// `users.username` is lowercase by construction (UserRecord.normalize);
  /// `client_tokens.username` attributes a token to its owner (Phase 10.1) --
  /// NULL for pre-10.1 rows, which AuthService resolves to the legacy admin.
  Future<void> ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $credentialsTable(
        id TEXT PRIMARY KEY,
        hash TEXT NOT NULL,
        updated_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tokensTable(
        token TEXT PRIMARY KEY,
        issued_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $usersTable(
        username TEXT PRIMARY KEY,
        hash TEXT NOT NULL,
        role TEXT NOT NULL,
        created_at TEXT
      )
    ''');
    // Idempotent column add for DBs whose `client_tokens` predates 10.1 (the
    // v19 migration normally does this; mirrors the defensive _addColumnSafe
    // spirit -- an existing column or a missing table is simply a no-op).
    try {
      await db.execute(
          'ALTER TABLE $tokensTable ADD COLUMN username TEXT');
    } catch (_) {/* column already present (the normal path) */}
  }

  Future<void> _ensure(Database db) => ensureSchema(db);

  @override
  Future<String?> loadCredential() async {
    final db = await _database();
    await _ensure(db);
    final rows = await db.query(
      credentialsTable,
      columns: ['hash'],
      where: 'id = ?',
      whereArgs: [credentialId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final hash = rows.first['hash'] as String?;
    if (hash == null || hash.isEmpty) return null;
    return hash;
  }

  @override
  Future<void> saveCredential(String hash) async {
    final db = await _database();
    await _ensure(db);
    await db.insert(
      credentialsTable,
      {
        'id': credentialId,
        'hash': hash,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<Set<String>> loadTokens() async {
    final db = await _database();
    await _ensure(db);
    final rows = await db.query(tokensTable, columns: ['token']);
    return rows.map((r) => r['token'] as String).toSet();
  }

  /// Replaces the persisted token set with [tokens] (removes revoked tokens,
  /// adds newly-issued ones) in a single transaction.
  @override
  Future<void> saveTokens(Set<String> tokens) async {
    final db = await _database();
    await _ensure(db);
    await db.transaction((txn) async {
      final existing =
          (await txn.query(tokensTable, columns: ['token']))
              .map((r) => r['token'] as String)
              .toSet();

      final toRemove = existing.difference(tokens);
      final toAdd = tokens.difference(existing);

      if (toRemove.isNotEmpty) {
        await txn.delete(
          tokensTable,
          where: 'token IN (${List.filled(toRemove.length, '?').join(',')})',
          whereArgs: toRemove.toList(),
        );
      }
      final now = DateTime.now().toIso8601String();
      for (final t in toAdd) {
        await txn.insert(tokensTable, {'token': t, 'issued_at': now});
      }
    });
  }

  // ==========================================================================
  // Named accounts & token attribution (Phase 10.1)
  // ==========================================================================

  @override
  Future<Map<String, ({UserRole role, String? createdAt})>> listUsers() async {
    final db = await _database();
    await _ensure(db);
    final rows =
        await db.query(usersTable, columns: ['username', 'role', 'created_at']);
    return {
      for (final r in rows)
        r['username'] as String: (
          role: UserRole.parse(r['role']),
          createdAt: r['created_at'] as String?,
        ),
    };
  }

  @override
  Future<void> upsertUser(String username, String hash, UserRole role) async {
    final db = await _database();
    await _ensure(db);
    // Preserve created_at across UPDATEs: changeUserRole/setUserPassword also
    // upsert, and blindly stamping 'now' would silently falsify the account's
    // creation date in the audit trail.
    final existing = await db.query(usersTable,
        columns: ['created_at'],
        where: 'username = ?',
        whereArgs: [username],
        limit: 1);
    await db.insert(usersTable, {
      'username': username,
      'hash': hash,
      'role': role.storage,
      'created_at': existing.isEmpty
          ? DateTime.now().toIso8601String()
          : existing.first['created_at'],
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<String?> userHash(String username) async {
    final db = await _database();
    await _ensure(db);
    final rows = await db.query(usersTable,
        columns: ['hash'], where: 'username = ?', whereArgs: [username], limit: 1);
    if (rows.isEmpty) return null;
    final hash = rows.first['hash'] as String?;
    return (hash == null || hash.isEmpty) ? null : hash;
  }

  @override
  Future<void> removeUserRow(String username) async {
    final db = await _database();
    await _ensure(db);
    await db
        .delete(usersTable, where: 'username = ?', whereArgs: [username]);
  }

  @override
  Future<Map<String, ({String username, UserRole role})>>
      loadTokenPrincipals() async {
    final db = await _database();
    await _ensure(db);
    // Roles are resolved through the users table so a role change takes
    // effect for ALREADY-ISSUED tokens; a token whose owner has no `users`
    // row (legacy/pairing) is attributed to the bootstrap admin, matching
    // AuthService.principalFor's documented degradation.
    final rows = await db.query(tokensTable,
        columns: ['token', 'username'], where: 'username IS NOT NULL');
    if (rows.isEmpty) return {};
    final roles = await listUsers();
    return {
      for (final r in rows)
        r['token'] as String: (
          username: r['username'] as String,
          role: roles[r['username']]?.role ?? UserRole.admin,
        ),
    };
  }

  @override
  Future<void> saveTokenPrincipals(
      Map<String, ({String username, UserRole role})> principals) async {
    final db = await _database();
    await _ensure(db);
    await db.transaction((txn) async {
      // Attribute newly-owned tokens; drop attribution for revoked ones (the
      // rows themselves are removed by saveTokens -- here we only clear the
      // username of any token no longer owned, keeping legacy NULL rows as-is).
      final owned = await txn.query(tokensTable,
          columns: ['token', 'username'], where: 'username IS NOT NULL');
      for (final r in owned) {
        final token = r['token'] as String;
        if (!principals.containsKey(token)) {
          await txn.update(tokensTable, {'username': null},
              where: 'token = ?', whereArgs: [token]);
        }
      }
      for (final e in principals.entries) {
        final changed = await txn.update(tokensTable, {'username': e.value.username},
            where: 'token = ?', whereArgs: [e.key]);
        // A token can reach here BEFORE saveTokens has persisted its row (e.g.
        // a role change touching an already-paired token). Inserting the
        // attribution keeps it durable instead of silently losing the owner on
        // restart -- where a lost attribution would degrade to legacy ADMIN.
        if (changed == 0) {
          await txn.insert(tokensTable, {
            'token': e.key,
            'issued_at': DateTime.now().toIso8601String(),
            'username': e.value.username,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    });
  }
}

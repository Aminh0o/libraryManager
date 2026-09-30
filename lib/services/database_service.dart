import 'dart:io';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import '../models/library_item.dart';
import '../models/member.dart';
import '../models/loan.dart';
import '../models/item_copy.dart';
import '../models/fine.dart';
import '../models/reservation.dart';
import '../domain/copy_ledger.dart';
import '../domain/fine_policy.dart';
import '../domain/hold_policy.dart';
import '../domain/report_query.dart';
import '../models/report.dart';
import 'repository.dart';
import 'app_logger.dart';

/// Thrown when a delete would strand an in-flight (active) loan (BL-04). The
/// server maps it to HTTP 409 so host and remote clients behave identically,
/// and the item / member is left in place rather than silently orphaning data.
class ActiveLoanConflictException implements Exception {
  ActiveLoanConflictException(this.message);
  final String message;
  @override
  String toString() => 'ActiveLoanConflictException: $message';
}

/// Thrown when a restore candidate is rejected BEFORE the live database is
/// touched (DB-04): missing file, not a database, corrupt, not a library
/// database, or a schema newer than this build understands. The current
/// database is always left intact when this is raised.
class RestoreException implements Exception {
  RestoreException(this.message);
  final String message;
  @override
  String toString() => 'RestoreException: $message';
}

/// Thrown when editing a member would assign them a `member_id` (card id)
/// already held by a DIFFERENT member. `members.member_id` is UNIQUE and is the
/// key `loans` join on, so a silent collision would merge two people's history
/// (DB-01). The server maps it to HTTP 409 like the other integrity conflicts.
class MemberIdConflictException implements Exception {
  MemberIdConflictException(this.message);
  final String message;
  @override
  String toString() => 'MemberIdConflictException: $message';
}

/// Thrown when adding an item whose `code` (the PRIMARY KEY) already exists.
/// Previously a duplicate -- including two concurrent adds that both picked the
/// same generated code (BE-07) -- surfaced as a raw PRIMARY KEY ConstraintError
/// -> an opaque 500. The server maps this to HTTP 409 like the other conflicts.
class ItemCodeConflictException implements Exception {
  ItemCodeConflictException(this.message);
  final String message;
  @override
  String toString() => 'ItemCodeConflictException: $message';
}

/// Thrown when a title's non-empty `barcode` duplicates one already held by a
/// DIFFERENT title. Phase 4 added the partial UNIQUE index `uq_items_barcode`
/// (blank barcodes exempt) so a scanned ISBN resolves to exactly one catalogue
/// row (DB-01), but the write paths only guarded the PRIMARY KEY -- a repeated
/// barcode surfaced as a raw UNIQUE ConstraintError -> an opaque 500. This typed
/// conflict lets the server answer 409 and the write roll back cleanly.
class BarcodeConflictException implements Exception {
  BarcodeConflictException(this.message);
  final String message;
  @override
  String toString() => 'BarcodeConflictException: $message';
}

/// Thrown when adding an attribute definition whose `(type, value)` pair the
/// catalogue already holds. `attribute_definitions` had no UNIQUE(type,value)
/// (DB-01 "duplicate statuses"), so the same value could be inserted over and
/// over. Phase 9.15 adds the `uq_attr_type_value` index defensively; without a
/// typed pre-check a repeat raised a raw UNIQUE ConstraintError -> an opaque
/// 500. The server maps this conflict to HTTP 409 like the other integrity
/// conflicts, and the add rolls back cleanly.
class AttributeConflictException implements Exception {
  AttributeConflictException(this.message);
  final String message;
  @override
  String toString() => 'AttributeConflictException: $message';
}

/// Thrown by an optimistic-concurrency update (TX-06) when the row the caller
/// is editing has changed underneath them since it was read: the whole-row PUT
/// would otherwise silently clobber another client's edit (a lost update). The
/// caller supplied an expected `row_version` that no longer matches the stored
/// one, so the write is refused and the server maps this to HTTP 409.
class ConcurrentUpdateConflictException implements Exception {
  ConcurrentUpdateConflictException(this.message);
  final String message;
  @override
  String toString() => 'ConcurrentUpdateConflictException: $message';
}

/// Thrown when a write path is handed a title-level `status` OUTSIDE the
/// canonical copy-derived vocabulary (`CopyState.titleStatusVocabulary`). BL-05
/// makes a title's status the rollup of its copies, so an arbitrary/legacy
/// string ('Endommagé', 'Payé', a typo, a hostile client value) can never be
/// persisted as an orphan title status -- it is refused instead of stored and
/// silently clobbered on the next loan. The server maps it to HTTP 400 (a bad
/// request value, not a state conflict); the host gets it straight from
/// `DatabaseService`. `describeError` categorizes it as a bad request.
class InvalidStatusException implements Exception {
  InvalidStatusException(this.message);
  final String message;
  @override
  String toString() => 'InvalidStatusException: $message';
}

/// Thrown when a per-copy edit is refused because the operation is not allowed
/// on that copy RIGHT NOW (Phase 12/13 copy ledger): the copy no longer exists,
/// it is on loan / reserved (owned by the circulation flow, so it cannot be
/// hand-edited or hand-deleted), it is a title's LAST physical unit, or its
/// parent item is gone. This is a state conflict, not a bad input value, so
/// `describeError` maps it to the localized conflict message and the raw reason
/// is never leaked to the operator. Host-only — the copy editor has no HTTP
/// route — but kept a typed exception so host and any future client agree.
class CopyConflictException implements Exception {
  CopyConflictException(this.message);
  final String message;
  @override
  String toString() => 'CopyConflictException: $message';
}

/// Outcome of a bulk Excel import (FW-03). `inserted` counts genuinely-new rows
/// that were committed; `skippedCodes` lists every row whose `code` already
/// existed in the catalogue (or duplicated another row within the same file),
/// and `skippedBarcodes` lists rows dropped because their non-empty `barcode`
/// collided with an existing title or an earlier row in the same file (DB-01).
/// Import **never overwrites** an existing item -- previously `ConflictAlgorithm.
/// replace` silently clobbered its designation/quantity/status.
class ImportResult {
  ImportResult({
    required this.inserted,
    required this.skippedCodes,
    this.skippedBarcodes = const [],
    this.invalidStatusCodes = const [],
  });
  final int inserted;
  final List<String> skippedCodes;
  final List<String> skippedBarcodes;

  /// BL-05: rows whose imported status column was outside the copy-derived
  /// vocabulary. They are still imported (as `Disponible`, the honest rollup of
  /// freshly-materialized available copies), but the anomaly is surfaced so the
  /// operator learns a value was ignored rather than silently trusted.
  final List<String> invalidStatusCodes;
  int get skipped => skippedCodes.length + skippedBarcodes.length;
}

/// Thrown when a safety backup that MUST precede an irreversible operation
/// (a full wipe) cannot be written. The destructive operation then ABORTS with
/// the data intact, so a mistaken "Erase all data" always leaves a recoverable
/// snapshot behind (BR-04 / REL-02).
class BackupFailedException implements Exception {
  BackupFailedException(this.message);
  final String message;
  @override
  String toString() => 'BackupFailedException: $message';
}

/// A rotating-backup candidate for the retention policy: its file [path] and
/// the [time] it represents (when it was written).
class BackupEntry {
  const BackupEntry(this.path, this.time);
  final String path;
  final DateTime time;
}

/// Rolling retention bound for the audit `history` table (DB-05). Named so the
/// policy lives in one place (see `_trimHistory`) instead of duplicated SQL.
const int kHistoryRetainRows = 1000;

/// Decides which ROTATING backups to delete (BR-05). Pure + clock-injectable so
/// the policy is provable without touching the wall clock or the disk.
///
/// A count-only "keep last N" is fragile: a burst of edits inside a few minutes
/// can create N backups all timestamped within that burst and rotate out EVERY
/// meaningful older recovery point, leaving history that spans minutes instead of
/// days. So this keeps, unconditionally:
///  * the newest [keepCount] backups (an always-recent restore point), AND
///  * the single newest backup from each of the last [keepDaily] calendar days
///    (a daily floor that spans time), even when those fall outside the top N.
/// Anything older than both is returned for deletion.
List<String> selectBackupsToDelete(
  List<BackupEntry> backups, {
  required DateTime now,
  int keepCount = 10,
  int keepDaily = 7,
}) {
  if (backups.length <= keepCount) return const [];
  final sorted = [...backups]..sort((a, b) => b.time.compareTo(a.time));

  final keep = <String>{};
  for (var i = 0; i < keepCount; i++) {
    keep.add(sorted[i].path);
  }
  // Newest-per-day floor: the list is newest-first, so the FIRST backup seen for
  // a given calendar day is that day's newest. Keep it if within the horizon.
  final seenDays = <String>{};
  for (final b in sorted) {
    final dayKey = '${b.time.year}-${b.time.month}-${b.time.day}';
    if (seenDays.add(dayKey)) {
      final ageDays = now.difference(b.time).inDays;
      if (ageDays >= 0 && ageDays < keepDaily) {
        keep.add(b.path);
      }
    }
  }
  return sorted
      .where((b) => !keep.contains(b.path))
      .map((b) => b.path)
      .toList();
}

class DatabaseService implements LibraryRepository {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() {
    return _instance;
  }

  DatabaseService._internal();

  /// Test seam: point the singleton at a pre-opened (in-memory) database so the
  /// data-access + server-side rules can be exercised without `path_provider`.
  @visibleForTesting
  static void useDatabaseForTesting(Database db) => _database = db;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Current schema version. Bump together with a matching `_onUpgrade` step.
  static const int _dbVersion = 23;

  /// The schema version this build opens databases at (exposed for migration
  /// integration tests, DB-08).
  static int get currentSchemaVersion => _dbVersion;

  Future<Database> _initDatabase() async {
    final Directory documentsDirectory =
        await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, 'library_manager.db');
    return openDatabaseAt(path);
  }

  /// Opens (and migrates) the database at [path] using the production schema,
  /// migrations and pragmas. Exposed for integration tests that must drive
  /// `onCreate`/`onUpgrade` against a real file database (closes DB-08, which
  /// the `useDatabaseForTesting` seam cannot exercise).
  @visibleForTesting
  Future<Database> openDatabaseAt(String path) => openDatabase(
    path,
    version: _dbVersion,
    onCreate: _onCreate,
    onUpgrade: _onUpgrade,
    onConfigure: _onConfigure,
  );

  /// Runs on every open. Enables foreign-key enforcement (DB-01). A no-op for
  /// the current schema (no FKs declared yet) and correct once they are.
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _addColumnSafe(
        db,
        'library_items',
        'status',
        "ALTER TABLE library_items ADD COLUMN status TEXT DEFAULT 'Disponible'",
      );
    }
    if (oldVersion < 3) {
      await _addColumnSafe(
        db,
        'library_items',
        'code_type',
        "ALTER TABLE library_items ADD COLUMN code_type TEXT DEFAULT 'LIV'",
      );
      // Update existing status values to French. Guarded: a partial legacy
      // install may lack library_items entirely (DB-08).
      if (await _tableExists(db, 'library_items')) {
        await _runSafe(db, 'status i18n backfill', () async {
          await db.execute(
            "UPDATE library_items SET status = 'Disponible' WHERE status = 'Available'",
          );
          await db.execute(
            "UPDATE library_items SET status = 'Emprunté' WHERE status = 'Borrowed'",
          );
          await db.execute(
            "UPDATE library_items SET status = 'Payé' WHERE status = 'Paid'",
          );
        });
      }
    }
    if (oldVersion < 4) {
      await db.execute('''
            CREATE TABLE IF NOT EXISTS code_definitions(
              prefix TEXT PRIMARY KEY,
              label TEXT
            )
          ''');

      // Seed defaults. Ignore conflicts so a partial install that already
      // holds some (or all) of these prefixes never aborts onUpgrade (DB-08).
      final defaults = [
        {'prefix': 'LIV', 'label': 'Livre'},
        {'prefix': 'REV', 'label': 'Revue'},
        {'prefix': 'THE', 'label': 'Thèse'},
        {'prefix': 'MEM', 'label': 'Mémoire'},
        {'prefix': 'PER', 'label': 'Périodique'},
        {'prefix': 'DOC', 'label': 'Document'},
      ];

      for (final def in defaults) {
        await db.insert(
          'code_definitions',
          def,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
    if (oldVersion < 5) {
      await db.execute('''
            CREATE TABLE IF NOT EXISTS history(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              timestamp TEXT,
              operation TEXT,
              details TEXT,
              user TEXT
            )
          ''');
    }
    if (oldVersion < 6) {
      await _addColumnSafe(
        db,
        'library_items',
        'barcode',
        'ALTER TABLE library_items ADD COLUMN barcode TEXT',
      );
    }
    if (oldVersion < 7) {
      await db.execute('''
            CREATE TABLE IF NOT EXISTS metadata(
              key TEXT PRIMARY KEY,
              value TEXT
            )
          ''');
      await db.insert('metadata', {
        'key': 'db_version',
        'value': DateTime.now().millisecondsSinceEpoch.toString(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    if (oldVersion < 8) {
      await db.execute('''
            CREATE TABLE IF NOT EXISTS attribute_definitions(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              type TEXT,
              value TEXT
            )
          ''');

      // Seed default statuses - These are System Enums. Ignore conflicts so
      // an install that already holds them is not aborted (DB-08).
      final statuses = [
        'Disponible',
        'Emprunté',
        'En Réparation',
        'Perdu',
        'Archivé',
      ];
      for (final status in statuses) {
        await db.insert('attribute_definitions', {
          'type': 'STATUS',
          'value': status,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
    if (oldVersion < 9) {
      await db.execute('''
            CREATE TABLE IF NOT EXISTS members(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              first_name TEXT,
              last_name TEXT,
              email TEXT,
              phone TEXT,
              member_id TEXT UNIQUE,
              registered_at TEXT
            )
          ''');

      await db.execute('''
            CREATE TABLE IF NOT EXISTS loans(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              item_code TEXT,
              member_id TEXT,
              member_name TEXT,
              item_title TEXT,
              loan_date TEXT,
              due_date TEXT,
              return_date TEXT,
              status TEXT
            )
          ''');
    }
    if (oldVersion < 10) {
      // Server-side auth (SEC-02/SEC-03/NET-01): admin credential hash +
      // issued bearer tokens. DDL kept identical to SqfliteAuthStore.
      await db.execute('''
            CREATE TABLE IF NOT EXISTS admin_credentials(
              id TEXT PRIMARY KEY,
              hash TEXT NOT NULL,
              updated_at TEXT
            )
          ''');
      await db.execute('''
            CREATE TABLE IF NOT EXISTS client_tokens(
              token TEXT PRIMARY KEY,
              issued_at TEXT
            )
          ''');
    }
    if (oldVersion < 11) {
      // Phase 2 / DB-02: per-copy physical state. Additive — backfill one
      // copy per existing unit from library_items.quantite.
      await db.execute('''
            CREATE TABLE IF NOT EXISTS item_copies(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              item_code TEXT NOT NULL,
              barcode TEXT,
              state TEXT NOT NULL DEFAULT 'Disponible',
              note TEXT,
              acquired_at TEXT
            )
          ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_item_copies_item ON item_copies(item_code)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_item_copies_barcode ON item_copies(barcode)',
      );
      // Defensive (DB-08): the backfill reads library_items, which a
      // partial legacy install may lack; skip rather than abort onUpgrade.
      if (await _tableExists(db, 'library_items')) {
        await _runSafe(db, 'copy backfill', () async {
          await _backfillCopies(db);
        });
      }
    }
    if (oldVersion < 12) {
      // Phase 2 / DB-02: a loan now references the specific physical copy.
      // Defensive (DB-08): a legacy/partial install may lack `loans`.
      await _addColumnSafe(
        db,
        'loans',
        'copy_id',
        'ALTER TABLE loans ADD COLUMN copy_id INTEGER',
      );
    }
    if (oldVersion < 13) {
      // Phase 4 / DB-01: add the missing indexes on existing installs
      // (non-unique, idempotent — no data can violate them).
      await _createIndexes(db);
    }
    if (oldVersion < 14) {
      // Phase 4 / DB-01 + BL-01: add the UNIQUE constraints defensively.
      await _applyConstraintsSafely(db);
    }
    if (oldVersion < 15) {
      // P9-9.15 / DB-01: idempotently re-run to pick up the new
      // attribute_definitions UNIQUE(type,value) index on existing installs
      // (already-present constraints are IF NOT EXISTS no-ops).
      await _applyConstraintsSafely(db);
    }
    if (oldVersion < 16) {
      // P9-9.16 / TX-06: per-row optimistic-concurrency token. Additive and
      // DEFENSIVE (DB-08): an unguarded ALTER on a table that a legacy/partial
      // install lacks would abort onUpgrade and boot-loop every launch, so
      // _addRowVersionColumnSafely skips a missing table / already-present
      // column and swallows any unexpected error, leaving the DB usable.
      await _addRowVersionColumnSafely(db);
    }
    if (oldVersion < 17) {
      // P9-9.21 / DB-01: real column-level FOREIGN KEYs on loans +
      // item_copies. SQLite cannot add an FK via ALTER, so the tables are
      // rebuilt. Fully DEFENSIVE (DB-08): the rebuild is skipped-with-log
      // when a prerequisite table is missing, when FKs already exist, or
      // when the existing data has orphan rows that would violate the new
      // constraints -- an app whose legacy DB has orphans must still open,
      // not boot-loop. App-level guards (BL-04 delete guards, TX-02 CAS)
      // remain the authoritative enforcement path regardless.
      await _applyForeignKeysSafely(db);
    }
    if (oldVersion < 18) {
      // P9-9.48 / TX-06: per-row optimistic-concurrency token on `members`,
      // mirroring `library_items.row_version` (v16). Additive and DEFENSIVE
      // (DB-08): `_addColumnSafe` skips a missing table / already-present
      // column and swallows any error, so a legacy/partial install can never
      // abort onUpgrade and boot-loop. Existing rows default 0.
      await _addColumnSafe(
        db,
        'members',
        'row_version',
        'ALTER TABLE members ADD COLUMN row_version INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 19) {
      // Phase 10.1 / USERS-ROLES: named accounts + per-token attribution.
      // The `users` table is additive (CREATE IF NOT EXISTS via _runSafe,
      // which can never abort onUpgrade -- DB-08); `client_tokens.username`
      // attributes newly-minted bearer tokens to their owner, NULL for
      // pre-10.1 rows which AuthService resolves to the legacy admin so
      // already-paired clients are never stranded by this upgrade.
      await _runSafe(
        db,
        'create users table',
        () => db.execute('''
            CREATE TABLE IF NOT EXISTS users(
              username TEXT PRIMARY KEY,
              hash TEXT NOT NULL,
              role TEXT NOT NULL,
              created_at TEXT
            )
          '''),
      );
      await _addColumnSafe(
        db,
        'client_tokens',
        'username',
        'ALTER TABLE client_tokens ADD COLUMN username TEXT',
      );
    }
    if (oldVersion < 20) {
      // Phase 10.2 / FINES: an append-mostly ledger of monetary charges.
      // Additive (CREATE IF NOT EXISTS via _runSafe -> never aborts
      // onUpgrade, DB-08). No rows are back-filled: enabling fines is an
      // explicit admin action (a rate in `metadata`) and accrual happens
      // only on FUTURE overdue returns, so no existing member is ever
      // retroactively charged by this upgrade.
      await _runSafe(
        db,
        'create fines table',
        () => db.execute('''
            CREATE TABLE IF NOT EXISTS fines(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              loan_id INTEGER,
              member_id TEXT NOT NULL,
              amount REAL NOT NULL,
              status TEXT NOT NULL,
              reason TEXT,
              created_at TEXT,
              resolved_at TEXT,
              resolved_by TEXT
            )
          '''),
      );
      await _runSafe(db, 'create fines indexes', () async {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_fines_member ON fines(member_id)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_fines_status ON fines(status)',
        );
      });
    }
    if (oldVersion < 21) {
      // Phase 10.3 / RESERVATIONS: the hold queue. Additive (CREATE IF NOT
      // EXISTS via _runSafe -> never aborts onUpgrade, DB-08). No rows are
      // back-filled and no copy changes state: a hold only claims a copy
      // at PROMOTION time, so upgrading can never strand a copy off the
      // shelf. `copy_id` is intentionally NOT an FK: promoted holds point
      // at copies, and deleting a copy must not delete queue history --
      // the promotion/claim paths verify copy existence inside their
      // transactions instead.
      await _runSafe(
        db,
        'create reservations table',
        () => db.execute('''
            CREATE TABLE IF NOT EXISTS reservations(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              item_code TEXT NOT NULL,
              member_id TEXT NOT NULL,
              copy_id INTEGER,
              status TEXT NOT NULL,
              created_at TEXT,
              available_at TEXT,
              available_until TEXT,
              ended_at TEXT,
              note TEXT,
              rank INTEGER
            )
          '''),
      );
      await _runSafe(db, 'create reservations indexes', () async {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_reservations_item ON reservations(item_code)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_reservations_member ON reservations(member_id)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_reservations_status ON reservations(status)',
        );
      });
    }
    if (oldVersion < 22) {
      // BL-05: make copy state authoritative for every title's status. This
      // is a DATA migration (no schema change) and, unlike the additive
      // DDL steps above, it is NOT wrapped in _runSafe: it runs in one
      // transaction so a genuine failure ABORTS onUpgrade (the version is
      // not recorded, so the next launch retries it) rather than leaving a
      // half-reconciled catalogue. A legacy/partial install that lacks the
      // tables entirely is skipped by the existence guard (DB-08).
      if (await _tableExists(db, 'library_items') &&
          await _tableExists(db, 'item_copies')) {
        await _reconcileStatusesFromCopies(db);
      }
    }
    if (oldVersion < 23) {
      // Pass 6: manual reorder of the hold queue. A nullable `rank`
      // column lets an operator pull a walk-in to the front without
      // cancelling + re-placing (which would lose the original
      // created_at and write two spurious audit rows). NULL means
      // "not manually ordered" and every read resolves it via
      // `COALESCE(rank, id)`, so pre-Pass-6 rows continue to sort in
      // their original FIFO order without a backfill. Additive +
      // idempotent via _addColumnSafe (DB-08 boot-loop guard).
      await _addColumnSafe(
        db,
        'reservations',
        'rank',
        'ALTER TABLE reservations ADD COLUMN rank INTEGER',
      );
    }
  }

  /// True if a table exists in the current schema. Reads sqlite_master's `name`
  /// column (NOT `table_name`, a common mistake that silently matches nothing).
  Future<bool> _tableExists(Database db, String table) async {
    final rows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
      [table],
    );
    return rows.isNotEmpty;
  }

  /// Runs an arbitrary migration statement body, swallowing any error so a
  /// legacy/partial schema can never abort `onUpgrade` (DB-08 boot-loop). Logs
  /// what was skipped so the residual gap is observable, not silent.
  Future<void> _runSafe(
    Database db,
    String label,
    Future<void> Function() body,
  ) async {
    try {
      await body();
    } catch (e) {
      debugPrint('migration: "$label" skipped (non-fatal): $e');
    }
  }

  /// Adds a column ONLY when its table exists and the column is still absent,
  /// swallowing any unexpected error so a legacy/partial install (a table that
  /// was never created, or a column a prior partial run already added) can never
  /// abort `onUpgrade` and boot-loop every later launch (DB-08). Idempotent.
  ///
  /// [ddl] must be the full `ALTER TABLE <table> ADD COLUMN <column> ...`
  /// statement; [table]/[column] are used purely for the existence guards.
  Future<void> _addColumnSafe(
    Database db,
    String table,
    String column,
    String ddl,
  ) async {
    try {
      if (!await _tableExists(db, table)) {
        debugPrint(
          'migration: skipped ADD COLUMN $table.$column (no such table)',
        );
        return;
      }
      final cols = await db.rawQuery('PRAGMA table_info($table)');
      if (cols.any((c) => c['name'] == column)) return;
      await db.execute(ddl);
    } catch (e) {
      debugPrint(
        'migration: ADD COLUMN $table.$column skipped (non-fatal): $e',
      );
    }
  }

  /// Adds `library_items.row_version` (TX-06) defensively. Kept as a named
  /// helper (referenced by the TX-06/DB-08 notes); the guard logic now lives in
  /// the reusable [_addColumnSafe].
  Future<void> _addRowVersionColumnSafely(Database db) async {
    await _addColumnSafe(
      db,
      'library_items',
      'row_version',
      'ALTER TABLE library_items ADD COLUMN row_version INTEGER NOT NULL DEFAULT 0',
    );
  }

  /// DB-01: adds real FOREIGN KEYs to `loans` and `item_copies`, which SQLite
  /// cannot attach with ALTER, by rebuilding each table. Entirely DEFENSIVE
  /// (DB-08): the whole thing is wrapped so it can never abort `onUpgrade`, and
  /// it is deliberately SKIPPED (leaving the DB fully usable) when a
  /// prerequisite table is absent, when the FKs already exist (idempotent), or
  /// when the current data holds orphan rows that would violate the new
  /// constraints. In the orphan case the application-level guards (BL-04 delete
  /// guards, TX-02 CAS, the barcode/member checks) remain the sole enforcement
  /// path -- exactly the pre-v17 behavior -- so no install is ever locked out by
  /// a migration it cannot satisfy.
  Future<void> _applyForeignKeysSafely(Database db) async {
    try {
      if (!await _tableExists(db, 'library_items') ||
          !await _tableExists(db, 'loans') ||
          !await _tableExists(db, 'item_copies')) {
        debugPrint(
          'FK rebuild skipped: prerequisite table(s) missing (partial schema)',
        );
        return;
      }
      // Idempotent: a prior run already rebuilt loans with an FK.
      final existingFks = await db.rawQuery('PRAGMA foreign_key_list(loans)');
      if (existingFks.isNotEmpty) return;

      Future<int> scalar(String sql) async {
        final r = await db.rawQuery(sql);
        return (r.first.values.first as int?) ?? 0;
      }

      // Only rebuild when the data already satisfies the FKs we are about to
      // add; otherwise a legacy DB with historical orphans (accumulated over
      // years without FKs) would fail the INSERT..SELECT and, absent this guard,
      // boot-loop. Skip-with-log keeps it open.
      final orphanLoanItem = await scalar(
        'SELECT COUNT(*) FROM loans WHERE item_code IS NOT NULL AND item_code NOT IN (SELECT code FROM library_items)',
      );
      final orphanLoanCopy = await scalar(
        'SELECT COUNT(*) FROM loans WHERE copy_id IS NOT NULL AND copy_id NOT IN (SELECT id FROM item_copies)',
      );
      final orphanCopyItem = await scalar(
        'SELECT COUNT(*) FROM item_copies WHERE item_code NOT IN (SELECT code FROM library_items)',
      );
      if (orphanLoanItem > 0 || orphanLoanCopy > 0 || orphanCopyItem > 0) {
        debugPrint(
          'FK rebuild skipped: pre-existing orphans '
          '(loans.missing_item=$orphanLoanItem loans.missing_copy=$orphanLoanCopy '
          'copies.missing_item=$orphanCopyItem); app-level guards stay authoritative',
        );
        return;
      }

      // item_copies first (it is a parent of loans); then loans.
      await _rebuildTableWithFk(
        db,
        oldName: 'item_copies',
        columns: 'id, item_code, barcode, state, note, acquired_at',
        createBody: '''
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          item_code TEXT NOT NULL REFERENCES library_items(code) ON DELETE CASCADE,
          barcode TEXT,
          state TEXT NOT NULL DEFAULT 'Disponible',
          note TEXT,
          acquired_at TEXT''',
        indexes: const [
          'CREATE INDEX IF NOT EXISTS idx_item_copies_item ON item_copies(item_code)',
          'CREATE INDEX IF NOT EXISTS idx_item_copies_barcode ON item_copies(barcode)',
        ],
        uniqueIndexes: const [
          "CREATE UNIQUE INDEX IF NOT EXISTS uq_copies_barcode ON item_copies(barcode) WHERE barcode IS NOT NULL AND barcode <> ''",
        ],
      );
      await _rebuildTableWithFk(
        db,
        oldName: 'loans',
        columns:
            'id, item_code, copy_id, member_id, member_name, item_title, loan_date, due_date, return_date, status',
        createBody: '''
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          item_code TEXT REFERENCES library_items(code) ON DELETE SET NULL,
          copy_id INTEGER REFERENCES item_copies(id) ON DELETE SET NULL,
          member_id TEXT,
          member_name TEXT,
          item_title TEXT,
          loan_date TEXT,
          due_date TEXT,
          return_date TEXT,
          status TEXT''',
        indexes: const [
          'CREATE INDEX IF NOT EXISTS idx_loans_status ON loans(status)',
          'CREATE INDEX IF NOT EXISTS idx_loans_item ON loans(item_code)',
          'CREATE INDEX IF NOT EXISTS idx_loans_copy ON loans(copy_id)',
        ],
        uniqueIndexes: const [
          "CREATE UNIQUE INDEX IF NOT EXISTS uq_loans_active_copy ON loans(copy_id) WHERE status = 'Active' AND copy_id IS NOT NULL",
        ],
      );
    } catch (e) {
      debugPrint('FK rebuild skipped (non-fatal): $e');
    }
  }

  /// SQLite's documented table-rebuild sequence (create new with the desired
  /// schema -> copy rows -> verify the copy is complete -> drop old -> rename
  /// -> recreate indexes). Runs inside sqflite's migration transaction; because
  /// the caller has already guaranteed zero orphans, the copy cannot violate the
  /// new FKs even though `foreign_keys` is ON. Throws on any inconsistency
  /// BEFORE dropping the old table, so data is never lost; the caller's
  /// try/catch then rolls the whole upgrade back.
  Future<void> _rebuildTableWithFk(
    Database db, {
    required String oldName,
    required String columns,
    required String createBody,
    required List<String> indexes,
    required List<String> uniqueIndexes,
  }) async {
    final tmp = '${oldName}_fkrebuild';
    await db.execute('DROP TABLE IF EXISTS $tmp');
    await db.execute('CREATE TABLE $tmp($createBody)');
    await db.execute(
      'INSERT INTO $tmp($columns) SELECT $columns FROM $oldName',
    );
    // Belt-and-suspenders: refuse to drop the source unless every row landed.
    final oldCount =
        ((await db.rawQuery('SELECT COUNT(*) FROM $oldName')).first.values.first
            as int?) ??
        0;
    final newCount =
        ((await db.rawQuery('SELECT COUNT(*) FROM $tmp')).first.values.first
            as int?) ??
        0;
    if (oldCount != newCount) {
      throw StateError(
        'FK rebuild aborted: $oldName had $oldCount rows but $tmp got $newCount',
      );
    }
    await db.execute('DROP TABLE $oldName');
    await db.execute('ALTER TABLE $tmp RENAME TO $oldName');
    // Indexes are (re)created against the renamed table's real name.
    for (final sql in indexes) {
      await db.execute(sql);
    }
    for (final sql in uniqueIndexes) {
      try {
        await db.execute(sql);
      } catch (e) {
        debugPrint(
          'FK rebuild: unique index skipped (violation): '
          '${sql.split(RegExp(r'\s+')).take(5).join(' ')} ... -> $e',
        );
      }
    }
  }

  /// Non-unique performance / integrity indexes (DB-01). `IF NOT EXISTS` so it
  /// is safe to call from both `_onCreate` and the v13 migration step, and to
  /// re-run over installs that already have some of them.
  Future<void> _createIndexes(Database db) async {
    // Each index is applied independently and defensively: a partial legacy
    // schema may lack the target table, and an uncaught throw here would abort
    // onUpgrade and boot-loop the app (DB-08). `IF NOT EXISTS` also makes this
    // safe to re-run from both _onCreate and the v13 migration step.
    Future<void> attempt(String sql) async {
      try {
        await db.execute(sql);
      } catch (e) {
        debugPrint(
          'Index skipped (non-fatal): '
          '${sql.split(RegExp(r'\s+')).take(6).join(' ')} ... -> $e',
        );
      }
    }

    await attempt(
      'CREATE INDEX IF NOT EXISTS idx_loans_status ON loans(status)',
    );
    await attempt(
      'CREATE INDEX IF NOT EXISTS idx_loans_item ON loans(item_code)',
    );
    await attempt(
      'CREATE INDEX IF NOT EXISTS idx_loans_copy ON loans(copy_id)',
    );
    await attempt(
      'CREATE INDEX IF NOT EXISTS idx_items_status ON library_items(status)',
    );
    await attempt(
      'CREATE INDEX IF NOT EXISTS idx_item_copies_item ON item_copies(item_code)',
    );
    await attempt(
      'CREATE INDEX IF NOT EXISTS idx_item_copies_barcode ON item_copies(barcode)',
    );
  }

  /// Attempt to add the UNIQUE constraints that strengthen DB-01 (barcode
  /// determinism) and BL-01 (at most one active loan per physical copy).
  ///
  /// Each is applied **independently and defensively**: a pre-existing install
  /// may already hold data that violates one (duplicate ISBNs, or the historic
  /// double-active-loan bug). An uncaught throw inside `onUpgrade` would abort
  /// the whole migration and boot-loop the app on every launch (the DB-08
  /// failure mode), so on violation we log and skip — leaving the database
  /// usable. Fresh installs (empty data) always get every constraint, and the
  /// application-level CAS guards in `addLoan` still hold regardless.
  Future<void> _applyConstraintsSafely(Database db) async {
    Future<void> attempt(String sql) async {
      try {
        await db.execute(sql);
      } catch (e) {
        debugPrint(
          'Integrity constraint skipped (pre-existing violation): '
          '${sql.split(RegExp(r'\s+')).take(5).join(' ')} ... -> $e',
        );
      }
    }

    // BL-01 defense-in-depth: a physical copy can have at most one *active*
    // loan. Partial (WHERE) so returned/historical duplicates stay allowed.
    await attempt(
      "CREATE UNIQUE INDEX IF NOT EXISTS uq_loans_active_copy "
      "ON loans(copy_id) "
      "WHERE status = 'Active' AND copy_id IS NOT NULL",
    );
    // DB-01: a non-empty title barcode must be unique (NULL / '' are exempt so
    // blank barcodes never collide).
    await attempt(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_items_barcode '
      "ON library_items(barcode) "
      "WHERE barcode IS NOT NULL AND barcode <> ''",
    );
    await attempt(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_copies_barcode '
      "ON item_copies(barcode) "
      "WHERE barcode IS NOT NULL AND barcode <> ''",
    );
    // DB-01: an attribute value must be unique WITHIN its type (the historic
    // "duplicate statuses" defect). A pre-existing install that already holds a
    // duplicate simply skips this index (defensive); the application-level
    // pre-check in addAttributeDefinition still blocks NEW duplicates.
    await attempt(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_attr_type_value '
      'ON attribute_definitions(type, value)',
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
          CREATE TABLE library_items(
            code TEXT PRIMARY KEY,
            barcode TEXT,
            code_type TEXT DEFAULT 'LIV',
            designation TEXT,
            quantite INTEGER,
            emplacement TEXT,
            taux REAL,
            emplacement_stock TEXT,
            status TEXT DEFAULT 'Disponible',
            row_version INTEGER NOT NULL DEFAULT 0
          )
        ''');

    await db.execute('''
          CREATE TABLE code_definitions(
            prefix TEXT PRIMARY KEY,
            label TEXT
          )
        ''');

    // Seed defaults
    final defaults = [
      {'prefix': 'LIV', 'label': 'Livre'},
      {'prefix': 'REV', 'label': 'Revue'},
      {'prefix': 'THE', 'label': 'Thèse'},
      {'prefix': 'MEM', 'label': 'Mémoire'},
      {'prefix': 'PER', 'label': 'Périodique'},
      {'prefix': 'DOC', 'label': 'Document'},
    ];

    for (final def in defaults) {
      await db.insert('code_definitions', def);
    }

    await db.execute('''
          CREATE TABLE attribute_definitions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT,
            value TEXT
          )
        ''');

    // Seed defaults for attributes
    final statuses = [
      'Disponible',
      'Emprunté',
      'En Réparation',
      'Perdu',
      'Archivé',
    ];
    for (final status in statuses) {
      await db.insert('attribute_definitions', {
        'type': 'STATUS',
        'value': status,
      });
    }

    await db.execute('''
          CREATE TABLE history(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT,
            operation TEXT,
            details TEXT,
            user TEXT
          )
        ''');

    await db.execute('''
          CREATE TABLE metadata(
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');

    await db.execute('''
      CREATE TABLE members(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        first_name TEXT,
        last_name TEXT,
        email TEXT,
        phone TEXT,
        member_id TEXT UNIQUE,
        registered_at TEXT,
        row_version INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE loans(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_code TEXT REFERENCES library_items(code) ON DELETE SET NULL,
        copy_id INTEGER REFERENCES item_copies(id) ON DELETE SET NULL,
        member_id TEXT,
        member_name TEXT,
        item_title TEXT,
        loan_date TEXT,
        due_date TEXT,
        return_date TEXT,
        status TEXT
      )
    ''');
    // Server-side auth tables (see version 10 migration).
    await db.execute('''
      CREATE TABLE admin_credentials(
        id TEXT PRIMARY KEY,
        hash TEXT NOT NULL,
        updated_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE client_tokens(
        token TEXT PRIMARY KEY,
        issued_at TEXT,
        username TEXT
      )
    ''');
    // Phase 10.1: named accounts (mirrors the v19 migration step; hashes are
    // PBKDF2, roles are the UserRole.storage vocabulary -- see user_account.dart).
    await db.execute('''
      CREATE TABLE users(
        username TEXT PRIMARY KEY,
        hash TEXT NOT NULL,
        role TEXT NOT NULL,
        created_at TEXT
      )
    ''');
    // Phase 2 / DB-02: per-copy physical state (fresh DB; no backfill needed).
    await db.execute('''
      CREATE TABLE item_copies(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_code TEXT NOT NULL REFERENCES library_items(code) ON DELETE CASCADE,
        barcode TEXT,
        state TEXT NOT NULL DEFAULT 'Disponible',
        note TEXT,
        acquired_at TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_item_copies_item ON item_copies(item_code)',
    );
    await db.execute(
      'CREATE INDEX idx_item_copies_barcode ON item_copies(barcode)',
    );
    // Fines ledger (Phase 10.2) -- schema-identical to the v20 upgrade step so
    // a fresh install and an upgraded one converge on the same shape.
    await db.execute('''
      CREATE TABLE fines(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        loan_id INTEGER,
        member_id TEXT NOT NULL,
        amount REAL NOT NULL,
        status TEXT NOT NULL,
        reason TEXT,
        created_at TEXT,
        resolved_at TEXT,
        resolved_by TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_fines_member ON fines(member_id)');
    await db.execute('CREATE INDEX idx_fines_status ON fines(status)');
    // Hold queue (Phase 10.3) -- schema-identical to the v21 upgrade step so
    // a fresh install and an upgraded one converge on the same shape.
    await db.execute('''
      CREATE TABLE reservations(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_code TEXT NOT NULL,
        member_id TEXT NOT NULL,
        copy_id INTEGER,
        status TEXT NOT NULL,
        created_at TEXT,
        available_at TEXT,
        available_until TEXT,
        ended_at TEXT,
        note TEXT,
        rank INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_reservations_item ON reservations(item_code)',
    );
    await db.execute(
      'CREATE INDEX idx_reservations_member ON reservations(member_id)',
    );
    await db.execute(
      'CREATE INDEX idx_reservations_status ON reservations(status)',
    );
    // Additional integrity/performance indexes (DB-01), kept in sync with the
    // v13 migration (`IF NOT EXISTS`, so the copy indexes above are no-ops).
    await _createIndexes(db);
    // UNIQUE constraints (DB-01 barcode determinism, BL-01 one-active-loan-per-
    // copy). On an empty fresh DB these always succeed.
    await _applyConstraintsSafely(db);
    await db.insert('metadata', {
      'key': 'db_version',
      'value': DateTime.now().millisecondsSinceEpoch.toString(),
    });
  }

  /// Generates the next sequential code for a given code type.
  ///
  /// BE-07: only *purely numeric* codes participate in the maximum. The old
  /// query ordered by `CAST(code AS INTEGER)`, which folds every legacy
  /// non-numeric code onto its leading digits and can even surface such a row
  /// as the "last" code -- `int.tryParse` then fails and the generator silently
  /// restarts at 0001, colliding with an existing item. Scanning the real
  /// integer values removes both failure modes.
  Future<String> generateNextCode(String codeType) async {
    final db = await database;
    final rows = await db.query(
      'library_items',
      columns: ['code'],
      where: 'code_type = ?',
      whereArgs: [codeType],
    );
    var maxNumber = 0;
    for (final r in rows) {
      final n = int.tryParse((r['code'] as String?) ?? '');
      if (n != null && n > maxNumber) maxNumber = n;
    }
    // Format with leading zeros (e.g., 0001, 0002)
    return (maxNumber + 1).toString().padLeft(4, '0');
  }

  Future<void> insertItem(LibraryItem item) async {
    await addItem(item);
  }

  /// Code of an existing title that already owns a non-empty barcode [bc], or
  /// null when [bc] is free. Pass [exceptCode] on updates so a title keeping
  /// its own barcode is not a clash. Blank/null barcodes are always free,
  /// mirroring the partial `uq_items_barcode` index (which exempts them).
  Future<String?> _barcodeHolder(
    Transaction txn,
    String? bc, {
    String? exceptCode,
  }) async {
    if (bc == null || bc.isEmpty) return null;
    final rows = await txn.query(
      'library_items',
      columns: ['code'],
      where: 'barcode = ? AND code <> ?',
      whereArgs: [bc, exceptCode ?? ''],
    );
    return rows.isEmpty ? null : rows.first['code'] as String;
  }

  @override
  Future<void> addItem(LibraryItem item, {Map<String, dynamic>? audit}) async {
    final db = await database;
    await db.transaction((txn) async {
      // BE-08 / BE-07: a duplicate primary key used to surface as an opaque 500
      // (raw PRIMARY KEY ConstraintError) -- notably when two concurrent adds
      // both picked the same generated code. Detect it first, inside the
      // transaction, so it fails as a clean typed conflict the server maps to
      // 409 and the whole add rolls back.
      final clash = await txn.rawQuery(
        'SELECT COUNT(*) FROM library_items WHERE code = ?',
        [item.code],
      );
      if (((clash.first.values.first as int?) ?? 0) > 0) {
        throw ItemCodeConflictException(
          'Item code ${item.code} already exists.',
        );
      }
      // DB-01: the partial UNIQUE index `uq_items_barcode` makes a non-empty
      // barcode unique across titles. A repeat used to blow up as a raw
      // ConstraintError -> an opaque 500; pre-check it inside the txn so it
      // fails as a clean typed conflict (the server maps it to 409) and the add
      // rolls back. Blank/null barcodes are exempt and never collide.
      final bHolder = await _barcodeHolder(txn, item.barcode);
      if (bHolder != null) {
        throw BarcodeConflictException(
          'Barcode ${item.barcode} is already used by item $bHolder.',
        );
      }
      // BL-05: a supplied title status outside the copy-derived vocabulary is a
      // bad value, refused rather than stored-then-clobbered. A *new* title is
      // always born with N physically-present (available) copies, so its stored
      // status is the derived rollup ('Disponible'), never the caller's string.
      if (!CopyState.isTitleStatus(item.status)) {
        throw InvalidStatusException('Unknown item status "${item.status}".');
      }
      final stored = item.toMap()..['status'] = CopyState.available.storage;
      await txn.insert('library_items', stored);
      // A title owns physical copies from birth (Phase 2 / DB-02).
      await _seedCopies(
        txn,
        item.code,
        item.quantite,
        CopyState.available.storage,
      );
      await _writeAudit(txn, audit);
      await _touchVersion(txn);
    });
  }

  /// Bulk Excel import (host-only). FW-03: previously used
  /// `ConflictAlgorithm.replace`, so any imported row whose `code` already
  /// existed SILENTLY overwrote the catalogue entry (designation/quantity/
  /// status lost). Now existing codes are skipped and reported, new rows are
  /// inserted with their per-copy set seeded, and the whole batch + audit line +
  /// `db_version` stamp commit atomically (one transaction), closing the import
  /// half of BE-09 / RC-06.
  Future<ImportResult> batchInsertItems(
    List<LibraryItem> items, {
    Map<String, dynamic>? audit,
  }) async {
    final db = await database;
    late ImportResult result;
    await db.transaction((txn) async {
      final existing = <String>{
        for (final r in await txn.query('library_items', columns: ['code']))
          r['code'] as String,
      };
      final existingBarcodes = <String>{
        for (final r in await txn.query(
          'library_items',
          columns: ['barcode'],
          where: "barcode IS NOT NULL AND barcode <> ''",
        ))
          r['barcode'] as String,
      };
      final seen = <String>{};
      final seenBarcodes = <String>{};
      final skipped = <String>[];
      final skippedBarcodes = <String>[];
      final invalidStatus = <String>[];
      var inserted = 0;
      for (final item in items) {
        // Skip collisions with the catalogue AND duplicate codes within the
        // same file (importing the same code twice must not insert twice).
        if (existing.contains(item.code) || !seen.add(item.code)) {
          skipped.add(item.code);
          continue;
        }
        final bc = item.barcode;
        if (bc != null &&
            bc.isNotEmpty &&
            (existingBarcodes.contains(bc) || !seenBarcodes.add(bc))) {
          // A duplicate ISBN would violate uq_items_barcode and abort the whole
          // batch; skip it (first holder wins) and report it instead.
          skippedBarcodes.add(item.code);
          continue;
        }
        // BL-05: a flat file carries no copy/loan truth, so an imported title
        // is materialized as N physically-present (available) copies and its
        // status is the derived rollup -- never the supplied string. A column-7
        // value outside the copy vocabulary is IGNORED (row still imported as
        // available) and reported, so it is not silently trusted.
        if (!CopyState.isTitleStatus(item.status)) {
          invalidStatus.add(item.code);
        }
        final stored = item.toMap()..['status'] = CopyState.available.storage;
        await txn.insert(
          'library_items',
          stored,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        await _seedCopies(
          txn,
          item.code,
          item.quantite,
          CopyState.available.storage,
        );
        inserted++;
      }
      await _writeAudit(txn, audit);
      await _touchVersion(txn);
      result = ImportResult(
        inserted: inserted,
        skippedCodes: skipped,
        skippedBarcodes: skippedBarcodes,
        invalidStatusCodes: invalidStatus,
      );
    });
    return result;
  }

  @override
  Future<LibraryItem?> getItemByBarcode(String barcode) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'library_items',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return LibraryItem.fromMap(maps.first);
  }

  Future<void> _updateDbVersion() async {
    final db = await database;
    // Reuse the monotonic in-transaction stamper (DB-06) so the post-restore
    // bump behaves identically to a mutation's own stamp.
    await db.transaction(_touchVersion);
  }

  /// Test-only fault hook invoked **inside** the mutation transaction just
  /// before the `db_version` stamp is written. When it throws, the whole
  /// transaction — data change included — rolls back, proving the two are
  /// atomic (TX-01). Always null in production.
  @visibleForTesting
  Future<void> Function(Transaction txn)? debugBeforeVersionStamp;

  /// Stamp the sync marker **inside** the caller's transaction. Used by every
  /// mutation so a committed data change is never observable without its
  /// `db_version` bump (TX-01).
  Future<void> _touchVersion(Transaction txn) async {
    await debugBeforeVersionStamp?.call(txn);
    // The value is a CHANGE TOKEN, not a real timestamp: clients only compare
    // it for inequality (provider `_lastDbVersion != version`). A bare
    // millisecond stamp let two commits in the same ms -- or a host clock
    // rollback -- produce an IDENTICAL/lower token, so a polling client saw "no
    // change" and silently missed the write (DB-06). Read the current token in
    // this same (writer-serialized) transaction and guarantee strict
    // monotonicity: never go backwards, always advance by at least 1.
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await txn.query(
      'metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['db_version'],
    );
    final current = rows.isEmpty
        ? 0
        : int.tryParse('${rows.first['value']}') ?? 0;
    final next = now > current ? now : current + 1;
    await txn.insert('metadata', {
      'key': 'db_version',
      'value': next.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Run [op] and the sync-marker bump in a SINGLE transaction. Any throw inside
  /// [op] rolls back both the data change and the version, so the database can
  /// never end up mutated-but-stale (which would strand LAN clients polling an
  /// old `db_version`). Small mutations funnel through here.
  Future<R> _atomic<R>(Future<R> Function(Transaction txn) op) async {
    final db = await database;
    return db.transaction<R>((txn) async {
      final result = await op(txn);
      await _touchVersion(txn);
      return result;
    });
  }

  /// The columns the audit `history` table accepts. `_auditRow` projects onto
  /// this set so no caller (or remote POST) can smuggle an `id` -- which would
  /// collide with the AUTOINCREMENT sequence and throw a ConstraintError -- or
  /// an unknown column, which `insert` rejects with a 500 (DB-05).
  static const List<String> _historyColumns = [
    'timestamp',
    'operation',
    'details',
    'user',
  ];

  Map<String, dynamic> _auditRow(Map<String, dynamic> row) {
    final safe = <String, dynamic>{};
    for (final col in _historyColumns) {
      if (row.containsKey(col)) safe[col] = row[col];
    }
    return safe;
  }

  /// Bounded audit retention, run in the SAME transaction as the insert so a
  /// mutation and its (trimmed) audit line commit together. Centralized from
  /// the two former copies of the DELETE. DB-05 residual: this is a deliberate
  /// rolling cap, not an unbounded append-only ledger.
  Future<void> _trimHistory(Transaction txn) async {
    await txn.execute(
      'DELETE FROM history WHERE id IN (SELECT id FROM history ORDER BY timestamp DESC LIMIT -1 OFFSET $kHistoryRetainRows)',
    );
  }

  /// Write the optional audit row **inside** the caller's transaction (before
  /// the version stamp), so a committed mutation always carries its history
  /// line and vice-versa (TX-01 / 5.2). A no-op when [audit] is null (e.g. the
  /// server owns audit for remote-client requests). The map is server-authored
  /// and trusted, so it is inserted as-is -- only the client-facing
  /// [addHistoryEntry] projects onto the audit columns (DB-05); both share the
  /// bounded `_trimHistory` retention.
  Future<void> _writeAudit(Transaction txn, Map<String, dynamic>? audit) async {
    if (audit == null) return;
    await txn.insert('history', audit);
    await _trimHistory(txn);
  }

  @override
  Future<String> getDbVersion() async {
    final db = await database;
    final results = await db.query(
      'metadata',
      where: 'key = ?',
      whereArgs: ['db_version'],
    );
    if (results.isNotEmpty) {
      return results.first['value'] as String;
    }
    return '0';
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
  }) async {
    final db = await database;
    final f = _itemFilterWhere(
      search: search,
      status: status,
      codeType: codeType,
    );
    // Core Workflow Recovery: column sort is applied SERVER-side so a
    // paginated view stays correct across pages (a client-side sort would
    // only reorder the visible page). Whitelist guards against SQL injection:
    // only known column identifiers reach the ORDER BY clause; anything else
    // falls back to the default `(code_type, code)` order.
    const Map<String, String> sortColumn = {
      'code': 'code',
      'designation': 'designation',
      'quantity': 'quantite',
      'status': 'status',
    };
    final mapped = sort == null ? null : sortColumn[sort];
    final orderBy = mapped == null
        ? 'code_type, code'
        : '$mapped ${ascending ? 'ASC' : 'DESC'}, code ASC';
    final List<Map<String, dynamic>> maps = await db.query(
      'library_items',
      where: f.where.isEmpty ? null : f.where,
      whereArgs: f.args.isEmpty ? null : f.args,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    return List.generate(maps.length, (i) {
      return LibraryItem.fromMap(maps[i]);
    });
  }

  @override
  Future<int> countItems({
    String? search,
    String? status,
    String? codeType,
  }) async {
    final db = await database;
    final f = _itemFilterWhere(
      search: search,
      status: status,
      codeType: codeType,
    );
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM library_items'
      '${f.where.isEmpty ? '' : ' WHERE ${f.where}'}',
      f.args,
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Build the shared `WHERE` (+ args) used by BOTH [getItems] and
  /// [countItems] so a page and its total can never disagree (Phase 7).
  /// `search` is matched case-insensitively (SQLite `LIKE`) across the
  /// user-facing columns; `%`/`_` in the term are escaped so they are literal.
  ({String where, List<Object?> args}) _itemFilterWhere({
    String? search,
    String? status,
    String? codeType,
  }) {
    final clauses = <String>[];
    final args = <Object?>[];
    if (status != null && status.isNotEmpty) {
      clauses.add('status = ?');
      args.add(status);
    }
    if (codeType != null && codeType.isNotEmpty) {
      clauses.add('code_type = ?');
      args.add(codeType);
    }
    final term = search?.trim();
    if (term != null && term.isNotEmpty) {
      final escaped = term
          .replaceAll('\\', '\\\\')
          .replaceAll('%', '\\%')
          .replaceAll('_', '\\_');
      final like = '%$escaped%';
      clauses.add(
        "(designation LIKE ? ESCAPE '\\' "
        "OR code LIKE ? ESCAPE '\\' "
        "OR barcode LIKE ? ESCAPE '\\' "
        "OR emplacement LIKE ? ESCAPE '\\' "
        "OR (code_type || '-' || code) LIKE ? ESCAPE '\\')",
      );
      for (var i = 0; i < 5; i++) {
        args.add(like);
      }
    }
    return (where: clauses.isEmpty ? '' : clauses.join(' AND '), args: args);
  }

  @override
  Future<void> updateItem(
    LibraryItem item, {
    Map<String, dynamic>? audit,
    int? expectedVersion,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      // BL-05: an out-of-vocabulary inbound status is a bad value -- refuse it
      // (server 400) rather than store-and-later-clobber. Note the inbound
      // value is only VALIDATED here; the stored status is then derived from
      // the copies below, so a stale metadata edit or a hostile client can
      // never persist a title-level status that contradicts the rollup.
      if (!CopyState.isTitleStatus(item.status)) {
        throw InvalidStatusException('Unknown item status "${item.status}".');
      }
      // DB-01: reject a barcode now held by a DIFFERENT title as a typed
      // conflict (409) instead of a raw UNIQUE ConstraintError (500). Ignoring
      // this row's own code lets an edit that keeps its barcode succeed.
      final bHolder = await _barcodeHolder(
        txn,
        item.barcode,
        exceptCode: item.code,
      );
      if (bHolder != null) {
        throw BarcodeConflictException(
          'Barcode ${item.barcode} is already used by item $bHolder.',
        );
      }
      // TX-06 / BL-05: verify existence + the caller's expected version BEFORE
      // reconciling copies. `item_copies.item_code` has a FK to library_items,
      // so reconciling a row that does not exist would abort on a raw FK error
      // instead of the typed conflict this path must raise. The read and the
      // write share one serialized transaction, so this check is race-free.
      final cur = await txn.query(
        'library_items',
        columns: ['row_version'],
        where: 'code = ?',
        whereArgs: [item.code],
        limit: 1,
      );
      if (cur.isEmpty) {
        throw ConcurrentUpdateConflictException(
          'Item ${item.code} no longer exists.',
        );
      }
      final stored = (cur.first['row_version'] as num?)?.toInt() ?? 0;
      if (expectedVersion != null && expectedVersion != stored) {
        // A stale whole-row write is refused (409) so the caller reloads rather
        // than silently clobbering another client's edit.
        throw ConcurrentUpdateConflictException(
          'Item ${item.code} was modified by another client (now version '
          '$stored, expected $expectedVersion).',
        );
      }
      // Copies are authoritative: reconcile the physical set to the declared
      // quantity, then derive the title status from it -- never from the inbound
      // row. `row_version` advances by exactly one from the stored token.
      await _reconcileCopies(txn, item.code, item.quantite);
      final copyRows = await txn.query(
        'item_copies',
        where: 'item_code = ?',
        whereArgs: [item.code],
        orderBy: 'id',
      );
      final derived = CopyLedger.deriveTitleStatus(
        copyRows.map(ItemCopy.fromMap).toList(),
      );
      // row_version is owned by the server, never taken from the inbound row;
      // status is derived from copies, never taken from the inbound row (BL-05).
      final values = item.toMap()
        ..remove('row_version')
        ..['status'] = derived;
      await txn.update(
        'library_items',
        {...values, 'row_version': stored + 1},
        where: 'code = ?',
        whereArgs: [item.code],
      );
      // Copies were reconciled above, so the derived status written in `values`
      // already reflects the post-reconcile physical set.
      await _writeAudit(txn, audit);
      await _touchVersion(txn);
    });
  }

  /// Insert `quantity` copies (min 1) for a title, all in the given state.
  Future<void> _seedCopies(
    Transaction txn,
    String code,
    int quantity,
    String state,
  ) async {
    final n = quantity < 1 ? 1 : quantity;
    for (var i = 0; i < n; i++) {
      await txn.insert('item_copies', {'item_code': code, 'state': state});
    }
  }

  /// Adjust a title's copies to [quantity] (min 1). Adds available copies when
  /// growing; removes only *available* copies when shrinking, never dropping
  /// below the number currently on loan (an on-loan copy cannot vanish).
  Future<void> _reconcileCopies(
    Transaction txn,
    String code,
    int quantity,
  ) async {
    final rows = await txn.query(
      'item_copies',
      where: 'item_code = ?',
      whereArgs: [code],
      orderBy: 'id',
    );
    if (rows.isEmpty) {
      await _seedCopies(txn, code, quantity, CopyState.available.storage);
      return;
    }
    final copies = rows.map(ItemCopy.fromMap).toList();
    final target = quantity < 1 ? 1 : quantity;
    final current = copies.length;
    if (target > current) {
      for (var i = 0; i < target - current; i++) {
        await txn.insert('item_copies', {
          'item_code': code,
          'state': CopyState.available.storage,
        });
      }
    } else if (target < current) {
      final removable = copies.where((c) => c.isAvailable).toList();
      final drop = current - target;
      for (var i = 0; i < drop && i < removable.length; i++) {
        await txn.delete(
          'item_copies',
          where: 'id = ?',
          whereArgs: [removable[i].id],
        );
      }
    }
  }

  /// Recompute a title's status from the *committed* states of its copies and
  /// write it back (single source of truth for the derived rollup). No-op for
  /// titles that own no copies, so the caller's explicit status is preserved.
  /// TX-06: the write also advances `row_version` so the token is TRUEFUL
  /// staleness — a client that read the title before a checkout/return sees a
  /// version bump and gets its whole-row edit refused (409) instead of
  /// clobbering the loan-derived status with a stale value. Raw SQL because
  /// sqflite `update` cannot express `col = col + 1`.
  Future<void> _recalcItemStatus(Transaction txn, String code) async {
    final rows = await txn.query(
      'item_copies',
      where: 'item_code = ?',
      whereArgs: [code],
      orderBy: 'id',
    );
    if (rows.isEmpty) return;
    final copies = rows.map(ItemCopy.fromMap).toList();
    await txn.rawUpdate(
      'UPDATE library_items SET status = ?, row_version = row_version + 1 WHERE code = ?',
      [CopyLedger.deriveTitleStatus(copies), code],
    );
  }

  /// Count loans that are still **active** and reference this title, either
  /// directly (legacy per-title loans) or through one of its physical copies
  /// (BL-04). Run inside a transaction so the check and the delete are atomic.
  Future<int> _activeLoanCountForItem(Transaction txn, String code) async {
    final active = LoanStatus.active.storage;
    final direct = await txn.rawQuery(
      'SELECT COUNT(*) FROM loans WHERE item_code = ? AND status = ?',
      [code, active],
    );
    final viaCopies = await txn.rawQuery(
      'SELECT COUNT(*) FROM loans l JOIN item_copies c ON l.copy_id = c.id '
      'WHERE c.item_code = ? AND l.status = ?',
      [code, active],
    );
    return ((direct.first.values.first as int?) ?? 0) +
        ((viaCopies.first.values.first as int?) ?? 0);
  }

  @override
  Future<void> deleteItem(String code, {Map<String, dynamic>? audit}) async {
    final db = await database;
    await db.transaction((txn) async {
      // BL-04: never delete a title that is currently on loan — that would
      // orphan the active loan. Historical (returned) loans are fine to keep.
      final activeLoans = await _activeLoanCountForItem(txn, code);
      if (activeLoans > 0) {
        throw ActiveLoanConflictException(
          'Cannot delete item $code: it has $activeLoans active loan(s).',
        );
      }
      await txn.delete('library_items', where: 'code = ?', whereArgs: [code]);
      // Deleting the title cascades to its physical copies (item_copies FK,
      // ON DELETE CASCADE) and SET NULLs the item/copy references on any
      // historical loans (BL-04 keeps that audit history). This explicit delete
      // is redundant on FK-enabled installs but still removes copies on the
      // orphaned legacy installs where the FK rebuild was intentionally skipped.
      await txn.delete(
        'item_copies',
        where: 'item_code = ?',
        whereArgs: [code],
      );
      await _writeAudit(txn, audit);
      await _touchVersion(txn);
    });
  }

  // ---- Item copies (Phase 2 / DB-02) -------------------------------------
  // Additive data-access over `item_copies`. Not yet on the LibraryRepository
  // seam: increment 2.2c widens the interface + adds the HTTP routes when the
  // provider/server are wired through CopyLedger.

  /// Idempotently materialize one physical copy per existing unit for every
  /// title that has no copies yet. Safe to re-run (titles that already own
  /// copies are skipped, so no duplicates). Returns the number created.
  ///
  /// The v10->v11 migration calls this; it is also public so it can be proven
  /// against an already-open database in tests.
  static Future<int> _backfillCopies(Database db) async {
    final items = await db.query('library_items');
    var created = 0;
    for (final it in items) {
      final code = it['code'] as String;
      final existing = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM item_copies WHERE item_code = ?',
        [code],
      );
      if (((existing.first['c'] as int?) ?? 0) > 0) continue;
      final qty = (it['quantite'] as int?) ?? 0;
      final status = (it['status'] as String?) ?? CopyState.available.storage;
      // A title row implies at least one physical unit even if quantite is
      // missing/zero; never backfill zero copies for an existing title.
      final n = qty < 1 ? 1 : qty;
      await db.transaction((txn) async {
        for (var i = 0; i < n; i++) {
          String state = CopyState.available.storage;
          if (status == CopyState.onLoan.storage) {
            // The old per-title model allowed exactly one active loan, so
            // reflect it on the first copy only.
            state = i == 0
                ? CopyState.onLoan.storage
                : CopyState.available.storage;
          } else if (status == CopyState.lost.storage ||
              status == CopyState.archived.storage ||
              status == CopyState.maintenance.storage) {
            // Preserve a terminal/non-lendable title signal on every copy.
            state = status;
          }
          await txn.insert('item_copies', {'item_code': code, 'state': state});
          created++;
        }
      });
    }
    return created;
  }

  /// Public wrapper so the backfill can be exercised on an open database.
  Future<int> backfillCopiesFromItems() async =>
      _backfillCopies(await database);

  /// BL-05 (schema v22): make physical copy state authoritative for every
  /// title's derived status. In ONE transaction it (a) backfills a copy set for
  /// any title that has none, (b) reconciles each copy's state against the
  /// AUTHORITATIVE evidence -- an active loan's referenced copy and a promoted
  /// hold's claimed copy -- so a real `Emprunté`/`Réservé` never flips to
  /// `Disponible`, and (c) writes each title's status as
  /// `CopyLedger.deriveTitleStatus(copies)` WITHOUT bumping `row_version` (a
  /// one-time migration must not invalidate every client's concurrency token).
  ///
  /// Deliberately NOT wrapped in [_runSafe]: a genuine failure aborts
  /// `onUpgrade` (the version is left unrecorded so the next launch retries)
  /// rather than half-migrating the catalogue. It is idempotent -- re-running
  /// derives the same states -- so a retry after an abort is safe.
  Future<void> _reconcileStatusesFromCopies(Database db) async {
    // Schema (not data) check, done before the write transaction: the v21 step
    // guarantees `reservations` exists on any install reaching v22, and
    // `item_copies` since v11, but a defensive probe keeps a partial legacy DB
    // from throwing here.
    final hasReservations = await _tableExists(db, 'reservations');
    await db.transaction((txn) async {
      // Active-loan evidence: copies explicitly referenced by a loan, plus
      // legacy loans that only name the title (copy_id NULL in the old model).
      final loans = await txn.rawQuery(
        'SELECT item_code, copy_id FROM loans WHERE status = ?',
        [LoanStatus.active.storage],
      );
      final onLoanCopyIds = <int>{};
      final legacyLoanItems = <String>{};
      for (final l in loans) {
        final cid = l['copy_id'];
        if (cid != null) {
          onLoanCopyIds.add((cid as num).toInt());
        } else {
          final code = l['item_code'];
          if (code is String) legacyLoanItems.add(code);
        }
      }

      // Promoted-hold evidence: a copy a holder was told to come collect.
      final promotedCopyIds = <int>{};
      final promotedItemCodes = <String>{};
      if (hasReservations) {
        final res = await txn.rawQuery(
          'SELECT item_code, copy_id FROM reservations WHERE status = ?',
          [ReservationStatus.available.storage],
        );
        for (final r in res) {
          final cid = r['copy_id'];
          if (cid != null) promotedCopyIds.add((cid as num).toInt());
          final code = r['item_code'];
          if (code is String) promotedItemCodes.add(code);
        }
      }

      final titles = await txn.query(
        'library_items',
        columns: ['code', 'quantite'],
      );
      for (final t in titles) {
        final code = t['code'] as String;
        final qty = (t['quantite'] as int?) ?? 0;
        // Work on MUTABLE copies of the rows: `txn.query` returns read-only
        // `QueryRow`s, and the reconciliation below must reflect each state it
        // writes into the in-memory set it derives the rollup from.
        Future<List<Map<String, dynamic>>> loadCopies() async => [
          for (final r in await txn.query(
            'item_copies',
            where: 'item_code = ?',
            whereArgs: [code],
            orderBy: 'id',
          ))
            Map<String, dynamic>.from(r),
        ];
        var rows = await loadCopies();

        // (a) A title with no copies still owns physical units (min 1); seed
        // them available, then the evidence pass below marks loan/hold states.
        if (rows.isEmpty) {
          final n = qty < 1 ? 1 : qty;
          for (var i = 0; i < n; i++) {
            await txn.insert('item_copies', {
              'item_code': code,
              'state': CopyState.available.storage,
            });
          }
          rows = await loadCopies();
        }

        // (b) Reconcile copy states to the authoritative evidence (idempotent:
        // writing the same state twice is a no-op). Never demotes a genuinely
        // on-loan copy, and leaves terminal (lost/archived/repaired) copies as
        // they are -- those are physical facts, not loan/hold-driven.
        for (final row in rows) {
          final id = (row['id'] as num).toInt();
          final cur = row['state'] as String?;
          String? next;
          if (onLoanCopyIds.contains(id)) {
            next = CopyState.onLoan.storage;
          } else if (promotedCopyIds.contains(id) &&
              cur != CopyState.onLoan.storage) {
            next = CopyState.reserved.storage;
          }
          if (next != null && next != cur) {
            await txn.update(
              'item_copies',
              {'state': next},
              where: 'id = ?',
              whereArgs: [id],
            );
            row['state'] = next;
          }
        }

        // A legacy copy-less active loan: guarantee the title still reads as
        // out by marking one still-available copy on loan (only if none is).
        if (legacyLoanItems.contains(code) &&
            !rows.any((c) => c['state'] == CopyState.onLoan.storage)) {
          for (final row in rows) {
            if (row['state'] == CopyState.available.storage) {
              await txn.update(
                'item_copies',
                {'state': CopyState.onLoan.storage},
                where: 'id = ?',
                whereArgs: [(row['id'] as num).toInt()],
              );
              row['state'] = CopyState.onLoan.storage;
              break;
            }
          }
        }
        // A promoted hold that names only the title: mark one available copy
        // reserved (unless a copy is already reserved/on loan).
        if (promotedItemCodes.contains(code) &&
            !rows.any(
              (c) =>
                  c['state'] == CopyState.reserved.storage ||
                  c['state'] == CopyState.onLoan.storage,
            )) {
          for (final row in rows) {
            if (row['state'] == CopyState.available.storage) {
              await txn.update(
                'item_copies',
                {'state': CopyState.reserved.storage},
                where: 'id = ?',
                whereArgs: [(row['id'] as num).toInt()],
              );
              row['state'] = CopyState.reserved.storage;
              break;
            }
          }
        }

        // (c) Title status := the rollup of its (now evidence-bearing) copies.
        final derived = CopyLedger.deriveTitleStatus(
          rows.map(ItemCopy.fromMap).toList(),
        );
        await txn.rawUpdate(
          'UPDATE library_items SET status = ? WHERE code = ?',
          [derived, code],
        );
      }
    });
  }

  Future<List<ItemCopy>> getCopies(String itemCode) async {
    final db = await database;
    final rows = await db.query(
      'item_copies',
      where: 'item_code = ?',
      whereArgs: [itemCode],
      orderBy: 'id',
    );
    return rows.map(ItemCopy.fromMap).toList();
  }

  Future<ItemCopy?> getCopyById(int id) async {
    final db = await database;
    final rows = await db.query(
      'item_copies',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : ItemCopy.fromMap(rows.first);
  }

  /// Resolve a per-copy barcode to its copy (BL-03 seam). Distinct from
  /// [getItemByBarcode], which matches the shared ISBN on the title row.
  Future<ItemCopy?> getCopyByBarcode(String barcode) async {
    final db = await database;
    final rows = await db.query(
      'item_copies',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );
    return rows.isEmpty ? null : ItemCopy.fromMap(rows.first);
  }

  Future<int> addCopy(ItemCopy copy) =>
      _atomic((txn) => txn.insert('item_copies', copy.toMap()));

  Future<void> updateCopy(ItemCopy copy) => _atomic(
    (txn) => txn.update(
      'item_copies',
      copy.toMap(),
      where: 'id = ?',
      whereArgs: [copy.id],
    ),
  );

  Future<void> deleteCopiesForItem(String itemCode) => _atomic(
    (txn) => txn.delete(
      'item_copies',
      where: 'item_code = ?',
      whereArgs: [itemCode],
    ),
  );

  /// Phase 12 / BL-05 follow-up: set a physical copy's CONDITION to one of the
  /// staff-editable states {available, maintenance, lost, archived}. The
  /// circulation-driven states (Emprunté / Réservé) are owned solely by the loan
  /// and hold flows, so (a) they can never be *requested* here and (b) a copy
  /// that is *currently* on loan or reserved can never be hand-edited — it must
  /// be returned / have its hold released first. This keeps the copy ledger
  /// truthful, and because the title rollup is re-derived in the SAME
  /// transaction (`_recalcItemStatus` bumps `row_version`; `_atomic` bumps the
  /// global db_version) `library_items.status` stays authoritative and LAN
  /// clients refresh. Throws [InvalidStatusException] for a non-editable target
  /// and [CopyConflictException] when the copy is unknown or checked-out/held.
  Future<void> setCopyCondition(
    int copyId,
    CopyState target, {
    Map<String, dynamic>? audit,
  }) async {
    // (1) Only a physical condition may be requested by hand.
    if (target != CopyState.available &&
        target != CopyState.maintenance &&
        target != CopyState.lost &&
        target != CopyState.archived) {
      throw InvalidStatusException(
        'A copy\'s "${target.storage}" state is managed by loans / holds, '
        'not by hand.',
      );
    }
    await _atomic((txn) async {
      final rows = await txn.query(
        'item_copies',
        columns: ['item_code'],
        where: 'id = ?',
        whereArgs: [copyId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw CopyConflictException('Copy $copyId no longer exists.');
      }
      // (2) CAS: refuse to touch a copy that is checked out or claimed by a
      // hold, re-checking atomically so a concurrent checkout that wins the
      // race turns this into a refused no-op rather than a silent clobber.
      final affected = await txn.rawUpdate(
        'UPDATE item_copies SET state = ? '
        'WHERE id = ? AND state NOT IN (?, ?)',
        [
          target.storage,
          copyId,
          CopyState.onLoan.storage,
          CopyState.reserved.storage,
        ],
      );
      if (affected == 0) {
        throw CopyConflictException(
          'Copy $copyId is checked out or reserved and must be changed via '
          'the loan / hold flow.',
        );
      }
      // (3) The title status is always the rollup of its copies (BL-05).
      await _recalcItemStatus(txn, rows.first['item_code'] as String);
      await _writeAudit(txn, audit);
    });
  }

  /// Phase 13: add one physical copy (available) to a title, keep the declared
  /// `quantite` in lock-step with the real copy count, and re-derive the title
  /// status (BL-05: `quantite` and the copy set must never disagree, or a later
  /// item-form save would silently add/remove copies under the editor). Host-only
  /// by caller policy; returns the new copy id.
  Future<int> addCopyForItem(
    String itemCode, {
    Map<String, dynamic>? audit,
  }) async {
    late int newId;
    await _atomic((txn) async {
      final exists = await txn.query(
        'library_items',
        columns: ['code'],
        where: 'code = ?',
        whereArgs: [itemCode],
        limit: 1,
      );
      if (exists.isEmpty) {
        throw CopyConflictException('Item $itemCode does not exist.');
      }
      newId = await txn.insert('item_copies', {
        'item_code': itemCode,
        'state': CopyState.available.storage,
      });
      final c = await txn.rawQuery(
        'SELECT COUNT(*) AS c FROM item_copies WHERE item_code = ?',
        [itemCode],
      );
      final count = ((c.first['c'] as num?) ?? 0).toInt();
      await txn.update(
        'library_items',
        {'quantite': count},
        where: 'code = ?',
        whereArgs: [itemCode],
      );
      await _recalcItemStatus(txn, itemCode);
      await _writeAudit(txn, audit);
    });
    return newId;
  }

  /// Phase 13: remove one physical copy. A copy that is checked-out / on hold is
  /// owned by the loan / hold flow and cannot be removed by hand (the same CAS
  /// rule as [setCopyCondition]), and the LAST copy of a title cannot be removed
  /// (delete the item instead) so a title always keeps a physical unit — matching
  /// [_reconcileCopies], which never drops below one or below the on-loan count.
  /// Deleting a copy SET NULLs any historical (returned) loan's `copy_id` (the
  /// schema FK is ON DELETE SET NULL); an active loan can never reference a copy
  /// we allow deleting. `quantite` is re-synced and the title status re-derived.
  /// Host-only by caller policy.
  Future<void> removeCopy(int copyId, {Map<String, dynamic>? audit}) async {
    await _atomic((txn) async {
      final rows = await txn.query(
        'item_copies',
        columns: ['item_code'],
        where: 'id = ?',
        whereArgs: [copyId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw CopyConflictException('Copy $copyId no longer exists.');
      }
      final code = rows.first['item_code'] as String;
      // (1) Keep at least one physical unit for the title.
      final before = await txn.rawQuery(
        'SELECT COUNT(*) AS c FROM item_copies WHERE item_code = ?',
        [code],
      );
      if ((((before.first['c'] as num?) ?? 0).toInt()) <= 1) {
        throw CopyConflictException(
          'Cannot remove the last copy of $code. Delete the item instead.',
        );
      }
      // (2) CAS: never drop a copy that is on loan or reserved.
      final affected = await txn.rawUpdate(
        'DELETE FROM item_copies WHERE id = ? AND state NOT IN (?, ?)',
        [copyId, CopyState.onLoan.storage, CopyState.reserved.storage],
      );
      if (affected == 0) {
        throw CopyConflictException(
          'Copy $copyId is checked out or reserved and cannot be removed.',
        );
      }
      // (3) Re-sync quantite and re-derive the title rollup.
      final after = await txn.rawQuery(
        'SELECT COUNT(*) AS c FROM item_copies WHERE item_code = ?',
        [code],
      );
      final count = ((after.first['c'] as num?) ?? 0).toInt();
      await txn.update(
        'library_items',
        {'quantite': count},
        where: 'code = ?',
        whereArgs: [code],
      );
      await _recalcItemStatus(txn, code);
      await _writeAudit(txn, audit);
    });
  }

  /// Phase 13: set (or clear, when blank) one copy's per-copy barcode. The
  /// `uq_copies_barcode` partial UNIQUE index means a non-empty barcode must be
  /// unique across all copies, so a value already claimed by another copy is
  /// refused with [BarcodeConflictException] (-> errConflict / HTTP 409). A
  /// per-copy barcode may legitimately equal the TITLE's shared ISBN (a
  /// different table). Barcode is not part of the status rollup, so no
  /// re-derivation is needed. Host-only by caller policy.
  Future<void> setCopyBarcode(
    int copyId,
    String? barcode, {
    Map<String, dynamic>? audit,
  }) async {
    final trimmed = barcode?.trim();
    final normalized = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    await _atomic((txn) async {
      final rows = await txn.query(
        'item_copies',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [copyId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw CopyConflictException('Copy $copyId no longer exists.');
      }
      if (normalized != null) {
        final clash = await txn.query(
          'item_copies',
          columns: ['id'],
          where: 'barcode = ? AND id <> ?',
          whereArgs: [normalized, copyId],
          limit: 1,
        );
        if (clash.isNotEmpty) {
          throw BarcodeConflictException(
            'Barcode $normalized is already assigned to another copy.',
          );
        }
      }
      await txn.update(
        'item_copies',
        {'barcode': normalized},
        where: 'id = ?',
        whereArgs: [copyId],
      );
      await _writeAudit(txn, audit);
    });
  }

  // History Methods
  @override
  Future<List<Map<String, dynamic>>> getHistory({
    int limit = 20,
    int offset = 0,
    String? subject,
  }) async {
    final db = await database;
    // Per-record audit trail (Pass 5): a subject string filters to rows whose
    // `details` mention it. Null / empty means no filter, matching every
    // existing caller. LIKE is used instead of a new column because the
    // existing audit writers already embed the item code and/or member id in
    // `details` ("Emprunt: BK-001 par Amira", "Copie #3 de BK-001 -> ..."),
    // so a scan on the 1,000-row retention window is cheap and gives a
    // correct answer without a migration. Callers pass a bare code or member
    // id, which never contains LIKE metacharacters (`%` or `_`), so no
    // escaping layer is required here.
    final hasSubject = subject != null && subject.isNotEmpty;
    return await db.query(
      'history',
      where: hasSubject ? 'details LIKE ?' : null,
      whereArgs: hasSubject ? ['%$subject%'] : null,
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<void> addHistoryEntry(Map<String, dynamic> entry) =>
      _atomic((txn) async {
        // DB-05: project onto the known audit columns (id and unknown keys are
        // dropped, so a client-supplied id can neither collide nor overwrite).
        await txn.insert('history', _auditRow(entry));
        await _trimHistory(txn);
      });

  @override
  Future<Map<String, dynamic>> getStats() async {
    final db = await database;

    // Phase 2 / DB-06: physical copies are the source of truth. Count copies,
    // falling back to the declared `quantite` only for legacy titles that own
    // no copies yet (so mixed migrations don't under-report).
    final totalDocs = await db.rawQuery('''
      SELECT SUM(COALESCE(cb.cnt, i.quantite, 0)) AS total
      FROM library_items i
      LEFT JOIN (SELECT item_code, COUNT(*) cnt FROM item_copies
                 GROUP BY item_code) cb ON cb.item_code = i.code
    ''');
    final totalValue = await db.rawQuery(
      'SELECT SUM(quantite * taux) as total FROM library_items',
    );
    final onLoan = await db.rawQuery(
      '''
      SELECT (SELECT COUNT(*) FROM item_copies WHERE state = ?) +
             (SELECT COALESCE(SUM(i.quantite), 0) FROM library_items i
                WHERE i.status = ?
                  AND i.code NOT IN (SELECT item_code FROM item_copies)) AS total
    ''',
      [CopyState.onLoan.storage, CopyState.onLoan.storage],
    );

    // Type distributions (copies where present, else declared quantity).
    final typeCounts = await db.rawQuery('''
      SELECT i.code_type AS code_type,
             SUM(COALESCE(cb.cnt, i.quantite, 0)) AS count
      FROM library_items i
      LEFT JOIN (SELECT item_code, COUNT(*) cnt FROM item_copies
                 GROUP BY item_code) cb ON cb.item_code = i.code
      GROUP BY i.code_type
    ''');

    return {
      'totalQuantity': totalDocs.first['total'] ?? 0,
      'totalValue': (totalValue.first['total'] as num? ?? 0.0).toDouble(),
      'onLoan': onLoan.first['total'] ?? 0,
      'typeDist': {
        for (var row in typeCounts)
          row['code_type'] as String: row['count'] ?? 0,
      },
    };
  }

  // Code Definition Methods
  @override
  Future<List<Map<String, dynamic>>> getCodeDefinitions() async {
    final db = await database;
    return await db.query('code_definitions');
  }

  @override
  Future<void> addCodeDefinition(
    String prefix,
    String label, {
    Map<String, dynamic>? audit,
  }) => _atomic((txn) async {
    await txn.insert('code_definitions', {'prefix': prefix, 'label': label});
    await _writeAudit(txn, audit);
  });

  @override
  Future<void> updateCodeDefinition(
    String oldPrefix,
    String newPrefix,
    String label, {
    Map<String, dynamic>? audit,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'code_definitions',
        {'prefix': newPrefix, 'label': label},
        where: 'prefix = ?',
        whereArgs: [oldPrefix],
      );

      if (oldPrefix != newPrefix) {
        // TX-06: a prefix rename rewrites `code_type` on every row of the
        // type, so those rows advance their version token too — a form opened
        // under the old prefix can no longer silently write it back.
        await txn.rawUpdate(
          'UPDATE library_items SET code_type = ?, row_version = row_version + 1 WHERE code_type = ?',
          [newPrefix, oldPrefix],
        );
      }
      await _writeAudit(txn, audit);
      await _touchVersion(txn);
    });
  }

  @override
  Future<void> deleteCodeDefinition(
    String prefix, {
    Map<String, dynamic>? audit,
  }) => _atomic((txn) async {
    await txn.delete(
      'code_definitions',
      where: 'prefix = ?',
      whereArgs: [prefix],
    );
    await _writeAudit(txn, audit);
  });

  // Attribute Definitions Implementation
  @override
  Future<List<Map<String, dynamic>>> getAttributeDefinitions(
    String? type,
  ) async {
    final db = await database;
    if (type != null) {
      return await db.query(
        'attribute_definitions',
        where: 'type = ?',
        whereArgs: [type],
      );
    }
    return await db.query('attribute_definitions');
  }

  @override
  Future<void> addAttributeDefinition(
    String type,
    String value, {
    Map<String, dynamic>? audit,
  }) => _atomic((txn) async {
    // DB-01: reject a (type, value) the catalogue already holds as a typed
    // conflict (server -> 409) rather than tripping the uq_attr_type_value
    // UNIQUE index with a raw ConstraintError (500). The whole add rolls
    // back so no audit line is written for a rejected definition.
    final clash = await txn.query(
      'attribute_definitions',
      columns: ['id'],
      where: 'type = ? AND value = ?',
      whereArgs: [type, value],
      limit: 1,
    );
    if (clash.isNotEmpty) {
      throw AttributeConflictException(
        'Attribute ($type, $value) already exists.',
      );
    }
    await txn.insert('attribute_definitions', {'type': type, 'value': value});
    await _writeAudit(txn, audit);
  });

  @override
  Future<void> deleteAttributeDefinition(
    int id, {
    Map<String, dynamic>? audit,
  }) => _atomic((txn) async {
    await txn.delete('attribute_definitions', where: 'id = ?', whereArgs: [id]);
    await _writeAudit(txn, audit);
  });

  /// Wipes all data and resets to defaults.
  ///
  /// A full erase is irreversible, so a durable `pre_wipe` safety snapshot of
  /// the CURRENT database is written FIRST (BR-04 / REL-02); the previous design
  /// only fired an auto-backup *after* the wipe, so a mistaken erase could be
  /// unrecoverable if no backup was newer than the 30-minute interval. If the
  /// snapshot cannot be created the wipe ABORTS via [BackupFailedException]
  /// leaving every row intact. Runs inside the caller's LAN-maintenance window
  /// so the snapshot is taken with no concurrent server writes.
  Future<void> clearAllData({Map<String, dynamic>? audit}) async {
    await createSafetyBackup('pre_wipe');
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('library_items');
      // RC-05: the per-copy table was added after the original 6-table wipe
      // list, so a "complete erase" silently left every physical-copy row
      // behind -- orphans that resurface (stale on-loan state, double-seeded
      // copies) the moment a code is re-imported/re-added. Clear it with the
      // rest of the catalogue. (`admin_credentials`/`client_tokens` are auth,
      // not catalog data: wiping the host admin password would lock the
      // operator out of their own machine, so they are intentionally kept.)
      await txn.delete('item_copies');
      await txn.delete('members');
      await txn.delete('loans');
      await txn.delete('history');
      await txn.delete('attribute_definitions');
      await txn.delete('code_definitions');

      // Seed defaults
      final defaults = [
        {'prefix': 'LIV', 'label': 'Livre'},
        {'prefix': 'REV', 'label': 'Revue'},
        {'prefix': 'THE', 'label': 'Thèse'},
        {'prefix': 'MEM', 'label': 'Mémoire'},
        {'prefix': 'PER', 'label': 'Périodique'},
        {'prefix': 'DOC', 'label': 'Document'},
      ];

      for (final def in defaults) {
        await txn.insert('code_definitions', def);
      }

      final statuses = [
        'Disponible',
        'Emprunté',
        'En Réparation',
        'Perdu',
        'Archivé',
      ];
      for (final status in statuses) {
        await txn.insert('attribute_definitions', {
          'type': 'STATUS',
          'value': status,
        });
      }
      await _writeAudit(txn, audit);
      await _touchVersion(txn);
    });
  }

  /// Get count of items by code type
  Future<Map<String, int>> getCountByCodeType() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT code_type, COUNT(*) as count FROM library_items GROUP BY code_type",
    );

    final Map<String, int> counts = {};
    for (final row in result) {
      counts[row['code_type'] as String] = row['count'] as int;
    }
    return counts;
  }

  /// Get count of items by status
  Future<Map<String, int>> getCountByStatus() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT status, COUNT(*) as count FROM library_items GROUP BY status",
    );

    final Map<String, int> counts = {};
    for (final row in result) {
      counts[row['status'] as String] = row['count'] as int;
    }
    return counts;
  }

  Future<String> getDatabasePath() async {
    final Directory documentsDirectory =
        await getApplicationDocumentsDirectory();
    return join(documentsDirectory.path, 'library_manager.db');
  }

  /// Writes a consistent, standalone snapshot of the live database to
  /// [destinationPath] using SQLite's `VACUUM INTO`. This is deliberately NOT a
  /// raw `File.copy`: copying a database that is open for writes can capture a
  /// torn / half-committed image (and misses any `-wal` sidecar under WAL),
  /// yielding a backup that fails `integrity_check` or silently loses recent
  /// commits (DB-03). `VACUUM INTO` produces a single checkpointed, WAL-free
  /// file that is transactionally consistent with the moment of the snapshot.
  Future<void> backupDatabase(String destinationPath) async {
    final db = await database;
    final dest = File(destinationPath);
    await dest.parent.create(recursive: true);
    // VACUUM INTO refuses to overwrite an existing file.
    if (await dest.exists()) await dest.delete();
    try {
      await db.execute('VACUUM INTO ?', [destinationPath]);
    } on DatabaseException catch (_) {
      // Belt-and-suspenders: fall back to a literal target with quotes escaped
      // for bindings that reject a parameterised VACUUM filename.
      final escaped = destinationPath.replaceAll("'", "''");
      await db.execute("VACUUM INTO '$escaped'");
    }
    // A backup is worthless if it is not actually restorable. Verify the file
    // we just produced BEFORE handing it back (BR-02 / REL-01); on failure,
    // delete the bogus snapshot so it can never be mistaken for a recovery
    // point, then rethrow. This covers EVERY creation path (auto, safety,
    // pre-restore) because they all funnel through here.
    try {
      await verifyBackupOrThrow(destinationPath);
    } catch (_) {
      try {
        await dest.delete();
      } catch (e) {
        // RC-07: the original verify failure is rethrown, but a failure to
        // remove the bogus snapshot is now surfaced (it could masquerade as a
        // recovery point on disk).
        appLog.warn('backup', 'Failed to delete invalid backup snapshot', e);
      }
      rethrow;
    }
  }

  /// Confirms [path] is a complete, integral, compatible library backup by
  /// opening it read-only and running the same probe a restore uses
  /// (`PRAGMA integrity_check` + core tables + not-a-newer-schema). Throws
  /// [BackupFailedException] if it is not (BR-02 / REL-01). Shared by backup
  /// creation (post-write verification) and restore (pre-write validation).
  @visibleForTesting
  Future<void> verifyBackupOrThrow(String path) async {
    final reason = await _incompatibleBackupReason(path);
    if (reason != null) {
      throw BackupFailedException('Backup verification failed: $reason');
    }
  }

  /// Validates [sourcePath] is a real, integral, compatible library backup and
  /// only THEN restores it over the live database (DB-04). The candidate is
  /// inspected read-only FIRST, a safety snapshot of the CURRENT database is
  /// taken, and stale journal/WAL sidecars are cleared so the old log is never
  /// replayed onto the restored file. A rejected candidate throws
  /// [RestoreException] WITHOUT modifying the live database.
  Future<void> restoreDatabase(String sourcePath) async {
    final dbPath = await getDatabasePath();
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw RestoreException('Backup file not found: $sourcePath');
    }
    final reason = await _incompatibleBackupReason(sourcePath);
    if (reason != null) {
      throw RestoreException(reason);
    }

    // Safety net: snapshot the current database before we overwrite it, so a
    // bad-but-valid restore is itself recoverable.
    if (await File(dbPath).exists()) {
      try {
        await backupDatabase('$dbPath.pre_restore');
      } catch (e) {
        debugPrint('Pre-restore safety backup failed: $e');
      }
    }

    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
    await _deleteStaleJournals(dbPath);

    await source.copy(dbPath);
    await database; // reopen (runs migrations for an older-but-valid schema)
    await _updateDbVersion();
  }

  /// Returns `null` if [path] is a safe backup to restore, or a human-readable
  /// reason it is not. Opens the candidate read-only so the live DB is never
  /// touched during validation.
  Future<String?> _incompatibleBackupReason(String path) async {
    Database? probe;
    try {
      probe = await openDatabase(path, readOnly: true, singleInstance: false);
      final check = await probe.rawQuery('PRAGMA integrity_check');
      if (check.isEmpty || '${check.first.values.first}' != 'ok') {
        return 'Backup failed integrity check (the file is corrupt).';
      }
      final tables = (await probe.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      )).map((r) => '${r['name']}').toSet();
      if (!tables.contains('library_items') || !tables.contains('metadata')) {
        return 'Backup is not a library database (missing core tables).';
      }
      final uv = await probe.rawQuery('PRAGMA user_version');
      final schemaVersion = (uv.first.values.first as int?) ?? 0;
      if (schemaVersion > _dbVersion) {
        return 'Backup is from a newer schema ($schemaVersion) than this app '
            '($_dbVersion); upgrade before restoring.';
      }
      return null;
    } on DatabaseException catch (e) {
      return 'Backup is not a readable SQLite database: $e';
    } catch (e) {
      return 'Backup could not be validated: $e';
    } finally {
      await probe?.close();
    }
  }

  Future<void> _deleteStaleJournals(String dbPath) async {
    for (final suffix in const ['-wal', '-shm', '-journal']) {
      final f = File('$dbPath$suffix');
      try {
        if (await f.exists()) await f.delete();
      } catch (e) {
        debugPrint('Could not remove stale $suffix sidecar: $e');
      }
    }
  }

  Future<void> createAutoBackup() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(join(docsDir.path, 'library_backups'));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final backupPath = join(backupDir.path, 'library_backup_$timestamp.db');

    await backupDatabase(backupPath);

    // Retention (BR-05): keep the last [keepCount] ROTATING backups AND a
    // newest-per-day floor over the retention horizon, so a burst of writes
    // cannot rotate out every older recovery point. Safety snapshots
    // (pre_wipe_*, written before an irreversible wipe) are deliberately NOT
    // considered here, so the recovery point for a mistaken erase always
    // survives (BR-04). Reading each file's mtime once (outside the sort) also
    // avoids the previous `statSync`-inside-comparator blocking + choking on
    // stray non-file entries.
    try {
      final files = (await backupDir.list().toList())
          .whereType<File>()
          .where((f) => basename(f.path).startsWith('library_backup_'))
          .toList();
      final entries = <BackupEntry>[];
      for (final f in files) {
        try {
          entries.add(BackupEntry(f.path, f.statSync().modified));
        } catch (e) {
          // RC-07: a per-file stat failure (stray entry / locked file) is
          // non-fatal but was fully silent; record at debug so retention bugs
          // are diagnosable without spamming higher levels.
          appLog.debug('backup', 'Skipped unreadable backup file ${f.path}', e);
        }
      }
      for (final path in selectBackupsToDelete(entries, now: DateTime.now())) {
        try {
          await File(path).delete();
        } catch (e) {
          // RC-07: a failed old-backup delete is non-fatal but was silent; a
          // growing backlog should be observable.
          appLog.warn('backup', 'Failed to delete expired backup $path', e);
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up backups: $e');
    }
  }

  /// Writes a durable, consistently-snapshotted safety backup tagged [tag]
  /// (e.g. `pre_wipe`) into the backups directory and returns its path. Unlike
  /// [createAutoBackup] the result is exempt from the keep-last-10 rotation, so
  /// a snapshot taken ahead of an irreversible operation survives. A failure to
  /// write it throws [BackupFailedException] so the caller aborts rather than
  /// destroying data with no way back.
  Future<String> createSafetyBackup(String tag) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final backupDir = Directory(join(docsDir.path, 'library_backups'));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final backupPath = join(backupDir.path, '${tag}_$timestamp.db');
      await backupDatabase(backupPath);
      return backupPath;
    } catch (e) {
      throw BackupFailedException(
        'Could not create a "$tag" safety backup ($e). No data was changed.',
      );
    }
  }

  // Members
  @override
  Future<List<Member>> getMembers() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('members');
    return List.generate(maps.length, (i) => Member.fromMap(maps[i]));
  }

  @override
  Future<String> generateMemberID() async {
    final db = await database;
    final year = DateTime.now().year.toString().substring(
      2,
    ); // Last 2 digits of year

    final yearPrefix = year;
    final result = await db.rawQuery(
      "SELECT MAX(member_id) as max_id FROM members WHERE member_id LIKE ?",
      ['$yearPrefix%'],
    );

    final maxId = result.isNotEmpty
        ? (result.first['max_id'] as String?)
        : null;
    var next = 1;
    if (maxId != null && maxId.length >= 6) {
      final suffix = maxId.substring(2);
      final parsed = int.tryParse(suffix);
      if (parsed != null) {
        next = parsed + 1;
      }
    }

    final nextNumber = next.toString().padLeft(4, '0');
    return '$yearPrefix$nextNumber'; // Format: YY0001, YY0002, etc.
  }

  @override
  Future<void> addMember(Member member, {Map<String, dynamic>? audit}) =>
      _atomic((txn) async {
        // BE-08: a duplicate card id (`members.member_id` is UNIQUE) used to
        // surface as a raw ConstraintError -> 500. Reject it as a typed
        // conflict (409), consistent with the updateMember rename guard.
        final clash = await txn.rawQuery(
          'SELECT COUNT(*) FROM members WHERE member_id = ?',
          [member.memberId],
        );
        if (((clash.first.values.first as int?) ?? 0) > 0) {
          throw MemberIdConflictException(
            'Card id ${member.memberId} is already assigned to a member.',
          );
        }
        // row_version is server-owned (starts at the column DEFAULT 0), never
        // taken from the inbound row -- mirrors library_items.addItem.
        final values = member.toMap()..remove('row_version');
        await txn.insert('members', values);
        await _writeAudit(txn, audit);
      });

  @override
  Future<void> updateMember(
    Member member, {
    Map<String, dynamic>? audit,
    int? expectedVersion,
  }) => _atomic((txn) async {
    final current = await txn.query(
      'members',
      columns: ['member_id', 'row_version'],
      where: 'id = ?',
      whereArgs: [member.id],
      limit: 1,
    );
    final oldMemberId = current.isEmpty
        ? null
        : current.first['member_id'] as String?;
    final renamed = oldMemberId != null && oldMemberId != member.memberId;
    if (renamed) {
      // DB-01: reject a rename onto another member's card id before it can
      // collide on the UNIQUE index (which would otherwise surface as a raw
      // 500 and could blur two members' loan histories).
      final clash = await txn.rawQuery(
        'SELECT COUNT(*) FROM members WHERE member_id = ? AND id <> ?',
        [member.memberId, member.id],
      );
      if (((clash.first.values.first as int?) ?? 0) > 0) {
        throw MemberIdConflictException(
          'Card id ${member.memberId} is already assigned to another member.',
        );
      }
    }
    // The primary key (`id`) and the concurrency token (`row_version`) are
    // both server-owned and must NOT be part of the SET clause: `id` selects
    // the row via the WHERE, and a null `id` in the map would otherwise
    // overwrite the PK with NULL and relocate the row. `row_version` is
    // advanced explicitly below.
    final values = member.toMap()
      ..remove('id')
      ..remove('row_version');
    final stored = current.isEmpty
        ? null
        : ((current.first['row_version'] as num?)?.toInt() ?? 0);
    if (expectedVersion != null) {
      // TX-06: guard the write on the version the caller read. A 0-row
      // result means the row changed (or vanished) since then -> the
      // lost-update is refused and NOTHING (data, rename cascade, audit,
      // version) commits.
      final r = await txn.update(
        'members',
        {...values, 'row_version': expectedVersion + 1},
        where: 'id = ? AND row_version = ?',
        whereArgs: [member.id, expectedVersion],
      );
      if (r == 0) {
        throw ConcurrentUpdateConflictException(
          current.isEmpty
              ? 'Member ${member.memberId} no longer exists.'
              : 'Member ${member.memberId} was modified by another client '
                    '(now version $stored, expected $expectedVersion).',
        );
      }
    } else {
      // No expected version -> unconditional (legacy / host UI) write, but
      // the stored token still advances so any future optimistic check is
      // meaningful (strictly monotonic from the just-read stored value).
      await txn.update(
        'members',
        {...values, 'row_version': (stored ?? 0) + 1},
        where: 'id = ?',
        whereArgs: [member.id],
      );
    }
    if (renamed) {
      // `member_id` is the join key loans carry; cascade it so a rename does
      // not orphan their history (which would also blind deleteMember's
      // active-loan guard, since it looks up loans by the NEW id). Runs only
      // after the guarded write above succeeded, so a refused conflict never
      // half-applies the cascade.
      await txn.rawUpdate(
        'UPDATE loans SET member_id = ? WHERE member_id = ?',
        [member.memberId, oldMemberId],
      );
    }
    await _writeAudit(txn, audit);
  });

  @override
  Future<void> deleteMember(
    String memberId, {
    Map<String, dynamic>? audit,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      // BL-04: a member with items still out cannot be deleted (would orphan
      // their active loans). Returned-loan history may remain untouched.
      final rows = await txn.rawQuery(
        'SELECT COUNT(*) FROM loans WHERE member_id = ? AND status = ?',
        [memberId, LoanStatus.active.storage],
      );
      final activeLoans = (rows.first.values.first as int?) ?? 0;
      if (activeLoans > 0) {
        throw ActiveLoanConflictException(
          'Cannot delete member $memberId: they have $activeLoans active loan(s).',
        );
      }
      await txn.delete(
        'members',
        where: 'member_id = ?',
        whereArgs: [memberId],
      );
      await _writeAudit(txn, audit);
      await _touchVersion(txn);
    });
  }

  // Loans
  @override
  Future<List<Loan>> getLoans({bool activeOnly = false}) async {
    final db = await database;
    String? whereClause;
    List<dynamic>? whereArgs;

    if (activeOnly) {
      whereClause = 'status = ?';
      whereArgs = [LoanStatus.active.storage];
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'loans',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'loan_date DESC',
    );
    return List.generate(maps.length, (i) => Loan.fromMap(maps[i]));
  }

  @override
  Future<void> addLoan(Loan loan, {Map<String, dynamic>? audit}) async {
    final db = await database; // Ensure DB is initialized
    await db.transaction((txn) async {
      final itemRows = await txn.query(
        'library_items',
        columns: ['status'],
        where: 'code = ?',
        whereArgs: [loan.itemCode],
        limit: 1,
      );
      if (itemRows.isEmpty) {
        throw Exception('Unknown item: ${loan.itemCode}');
      }

      final copyRows = await txn.query(
        'item_copies',
        where: 'item_code = ?',
        whereArgs: [loan.itemCode],
        orderBy: 'id',
      );
      final copies = copyRows.map(ItemCopy.fromMap).toList();

      if (copies.isEmpty) {
        // Legacy per-title path: the item has no physical copies (created
        // before the copy model, or not yet backfilled). Preserve the original
        // one-active-loan-per-title semantics so nothing regresses, but claim
        // the title with a compare-and-swap on its status so a concurrent
        // checkout of the same row cannot double-book it (BL-01 / TX-02).
        final active = await txn.query(
          'loans',
          columns: ['id'],
          where: 'item_code = ? AND status = ?',
          whereArgs: [loan.itemCode, LoanStatus.active.storage],
          limit: 1,
        );
        if (active.isNotEmpty) {
          throw Exception('This item already has an active loan.');
        }
        // Phase 10.3 priority rule: a legacy title (one loan slot) with ANY
        // live hold belongs to its queue -- a walk-up borrower is refused and
        // sent to the line rather than cutting in front of the holders.
        if (await _hasLiveHoldByOther(txn, loan.itemCode, loan.memberId)) {
          throw StateError(
            'This title is reserved for a member in line. Place a hold instead.',
          );
        }
        final claimed = await txn.rawUpdate(
          // TX-06: the legacy claim mutates the row, so it advances
          // `row_version` too — every library_items write is now detectable by
          // an optimistic caller. The CAS predicate is unchanged.
          'UPDATE library_items SET status = ?, row_version = row_version + 1 WHERE code = ? AND status = ?',
          [
            CopyState.onLoan.storage,
            loan.itemCode,
            CopyState.available.storage,
          ],
        );
        if (claimed == 0) {
          throw Exception(
            'Item is not available (status: ${itemRows.first['status']}).',
          );
        }
        await txn.insert('loans', loan.toMap());
        return;
      }

      // Copy-level path (DB-02 + BL-01): lend ONE specific physical copy using
      // a compare-and-swap (`WHERE state = 'Disponible'`). If a concurrent
      // transaction already claimed the copy the update affects 0 rows and we
      // refuse the loan — so the borrow invariant holds even under interleaved
      // requests, independent of transaction serialization.
      int? claimedId;
      if (loan.copyId != null) {
        final idx = copies.indexWhere((c) => c.id == loan.copyId);
        if (idx == -1) {
          throw Exception('Unknown copy: ${loan.copyId}');
        }
        if (!copies[idx].isAvailable && !copies[idx].isReserved) {
          throw Exception('Copy ${loan.copyId} is not available.');
        }
        // A copy claimed for a promoted hold belongs to its holder ONLY
        // (Phase 10.3) -- a walk-up checkout can never cut an in-line member.
        if (copies[idx].isReserved &&
            await _isHeldForOther(txn, loan.copyId!, loan.memberId)) {
          throw StateError(
            'Copy ${loan.copyId} is reserved for another member.',
          );
        }
        // TX-02 CAS on the state actually read inside this transaction: a
        // racing claim sees 0 rows instead of double-booking the copy.
        final changed = await txn.rawUpdate(
          'UPDATE item_copies SET state = ? WHERE id = ? AND state = ?',
          [CopyState.onLoan.storage, loan.copyId, copies[idx].state],
        );
        if (changed == 0) {
          throw Exception('Copy ${loan.copyId} is not available.');
        }
        claimedId = loan.copyId;
      } else {
        // Auto-pick: try each available copy in order until a CAS claim wins.
        // Copies claimed for ANOTHER member's promoted hold are excluded --
        // they are physically on the shelf but spoken for (Phase 10.3).
        final availableIds = (await txn.rawQuery(
          'SELECT id FROM item_copies WHERE item_code = ? AND state = ? '
          'AND id NOT IN (${_reservedForOtherSql()}) '
          'ORDER BY id',
          [
            loan.itemCode,
            CopyState.available.storage,
            ReservationStatus.available.storage,
            loan.memberId,
          ],
        )).map((r) => r['id'] as int).toList();
        for (final id in availableIds) {
          final changed = await txn.rawUpdate(
            'UPDATE item_copies SET state = ? WHERE id = ? AND state = ?',
            [CopyState.onLoan.storage, id, CopyState.available.storage],
          );
          if (changed == 1) {
            claimedId = id;
            break;
          }
        }
        if (claimedId == null) {
          throw Exception('No copies available for ${loan.itemCode}.');
        }
      }

      await txn.insert('loans', loan.copyWith(copyId: claimedId).toMap());
      // Phase 10.3: a successful borrow settles the borrower's own promoted
      // hold (FULFILLED) so the queue never keeps a dead place for a copy
      // its holder just took out.
      await _fulfillHoldForBorrow(txn, loan, claimedId);
      // Title status is *derived* from the committed copy states, so a
      // multi-copy title stays `Disponible` while any copy remains and only
      // flips `Emprunté` when the last one goes out.
      await _recalcItemStatus(txn, loan.itemCode);
      await _writeAudit(txn, audit);
      await _touchVersion(txn);
    });
    // Borrowing can change what the queue sees (a fulfilled hold, a title
    // that lost its last free copy): run the expire/promote step after the
    // borrow commits, in its own transaction. Failures here never undo the
    // loan -- the next touchpoint retries the sweep.
    await _promoteStep(loan.itemCode);
  }

  @override
  Future<void> updateLoan(Loan loan, {Map<String, dynamic>? audit}) async {
    final db = await database;
    var isReturn = false;
    String? itemCode;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'loans',
        columns: ['status', 'item_code', 'copy_id'],
        where: 'id = ?',
        whereArgs: [loan.id],
        limit: 1,
      );
      if (existing.isEmpty) {
        throw Exception('Loan not found: ${loan.id}');
      }
      final currentStatus = existing.first['status'] as String?;
      final code =
          (loan.itemCode.isNotEmpty
                  ? loan.itemCode
                  : existing.first['item_code'])
              as String;
      itemCode = code;
      final storedCopyId = existing.first['copy_id'] as int?;

      // Transition guard (BL-02): a returned loan is terminal — it can never be
      // renewed/reactivated. Enforced here so no client can bypass the rule.
      if (currentStatus == LoanStatus.returned.storage &&
          loan.status == LoanStatus.active.storage) {
        throw Exception('Cannot renew or reactivate a returned loan.');
      }

      await txn.update(
        'loans',
        loan.toMap(),
        where: 'id = ?',
        whereArgs: [loan.id],
      );

      // Restore availability only on a real active -> returned transition.
      isReturn =
          loan.status == LoanStatus.returned.storage &&
          currentStatus != LoanStatus.returned.storage;
      if (isReturn) {
        if (storedCopyId != null) {
          // Free the *specific* copy (only a real on-loan copy is released) and
          // re-derive the title status from the committed copy states, so a
          // multi-copy title stays `Emprunté` while others are still out.
          await txn.rawUpdate(
            'UPDATE item_copies SET state = ? WHERE id = ? AND state = ?',
            [
              CopyState.available.storage,
              storedCopyId,
              CopyState.onLoan.storage,
            ],
          );
          await _recalcItemStatus(txn, code);
        } else {
          // Legacy per-title loan (no copy): restore the whole title.
          // TX-06: advances `row_version` like every other item write.
          await txn.rawUpdate(
            'UPDATE library_items SET status = ?, row_version = row_version + 1 WHERE code = ?',
            [CopyState.available.storage, code],
          );
        }
      }
      // Phase 10.2: an overdue return accrues a fine in THIS SAME transaction,
      // so a committed return and its monetary consequence are atomic (TX-01):
      // a fine is never assessed for a return that did not commit, and a failed
      // fine write rolls the return back. No-op when fines are disabled or the
      // loan was returned on time.
      if (isReturn) {
        await _maybeAccrueFine(txn, loan);
      }
      await _writeAudit(txn, audit);
      await _touchVersion(txn);
    });
    if (isReturn) {
      // Phase 10.3: a returned copy is what the queue has been waiting for.
      // Expire lapsed pickup windows and promote the next holders, atomically
      // per item, in a step AFTER the return transaction (the return itself is
      // never undone by a queue hiccup -- the next touchpoint retries).
      await _promoteStep(itemCode);
    }
  }

  @override
  Future<Loan?> findActiveLoanByScan(String scanned) async {
    final db = await database;
    final value = scanned.trim();
    if (value.isEmpty) return null;
    final active = LoanStatus.active.storage;

    // 1. Per-copy barcode (most specific): a copy tag identifies its exact loan.
    final copyRows = await db.query(
      'item_copies',
      columns: ['id'],
      where: 'barcode = ?',
      whereArgs: [value],
      limit: 1,
    );
    if (copyRows.isNotEmpty) {
      final copyId = copyRows.first['id'] as int;
      final byCopy = await db.query(
        'loans',
        where: 'copy_id = ? AND status = ?',
        whereArgs: [copyId, active],
        limit: 1,
      );
      if (byCopy.isNotEmpty) return Loan.fromMap(byCopy.first);
    }

    // 2. Resolve the scanned value to an item code: a title (ISBN) barcode
    //    takes precedence, otherwise the value is already the item code.
    var itemCode = value;
    final byTitleBarcode = await db.query(
      'library_items',
      columns: ['code'],
      where: 'barcode = ?',
      whereArgs: [value],
      limit: 1,
    );
    if (byTitleBarcode.isNotEmpty) {
      itemCode = byTitleBarcode.first['code'] as String;
    }

    // 3. Any active loan for that title (oldest first when several copies out).
    final loans = await db.query(
      'loans',
      where: 'item_code = ? AND status = ?',
      whereArgs: [itemCode, active],
      orderBy: 'loan_date ASC',
      limit: 1,
    );
    return loans.isEmpty ? null : Loan.fromMap(loans.first);
  }

  // ==========================================================================
  // Fines & payments (Phase 10.2). Server-authoritative money rules: accrual is
  // folded into the return transaction (see updateLoan -> _maybeAccrueFine) and
  // resolution (pay/waive) is a guarded, audited, compare-and-swap write so a
  // fine can never be double-collected, host or client alike.
  // ==========================================================================

  static const String _kFineRate = 'fine_rate_per_day';
  static const String _kFineCurrency = 'fine_currency';

  // ==========================================================================
  // Reservations / hold queue (Phase 10.3). The server owns the queue: a
  // member only ever QUEUES; a physical copy is claimed solely at PROMOTION,
  // through the same copy-level CAS every other transition uses. Promoted
  // copies are `Réservé` — on the shelf but spoken for — and a walk-up
  // checkout of one is refused. Expiry releases the copy to the next holder.
  // ==========================================================================

  static const String _kHoldPickupDays = 'hold_pickup_days';
  static const String _kHoldQueueMax = 'hold_queue_max_per_item';

  /// SQL set (TWO `?`: the promoted status, then the borrower) of copy ids
  /// claimed by a LIVE promoted hold belonging to a DIFFERENT member. Used in
  /// `id NOT IN (...)` so the meaning of "reserved for someone else" is
  /// defined in exactly one place.
  static String _reservedForOtherSql() =>
      'SELECT copy_id FROM reservations WHERE status = ? AND copy_id IS NOT '
      'NULL AND member_id <> ?';

  /// Whether [memberId] may borrow [copyId]: yes unless a live promoted hold
  /// claims it for somebody else. Evaluated INSIDE the caller's transaction.
  Future<bool> _isHeldForOther(
    Transaction txn,
    int copyId,
    String memberId,
  ) async {
    final rows = await txn.rawQuery(
      'SELECT 1 FROM reservations WHERE status = ? AND copy_id = ? '
      'AND member_id <> ? LIMIT 1',
      [ReservationStatus.available.storage, copyId, memberId],
    );
    return rows.isNotEmpty;
  }

  /// Whether some OTHER member has any live hold (queued or promoted) on the
  /// title — the legacy per-title path has no copies to mark, so the queue
  /// itself is the priority claim on the single loan slot.
  Future<bool> _hasLiveHoldByOther(
    Transaction txn,
    String itemCode,
    String memberId,
  ) async {
    final rows = await txn.rawQuery(
      'SELECT 1 FROM reservations WHERE item_code = ? AND member_id <> ? '
      'AND status IN (?, ?) LIMIT 1',
      [
        itemCode,
        memberId,
        ReservationStatus.queued.storage,
        ReservationStatus.available.storage,
      ],
    );
    return rows.isNotEmpty;
  }

  /// A successful borrow settles the borrower's own promoted hold for the
  /// title (the claimed copy first, else FIFO) inside the borrow txn.
  Future<void> _fulfillHoldForBorrow(
    Transaction txn,
    Loan loan,
    int? claimedId,
  ) async {
    final byCopy = claimedId != null && loan.copyId != null;
    final hit = await txn.rawQuery(
      'SELECT id FROM reservations WHERE item_code = ? AND member_id = ? '
      'AND status = ? '
      "ORDER BY ${byCopy ? 'CASE WHEN copy_id = ? THEN 0 ELSE 1 END, ' : ''}"
      'created_at ASC, id ASC LIMIT 1',
      <Object?>[
        loan.itemCode,
        loan.memberId,
        ReservationStatus.available.storage,
        if (byCopy) loan.copyId,
      ],
    );
    if (hit.isEmpty) return;
    await txn.update(
      'reservations',
      {
        'status': ReservationStatus.fulfilled.storage,
        'ended_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND status = ?',
      whereArgs: [hit.first['id'], ReservationStatus.available.storage],
    );
  }

  /// Reads the fine policy from the `metadata` key/value table. Absent or
  /// malformed values degrade to the safe DISABLED default (rate 0), so a
  /// half-written setting can never accrue a surprising charge.
  Future<FineSettings> _readFineSettings(DatabaseExecutor db) async {
    final rows = await db.query(
      'metadata',
      columns: ['key', 'value'],
      where: 'key IN (?, ?)',
      whereArgs: [_kFineRate, _kFineCurrency],
    );
    String? value(String key) {
      for (final r in rows) {
        if (r['key'] == key) return r['value'] as String?;
      }
      return null;
    }

    var rate = double.tryParse(value(_kFineRate) ?? '') ?? 0.0;
    if (!rate.isFinite || rate < 0) rate = 0.0;
    final currency = value(_kFineCurrency) ?? FineSettings.defaultCurrency;
    return FineSettings(ratePerDay: rate, currency: currency);
  }

  @override
  Future<FineSettings> getFineSettings() async =>
      _readFineSettings(await database);

  @override
  Future<void> setFineSettings(
    FineSettings settings, {
    Map<String, dynamic>? audit,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      var rate = settings.ratePerDay;
      if (!rate.isFinite || rate < 0) rate = 0.0;
      await txn.insert('metadata', {
        'key': _kFineRate,
        'value': rate.toString(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('metadata', {
        'key': _kFineCurrency,
        'value': settings.currency,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _writeAudit(txn, audit);
      await _touchVersion(txn);
    });
  }

  @override
  Future<List<Fine>> getFines({String? memberId, FineStatus? status}) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    if (memberId != null) {
      where.add('member_id = ?');
      args.add(memberId);
    }
    if (status != null) {
      where.add('status = ?');
      args.add(status.storage);
    }
    final rows = await db.query(
      'fines',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(Fine.fromMap).toList();
  }

  @override
  Future<double> outstandingBalance(String memberId) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM fines '
      'WHERE member_id = ? AND status = ?',
      [memberId, FineStatus.pending.storage],
    );
    return (rows.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  @override
  Future<void> payFine(
    int id, {
    String? operatorName,
    Map<String, dynamic>? audit,
  }) => _resolveFine(
    id,
    FineStatus.paid,
    operatorName: operatorName,
    audit: audit,
  );

  @override
  Future<void> waiveFine(
    int id, {
    String? operatorName,
    Map<String, dynamic>? audit,
  }) => _resolveFine(
    id,
    FineStatus.waived,
    operatorName: operatorName,
    audit: audit,
  );

  Future<void> _resolveFine(
    int id,
    FineStatus target, {
    String? operatorName,
    Map<String, dynamic>? audit,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final changed = await txn.update(
        'fines',
        {
          'status': target.storage,
          'resolved_at': DateTime.now().toIso8601String(),
          'resolved_by': operatorName,
        },
        // Compare-and-swap on the PENDING state: exactly one concurrent settle
        // can win; the loser sees 0 rows and we refuse it rather than silently
        // double-recording a payment.
        where: 'id = ? AND status = ?',
        whereArgs: [id, FineStatus.pending.storage],
      );
      if (changed == 0) {
        final exists = await txn.query(
          'fines',
          columns: ['status'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        throw StateError(
          exists.isEmpty
              ? 'No such fine #$id.'
              : 'Fine #$id is already resolved.',
        );
      }
      await _writeAudit(txn, audit);
      await _touchVersion(txn);
    });
  }

  /// Computes + persists the overdue fine for a just-returned loan, INSIDE the
  /// return transaction. No-ops when fines are disabled or the loan came back
  /// on time, so enabling the feature never retroactively charges anyone.
  Future<void> _maybeAccrueFine(Transaction txn, Loan returned) async {
    final returnDate = returned.returnDate;
    if (returnDate == null) return; // not an actual return
    final settings = await _readFineSettings(txn);
    if (!settings.enabled) return;
    final days = FinePolicy.overdueDays(returned.dueDate, returnDate);
    final amount = FinePolicy.amountFor(days, settings.ratePerDay);
    if (amount <= 0) return;
    await txn.insert('fines', {
      'loan_id': returned.id,
      'member_id': returned.memberId,
      'amount': amount,
      'status': FineStatus.pending.storage,
      'reason': FinePolicy.reasonFor(days),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // ==========================================================================
  // Reservations / hold queue -- PUBLIC API (Phase 10.3). Reads are pure;
  // every mutation runs inside a transaction and re-derives copy/title state
  // through the existing CAS paths, so the queue can never disagree with the
  // physical ledger.
  // ==========================================================================

  /// Reads the hold policy from `metadata`; absent/malformed values degrade
  /// to [HoldSettings.defaults] (mirrors the fine-rate degradation).
  Future<HoldSettings> _readHoldSettings(DatabaseExecutor db) async {
    final rows = await db.query(
      'metadata',
      columns: ['key', 'value'],
      where: 'key IN (?, ?)',
      whereArgs: [_kHoldPickupDays, _kHoldQueueMax],
    );
    String? value(String key) {
      for (final r in rows) {
        if (r['key'] == key) return r['value'] as String?;
      }
      return null;
    }

    return HoldSettings.fromMap({
      'pickup_days': int.tryParse(value(_kHoldPickupDays) ?? ''),
      'queue_max_per_item': int.tryParse(value(_kHoldQueueMax) ?? ''),
    });
  }

  @override
  Future<HoldSettings> getHoldSettings() async =>
      _readHoldSettings(await database);

  @override
  Future<void> setHoldSettings(
    HoldSettings settings, {
    Map<String, dynamic>? audit,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      // Persist the SANITISED values (fromMap degradation), so a caller can
      // never store a 0-day pickup window or an unbounded queue.
      final safe = HoldSettings.fromMap({
        'pickup_days': settings.pickupDays,
        'queue_max_per_item': settings.queueMaxPerItem,
      });
      await txn.insert('metadata', {
        'key': _kHoldPickupDays,
        'value': safe.pickupDays.toString(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('metadata', {
        'key': _kHoldQueueMax,
        'value': safe.queueMaxPerItem.toString(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _writeAudit(txn, audit);
      await _touchVersion(txn);
    });
  }

  @override
  Future<Reservation> placeReservation(
    String itemCode,
    String memberId, {
    Map<String, dynamic>? audit,
  }) async {
    final code = itemCode.trim();
    final member = memberId.trim();
    if (code.isEmpty || member.isEmpty) {
      throw StateError('Item code and member id are required.');
    }
    final db = await database;
    final id = await db.transaction((txn) async {
      final item = await txn.query(
        'library_items',
        columns: ['code'],
        where: 'code = ?',
        whereArgs: [code],
        limit: 1,
      );
      if (item.isEmpty) {
        throw StateError('Unknown item: $code.');
      }
      final memb = await txn.query(
        'members',
        columns: ['id'],
        where: 'member_id = ?',
        whereArgs: [member],
        limit: 1,
      );
      if (memb.isEmpty) {
        throw StateError('Unknown member: $member.');
      }
      final live = await txn.query(
        'reservations',
        where: 'item_code = ? AND status IN (?, ?)',
        whereArgs: [
          code,
          ReservationStatus.queued.storage,
          ReservationStatus.available.storage,
        ],
      );
      final settings = await _readHoldSettings(txn);
      final mine = live.where((r) => r['member_id'] == member);
      final refusal = HoldPolicy.refusalFor(
        mine.isNotEmpty ? Reservation.fromMap(mine.first) : null,
        live.length,
        settings,
      );
      if (refusal != null) throw StateError(refusal);
      return await txn.insert('reservations', {
        'item_code': code,
        'member_id': member,
        'status': ReservationStatus.queued.storage,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
    // The immediate-promotion step carries the audit line, so "A joined the
    // queue (and got the free copy)" commits as ONE unit.
    await _promoteStep(code, audit);
    final rows = await db.query(
      'reservations',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return Reservation.fromMap(rows.first);
  }

  @override
  Future<void> cancelReservation(int id, {Map<String, dynamic>? audit}) async {
    final db = await database;
    String? itemCode;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'reservations',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('No such hold #$id.');
      final r = Reservation.fromMap(rows.first);
      if (!r.isLive) {
        throw StateError('Hold #$id is already ${r.status.storage}.');
      }
      final changed = await txn.update(
        'reservations',
        {
          'status': ReservationStatus.cancelled.storage,
          'ended_at': DateTime.now().toIso8601String(),
        },
        // CAS: only a LIVE hold cancels -- a concurrent settle/expiry wins
        // instead of being silently overwritten.
        where: 'id = ? AND status IN (?, ?)',
        whereArgs: [
          id,
          ReservationStatus.queued.storage,
          ReservationStatus.available.storage,
        ],
      );
      if (changed == 0) {
        throw StateError('Hold #$id changed concurrently; retry.');
      }
      if (r.status == ReservationStatus.available && r.copyId != null) {
        // Release the claimed copy (only if it is STILL the reservation's
        // `Réservé` copy) and re-derive the title rollup.
        await txn.rawUpdate(
          'UPDATE item_copies SET state = ? WHERE id = ? AND state = ?',
          [CopyState.available.storage, r.copyId, CopyState.reserved.storage],
        );
        await _recalcItemStatus(txn, r.itemCode);
      }
      itemCode = r.itemCode;
      await _writeAudit(txn, audit);
      await _touchVersion(txn);
    });
    // The freed copy (or the shortened line) may unblock someone else.
    await _promoteStep(itemCode!);
  }

  /// Pass 6: swap [id]'s position with its immediate queued neighbour in
  /// the same item's line. `up` moves toward the front, `down` toward the
  /// back; a boundary row is a no-op. Only `queued` holds reorder --
  /// promoted (`available`) rows already have a physical copy claimed and
  /// their shelf order is server-owned. Everything happens inside one
  /// transaction so a concurrent return / cancel cannot see a half-swap.
  @override
  Future<void> moveReservation(
    int id, {
    required bool up,
    Map<String, dynamic>? audit,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final mine = await txn.query(
        'reservations',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (mine.isEmpty) throw StateError('No such hold #$id.');
      final me = Reservation.fromMap(mine.first);
      if (me.status != ReservationStatus.queued) {
        throw StateError(
          'Only queued holds can be reordered (this hold is '
          '${me.status.storage}).',
        );
      }
      // The item's queued line, in the CURRENT display order. Uses the
      // same `COALESCE(rank, id)` expression the read path uses so the
      // operator and this write agree on what "position N" means. The
      // moved row is always included; if a concurrent transaction just
      // added a row we still swap with the position that was visible at
      // click time, which is the semantic the UI promises.
      final line = await txn.rawQuery(
        'SELECT id, rank FROM reservations '
        'WHERE item_code = ? AND status = ? '
        'ORDER BY COALESCE(rank, id) ASC, id ASC',
        [me.itemCode, ReservationStatus.queued.storage],
      );
      final index = line.indexWhere((r) => (r['id'] as int) == id);
      if (index < 0) {
        // Should be unreachable -- we just read the row and filtered on
        // its item + status. A concurrent cancel landing between the two
        // reads is the only realistic cause; treat it as a no-op rather
        // than throwing (the next refresh will show the truth).
        return;
      }
      final neighbour = up ? index - 1 : index + 1;
      if (neighbour < 0 || neighbour >= line.length) {
        // Boundary row -- already at the requested extreme. No-op, no
        // audit row: recording a non-change would pollute the trail.
        return;
      }
      final meEff = (mine.first['rank'] as int?) ?? id;
      final nbrRow = line[neighbour];
      final nbrId = nbrRow['id'] as int;
      final nbrEff = (nbrRow['rank'] as int?) ?? nbrId;
      // Swap the two effective values. This is idempotent and does not
      // disturb any other row: everyone else keeps whatever effective
      // rank they already had, and the two involved rows now invert.
      await txn.update(
        'reservations',
        {'rank': nbrEff},
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.update(
        'reservations',
        {'rank': meEff},
        where: 'id = ?',
        whereArgs: [nbrId],
      );
      await _writeAudit(txn, audit);
      await _touchVersion(txn);
    });
  }

  @override
  Future<List<Reservation>> getReservations({
    String? itemCode,
    String? memberId,
    ReservationStatus? status,
    bool liveOnly = false,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    if (itemCode != null) {
      where.add('item_code = ?');
      args.add(itemCode);
    }
    if (memberId != null) {
      where.add('member_id = ?');
      args.add(memberId);
    }
    if (status != null) {
      where.add('status = ?');
      args.add(status.storage);
    } else if (liveOnly) {
      where.add('status IN (?, ?)');
      args
        ..add(ReservationStatus.queued.storage)
        ..add(ReservationStatus.available.storage);
    }
    final rows = await db.query(
      'reservations',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      // Queue order, mirroring HoldPolicy.queueOrder: promoted holders are
      // "at the counter", then the line. Pass 6: within each status bucket
      // the operator may have set an explicit `rank` via the reorder UI;
      // rows with NULL rank fall back to their id, which reproduces the
      // pre-Pass-6 FIFO (`created_at` and `id` are correlated on an
      // AUTOINCREMENT table, so `id ASC` is the same ordering on every
      // existing row).
      orderBy:
          "CASE status WHEN '${ReservationStatus.available.storage}' THEN 0 "
          "WHEN '${ReservationStatus.queued.storage}' THEN 1 ELSE 2 END, "
          'COALESCE(rank, id) ASC, id ASC',
    );
    return rows.map(Reservation.fromMap).toList();
  }

  @override
  Future<List<Reservation>> readyForPickup() async {
    final db = await database;
    // A lapsed hold is NOT ready even seconds before a sweep retires it: the
    // deadline is part of the answer, not just the status column.
    final rows = await db.query(
      'reservations',
      where:
          'status = ? AND available_until IS NOT NULL AND available_until > ?',
      whereArgs: [
        ReservationStatus.available.storage,
        DateTime.now().toIso8601String(),
      ],
      orderBy: 'available_until ASC, id ASC',
    );
    return rows.map(Reservation.fromMap).toList();
  }

  /// Expire lapsed pickup windows and hand free copies to the line, for one
  /// title (null = every title). Runs in its OWN transaction after the
  /// triggering write committed: a queue hiccup must never undo a return or
  /// a borrow, and every later touchpoint re-runs the sweep.
  Future<void> _promoteStep([
    String? itemCode,
    Map<String, dynamic>? audit,
  ]) async {
    final db = await database;
    await db.transaction((txn) async {
      await _sweepExpiredLocked(txn, itemCode);
      final codes = itemCode != null
          ? [itemCode]
          : (await txn.query(
              'reservations',
              columns: ['item_code'],
              distinct: true,
              where: 'status IN (?, ?)',
              whereArgs: [
                ReservationStatus.queued.storage,
                ReservationStatus.available.storage,
              ],
            )).map((r) => r['item_code'] as String).toList();
      for (final code in codes) {
        await _promoteLocked(txn, code);
      }
      await _writeAudit(txn, audit);
      await _touchVersion(txn);
    });
  }

  /// Expire lapsed promoted holds (within [itemCode], or every title when
  /// null): the row goes terminal and its `Réservé` copy returns to the
  /// shelf. The copy release is itself a CAS on `Réservé`, so a copy that
  /// meanwhile went out or was cancelled is left untouched.
  Future<void> _sweepExpiredLocked(Transaction txn, String? itemCode) async {
    final now = DateTime.now().toIso8601String();
    final rows = await txn.query(
      'reservations',
      where:
          'status = ? AND available_until IS NOT NULL '
          'AND available_until <= ?',
      whereArgs: [ReservationStatus.available.storage, now],
    );
    final touchedItems = <String>{};
    for (final row in rows) {
      final r = Reservation.fromMap(row);
      if (itemCode != null && r.itemCode != itemCode) continue;
      final changed = await txn.update(
        'reservations',
        {'status': ReservationStatus.expired.storage, 'ended_at': now},
        where: 'id = ? AND status = ?',
        whereArgs: [r.id, ReservationStatus.available.storage],
      );
      if (changed == 0) continue; // a concurrent settle won; leave it alone
      if (r.copyId != null) {
        final freed = await txn.rawUpdate(
          'UPDATE item_copies SET state = ? WHERE id = ? AND state = ?',
          [CopyState.available.storage, r.copyId, CopyState.reserved.storage],
        );
        if (freed > 0) touchedItems.add(r.itemCode);
      }
    }
    for (final code in touchedItems) {
      await _recalcItemStatus(txn, code);
    }
  }

  /// Hand every genuinely free copy of [code] to the next in line, FIFO, or
  /// -- for a legacy no-copy title -- promote ONLY the front holder with
  /// `copy_id` NULL (the legacy borrow path then lets that holder claim the
  /// single slot and refuses every walk-up). Copies under ANY live promoted
  /// hold are excluded up front; the copy claim itself is the same
  /// `WHERE state = 'Disponible'` CAS every other transition uses, and a
  /// lost CAS simply moves to the next free copy.
  Future<void> _promoteLocked(Transaction txn, String code) async {
    final settings = await _readHoldSettings(txn);
    final freeRows = await txn.rawQuery(
      'SELECT id FROM item_copies WHERE item_code = ? AND state = ? '
      'AND id NOT IN (SELECT copy_id FROM reservations WHERE status = ? '
      'AND copy_id IS NOT NULL) ORDER BY id',
      [code, CopyState.available.storage, ReservationStatus.available.storage],
    );
    final freeIds = freeRows.map((r) => r['id'] as int).toList();
    final totalCopies = await txn.rawQuery(
      'SELECT COUNT(*) FROM item_copies WHERE item_code = ?',
      [code],
    );
    final copyMode = ((totalCopies.first.values.first as int?) ?? 0) > 0;

    final queue = await txn.query(
      'reservations',
      where: 'item_code = ? AND status = ?',
      whereArgs: [code, ReservationStatus.queued.storage],
      orderBy: 'created_at ASC, id ASC',
    );

    Future<void> promote(int holdId, {int? copyId}) async {
      final now = DateTime.now();
      await txn.update(
        'reservations',
        {
          'status': ReservationStatus.available.storage,
          'copy_id': copyId,
          'available_at': now.toIso8601String(),
          'available_until': HoldPolicy.deadlineFor(
            now,
            settings,
          ).toIso8601String(),
        },
        // CAS: only a still-queued hold is promoted -- a concurrent cancel
        // or settle wins and this row is simply left alone.
        where: 'id = ? AND status = ?',
        whereArgs: [holdId, ReservationStatus.queued.storage],
      );
    }

    if (!copyMode) {
      if (queue.isNotEmpty) await promote(queue.first['id'] as int);
      return;
    }
    var i = 0;
    for (final row in queue) {
      if (i >= freeIds.length) break; // the line now outruns the shelf
      final copyId = freeIds[i];
      final claimed = await txn.rawUpdate(
        'UPDATE item_copies SET state = ? WHERE id = ? AND state = ?',
        [CopyState.reserved.storage, copyId, CopyState.available.storage],
      );
      if (claimed == 0) {
        i++;
        continue; // someone else took this copy; try the NEXT one for them
      }
      await promote(row['id'] as int, copyId: copyId);
      i++;
    }
    await _recalcItemStatus(txn, code);
  }

  // ==========================================================================
  // Reports / management summaries (Phase 10.4). READ-ONLY server aggregates:
  // every figure is computed here so a LAN client and the host operator always
  // see identical numbers. Date windows are resolved by the shared
  // [ReportQuery] rules and compared on `substr(<date>, 1, 10)` (calendar-day
  // slices of the stored fixed-precision ISO timestamps), which sidesteps the
  // DB-07 time-of-day/DST ambiguity entirely. Rows arrive fully stringified so
  // no client can mis-format money or counts.
  // ==========================================================================

  @override
  Future<Report> generateReport(
    ReportKind kind, {
    String? from,
    String? to,
  }) async {
    switch (kind) {
      case ReportKind.circulation:
        return _reportCirculation(from, to);
      case ReportKind.overdue:
        return _reportOverdue();
      case ReportKind.inventory:
        return _reportInventory();
      case ReportKind.fines:
        return _reportFines(from, to);
      case ReportKind.members:
        return _reportMembers(from, to);
    }
  }

  static String _int(Object? v) => '${(v as num?)?.toInt() ?? 0}';

  static String _money(double v, String currency) =>
      '${v.toStringAsFixed(2)} $currency';

  static String _memberCell(Object? name, Object? id) {
    final n = name?.toString().trim() ?? '';
    return n.isNotEmpty ? n : (id?.toString() ?? '');
  }

  String _dayLabel(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<Report> _reportCirculation(String? from, String? to) async {
    final db = await database;
    final now = DateTime.now();
    final w = ReportQuery.window(
      ReportKind.circulation,
      from: from,
      to: to,
      now: now,
    )!;

    final borrowRows = await db.rawQuery(
      'SELECT substr(loan_date,1,10) AS day, COUNT(*) AS c FROM loans '
      'WHERE loan_date IS NOT NULL AND substr(loan_date,1,10) BETWEEN ? AND ? '
      'GROUP BY day',
      [w.fromDay, w.toDay],
    );
    final returnRows = await db.rawQuery(
      'SELECT substr(return_date,1,10) AS day, COUNT(*) AS c FROM loans '
      'WHERE return_date IS NOT NULL AND status = ? '
      'AND substr(return_date,1,10) BETWEEN ? AND ? GROUP BY day',
      [LoanStatus.returned.storage, w.fromDay, w.toDay],
    );

    final perDay = <String, List<int>>{};
    for (final r in borrowRows) {
      final day = r['day']?.toString();
      if (day == null || day.isEmpty) continue;
      (perDay[day] ??= [0, 0])[0] += (r['c'] as num?)?.toInt() ?? 0;
    }
    for (final r in returnRows) {
      final day = r['day']?.toString();
      if (day == null || day.isEmpty) continue;
      (perDay[day] ??= [0, 0])[1] += (r['c'] as num?)?.toInt() ?? 0;
    }
    final days = perDay.keys.toList()..sort();
    var totalBorrow = 0;
    var totalReturn = 0;
    final rows = <List<String>>[
      for (final day in days) [day, '${perDay[day]![0]}', '${perDay[day]![1]}'],
    ];
    for (final day in days) {
      totalBorrow += perDay[day]![0];
      totalReturn += perDay[day]![1];
    }
    return Report(
      kind: ReportKind.circulation,
      title: 'Circulation',
      generatedAt: now.toIso8601String(),
      from: w.fromDay,
      to: w.toDay,
      columns: const ['Date', 'Borrowed', 'Returned'],
      rows: rows,
      summary: {
        'Borrowed': '$totalBorrow',
        'Returned': '$totalReturn',
        'Days with activity': '${days.length}',
      },
    );
  }

  Future<Report> _reportOverdue() async {
    final db = await database;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayDay = _dayLabel(today);
    final rows0 = await db.rawQuery(
      'SELECT member_name, member_id, item_title, item_code, due_date FROM loans '
      'WHERE status = ? AND due_date IS NOT NULL AND substr(due_date,1,10) < ? '
      'ORDER BY substr(due_date,1,10) ASC',
      [LoanStatus.active.storage, todayDay],
    );
    final rows = <List<String>>[];
    var longest = 0;
    for (final r in rows0) {
      final dueRaw = r['due_date']?.toString();
      final due = dueRaw == null ? null : DateTime.tryParse(dueRaw);
      final daysOverdue = due == null
          ? 0
          : today.difference(DateTime(due.year, due.month, due.day)).inDays;
      if (daysOverdue > longest) longest = daysOverdue;
      rows.add([
        _memberCell(r['member_name'], r['member_id']),
        r['item_title']?.toString() ?? (r['item_code']?.toString() ?? ''),
        dueRaw == null
            ? ''
            : dueRaw.substring(0, dueRaw.length < 10 ? dueRaw.length : 10),
        '$daysOverdue',
      ]);
    }
    return Report(
      kind: ReportKind.overdue,
      title: 'Overdue loans',
      generatedAt: now.toIso8601String(),
      columns: const ['Member', 'Item', 'Due date', 'Days overdue'],
      rows: rows,
      summary: {
        'Overdue loans': '${rows.length}',
        'Longest overdue': '$longest day(s)',
      },
    );
  }

  Future<Report> _reportInventory() async {
    final db = await database;
    final now = DateTime.now();
    final titleRows = await db.rawQuery(
      'SELECT code_type AS t, COUNT(*) AS c FROM library_items GROUP BY code_type',
    );
    final copyRows = await db.rawQuery(
      'SELECT i.code_type AS t, COUNT(*) AS c FROM item_copies c '
      'JOIN library_items i ON i.code = c.item_code GROUP BY i.code_type',
    );
    final perType = <String, List<int>>{};
    var totalTitles = 0;
    var totalCopies = 0;
    for (final r in titleRows) {
      final t = (r['t']?.toString().trim()) ?? '';
      final key = t.isEmpty ? '—' : t;
      final c = (r['c'] as num?)?.toInt() ?? 0;
      (perType[key] ??= [0, 0])[0] += c;
      totalTitles += c;
    }
    for (final r in copyRows) {
      final t = (r['t']?.toString().trim()) ?? '';
      final key = t.isEmpty ? '—' : t;
      final c = (r['c'] as num?)?.toInt() ?? 0;
      (perType[key] ??= [0, 0])[1] += c;
      totalCopies += c;
    }
    final types = perType.keys.toList()..sort();
    final rows = <List<String>>[
      for (final t in types) [t, '${perType[t]![0]}', '${perType[t]![1]}'],
    ];
    return Report(
      kind: ReportKind.inventory,
      title: 'Inventory',
      generatedAt: now.toIso8601String(),
      columns: const ['Type', 'Titles', 'Copies'],
      rows: rows,
      summary: {'Titles': '$totalTitles', 'Physical copies': '$totalCopies'},
    );
  }

  Future<Report> _reportFines(String? from, String? to) async {
    final db = await database;
    final now = DateTime.now();
    final settings = await getFineSettings();
    final cur = settings.currency;
    final w = ReportQuery.window(
      ReportKind.fines,
      from: from,
      to: to,
      now: now,
    )!;

    Future<List<Object?>> agg(String where, List<Object?> args) async {
      final r = await db.rawQuery(
        'SELECT COUNT(*) AS c, COALESCE(SUM(amount),0) AS s FROM fines WHERE $where',
        args,
      );
      final row = r.first;
      return [
        (row['c'] as num?)?.toInt() ?? 0,
        (row['s'] as num?)?.toDouble() ?? 0.0,
      ];
    }

    final assessed = await agg('substr(created_at,1,10) BETWEEN ? AND ?', [
      w.fromDay,
      w.toDay,
    ]);
    final collected = await agg(
      "status = ? AND resolved_at IS NOT NULL AND substr(resolved_at,1,10) BETWEEN ? AND ?",
      [FineStatus.paid.storage, w.fromDay, w.toDay],
    );
    final waived = await agg(
      "status = ? AND resolved_at IS NOT NULL AND substr(resolved_at,1,10) BETWEEN ? AND ?",
      [FineStatus.waived.storage, w.fromDay, w.toDay],
    );
    final outstanding = await agg('status = ?', [FineStatus.pending.storage]);

    String money(Object? v) => _money((v as num?)?.toDouble() ?? 0.0, cur);
    return Report(
      kind: ReportKind.fines,
      title: 'Fines',
      generatedAt: now.toIso8601String(),
      from: w.fromDay,
      to: w.toDay,
      columns: const ['Metric', 'Count', 'Amount'],
      rows: [
        ['Assessed', '${assessed[0]}', money(assessed[1])],
        ['Collected', '${collected[0]}', money(collected[1])],
        ['Waived', '${waived[0]}', money(waived[1])],
        ['Still outstanding', '${outstanding[0]}', money(outstanding[1])],
      ],
      summary: {'Outstanding total': money(outstanding[1]), 'Currency': cur},
    );
  }

  Future<Report> _reportMembers(String? from, String? to) async {
    final db = await database;
    final now = DateTime.now();
    final w = ReportQuery.window(
      ReportKind.members,
      from: from,
      to: to,
      now: now,
    )!;
    final rows0 = await db.rawQuery(
      'SELECT member_id, member_name, COUNT(*) AS c FROM loans '
      'WHERE loan_date IS NOT NULL AND substr(loan_date,1,10) BETWEEN ? AND ? '
      'GROUP BY member_id ORDER BY c DESC, member_id ASC LIMIT 20',
      [w.fromDay, w.toDay],
    );
    final totals = await db.rawQuery(
      'SELECT COUNT(DISTINCT member_id) AS m, COUNT(*) AS c FROM loans '
      'WHERE loan_date IS NOT NULL AND substr(loan_date,1,10) BETWEEN ? AND ?',
      [w.fromDay, w.toDay],
    );
    var rank = 0;
    final rows = <List<String>>[
      for (final r in rows0)
        [
          '${++rank}',
          _memberCell(r['member_name'], r['member_id']),
          _int(r['c']),
        ],
    ];
    final t = totals.isEmpty ? <String, Object?>{} : totals.first;
    return Report(
      kind: ReportKind.members,
      title: 'Top borrowers',
      generatedAt: now.toIso8601String(),
      from: w.fromDay,
      to: w.toDay,
      columns: const ['Rank', 'Member', 'Items borrowed'],
      rows: rows,
      summary: {
        'Active borrowers': _int(t['m']),
        'Total checkouts': _int(t['c']),
      },
    );
  }
}

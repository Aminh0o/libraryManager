import '../models/library_item.dart';
import '../models/member.dart';
import '../models/loan.dart';
import '../models/fine.dart';
import '../models/reservation.dart';
import '../models/report.dart';

abstract class LibraryRepository {
  // Server-side query for the inventory list. `search` matches designation,
  // code, barcode, emplacement or the full `CODE_TYPE-code` string; `status`
  // and `codeType` are exact filters. Results are ordered and paged by the
  // implementation so the whole catalogue is reachable, not just a cached
  // page (FE-05 / FE2-05 / Phase 7). [countItems] returns the total number of
  // rows matching the SAME filters so the caller can paginate correctly.
  Future<List<LibraryItem>> getItems({
    int limit = 1000,
    int offset = 0,
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  });
  Future<int> countItems({String? search, String? status, String? codeType});
  // The mutating methods accept an optional `audit` history row. When present
  // it is written in the SAME transaction as the data change + `db_version`
  // bump, so a mutation can never commit without its audit line (TX-01/5.2).
  // This covers the definition (code/attribute) endpoints too: the embedded
  // server records audit for remote-client definition changes (real client IP
  // + clock), closing the last BE-05 / BE-09 gap on mutating routes.
  Future<void> addItem(LibraryItem item, {Map<String, dynamic>? audit});
  // TX-06: `expectedVersion` is the row_version the caller read. When supplied,
  // a whole-row update that no longer matches the stored version is refused
  // (ConcurrentUpdateConflictException -> HTTP 409) instead of silently
  // clobbering a concurrent edit. Null => unconditional write (host/legacy).
  Future<void> updateItem(
    LibraryItem item, {
    Map<String, dynamic>? audit,
    int? expectedVersion,
  });
  Future<void> deleteItem(String code, {Map<String, dynamic>? audit});

  // History
  Future<List<Map<String, dynamic>>> getHistory({
    int limit = 20,
    int offset = 0,
    String? subject,
  });
  Future<void> addHistoryEntry(Map<String, dynamic> entry);
  Future<LibraryItem?> getItemByBarcode(String barcode);
  // Statistics
  Future<Map<String, dynamic>> getStats();

  // Code Definitions (Variables)
  Future<List<Map<String, dynamic>>> getCodeDefinitions();
  Future<void> addCodeDefinition(
    String prefix,
    String label, {
    Map<String, dynamic>? audit,
  });
  Future<void> updateCodeDefinition(
    String oldPrefix,
    String newPrefix,
    String label, {
    Map<String, dynamic>? audit,
  });
  Future<void> deleteCodeDefinition(
    String prefix, {
    Map<String, dynamic>? audit,
  });

  // Attribute Definitions
  Future<List<Map<String, dynamic>>> getAttributeDefinitions(String? type);
  Future<void> addAttributeDefinition(
    String type,
    String value, {
    Map<String, dynamic>? audit,
  });
  Future<void> deleteAttributeDefinition(int id, {Map<String, dynamic>? audit});

  // Members
  Future<List<Member>> getMembers();
  Future<void> addMember(Member member, {Map<String, dynamic>? audit});
  Future<void> updateMember(
    Member member, {
    Map<String, dynamic>? audit,
    int? expectedVersion,
  });
  Future<void> deleteMember(String memberId, {Map<String, dynamic>? audit});

  // Loans
  Future<List<Loan>> getLoans({bool activeOnly = false});
  Future<void> addLoan(Loan loan, {Map<String, dynamic>? audit});
  Future<void> updateLoan(
    Loan loan, {
    Map<String, dynamic>? audit,
  }); // For returns/renewals

  /// Resolve a scanned/typed value to the single active loan to return
  /// (Phase 2 / BL-03). Matches, in order of specificity: a per-copy barcode,
  /// the title (ISBN) barcode, or the item code. Returns `null` when no active
  /// loan matches. Server-authoritative so host and clients behave identically.
  Future<Loan?> findActiveLoanByScan(String scanned);

  // Sync + identifiers (used by the embedded server handlers and the host
  // health check). Exposed on the seam so the HTTP server can be constructed
  // against the interface (and therefore tested with an in-memory repository)
  // instead of the concrete DatabaseService singleton.
  Future<String> getDbVersion();
  Future<String> generateMemberID();

  // ==========================================================================
  // Fines & payments (Phase 10.2). Server-authoritative: an overdue return
  // accrues a ledger fine inside the SAME transaction, and paying/waiving is a
  // guarded, audited mutation. Both host and LAN clients go through these so
  // the money rules are identical regardless of who is looking.
  // ==========================================================================

  /// The fine policy (rate per overdue day + currency). Defaults to disabled.
  Future<FineSettings> getFineSettings();
  Future<void> setFineSettings(
    FineSettings settings, {
    Map<String, dynamic>? audit,
  });

  /// Ledger query, newest-first. [memberId] and [status] are optional filters.
  Future<List<Fine>> getFines({String? memberId, FineStatus? status});

  /// Sum of a member's still-open (pending) fines.
  Future<double> outstandingBalance(String memberId);

  /// Settle an open fine. [operatorName] is the authenticated username recorded
  /// as `resolved_by`. Throws [StateError] if the fine is unknown or already
  /// resolved (surfaced as HTTP 409), so money is never double-collected.
  Future<void> payFine(
    int id, {
    String? operatorName,
    Map<String, dynamic>? audit,
  });

  /// Write off an open fine (same guards as [payFine]).
  Future<void> waiveFine(
    int id, {
    String? operatorName,
    Map<String, dynamic>? audit,
  });

  // ==========================================================================
  // Reservations / hold queue (Phase 10.3). Server-authoritative like the
  // fines ledger: a hold only ever QUEUES a member; the physical copy is
  // claimed solely at PROMOTION, which happens atomically inside a return
  // transaction (or an immediate promotion when a copy already sits on the
  // shelf). Expiry releases the copy back for the next holder. Borrowing a
  // reserved copy is refused for anyone but its holder, so a hold can never
  // be cut in line by a walk-up checkout.
  // ==========================================================================

  /// The hold policy (pickup window + per-title queue cap). Stored in
  /// `metadata`; [HoldSettings.defaults] when absent or malformed.
  Future<HoldSettings> getHoldSettings();
  Future<void> setHoldSettings(
    HoldSettings settings, {
    Map<String, dynamic>? audit,
  });

  /// Put [memberId] in line for [itemCode]. Throws [StateError] (-> HTTP 409)
  /// when the item or member is unknown, the member already holds a live
  /// hold on the title, or the queue is full. If a copy is free and
  /// unreserved on the shelf the hold is promoted IMMEDIATELY (claimed with
  /// the same CAS every other copy transition uses) and returned `available`
  /// with a pickup deadline; otherwise it returns `queued`. A reserved copy
  /// waiting for another holder is NEVER handed out.
  Future<Reservation> placeReservation(
    String itemCode,
    String memberId, {
    Map<String, dynamic>? audit,
  });

  /// Queue query. Filters combine; [liveOnly] restricts to queued/available.
  /// Newest-mutable-first ordering is decided by the caller's presentation —
  /// the host returns rows in queue order (promoted first, then line).
  Future<List<Reservation>> getReservations({
    String? itemCode,
    String? memberId,
    ReservationStatus? status,
    bool liveOnly = false,
  });

  /// Holds promoted and genuinely awaiting pickup right now (expired rows
  /// are NOT surfaced even before a sweep has retired them).
  Future<List<Reservation>> readyForPickup();

  /// Cancel a live hold (holder's request or staff action). Throws
  /// [StateError] (-> 409) when the hold is unknown or already terminal.
  /// Cancelling a PROMOTED hold releases its claimed copy to the shelf and
  /// promotes the next in line, atomically.
  Future<void> cancelReservation(
    int id, {
    Map<String, dynamic>? audit,
  });

  /// Pass 6: swap [id]'s queue position with its immediate neighbour in the
  /// same item's queued line. `up: true` moves it one position earlier,
  /// `up: false` one later; a boundary row (already at the top / bottom)
  /// is a no-op. Only queued (not-yet-promoted) rows are reorderable --
  /// a promoted row already has a physical copy waiting, its place is
  /// server-owned. Throws `StateError` when the id does not exist or the
  /// row's status is not `queued`.
  Future<void> moveReservation(
    int id, {
    required bool up,
    Map<String, dynamic>? audit,
  });

  // ==========================================================================
  // Reports / management summaries (Phase 10.4). READ-ONLY and
  // SERVER-AUTHORITATIVE: the host computes every aggregate, so a LAN client
  // sees exactly the same figures a host operator does. [from]/[to] are
  // `YYYY-MM-DD` calendar-day bounds honoured only by the windowed kinds
  // (circulation / fines / members); a malformed or reversed range is rejected
  // by the route (-> 400) before any query runs.
  // ==========================================================================

  /// Compute the [kind] report over the optional window and return a
  /// fully-formed, presentation-ready table.
  Future<Report> generateReport(
    ReportKind kind, {
    String? from,
    String? to,
  });
}

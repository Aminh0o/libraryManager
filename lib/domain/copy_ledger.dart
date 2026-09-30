import '../models/item_copy.dart';

/// Pure, side-effect-free rules over a title's physical copies
/// (Phase 2 / DB-02, and the copy-level complement to BL-01).
///
/// The historical bug was that borrow state lived on the *title* row, so:
///  - a title with `quantite = 5` could hold only one loan;
///  - returning any copy flipped the whole title back to `Disponible` even with
///    other copies still out;
///  - a copy could be checked out twice.
///
/// These functions make the *set of copies* the source of truth: availability
/// is counted, checkout/return act on one specific copy, and the title status is
/// *derived* from them. Illegal operations throw [StateError] instead of
/// silently mutating. Increment 2.2b persists copies to an `item_copies` table
/// and 2.2c wires the provider/server through these rules.
class CopyLedger {
  CopyLedger._();

  static int availableCount(List<ItemCopy> copies) =>
      copies.where((c) => c.isAvailable).length;

  static int onLoanCount(List<ItemCopy> copies) =>
      copies.where((c) => c.isOnLoan).length;

  /// Total physical copies. When copies are modeled, `quantite` becomes this
  /// derived value rather than an independently-trusted column.
  static int total(List<ItemCopy> copies) => copies.length;

  /// The first available copy, or `null` if none can be lent right now.
  static ItemCopy? findAvailable(List<ItemCopy> copies) {
    for (final c in copies) {
      if (c.isAvailable) return c;
    }
    return null;
  }

  /// Check a specific copy out. Returns a NEW list with that copy marked
  /// [CopyState.onLoan]. Throws if the copy does not belong to this ledger or
  /// is not currently available (prevents copy-level double-checkout).
  static List<ItemCopy> checkout(List<ItemCopy> copies, int copyId) {
    final idx = copies.indexWhere((c) => c.id == copyId);
    if (idx == -1) {
      throw StateError('Unknown copy: $copyId');
    }
    if (!copies[idx].isAvailable) {
      throw StateError(
        'Copy $copyId is not available (state: ${copies[idx].state}).',
      );
    }
    final next = List<ItemCopy>.of(copies);
    next[idx] = copies[idx].copyWith(state: CopyState.onLoan.storage);
    return next;
  }

  /// Return a specific copy. Returns a NEW list with that copy marked
  /// [CopyState.available]. Throws if the copy is unknown or not on loan
  /// (guards a double return / returning a copy that was never lent).
  static List<ItemCopy> returnCopy(List<ItemCopy> copies, int copyId) {
    final idx = copies.indexWhere((c) => c.id == copyId);
    if (idx == -1) {
      throw StateError('Unknown copy: $copyId');
    }
    if (!copies[idx].isOnLoan) {
      throw StateError(
        'Copy $copyId is not on loan (state: ${copies[idx].state}).',
      );
    }
    final next = List<ItemCopy>.of(copies);
    next[idx] = copies[idx].copyWith(state: CopyState.available.storage);
    return next;
  }

  /// Derive the title-level rollup status string from its copies.
  ///
  /// Precedence: a title is lendable (`Disponible`) if ANY copy is available;
  /// otherwise a copy specifically held for pickup makes the title
  /// `Réservé` (Phase 10.3), then it is `Emprunté` if any copy is out, then
  /// maintenance/archival states, then `Perdu`. An empty ledger is treated as
  /// `Disponible` (no physical evidence to the contrary) so legacy titles
  /// without copies do not disappear from availability.
  static String deriveTitleStatus(List<ItemCopy> copies) {
    if (copies.isEmpty) return CopyState.available.storage;
    if (availableCount(copies) > 0) return CopyState.available.storage;
    if (copies.any((c) => c.isReserved)) return CopyState.reserved.storage;
    if (onLoanCount(copies) > 0) return CopyState.onLoan.storage;
    final states = copies.map((c) => c.copyState).toSet();
    if (states.contains(CopyState.maintenance)) {
      return CopyState.maintenance.storage;
    }
    if (states.contains(CopyState.archived)) {
      return CopyState.archived.storage;
    }
    return CopyState.lost.storage;
  }

  /// Resolve a scanned barcode to a copy within this title's ledger.
  /// Returns `null` when no copy carries that barcode (BL-03 resolution — the
  /// caller then decides whether to treat it as a title code fallback).
  static ItemCopy? findByBarcode(List<ItemCopy> copies, String barcode) {
    for (final c in copies) {
      if (c.barcode != null && c.barcode == barcode) return c;
    }
    return null;
  }
}

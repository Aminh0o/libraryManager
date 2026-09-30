/// Canonical per-copy state (Phase 2 / DB-02).
///
/// The historical model stored borrow state on the *title* row
/// (`library_items.status` + `quantite`), which made a 5-copy title support
/// exactly one loan and let returning any copy mark the whole title available.
/// [CopyState] is the single authoritative state of a **physical copy**.
///
/// Storage strings intentionally reuse the seeded French status vocabulary so
/// copy state and the derived title rollup share ONE vocabulary (mitigates
/// BL-05). The enum is the source of truth; the string is only its persistence
/// format. Unknown/legacy values fall back to [CopyState.available].
enum CopyState {
  available('Disponible'),
  onLoan('Emprunté'),

  /// Physically on the shelf but CLAIMED for a promoted hold (Phase 10.3) —
  /// only its holder may borrow it. Reuses the seeded title vocabulary
  /// ('Réservé' is an existing STATUS attribute value).
  reserved('Réservé'),
  maintenance('En Réparation'),
  lost('Perdu'),
  archived('Archivé');

  const CopyState(this.storage);

  /// Value persisted in the `item_copies.state` column.
  final String storage;

  static CopyState parse(String? value) => CopyState.values.firstWhere(
    (s) => s.storage == value,
    orElse: () => CopyState.available,
  );

  /// BL-05: the title-level status vocabulary the rollup can actually produce
  /// is EXACTLY these storage strings (in enum order). The status filter and the
  /// create/update validators both read from here, so a value a title can never
  /// legitimately carry can never be offered as a filter or persisted.
  static List<String> get titleStatusVocabulary =>
      CopyState.values.map((s) => s.storage).toList(growable: false);

  /// Is [value] a status a title can hold (i.e. one `CopyLedger.deriveTitleStatus`
  /// can emit)? Unknown / legacy / arbitrary strings are NOT -- they must be
  /// rejected on write rather than silently stored then clobbered on next loan.
  static bool isTitleStatus(String? value) =>
      CopyState.values.any((s) => s.storage == value);
}

/// A single physical copy of a [LibraryItem].
///
/// Framework-free (no Flutter/DB/socket imports) so the model and the
/// [CopyLedger]-style rules over it are trivially unit-testable and shared by
/// host and client. This is additive: nothing reads it until increment 2.2b
/// (schema) and 2.2c (wiring) land.
class ItemCopy {
  final int? id;
  final String itemCode; // FK -> library_items.code (the title)
  final String? barcode; // per-copy barcode; may equal the shared ISBN
  final String state; // see [CopyState.storage]
  final String? note; // free text (condition, asset tag, ...)
  final String? acquiredAt;

  ItemCopy({
    this.id,
    required this.itemCode,
    this.barcode,
    this.state = 'Disponible',
    this.note,
    this.acquiredAt,
  });

  CopyState get copyState => CopyState.parse(state);
  bool get isAvailable => copyState == CopyState.available;
  bool get isOnLoan => copyState == CopyState.onLoan;
  bool get isReserved => copyState == CopyState.reserved;

  ItemCopy copyWith({
    int? id,
    String? itemCode,
    String? barcode,
    String? state,
    String? note,
    String? acquiredAt,
  }) {
    return ItemCopy(
      id: id ?? this.id,
      itemCode: itemCode ?? this.itemCode,
      barcode: barcode ?? this.barcode,
      state: state ?? this.state,
      note: note ?? this.note,
      acquiredAt: acquiredAt ?? this.acquiredAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'item_code': itemCode,
      'barcode': barcode,
      'state': state,
      'note': note,
      'acquired_at': acquiredAt,
    };
  }

  factory ItemCopy.fromMap(Map<String, dynamic> map) {
    return ItemCopy(
      id: map['id']?.toInt(),
      itemCode: map['item_code'] ?? '',
      barcode: map['barcode'],
      state: map['state'] ?? 'Disponible',
      note: map['note'],
      acquiredAt: map['acquired_at'],
    );
  }
}

/// Represents a library item (book, magazine, thesis, etc.)
class LibraryItem {
  final String code;
  final String? barcode; // ISBN/EAN (shared across copies)
  final String codeType; // LIV, REV, THE, MEM, PER
  final String designation;
  final int quantite;
  final String emplacement;
  final double taux; // Price in DZD
  final String emplacementStock;
  final String status;
  /// Per-row optimistic-concurrency token (TX-06). Advanced by the server on
  /// every successful update; surfaced on reads so a client can send it back as
  /// `X-Expected-Version` and have a stale whole-row write REJECTED (409) rather
  /// than silently clobber another client's edit. Defaults to 0 for a new item.
  final int rowVersion;

  LibraryItem({
    required this.code,
    this.barcode,
    required this.codeType,
    required this.designation,
    required this.quantite,
    required this.emplacement,
    required this.taux,
    required this.emplacementStock,
    this.status = 'Disponible',
    this.rowVersion = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'barcode': barcode,
      'code_type': codeType,
      'designation': designation,
      'quantite': quantite,
      'emplacement': emplacement,
      'taux': taux,
      'emplacement_stock': emplacementStock,
      'status': status,
      'row_version': rowVersion,
    };
  }

  factory LibraryItem.fromMap(Map<String, dynamic> map) {
    return LibraryItem(
      code: map['code'] ?? '',
      barcode: map['barcode'],
      codeType: map['code_type'] ?? 'LIV',
      designation: map['designation'] ?? '',
      quantite: map['quantite']?.toInt() ?? 0,
      emplacement: map['emplacement'] ?? '',
      taux: map['taux']?.toDouble() ?? 0.0,
      emplacementStock: map['emplacement_stock'] ?? '',
      status: map['status'] ?? 'Disponible',
      rowVersion: map['row_version']?.toInt() ?? 0,
    );
  }

  /// Returns the full formatted code with prefix
  String get fullCode => '$codeType-$code';
}

/// Item status definitions
class ItemStatus {
  static const String disponible = 'Disponible';
  static const String emprunte = 'Emprunté';
  static const String reserve = 'Réservé';
  static const String endommage = 'Endommagé';

  static const List<String> all = [disponible, emprunte, reserve, endommage];
}


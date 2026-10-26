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

  // ---- Phase 6 (schema v24) enrichment. All NULLABLE and additive; legacy
  // rows keep NULL and render as "not set" — nothing is back-filled or
  // invented at read time.
  final String? author;
  final String? category;
  final String? description;

  /// Language the title is written in (free text; the form offers the
  /// localized presets: French / Arabic / English).
  final String? language;

  final String? publisher;
  final int? year;

  /// Absolute path of the cover image inside the app's managed covers folder
  /// (the service copies the picked file in; NULL = no cover).
  final String? coverPath;

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
    this.author,
    this.category,
    this.description,
    this.language,
    this.publisher,
    this.year,
    this.coverPath,
  });

  /// Whole-row copy with overrides — see `Member.copyWith` for why hand-
  /// written rebuilds of a row are banned (they silently drop fields).
  LibraryItem copyWith({
    String? code,
    String? barcode,
    String? codeType,
    String? designation,
    int? quantite,
    String? emplacement,
    double? taux,
    String? emplacementStock,
    String? status,
    int? rowVersion,
    String? author,
    String? category,
    String? description,
    String? language,
    String? publisher,
    int? year,
    String? coverPath,
  }) {
    return LibraryItem(
      code: code ?? this.code,
      barcode: barcode ?? this.barcode,
      codeType: codeType ?? this.codeType,
      designation: designation ?? this.designation,
      quantite: quantite ?? this.quantite,
      emplacement: emplacement ?? this.emplacement,
      taux: taux ?? this.taux,
      emplacementStock: emplacementStock ?? this.emplacementStock,
      status: status ?? this.status,
      rowVersion: rowVersion ?? this.rowVersion,
      author: author ?? this.author,
      category: category ?? this.category,
      description: description ?? this.description,
      language: language ?? this.language,
      publisher: publisher ?? this.publisher,
      year: year ?? this.year,
      coverPath: coverPath ?? this.coverPath,
    );
  }

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
      'author': author,
      'category': category,
      'description': description,
      'language': language,
      'publisher': publisher,
      'year': year,
      'cover_path': coverPath,
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
      author: map['author'],
      category: map['category'],
      description: map['description'],
      language: map['language'],
      publisher: map['publisher'],
      year: map['year']?.toInt(),
      coverPath: map['cover_path'],
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

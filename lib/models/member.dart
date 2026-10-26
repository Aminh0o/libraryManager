class Member {
  final int? id;
  final String firstName;
  final String lastName;
  final String? email;
  final String? phone;
  final String memberId; // Unique Card ID or Student ID
  final DateTime registeredAt;

  /// Per-row optimistic-concurrency token (TX-06). Advanced by the server on
  /// every successful member edit; surfaced on reads so a client can send it
  /// back (as `X-Expected-Version`) and have a stale whole-row edit REJECTED
  /// (409) rather than silently clobber another client's change. Defaults to 0
  /// for a brand-new member (the server assigns the real value on insert).
  final int rowVersion;

  // ---- Phase 5 (schema v24) enrichment. All NULLABLE and additive: rows
  // written before v24 keep NULL and every reader treats NULL as "not set",
  // so no legacy data is rewritten or invented here.

  /// Absolute path of the member's photo inside the app's managed photo
  /// folder (NOT the raw picker path — the service copies it in). NULL when
  /// no photo has been attached.
  final String? photoPath;

  /// Card/membership type (e.g. Student, Teacher, Standard). Free-text at the
  /// model layer; the form offers the localized presets. NULL = not set.
  final String? memberType;

  /// Membership state ('active' / 'expired' / 'suspended' style values are a
  /// UI concern; stored as authored). NULL on pre-v24 rows — the UI renders
  /// those as "not set" rather than silently claiming they are active.
  final String? status;

  /// Membership expiry date, if the library tracks one. NULL = no expiry.
  final DateTime? expiryDate;

  final String? address;
  final String? notes;

  /// Gender / genre of the member (e.g. 'male', 'female', 'other'). Nullable.
  final String? gender;

  Member({
    this.id,
    required this.firstName,
    required this.lastName,
    this.email,
    this.phone,
    required this.memberId,
    required this.registeredAt,
    this.rowVersion = 0,
    this.photoPath,
    this.memberType,
    this.status,
    this.expiryDate,
    this.address,
    this.notes,
    this.gender,
  });

  /// Whole-row copy with overrides. Existence rule (ARC: rebuild-safety):
  /// every place that only needs to change ONE aspect of a member (e.g. swap
  /// an auto-generated card id) MUST go through this — hand-written
  /// constructors silently drop the enrichment fields, which is exactly how
  /// the POST /members auto-id path used to erase photos/notes.
  Member copyWith({
    int? id,
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
    String? memberId,
    DateTime? registeredAt,
    int? rowVersion,
    String? photoPath,
    String? memberType,
    String? status,
    DateTime? expiryDate,
    String? address,
    String? notes,
    String? gender,
  }) {
    return Member(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      memberId: memberId ?? this.memberId,
      registeredAt: registeredAt ?? this.registeredAt,
      rowVersion: rowVersion ?? this.rowVersion,
      photoPath: photoPath ?? this.photoPath,
      memberType: memberType ?? this.memberType,
      status: status ?? this.status,
      expiryDate: expiryDate ?? this.expiryDate,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      gender: gender ?? this.gender,
    );
  }

  String get fullName => '$firstName $lastName';

  /// Single uppercase letter for the member avatar, chosen defensively (FE2-07).
  /// `firstName` is a non-nullable [String] that [fromMap] fills with `''` when
  /// the stored column is null/empty, so the old `firstName[0]` threw a
  /// RangeError and crashed the ENTIRE member list on one nameless record. Try
  /// first name, then last name, then the card id, and return `''` (the caller
  /// renders a generic icon) only when every source is blank.
  String get avatarInitial {
    for (final source in [firstName, lastName, memberId]) {
      final trimmed = source.trim();
      if (trimmed.isNotEmpty) return trimmed[0].toUpperCase();
    }
    return '';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'phone': phone,
      'member_id': memberId,
      'registered_at': registeredAt.toIso8601String(),
      'row_version': rowVersion,
      'photo_path': photoPath,
      'member_type': memberType,
      'status': status,
      'expiry_date': expiryDate?.toIso8601String(),
      'address': address,
      'notes': notes,
      'gender': gender,
    };
  }

  /// Complete member QR code payload embedding all profile attributes.
  /// Scannable by any camera / external barcode reader, and automatically
  /// resolved by Library Manager scanners.
  String toQrPayload() {
    return '{"app":"LibraryManager","type":"MEMBER_CARD",'
        '"id":"$memberId",'
        '"name":"${fullName.replaceAll('"', r'\"')}",'
        '"gender":"${gender ?? ''}",'
        '"memberType":"${memberType ?? ''}",'
        '"status":"${status ?? ''}",'
        '"email":"${email ?? ''}",'
        '"phone":"${phone ?? ''}",'
        '"expiry":"${expiryDate?.toIso8601String() ?? ''}",'
        '"address":"${(address ?? '').replaceAll('"', r'\"')}"}';
  }

  factory Member.fromMap(Map<String, dynamic> map) {
    final expiryRaw = map['expiry_date'];
    return Member(
      id: map['id']?.toInt(),
      firstName: map['first_name'] ?? '',
      lastName: map['last_name'] ?? '',
      email: map['email'],
      phone: map['phone'],
      memberId: map['member_id'] ?? '',
      registeredAt: DateTime.parse(map['registered_at']),
      rowVersion: map['row_version']?.toInt() ?? 0,
      photoPath: map['photo_path'],
      memberType: map['member_type'],
      status: map['status'],
      expiryDate: expiryRaw == null
          ? null
          : DateTime.tryParse(expiryRaw.toString()),
      address: map['address'],
      notes: map['notes'],
      gender: map['gender'],
    );
  }
}

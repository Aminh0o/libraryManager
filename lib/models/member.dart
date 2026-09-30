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

  Member({
    this.id,
    required this.firstName,
    required this.lastName,
    this.email,
    this.phone,
    required this.memberId,
    required this.registeredAt,
    this.rowVersion = 0,
  });

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
    };
  }

  factory Member.fromMap(Map<String, dynamic> map) {
    return Member(
      id: map['id']?.toInt(),
      firstName: map['first_name'] ?? '',
      lastName: map['last_name'] ?? '',
      email: map['email'],
      phone: map['phone'],
      memberId: map['member_id'] ?? '',
      registeredAt: DateTime.parse(map['registered_at']),
      rowVersion: map['row_version']?.toInt() ?? 0,
    );
  }
}

class Member {
  final int? id;
  final String firstName;
  final String lastName;
  final String? email;
  final String? phone;
  final String memberId; // Unique Card ID or Student ID
  final DateTime registeredAt;

  Member({
    this.id,
    required this.firstName,
    required this.lastName,
    this.email,
    this.phone,
    required this.memberId,
    required this.registeredAt,
  });

  String get fullName => '$firstName $lastName';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'phone': phone,
      'member_id': memberId,
      'registered_at': registeredAt.toIso8601String(),
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
    );
  }
}

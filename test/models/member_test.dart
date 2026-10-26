import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/models/member.dart';

/// FE2-07: the member list used to render `member.firstName[0]`, which threw a
/// RangeError on a member whose stored first name is empty (Member.fromMap
/// coerces a null column to `''`), blanking the whole screen. `avatarInitial`
/// is the throw-free replacement.
void main() {
  Member build({
    String firstName = '',
    String lastName = '',
    String memberId = '',
  }) => Member(
    firstName: firstName,
    lastName: lastName,
    memberId: memberId,
    registeredAt: DateTime(2020),
  );

  group('Member.avatarInitial (FE2-07)', () {
    test('uses the first letter of the first name, uppercased', () {
      expect(build(firstName: 'adele').avatarInitial, 'A');
      expect(build(firstName: '  Bob  ').avatarInitial, 'B');
    });

    test('falls back to last name when first name is blank', () {
      expect(build(firstName: '', lastName: 'curie').avatarInitial, 'C');
      expect(build(firstName: '   ', lastName: 'curie').avatarInitial, 'C');
    });

    test('falls back to the card id when both names are blank', () {
      expect(
        build(firstName: '', lastName: '', memberId: 'AA0001').avatarInitial,
        'A',
      );
    });

    test('returns empty (never throws) when EVERY source is blank', () {
      // This is the exact case that used to crash: firstName == ''.
      expect(build().avatarInitial, '');
    });

    test('a nameless member built from a null DB column does not throw', () {
      final m = Member.fromMap({
        'id': 1,
        'first_name': null,
        'last_name': null,
        'member_id': null,
        'registered_at': DateTime(2020).toIso8601String(),
      });
      expect(m.avatarInitial, '');
      expect(m.fullName, ' ');
    });
  });

  // Phase 5 (schema v24): the enrichment fields must round-trip through the
  // DB map, stay NULL-tolerant for legacy rows, and survive every whole-row
  // rebuild (copyWith) -- the auto-id paths used to erase them.
  group('Member v24 enrichment', () {
    test('toMap/fromMap round-trips every enrichment field', () {
      final m = Member(
        id: 7,
        firstName: 'Amira',
        lastName: 'B',
        memberId: '250001',
        registeredAt: DateTime(2024, 5, 20),
        rowVersion: 3,
        photoPath: r'C:\x\members\250001.jpg',
        memberType: 'Student',
        status: 'Active',
        expiryDate: DateTime(2027, 1, 1),
        address: 'Tlemcen',
        notes: 'VIP',
        gender: 'female',
      );
      final back = Member.fromMap(m.toMap());
      expect(back.photoPath, m.photoPath);
      expect(back.memberType, 'Student');
      expect(back.status, 'Active');
      expect(back.expiryDate, m.expiryDate);
      expect(back.address, 'Tlemcen');
      expect(back.notes, 'VIP');
      expect(back.gender, 'female');
      expect(back.rowVersion, 3);
    });

    test('a legacy pre-v24 row reads with every enrichment field null', () {
      final legacy = Member.fromMap({
        'id': 1,
        'first_name': 'Old',
        'last_name': 'Row',
        'member_id': 'AA0001',
        'registered_at': DateTime(2020).toIso8601String(),
      });
      expect(legacy.photoPath, isNull);
      expect(legacy.memberType, isNull);
      expect(legacy.status, isNull);
      expect(legacy.expiryDate, isNull);
      expect(legacy.address, isNull);
      expect(legacy.notes, isNull);
      expect(legacy.gender, isNull);
      // And re-serializing one must not invent values.
      expect(legacy.toMap()['status'], isNull);
      expect(legacy.toMap()['gender'], isNull);
      expect(legacy.toMap()['expiry_date'], isNull);
    });

    test('copyWith (auto-id rebuild) keeps the enrichment fields', () {
      final m = Member(
        firstName: 'A',
        lastName: 'B',
        memberId: 'AUTO',
        registeredAt: DateTime(2024),
        photoPath: 'p.jpg',
        memberType: 'Teacher',
        status: 'Suspended',
        expiryDate: DateTime(2030),
        address: 'adr',
        notes: 'n',
        rowVersion: 9,
      );
      final swapped = m.copyWith(memberId: '250123');
      expect(swapped.memberId, '250123');
      expect(swapped.photoPath, 'p.jpg');
      expect(swapped.memberType, 'Teacher');
      expect(swapped.status, 'Suspended');
      expect(swapped.expiryDate, DateTime(2030));
      expect(swapped.address, 'adr');
      expect(swapped.notes, 'n');
      expect(swapped.rowVersion, 9);
    });

    test('an unparseable stored expiry reads as null (never throws)', () {
      final m = Member.fromMap({
        'id': 1,
        'first_name': 'A',
        'last_name': 'B',
        'member_id': 'X',
        'registered_at': DateTime(2020).toIso8601String(),
        'expiry_date': 'not-a-date',
      });
      expect(m.expiryDate, isNull);
    });
  });
}

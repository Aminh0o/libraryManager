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
  }) =>
      Member(
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
          build(firstName: '', lastName: '', memberId: 'AA0001')
              .avatarInitial,
          'A');
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
}

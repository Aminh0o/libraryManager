import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/models/loan.dart';

/// Loan model coverage. NOTE (P9-9.23): `Loan.fromMap` is deliberately STRICT --
/// it lets `DateTime.parse` throw on a missing/malformed date -- because the
/// server's `parseModel` wrapper turns that throw into a PROTO-01 400 for
/// POST/PUT /loans; a request body with an unparseable date MUST be rejected,
/// not silently coerced. So these tests pin the happy path and the nullable
/// return date, and do NOT assert any lenient fallback (there is none by
/// design; see the http_server_validation_test 400-on-bad-date contract).
void main() {
  Map<String, dynamic> base({
    Object? loanDate = '2026-01-05T00:00:00.000',
    Object? dueDate = '2026-01-20T00:00:00.000',
    Object? returnDate,
    Object? status = 'Active',
  }) =>
      {
        'id': 3,
        'item_code': '0500',
        'copy_id': 9,
        'member_id': 'AA0001',
        'member_name': 'Ada',
        'item_title': 'Book',
        'loan_date': loanDate,
        'due_date': dueDate,
        'return_date': returnDate,
        'status': status,
      };

  group('Loan.fromMap / toMap', () {
    test('a well-formed loan parses its dates exactly', () {
      final l = Loan.fromMap(base());
      expect(l.loanDate, DateTime.parse('2026-01-05T00:00:00.000'));
      expect(l.dueDate, DateTime.parse('2026-01-20T00:00:00.000'));
      expect(l.copyId, 9);
      expect(l.returnDate, isNull); // absent return_date => null
      expect(l.isActive, isTrue);
    });

    test('a present return_date is parsed; a returned loan is not active', () {
      final l = Loan.fromMap(
          base(returnDate: '2026-02-01T00:00:00.000', status: 'Returned'));
      expect(l.returnDate, DateTime.parse('2026-02-01T00:00:00.000'));
      expect(l.isReturned, isTrue);
      expect(l.isActive, isFalse);
    });

    test('toMap/fromMap round-trips a valid loan without loss', () {
      final original = Loan(
        id: 12,
        itemCode: '0600',
        copyId: 4,
        memberId: 'BB0002',
        memberName: 'Marie',
        itemTitle: 'Journal',
        loanDate: DateTime(2026, 3, 1),
        dueDate: DateTime(2026, 3, 16),
        returnDate: DateTime(2026, 3, 10),
        status: 'Returned',
      );
      final back = Loan.fromMap(original.toMap());
      expect(back.id, 12);
      expect(back.copyId, 4);
      expect(back.itemCode, '0600');
      expect(back.memberId, 'BB0002');
      expect(back.loanDate, original.loanDate);
      expect(back.dueDate, original.dueDate);
      expect(back.returnDate, original.returnDate);
      expect(back.status, 'Returned');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/domain/loan_transitions.dart';
import 'package:library_manager/models/loan.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 12);

  Loan active() => LoanTransitions.checkOut(
    itemCode: '0001',
    memberId: '250001',
    memberName: 'Alice',
    itemTitle: 'Book',
    now: t0,
    durationDays: 15,
  );

  group('checkOut', () {
    test('creates an active loan with dueDate = now + duration', () {
      final l = active();
      expect(l.status, 'Active');
      expect(l.isActive, isTrue);
      expect(l.isReturned, isFalse);
      expect(l.loanDate, t0);
      expect(l.dueDate, t0.add(const Duration(days: 15)));
      expect(l.returnDate, isNull);
    });
  });

  group('returnLoan', () {
    test('active -> returned sets status + return date', () {
      final r = LoanTransitions.returnLoan(
        active(),
        when: t0.add(const Duration(days: 3)),
      );
      expect(r.status, 'Returned');
      expect(r.isReturned, isTrue);
      expect(r.isActive, isFalse);
      expect(r.returnDate, t0.add(const Duration(days: 3)));
    });

    test('returning an already-returned loan throws (double return)', () {
      final r = LoanTransitions.returnLoan(active());
      expect(() => LoanTransitions.returnLoan(r), throwsA(isA<StateError>()));
    });
  });

  group('renew', () {
    test('extends due date of an active loan', () {
      final l = active();
      final renewed = LoanTransitions.renew(l, additionalDays: 7);
      expect(renewed.dueDate, l.dueDate.add(const Duration(days: 7)));
      expect(renewed.status, 'Active');
      expect(renewed.id, l.id);
    });

    test('BL-02: renewing a returned loan throws (no resurrection)', () {
      final returned = LoanTransitions.returnLoan(active());
      expect(() => LoanTransitions.renew(returned), throwsA(isA<StateError>()));
    });
  });

  group('canonical status (FB-01)', () {
    test('status is the single source of truth', () {
      final l = active().copyWith(status: 'Returned'); // status says returned
      expect(l.isReturned, isTrue, reason: 'status, not returnDate, decides');
      expect(l.isActive, isFalse);
    });

    test('overdue is derived and only for active loans', () {
      final past = Loan(
        itemCode: '0001',
        memberId: 'm',
        memberName: 'n',
        itemTitle: 't',
        loanDate: DateTime(2020),
        dueDate: DateTime(2020, 1, 15),
        status: 'Active',
      );
      expect(past.isOverdue, isTrue);
      final returnedPast = past.copyWith(status: 'Returned');
      expect(
        returnedPast.isOverdue,
        isFalse,
        reason: 'a returned loan is never overdue',
      );
    });
  });
}

import 'package:bulk_buying_companion/models/reservation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('names the student who holds the slot', () {
    final reservation = Reservation(
      dealId: 'deal-1',
      userId: 'user-1',
      studentName: 'Marco Villanueva',
      reservedAt: DateTime(2026, 7, 14),
      isHost: true,
    );

    expect(reservation.displayName, 'Marco Villanueva');
    expect(reservation.isHost, isTrue);
  });

  test('falls back to a person rather than a gap when the name is unknown', () {
    final reservation = Reservation(
      dealId: 'deal-1',
      userId: 'user-2',
      studentName: '   ',
      reservedAt: DateTime(2026, 7, 14),
    );

    expect(reservation.displayName, 'A student in this hub');
    expect(reservation.isHost, isFalse);
  });

  test('a reservation knows whether it is paid and collected', () {
    final unpaid = Reservation(
      dealId: 'd',
      userId: 'u',
      reservedAt: DateTime(2026, 7, 16),
    );
    expect(unpaid.hasPaid, isFalse);
    expect(unpaid.hasCollected, isFalse);

    final settled = Reservation(
      dealId: 'd',
      userId: 'u',
      reservedAt: DateTime(2026, 7, 16),
      paidAt: DateTime(2026, 7, 16),
      collectedAt: DateTime(2026, 7, 17),
    );
    expect(settled.hasPaid, isTrue);
    expect(settled.hasCollected, isTrue);
  });
}

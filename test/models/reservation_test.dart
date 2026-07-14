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
}

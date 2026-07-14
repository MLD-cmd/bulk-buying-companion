import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:flutter_test/flutter_test.dart';

Deal deal({
  int totalSlots = 4,
  required int availableSlots,
  int paidCount = 0,
  int collectedCount = 0,
  DateTime? purchasedAt,
  DateTime? cancelledAt,
}) {
  return Deal(
    id: 'd',
    hubId: 'h',
    title: 'Rice',
    category: DealCategory.grocery,
    totalPrice: 400,
    amount: 20,
    unit: DealUnit.kg,
    availableSlots: availableSlots,
    totalSlots: totalSlots,
    pickupLocation: 'Lobby',
    paidCount: paidCount,
    collectedCount: collectedCount,
    purchasedAt: purchasedAt,
    cancelledAt: cancelledAt,
  );
}

void main() {
  final now = DateTime(2026, 7, 16);

  test('slots still free is open', () {
    expect(deal(availableSlots: 2).status, DealStatus.open);
  });

  test('every claimed slot is a participant', () {
    expect(deal(totalSlots: 4, availableSlots: 1).participantCount, 3);
  });

  test('no slots left, not everyone paid, is full', () {
    expect(deal(availableSlots: 0, paidCount: 3).status, DealStatus.full);
  });

  test('no slots left and everyone paid is ready to purchase', () {
    expect(
      deal(availableSlots: 0, paidCount: 4).status,
      DealStatus.readyToPurchase,
    );
  });

  test('bought is ready for pickup, however many have paid', () {
    expect(
      deal(availableSlots: 0, paidCount: 1, purchasedAt: now).status,
      DealStatus.readyForPickup,
    );
  });

  test('bought and everyone collected is completed', () {
    expect(
      deal(
        availableSlots: 0,
        paidCount: 4,
        collectedCount: 4,
        purchasedAt: now,
      ).status,
      DealStatus.completed,
    );
  });

  test('cancelled beats everything else', () {
    expect(
      deal(
        availableSlots: 0,
        paidCount: 4,
        collectedCount: 4,
        purchasedAt: now,
        cancelledAt: now,
      ).status,
      DealStatus.cancelled,
    );
  });

  // The reason status is derived rather than stored: no code path makes this
  // happen, and it still has to be right.
  test('a student leaving a ready-to-purchase deal reopens it', () {
    final ready = deal(availableSlots: 0, paidCount: 4);
    expect(ready.status, DealStatus.readyToPurchase);

    final afterCancel = ready.copyWith(availableSlots: 1, paidCount: 3);
    expect(afterCancel.status, DealStatus.open);
  });

  // Goods that were never bought cannot be reported as collected.
  test('collected without a purchase is not completed', () {
    expect(
      deal(availableSlots: 0, paidCount: 4, collectedCount: 4).status,
      DealStatus.readyToPurchase,
    );
  });

  test('a deal with nobody in it is not completed', () {
    expect(
      deal(totalSlots: 4, availableSlots: 4, purchasedAt: now).status,
      DealStatus.readyForPickup,
    );
  });

  group('filling fast', () {
    test('an open deal with a quarter of its slots left is filling fast', () {
      final d = deal(totalSlots: 8, availableSlots: 2);
      expect(d.isFillingFast, isTrue);
      expect(d.statusLabel, 'Filling fast');
    });

    test('more than a quarter left is just open', () {
      final d = deal(totalSlots: 8, availableSlots: 3);
      expect(d.isFillingFast, isFalse);
      expect(d.statusLabel, 'Open');
    });

    // A quarter of 3 is less than one slot, so a bare quarter rule could never
    // fire on the smallest deals -- and one seat left is as urgent as it gets.
    test('the last slot is filling fast however small the deal', () {
      final threeWay = deal(totalSlots: 3, availableSlots: 1);
      expect(threeWay.isFillingFast, isTrue);
      expect(threeWay.statusLabel, 'Filling fast');

      final fourWay = deal(totalSlots: 4, availableSlots: 1);
      expect(fourWay.isFillingFast, isTrue);
    });

    test('a full deal is never filling fast', () {
      final d = deal(totalSlots: 8, availableSlots: 0);
      expect(d.isFillingFast, isFalse);
      expect(d.statusLabel, 'Full');
    });

    // Nobody can join a bought deal, so its empty seats are not urgent.
    test('a deal that has been bought is never filling fast', () {
      final d = deal(totalSlots: 4, availableSlots: 1, purchasedAt: now);
      expect(d.isFillingFast, isFalse);
      expect(d.statusLabel, 'Ready for pickup');
    });
  });

  group('what the host is holding', () {
    // The host's own slot is marked paid at creation -- they cannot pay
    // themselves -- so it is not money they owe back.
    test('the host is not counted as a student who paid', () {
      final d = deal(totalSlots: 4, availableSlots: 0, paidCount: 1);
      expect(d.studentsWhoPaid, 0);
      expect(d.amountHeld, 0);
    });

    // A Deal is built from whatever the database row holds, and this getter
    // runs inside build. It must floor, not go negative or throw.
    test('nobody paid at all is not a negative number of students', () {
      final d = deal(totalSlots: 4, availableSlots: 4);
      expect(d.studentsWhoPaid, 0);
      expect(d.amountHeld, 0);
    });

    test('money held is the students who paid, at the per-share price', () {
      final d = deal(totalSlots: 4, availableSlots: 0, paidCount: 3);
      expect(d.studentsWhoPaid, 2);
      expect(d.amountHeld, 200); // 400 / 4 slots = 100 each
    });
  });

  test('finished deals are the ones the board hides', () {
    expect(DealStatus.completed.isFinished, isTrue);
    expect(DealStatus.cancelled.isFinished, isTrue);
    expect(DealStatus.open.isFinished, isFalse);
    expect(DealStatus.readyForPickup.isFinished, isFalse);
  });
}

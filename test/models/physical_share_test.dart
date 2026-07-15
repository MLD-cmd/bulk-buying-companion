import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:bulk_buying_companion/models/physical_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('continuous goods divide freely', () {
    final share = PhysicalShare.from(amount: 25, unit: DealUnit.kg, slots: 7);

    expect(share.dividesEvenly, isTrue);
    expect(share.amountPerShare, closeTo(3.5714, 0.0001));
    expect(share.shareLabel, '3.57 kg');
    expect(share.totalLabel, '25 kg');
  });

  test('discrete goods that divide evenly give whole shares', () {
    final share = PhysicalShare.from(
      amount: 30,
      unit: DealUnit.pieces,
      slots: 5,
    );

    expect(share.dividesEvenly, isTrue);
    expect(share.amountPerShare, 6);
    expect(share.shareLabel, '6 pieces');
  });

  test('discrete goods that do not divide are caught', () {
    // 30 eggs across 4 slots is 7.5 eggs, and nobody can collect half an egg.
    final share = PhysicalShare.from(
      amount: 30,
      unit: DealUnit.pieces,
      slots: 4,
    );

    expect(share.dividesEvenly, isFalse);
  });

  test('a single share reads in the singular', () {
    final share = PhysicalShare.from(
      amount: 4,
      unit: DealUnit.bottles,
      slots: 4,
    );

    expect(share.shareLabel, '1 bottle');
  });

  test('lists the slot counts that actually work', () {
    final thirty = PhysicalShare.from(
      amount: 30,
      unit: DealUnit.pieces,
      slots: 4,
    );
    expect(thirty.workableSlotCounts, [2, 3, 5, 6, 10, 15, 30]);

    final twentyFour = PhysicalShare.from(
      amount: 24,
      unit: DealUnit.bottles,
      slots: 5,
    );
    expect(twentyFour.workableSlotCounts, [2, 3, 4, 6, 8, 12, 24]);
  });

  test('a continuous deal needs no suggestions, it always divides', () {
    final share = PhysicalShare.from(amount: 25, unit: DealUnit.kg, slots: 7);

    expect(share.workableSlotCounts, isEmpty);
    expect(share.dividesEvenly, isTrue);
  });

  test('a single item cannot be split at all', () {
    final share = PhysicalShare.from(
      amount: 1,
      unit: DealUnit.pieces,
      slots: 2,
    );

    expect(share.dividesEvenly, isFalse);
    expect(share.workableSlotCounts, isEmpty);
    expect(share.canBeSplit, isFalse);
  });

  test('a prime amount above the slot ceiling cannot be split either', () {
    // 97 is prime and larger than the 50-slot ceiling, so no allowed count
    // divides it.
    final share = PhysicalShare.from(
      amount: 97,
      unit: DealUnit.pieces,
      slots: 4,
    );

    expect(share.workableSlotCounts, isEmpty);
    expect(share.canBeSplit, isFalse);
  });

  test('rejects an amount of nothing', () {
    expect(
      () => PhysicalShare.from(amount: 0, unit: DealUnit.kg, slots: 4),
      throwsArgumentError,
    );
  });

  test('units know whether they can be halved', () {
    expect(DealUnit.kg.continuous, isTrue);
    expect(DealUnit.litre.continuous, isTrue);
    expect(DealUnit.pieces.discrete, isTrue);
    expect(DealUnit.bottles.discrete, isTrue);

    // Stored by Dart name, as DealCategory already is: 'litre', not 'L'.
    expect(DealUnit.litre.name, 'litre');
    expect(DealUnit.litre.label, 'L');
  });

  test('a deal knows what each student physically gets', () {
    const deal = Deal(
      id: 'rice',
      hubId: 'colon',
      title: '25kg Rice Sack',
      category: DealCategory.grocery,
      totalPrice: 900,
      amount: 25,
      unit: DealUnit.kg,
      availableSlots: 6,
      totalSlots: 7,
      pickupLocation: 'USJR Main Gate',
    );

    expect(deal.physicalShare.shareLabel, '3.57 kg');
    expect(deal.physicalShare.totalLabel, '25 kg');
    // The money and the goods answer the two questions a student actually has.
    expect(deal.priceLabel, 'P128.58/share');
  });
}

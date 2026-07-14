import 'package:bulk_buying_companion/models/cost_split.dart';
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an even split leaves no surplus', () {
    final split = CostSplit.from(totalPrice: 900, slots: 5);

    expect(split.totalCentavos, 90000);
    expect(split.perShareCentavos, 18000);
    expect(split.collectedCentavos, 90000);
    expect(split.surplusCentavos, 0);
    expect(split.isEven, isTrue);
    expect(split.pricePerShare, 180.0);
  });

  test('an uneven split rounds the share up and surfaces the surplus', () {
    // P900 over 7 slots is 128.5714... a share. Rounded up, every student pays
    // P128.58 and the host is left holding six centavos.
    final split = CostSplit.from(totalPrice: 900, slots: 7);

    expect(split.perShareCentavos, 12858);
    expect(split.collectedCentavos, 90006);
    expect(split.surplusCentavos, 6);
    expect(split.isEven, isFalse);
    expect(split.pricePerShare, 128.58);
    expect(split.surplus, closeTo(0.06, 1e-9));
  });

  test('the shares always cover the total, by under a centavo each', () {
    // The property the whole type exists to guarantee. Swept across the real
    // input range — sub-peso amounts, everyday campus prices, and the far end
    // of what the type accepts — rather than a couple of hand-picked cases.
    final totals = <int>[
      for (var centavos = 1; centavos <= 200; centavos++) centavos,
      for (var pesos = 1; pesos <= 5000; pesos += 7) pesos * 100 + 1,
      for (var pesos = 100000; pesos <= 1000000; pesos += 33333) pesos * 100 - 1,
    ];

    for (final centavos in totals) {
      for (var slots = 2; slots <= 50; slots++) {
        final split = CostSplit.from(totalPrice: centavos / 100, slots: slots);

        expect(
          split.collectedCentavos,
          greaterThanOrEqualTo(split.totalCentavos),
          reason: 'the host must never be short: $centavos c over $slots slots',
        );
        expect(
          split.surplusCentavos,
          lessThan(slots),
          reason: 'overshoot must stay under a centavo per slot',
        );
      }
    }
  });

  test('the smallest usable deal still charges something', () {
    final split = CostSplit.from(totalPrice: 0.01, slots: 2);

    expect(split.perShareCentavos, 1);
    expect(split.surplusCentavos, 1);
  });

  test('rejects a price that rounds away to nothing', () {
    expect(
      () => CostSplit.from(totalPrice: 0.001, slots: 2),
      throwsArgumentError,
    );
    expect(() => CostSplit.from(totalPrice: 0, slots: 2), throwsArgumentError);
  });

  test('rejects a split with no slots to split across', () {
    expect(() => CostSplit.from(totalPrice: 900, slots: 0), throwsArgumentError);
  });

  test('a deal that does not divide evenly rounds its share up', () {
    final deal = Deal(
      id: 'uneven',
      hubId: 'colon',
      title: '25kg Rice Sack',
      category: DealCategory.grocery,
      totalPrice: 900,
      amount: 25,
      unit: DealUnit.kg,
      availableSlots: 7,
      totalSlots: 7,
      pickupLocation: 'USJR Main Gate',
      status: DealStatus.open,
    );

    expect(deal.pricePerShare, 128.58);
    expect(deal.priceLabel, 'P128.58/share');
    expect(deal.costSplit.surplusCentavos, 6);
  });

  test('rejects a total that is not a finite number', () {
    // double.tryParse returns these for '1e400' and 'NaN', and (x * 100).round()
    // throws UnsupportedError on both.
    expect(
      () => CostSplit.from(totalPrice: double.infinity, slots: 5),
      throwsArgumentError,
    );
    expect(
      () => CostSplit.from(totalPrice: double.nan, slots: 5),
      throwsArgumentError,
    );
  });

  test('rejects a total so large the centavo arithmetic would overflow', () {
    // (1e30 * 100).round() saturates at the int64 ceiling, and the ceiling
    // division then wraps negative — the shares would stop covering the total.
    expect(() => CostSplit.from(totalPrice: 1e30, slots: 5), throwsArgumentError);

    // The boundary itself still splits correctly.
    final atLimit = CostSplit.from(
      totalPrice: CostSplit.maxTotalPrice,
      slots: 7,
    );
    expect(atLimit.collectedCentavos, greaterThanOrEqualTo(atLimit.totalCentavos));
    expect(atLimit.perShareCentavos, greaterThan(0));
  });

  test('a malformed deal is clamped rather than left to crash the feed', () {
    // A Deal is built straight from a database row and its split is read during
    // build. Bad rows must degrade, not throw.
    const noSlots = Deal(
      id: 'no-slots',
      hubId: 'colon',
      title: 'Malformed',
      category: DealCategory.grocery,
      totalPrice: 900,
      amount: 1,
      unit: DealUnit.pieces,
      availableSlots: 0,
      totalSlots: 0,
      pickupLocation: 'USJR Main Gate',
      status: DealStatus.open,
    );
    const noPrice = Deal(
      id: 'no-price',
      hubId: 'colon',
      title: 'Malformed',
      category: DealCategory.grocery,
      totalPrice: 0,
      amount: 1,
      unit: DealUnit.pieces,
      availableSlots: 5,
      totalSlots: 5,
      pickupLocation: 'USJR Main Gate',
      status: DealStatus.open,
    );

    expect(() => noSlots.pricePerShare, returnsNormally);
    expect(() => noPrice.pricePerShare, returnsNormally);
    expect(() => noSlots.priceLabel, returnsNormally);
    expect(() => noPrice.priceLabel, returnsNormally);
  });
}

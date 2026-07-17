import 'dart:async';

import 'package:bulk_buying_companion/data/repositories/deal_repository.dart';
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:bulk_buying_companion/ui/split_board/create_deal_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validation', () {
    final viewModel = CreateDealViewModel(dealRepository: MockDealRepository());

    test('rejects a missing or too-short product name', () {
      expect(viewModel.validateTitle(null), 'Enter the product name.');
      expect(viewModel.validateTitle('   '), 'Enter the product name.');
      expect(viewModel.validateTitle('Ri'), 'Product name is too short.');
      expect(viewModel.validateTitle('25kg Rice Sack'), isNull);
    });

    test('accepts an empty description but caps its length', () {
      expect(viewModel.validateDescription(null), isNull);
      expect(viewModel.validateDescription(''), isNull);
      expect(
        viewModel.validateDescription('x' * 281),
        'Keep the description under 280 characters.',
      );
    });

    test('accepts optional payment details but caps their length', () {
      expect(viewModel.validatePaymentMethod(null), isNull);
      expect(viewModel.validatePaymentMethod('GCash'), isNull);
      expect(
        viewModel.validatePaymentMethod('x' * 41),
        'Keep the payment method under 40 characters.',
      );
      expect(
        viewModel.validatePaymentAccountName('x' * 81),
        'Keep the account name under 80 characters.',
      );
      expect(
        viewModel.validatePaymentAccountHandle('x' * 81),
        'Keep the account number or handle under 80 characters.',
      );
      expect(
        viewModel.validatePaymentInstructions('x' * 181),
        'Keep the payment instructions under 180 characters.',
      );
    });

    test('rejects a price that is not a positive number', () {
      expect(viewModel.validateTotalPrice(''), 'Enter the total price.');
      expect(
        viewModel.validateTotalPrice('abc'),
        'Total price must be a number.',
      );
      expect(
        viewModel.validateTotalPrice('0'),
        'Total price must be more than 0.',
      );
      expect(
        viewModel.validateTotalPrice('-50'),
        'Total price must be more than 0.',
      );
      expect(viewModel.validateTotalPrice('900.50'), isNull);
    });

    test('bounds the slot count at both ends', () {
      // One slot is not a split.
      expect(
        viewModel.validateTotalSlots('1', amount: '25', unit: DealUnit.kg),
        'Slots must be at least $kMinDealSlots.',
      );
      expect(
        viewModel.validateTotalSlots(
          '${kMaxDealSlots + 1}',
          amount: '25',
          unit: DealUnit.kg,
        ),
        'Keep it to $kMaxDealSlots slots or fewer.',
      );
      expect(
        viewModel.validateTotalSlots('5', amount: '25', unit: DealUnit.kg),
        isNull,
      );
    });

    test('rejects a deadline that has already passed', () {
      expect(viewModel.validateDeadline(null), isNull);
      expect(
        viewModel.validateDeadline(
          DateTime.now().subtract(const Duration(days: 1)),
        ),
        'Pick a deadline in the future.',
      );
      expect(
        viewModel.validateDeadline(DateTime.now().add(const Duration(days: 1))),
        isNull,
      );
    });

    test('previews the per-share price only once the inputs are usable', () {
      expect(
        viewModel
            .previewSplit(totalPrice: '900', totalSlots: '5')
            ?.pricePerShare,
        180,
      );
      expect(viewModel.previewSplit(totalPrice: '900', totalSlots: ''), isNull);
      expect(
        viewModel.previewSplit(totalPrice: '900', totalSlots: '0'),
        isNull,
      );
    });

    test('previews nothing rather than throwing on junk the field allows', () {
      // double.tryParse takes all three of these happily, and the centavo
      // arithmetic throws on them. previewSplit runs inside build on every
      // keystroke, so it has to hand back null instead of taking down the form.
      for (final price in ['1e400', 'Infinity', 'NaN']) {
        expect(
          viewModel.previewSplit(totalPrice: price, totalSlots: '5'),
          isNull,
          reason: '$price must not reach the split arithmetic',
        );
        expect(
          viewModel.validateTotalPrice(price),
          'Total price must be a number.',
        );
      }
    });

    test('a one-way split is not previewed, since submit would reject it', () {
      expect(
        viewModel.previewSplit(totalPrice: '900', totalSlots: '1'),
        isNull,
      );
      expect(
        viewModel.validateTotalSlots('1', amount: '25', unit: DealUnit.kg),
        isNotNull,
      );
    });

    test('a price under a centavo is rejected, not rounded up into one', () {
      // (0.005 * 100).round() is 1, so a centavo-based check would let this
      // through and store a total the split does not agree with.
      expect(
        viewModel.validateTotalPrice('0.005'),
        'Total price must be at least P0.01.',
      );
      expect(viewModel.validateTotalPrice('0.01'), isNull);
    });
  });

  test('publishes a deal with the host already holding a slot', () async {
    final repository = MockDealRepository();
    final viewModel = CreateDealViewModel(dealRepository: repository);

    final deal = await viewModel.submit(
      const DealDraft(
        hubId: 'colon',
        title: '  Cooking Oil 5L  ',
        description: 'Baguio brand',
        category: DealCategory.pantry,
        totalPrice: 750,
        amount: 5,
        unit: DealUnit.litre,
        totalSlots: 5,
        pickupLocation: '  USJR Main Gate  ',
      ),
    );

    expect(deal, isNotNull);
    expect(deal!.title, 'Cooking Oil 5L');
    expect(deal.pickupLocation, 'USJR Main Gate');
    expect(deal.status, DealStatus.open);
    // "Split 5 ways" means the host and four others -- not five strangers.
    expect(deal.totalSlots, 5);
    expect(deal.availableSlots, 4);
    expect(deal.pricePerShare, 150);
    expect(deal.priceLabel, 'P150/share');
    expect(viewModel.errorMessage, isNull);

    // The deal has to show up on the board it was posted to.
    final deals = await repository.getDeals('colon');
    expect(deals.map((deal) => deal.title), contains('Cooking Oil 5L'));
  });

  test('surfaces the failure message when publishing is refused', () async {
    final viewModel = CreateDealViewModel(
      dealRepository: _RefusingDealRepository(),
    );

    final deal = await viewModel.submit(_draft);

    expect(deal, isNull);
    expect(
      viewModel.errorMessage,
      'You do not have permission to post a deal in this hub.',
    );
    expect(viewModel.isSubmitting, isFalse);
  });

  test('falls back to a safe message on an unexpected failure', () async {
    final viewModel = CreateDealViewModel(
      dealRepository: _CrashingDealRepository(),
    );

    final deal = await viewModel.submit(_draft);

    expect(deal, isNull);
    expect(
      viewModel.errorMessage,
      'Could not publish the deal. Please try again.',
    );
  });

  test('rejects a price that rounds away to nothing', () {
    final viewModel = CreateDealViewModel(dealRepository: MockDealRepository());

    expect(
      viewModel.validateTotalPrice('0.001'),
      'Total price must be at least P0.01.',
    );
    expect(viewModel.validateTotalPrice('0.01'), isNull);
  });

  test('previews an uneven split with its surplus', () {
    final viewModel = CreateDealViewModel(dealRepository: MockDealRepository());

    final split = viewModel.previewSplit(totalPrice: '900', totalSlots: '7');

    expect(split, isNotNull);
    expect(split!.pricePerShare, 128.58);
    expect(split.surplusCentavos, 6);
    expect(split.isEven, isFalse);

    // The poster's preview and the published deal must agree.
    const published = Deal(
      id: 'published',
      hubId: 'colon',
      title: '25kg Rice Sack',
      category: DealCategory.grocery,
      totalPrice: 900,
      amount: 25,
      unit: DealUnit.kg,
      availableSlots: 7,
      totalSlots: 7,
      pickupLocation: 'USJR Main Gate',
    );
    expect(published.pricePerShare, split.pricePerShare);
  });

  test('previews nothing when the price is unusable', () {
    final viewModel = CreateDealViewModel(dealRepository: MockDealRepository());

    expect(
      viewModel.previewSplit(totalPrice: '0.001', totalSlots: '7'),
      isNull,
    );
    expect(viewModel.previewSplit(totalPrice: '900', totalSlots: '0'), isNull);
  });

  test('rejects an amount that is not a positive number', () {
    final viewModel = CreateDealViewModel(dealRepository: MockDealRepository());

    expect(viewModel.validateAmount('', DealUnit.kg), 'Enter the amount.');
    expect(
      viewModel.validateAmount('abc', DealUnit.kg),
      'Amount must be a number.',
    );
    expect(
      viewModel.validateAmount('0', DealUnit.kg),
      'Amount must be more than 0.',
    );
    expect(viewModel.validateAmount('25', DealUnit.kg), isNull);
  });

  test('countable goods must come in whole numbers', () {
    final viewModel = CreateDealViewModel(dealRepository: MockDealRepository());

    // Half a bottle is not a thing you can buy.
    expect(
      viewModel.validateAmount('24.5', DealUnit.bottles),
      'Bottles come in whole numbers.',
    );
    expect(viewModel.validateAmount('24', DealUnit.bottles), isNull);

    // Weights and volumes are happy to be fractional.
    expect(viewModel.validateAmount('25.5', DealUnit.kg), isNull);
  });

  test('refuses a slot count that cannot divide the goods', () {
    final viewModel = CreateDealViewModel(dealRepository: MockDealRepository());

    // 30 eggs across 4 slots is 7.5 eggs each, which nobody can collect.
    expect(
      viewModel.validateTotalSlots('4', amount: '30', unit: DealUnit.pieces),
      '30 pieces across 4 slots leaves 7.5 each. Try 3 or 5 slots.',
    );

    // 5 works, and so does anything else that divides 30.
    expect(
      viewModel.validateTotalSlots('5', amount: '30', unit: DealUnit.pieces),
      isNull,
    );
  });

  test('a weight divides at any slot count', () {
    final viewModel = CreateDealViewModel(dealRepository: MockDealRepository());

    expect(
      viewModel.validateTotalSlots('7', amount: '25', unit: DealUnit.kg),
      isNull,
    );
  });

  test('says plainly when goods cannot be split at all', () {
    final viewModel = CreateDealViewModel(dealRepository: MockDealRepository());

    expect(
      viewModel.validateTotalSlots('2', amount: '1', unit: DealUnit.pieces),
      'A single piece cannot be split.',
    );
  });

  test('still enforces the slot bounds', () {
    final viewModel = CreateDealViewModel(dealRepository: MockDealRepository());

    expect(
      viewModel.validateTotalSlots('1', amount: '25', unit: DealUnit.kg),
      'Slots must be at least $kMinDealSlots.',
    );
    expect(
      viewModel.validateTotalSlots(
        '${kMaxDealSlots + 1}',
        amount: '25',
        unit: DealUnit.kg,
      ),
      'Keep it to $kMaxDealSlots slots or fewer.',
    );
  });

  test('previews what each student physically gets', () {
    final viewModel = CreateDealViewModel(dealRepository: MockDealRepository());

    final share = viewModel.previewShare(
      amount: '25',
      unit: DealUnit.kg,
      totalSlots: '7',
    );

    expect(share, isNotNull);
    expect(share!.shareLabel, '3.57 kg');

    expect(
      viewModel.previewShare(amount: '', unit: DealUnit.kg, totalSlots: '7'),
      isNull,
    );
  });

  test(
    'publishing that outlives the screen does not notify after dispose',
    () async {
      final repository = _BlockedDealRepository();
      final viewModel = CreateDealViewModel(dealRepository: repository);
      var notifications = 0;
      viewModel.addListener(() => notifications += 1);

      final pending = viewModel.submit(_draft);
      await Future<void>.value();
      final beforeDispose = notifications;

      // The student leaves the screen while the deal is still in flight.
      viewModel.dispose();
      repository.complete();
      await pending;

      // A ChangeNotifier that notifies after dispose throws; nothing should have
      // reached the listener either.
      expect(notifications, beforeDispose);
    },
  );

  test('submitting after dispose is refused instead of throwing', () async {
    final viewModel = CreateDealViewModel(dealRepository: MockDealRepository());
    viewModel.dispose();

    await expectLater(viewModel.submit(_draft), completion(isNull));
  });
}

const _draft = DealDraft(
  hubId: 'colon',
  title: 'Cooking Oil 5L',
  category: DealCategory.pantry,
  totalPrice: 750,
  amount: 5,
  unit: DealUnit.litre,
  totalSlots: 5,
  pickupLocation: 'USJR Main Gate',
);

/// Holds [createDeal] open so a publish can still be in flight when the screen
/// that started it goes away.
class _BlockedDealRepository implements DealRepository {
  final _gate = Completer<Deal>();

  void complete() => _gate.complete(
    Deal(
      id: 'published',
      hubId: _draft.hubId,
      title: _draft.title,
      category: _draft.category,
      totalPrice: _draft.totalPrice,
      amount: _draft.amount,
      unit: _draft.unit,
      availableSlots: _draft.totalSlots - 1,
      totalSlots: _draft.totalSlots,
      pickupLocation: _draft.pickupLocation,
    ),
  );

  @override
  Future<List<Deal>> getDeals(String hubId) async => const [];

  @override
  Future<Deal> createDeal(DealDraft draft) => _gate.future;

  /// The default on [DealRepository]; `implements` does not inherit it.
  @override
  Stream<List<Deal>> watchDeals(String hubId) async* {
    yield await getDeals(hubId);
  }
}

class _RefusingDealRepository implements DealRepository {
  @override
  Future<List<Deal>> getDeals(String hubId) async => const [];

  @override
  Stream<List<Deal>> watchDeals(String hubId) async* {
    yield await getDeals(hubId);
  }

  @override
  Future<Deal> createDeal(DealDraft draft) {
    throw const DealFailure(
      'You do not have permission to post a deal in this hub.',
    );
  }
}

class _CrashingDealRepository implements DealRepository {
  @override
  Future<List<Deal>> getDeals(String hubId) async => const [];

  @override
  Stream<List<Deal>> watchDeals(String hubId) async* {
    yield await getDeals(hubId);
  }

  @override
  Future<Deal> createDeal(DealDraft draft) {
    throw StateError('deals table unavailable');
  }
}

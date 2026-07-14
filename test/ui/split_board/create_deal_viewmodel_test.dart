import 'package:bulk_buying_companion/data/repositories/deal_repository.dart';
import 'package:bulk_buying_companion/models/deal.dart';
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

    test('requires a whole quantity of at least one', () {
      expect(viewModel.validateQuantity('0'), 'Quantity must be at least 1.');
      expect(
        viewModel.validateQuantity('2.5'),
        'Quantity must be a whole number.',
      );
      expect(viewModel.validateQuantity('24'), isNull);
    });

    test('bounds the slot count at both ends', () {
      // One slot is not a split.
      expect(
        viewModel.validateTotalSlots('1'),
        'Slots must be at least $kMinDealSlots.',
      );
      expect(
        viewModel.validateTotalSlots('${kMaxDealSlots + 1}'),
        'Keep it to $kMaxDealSlots slots or fewer.',
      );
      expect(viewModel.validateTotalSlots('5'), isNull);
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
        viewModel.previewSplit(totalPrice: '900', totalSlots: '5')?.pricePerShare,
        180,
      );
      expect(
        viewModel.previewSplit(totalPrice: '900', totalSlots: ''),
        isNull,
      );
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
      expect(viewModel.previewSplit(totalPrice: '900', totalSlots: '1'), isNull);
      expect(viewModel.validateTotalSlots('1'), isNotNull);
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
        quantity: 1,
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
      quantity: 1,
      availableSlots: 7,
      totalSlots: 7,
      pickupLocation: 'USJR Main Gate',
      status: DealStatus.open,
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
}

const _draft = DealDraft(
  hubId: 'colon',
  title: 'Cooking Oil 5L',
  category: DealCategory.pantry,
  totalPrice: 750,
  quantity: 1,
  totalSlots: 5,
  pickupLocation: 'USJR Main Gate',
);

class _RefusingDealRepository implements DealRepository {
  @override
  Future<List<Deal>> getDeals(String hubId) async => const [];

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
  Future<Deal> createDeal(DealDraft draft) {
    throw StateError('deals table unavailable');
  }
}

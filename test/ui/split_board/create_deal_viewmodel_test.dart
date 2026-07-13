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
        viewModel.previewPricePerShare(totalPrice: '900', totalSlots: '5'),
        180,
      );
      expect(
        viewModel.previewPricePerShare(totalPrice: '900', totalSlots: ''),
        isNull,
      );
      expect(
        viewModel.previewPricePerShare(totalPrice: '900', totalSlots: '0'),
        isNull,
      );
    });
  });

  test('publishes a deal with every slot still open', () async {
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
    expect(deal.availableSlots, 5);
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

import 'package:bulk_buying_companion/data/repositories/deal_repository.dart';
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:bulk_buying_companion/ui/split_board/split_board_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads the deals for its hub on construction', () async {
    final repository = _FakeDealRepository({
      'colon': const [
        _StubDeal(id: 'a', title: 'Rice Sack'),
        _StubDeal(id: 'b', title: 'Water Case'),
      ],
    });
    final viewModel = SplitBoardViewModel(
      dealRepository: repository,
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );

    expect(viewModel.isLoading, isTrue);
    expect(viewModel.hubName, 'Colon Street Hub');
    await Future<void>.value();

    expect(viewModel.isLoading, isFalse);
    expect(viewModel.deals, hasLength(2));
    expect(viewModel.deals.first.title, 'Rice Sack');
  });

  test('exposes an empty list for a hub with no deals', () async {
    final viewModel = SplitBoardViewModel(
      dealRepository: _FakeDealRepository(const {}),
      hubId: 'empty',
      hubName: 'Empty Hub',
    );
    await Future<void>.value();

    expect(viewModel.deals, isEmpty);
    expect(viewModel.hasError, isFalse);
  });

  test('refresh re-fetches the hub deals', () async {
    final repository = _FakeDealRepository({
      'colon': const [_StubDeal(id: 'a', title: 'Rice Sack')],
    });
    final viewModel = SplitBoardViewModel(
      dealRepository: repository,
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );
    await Future<void>.value();
    expect(repository.getDealsCalls, 1);

    await viewModel.refresh();

    expect(repository.getDealsCalls, 2);
  });

  test('flags an error when loading fails, then recovers on refresh', () async {
    final repository = _FakeDealRepository({
      'colon': const [_StubDeal(id: 'a', title: 'Rice Sack')],
    }, failFirstCall: true);
    final viewModel = SplitBoardViewModel(
      dealRepository: repository,
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );
    await Future<void>.value();

    expect(viewModel.hasError, isTrue);
    expect(viewModel.deals, isEmpty);

    await viewModel.refresh();

    expect(viewModel.hasError, isFalse);
    expect(viewModel.deals, hasLength(1));
  });

  test('filters loaded deals by product name', () async {
    final viewModel = SplitBoardViewModel(
      dealRepository: _FakeDealRepository({
        'colon': [
          _StubDeal(id: 'a', title: 'Rice Sack'),
          _StubDeal(id: 'b', title: 'Water Case'),
        ],
      }),
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );
    await Future<void>.value();

    viewModel.updateSearchQuery('rice');

    expect(viewModel.filteredDeals, hasLength(1));
    expect(viewModel.filteredDeals.single.title, 'Rice Sack');
  });

  test('filters loaded deals by category and status', () async {
    final viewModel = SplitBoardViewModel(
      dealRepository: _FakeDealRepository({
        'colon': [
          _StubDeal(
            id: 'a',
            title: 'Rice Sack',
            category: DealCategory.grocery,
            status: DealStatus.open,
          ),
          _StubDeal(
            id: 'b',
            title: 'Laundry Detergent',
            category: DealCategory.household,
            status: DealStatus.full,
          ),
          _StubDeal(
            id: 'c',
            title: 'Water Case',
            category: DealCategory.grocery,
            status: DealStatus.full,
          ),
        ],
      }),
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );
    await Future<void>.value();

    viewModel.updateCategoryFilter(DealCategory.grocery);
    viewModel.updateStatusFilter(DealStatus.full);

    expect(viewModel.filteredDeals, hasLength(1));
    expect(viewModel.filteredDeals.single.title, 'Water Case');
  });

  test('sorts loaded deals by deadline or price', () async {
    final viewModel = SplitBoardViewModel(
      dealRepository: _FakeDealRepository({
        'colon': [
          _StubDeal(
            id: 'a',
            title: 'Rice Sack',
            totalPrice: 4800, // P1,200/share
            closesAt: DateTime(2026, 7, 14),
          ),
          _StubDeal(
            id: 'b',
            title: 'Water Case',
            totalPrice: 380, // P95/share
            closesAt: DateTime(2026, 7, 16),
          ),
          _StubDeal(
            id: 'c',
            title: 'Coffee Pack',
            totalPrice: 600, // P150/share
            closesAt: DateTime(2026, 7, 15),
          ),
        ],
      }),
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );
    await Future<void>.value();

    viewModel.updateSortOption(DealSortOption.deadline);

    expect(viewModel.filteredDeals.map((deal) => deal.title), [
      'Rice Sack',
      'Coffee Pack',
      'Water Case',
    ]);

    viewModel.updateSortOption(DealSortOption.price);

    expect(viewModel.filteredDeals.map((deal) => deal.title), [
      'Water Case',
      'Coffee Pack',
      'Rice Sack',
    ]);
  });

  test('sorts by price on the real per-share number, not a formatted string', () async {
    // 100 / 3 rounds up to P33.34/share; 100 / 4 is an exact P25.00/share.
    // A regex over the formatted label would still parse both correctly, so
    // this is a regression guard for the refactor away from that regex.
    final viewModel = SplitBoardViewModel(
      dealRepository: _FakeDealRepository({
        'colon': [
          const Deal(
            id: 'thirds',
            hubId: 'colon',
            title: 'Thirds Deal',
            category: DealCategory.grocery,
            totalPrice: 100,
            amount: 1,
            unit: DealUnit.kg,
            availableSlots: 1,
            totalSlots: 3,
            pickupLocation: 'Campus Gate',
            status: DealStatus.open,
          ),
          const Deal(
            id: 'quarters',
            hubId: 'colon',
            title: 'Quarters Deal',
            category: DealCategory.grocery,
            totalPrice: 100,
            amount: 1,
            unit: DealUnit.kg,
            availableSlots: 1,
            totalSlots: 4,
            pickupLocation: 'Campus Gate',
            status: DealStatus.open,
          ),
        ],
      }),
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );
    await Future<void>.value();

    viewModel.updateSortOption(DealSortOption.price);

    expect(viewModel.filteredDeals.map((deal) => deal.id), [
      'quarters',
      'thirds',
    ]);
  });

  test('replaces a deal when its slot count changes', () async {
    const rice = Deal(
      id: 'rice',
      hubId: 'colon',
      title: 'Rice Sack',
      category: DealCategory.grocery,
      totalPrice: 400,
      amount: 1,
      unit: DealUnit.kg,
      availableSlots: 4,
      totalSlots: 5,
      pickupLocation: 'Campus Gate',
      status: DealStatus.open,
    );
    final viewModel = SplitBoardViewModel(
      dealRepository: _FakeDealRepository({
        'colon': const [rice],
      }),
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );
    await pumpEventQueue();

    viewModel.replaceDeal(
      const Deal(
        id: 'rice',
        hubId: 'colon',
        title: 'Rice Sack',
        category: DealCategory.grocery,
        totalPrice: 400,
        amount: 1,
        unit: DealUnit.kg,
        availableSlots: 3,
        totalSlots: 5,
        pickupLocation: 'Campus Gate',
        status: DealStatus.open,
      ),
    );

    expect(viewModel.filteredDeals.single.availableSlots, 3);
  });
}

/// Every stub splits 4 ways, so totalPrice / 4 is the per-share price the
/// board sorts and renders: 400 -> 'P100/share'.
class _StubDeal extends Deal {
  const _StubDeal({
    required super.id,
    required super.title,
    super.category = DealCategory.grocery,
    super.totalPrice = 400,
    super.status = DealStatus.open,
    super.closesAt,
  }) : super(
         hubId: 'colon',
         amount: 1,
         unit: DealUnit.kg,
         availableSlots: 1,
         totalSlots: 4,
         pickupLocation: 'Campus Gate',
       );
}

class _FakeDealRepository implements DealRepository {
  _FakeDealRepository(this._dealsByHub, {this.failFirstCall = false});

  final Map<String, List<Deal>> _dealsByHub;
  final bool failFirstCall;
  int getDealsCalls = 0;

  @override
  Future<List<Deal>> getDeals(String hubId) async {
    getDealsCalls++;
    if (failFirstCall && getDealsCalls == 1) {
      throw Exception('network error');
    }
    return _dealsByHub[hubId] ?? const [];
  }

  @override
  Future<Deal> createDeal(DealDraft draft) {
    throw UnimplementedError();
  }
}

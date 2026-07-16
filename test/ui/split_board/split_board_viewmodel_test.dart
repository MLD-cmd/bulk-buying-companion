import 'dart:async';

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
    expect(viewModel.refreshErrorMessage, isNull);
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
    expect(viewModel.refreshErrorMessage, isNull);

    await viewModel.refresh();

    expect(viewModel.hasError, isFalse);
    expect(viewModel.deals, hasLength(1));
    expect(viewModel.refreshErrorMessage, isNull);
  });

  test(
    'failed refresh preserves cached deals and every board control',
    () async {
      const cachedDeals = <Deal>[
        _StubDeal(id: 'a', title: 'Rice Sack'),
        _StubDeal(id: 'b', title: 'Water Case'),
      ];
      final repository = _SequencedDealRepository([
        () async => cachedDeals,
        () async => throw StateError('offline'),
      ]);
      final viewModel = SplitBoardViewModel(
        dealRepository: repository,
        hubId: 'colon',
        hubName: 'Colon Street Hub',
      );
      await pumpEventQueue();
      viewModel.updateSearchQuery('rice');
      viewModel.updateCategoryFilter(DealCategory.grocery);
      viewModel.updateStatusFilter(DealStatus.open);
      viewModel.updateSortOption(DealSortOption.price);
      final dealsBeforeRefresh = viewModel.deals;

      await viewModel.refresh();

      expect(viewModel.deals, same(dealsBeforeRefresh));
      expect(viewModel.deals, same(cachedDeals));
      expect(viewModel.hasError, isFalse);
      expect(
        viewModel.refreshErrorMessage,
        'Couldn’t refresh deals. Showing the deals already loaded.',
      );
      expect(viewModel.searchQuery, 'rice');
      expect(viewModel.categoryFilter, DealCategory.grocery);
      expect(viewModel.statusFilter, DealStatus.open);
      expect(viewModel.sortOption, DealSortOption.price);
    },
  );

  test('refresh exposes progress and coalesces duplicate requests', () async {
    final refreshResponse = Completer<List<Deal>>();
    final repository = _SequencedDealRepository([
      () async => const [_StubDeal(id: 'a', title: 'Rice Sack')],
      () => refreshResponse.future,
    ]);
    final viewModel = SplitBoardViewModel(
      dealRepository: repository,
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );
    await pumpEventQueue();

    final firstRefresh = viewModel.refresh();
    final duplicateRefresh = viewModel.refresh();

    expect(viewModel.isRefreshing, isTrue);
    expect(repository.getDealsCalls, 2);
    expect(duplicateRefresh, same(firstRefresh));

    refreshResponse.complete(const [_StubDeal(id: 'b', title: 'Water Case')]);
    await firstRefresh;
    expect(viewModel.isRefreshing, isFalse);
    expect(viewModel.deals.single.id, 'b');
  });

  test(
    'successful retry replaces cached deals and clears refresh error',
    () async {
      const replacement = <Deal>[_StubDeal(id: 'b', title: 'Water Case')];
      final repository = _SequencedDealRepository([
        () async => const [_StubDeal(id: 'a', title: 'Rice Sack')],
        () async => throw StateError('offline'),
        () async => replacement,
      ]);
      final viewModel = SplitBoardViewModel(
        dealRepository: repository,
        hubId: 'colon',
        hubName: 'Colon Street Hub',
      );
      await pumpEventQueue();
      await viewModel.refresh();
      expect(viewModel.refreshErrorMessage, isNotNull);

      await viewModel.refresh();

      expect(viewModel.deals, same(replacement));
      expect(viewModel.refreshErrorMessage, isNull);
      expect(viewModel.hasError, isFalse);
    },
  );

  test('stale initial load cannot overwrite a newer refresh', () async {
    final initialResponse = Completer<List<Deal>>();
    final refreshResponse = Completer<List<Deal>>();
    final repository = _SequencedDealRepository([
      () => initialResponse.future,
      () => refreshResponse.future,
    ]);
    final viewModel = SplitBoardViewModel(
      dealRepository: repository,
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );

    final refresh = viewModel.refresh();
    refreshResponse.complete(const [
      _StubDeal(id: 'new', title: 'Newest deals'),
    ]);
    await refresh;
    expect(viewModel.deals.single.id, 'new');

    initialResponse.complete(const [
      _StubDeal(id: 'old', title: 'Stale deals'),
    ]);
    await pumpEventQueue();

    expect(viewModel.deals.single.id, 'new');
    expect(viewModel.isLoading, isFalse);
    expect(viewModel.isRefreshing, isFalse);
  });

  test('initial load completion is safe after disposal', () async {
    final initialResponse = Completer<List<Deal>>();
    final viewModel = SplitBoardViewModel(
      dealRepository: _SequencedDealRepository([() => initialResponse.future]),
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );
    var notifications = 0;
    viewModel.addListener(() => notifications++);

    viewModel.dispose();
    initialResponse.complete(const [_StubDeal(id: 'late', title: 'Late deal')]);
    await pumpEventQueue();

    expect(notifications, 0);
  });

  test('refresh future finishes safely after disposal', () async {
    final refreshResponse = Completer<List<Deal>>();
    final viewModel = SplitBoardViewModel(
      dealRepository: _SequencedDealRepository([
        () async => const [_StubDeal(id: 'a', title: 'Rice Sack')],
        () => refreshResponse.future,
      ]),
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );
    await pumpEventQueue();

    final refresh = viewModel.refresh();
    viewModel.dispose();
    refreshResponse.complete(const [_StubDeal(id: 'b', title: 'Water Case')]);

    await expectLater(refresh, completes);
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
          ),
          _StubDeal(
            id: 'b',
            title: 'Laundry Detergent',
            category: DealCategory.household,
            availableSlots: 0,
          ),
          _StubDeal(
            id: 'c',
            title: 'Water Case',
            category: DealCategory.grocery,
            availableSlots: 0,
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

  test('hides finished deals unless they are asked for by name', () async {
    final viewModel = SplitBoardViewModel(
      dealRepository: _FakeDealRepository({
        'colon': [
          const _StubDeal(id: 'a', title: 'Rice Sack'),
          _StubDeal(
            id: 'b',
            title: 'Water Case',
            cancelledAt: DateTime(2026, 7, 16),
          ),
        ],
      }),
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );
    await Future<void>.value();

    expect(viewModel.filteredDeals.map((deal) => deal.id), ['a']);

    viewModel.updateStatusFilter(DealStatus.cancelled);

    expect(viewModel.filteredDeals.map((deal) => deal.id), ['b']);
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

  test(
    'sorts by price on the real per-share number, not a formatted string',
    () async {
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
    },
  );

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
    // Two of four slots left, so the stubs stay Open and these tests stay about
    // sorting and filtering. One of four is a quarter, which would make every
    // stub read "Filling fast".
    super.availableSlots = 2,
    super.cancelledAt,
    super.closesAt,
  }) : super(
         hubId: 'colon',
         amount: 1,
         unit: DealUnit.kg,
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

class _SequencedDealRepository implements DealRepository {
  _SequencedDealRepository(this._responses);

  final List<Future<List<Deal>> Function()> _responses;
  int getDealsCalls = 0;

  @override
  Future<List<Deal>> getDeals(String hubId) {
    return _responses[getDealsCalls++]();
  }

  @override
  Future<Deal> createDeal(DealDraft draft) {
    throw UnimplementedError();
  }
}

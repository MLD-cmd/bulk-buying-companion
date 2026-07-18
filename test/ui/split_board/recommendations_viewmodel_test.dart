import 'dart:async';

import 'package:bulk_buying_companion/data/repositories/deal_repository.dart';
import 'package:bulk_buying_companion/data/repositories/recommendation_repository.dart';
import 'package:bulk_buying_companion/data/repositories/reservation_repository.dart';
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:bulk_buying_companion/models/reservation.dart';
import 'package:bulk_buying_companion/ui/split_board/recommendations_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

Deal _deal({
  required String id,
  DealCategory category = DealCategory.grocery,
  int availableSlots = 3,
  String createdBy = 'host',
}) {
  return Deal(
    id: id,
    hubId: 'colon',
    title: 'Deal $id',
    category: category,
    totalPrice: 400,
    amount: 4,
    unit: DealUnit.kg,
    availableSlots: availableSlots,
    totalSlots: 4,
    pickupLocation: 'Gate',
    createdBy: createdBy,
    paidCount: 1,
  );
}

class _FakeDealRepository extends DealRepository {
  _FakeDealRepository(this._deals);

  final List<Deal> _deals;
  final _controller = StreamController<List<Deal>>.broadcast();

  @override
  Future<List<Deal>> getDeals(String hubId) async => _deals;

  @override
  Stream<List<Deal>> watchDeals(String hubId) async* {
    yield _deals;
    yield* _controller.stream;
  }

  @override
  Future<Deal> createDeal(DealDraft draft) => throw UnimplementedError();
}

class _FakeReservationRepository
    implements ReservationRepository, BatchReservationRepository {
  _FakeReservationRepository({this.heldDealIds = const {}});

  final Set<String> heldDealIds;

  @override
  Future<Set<String>> getDealIdsWithSlotFor(
    String userId,
    List<String> dealIds,
  ) async {
    return heldDealIds.intersection(dealIds.toSet());
  }

  @override
  Future<List<Reservation>> getParticipants(String dealId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A recommendation repository that refuses every dismissal, so the ViewModel's
/// rollback-and-report path can be exercised.
class _FailingDismissRepository extends MockRecommendationRepository {
  _FailingDismissRepository({super.preferredCategories});

  @override
  Future<void> dismissDeal(String userId, String dealId) async {
    throw const RecommendationFailure('offline');
  }
}

void main() {
  test('recommends open deals in a preferred category', () async {
    final viewModel = RecommendationsViewModel(
      dealRepository: _FakeDealRepository([
        _deal(id: 'grocery', category: DealCategory.grocery),
        _deal(id: 'household', category: DealCategory.household),
      ]),
      reservationRepository: _FakeReservationRepository(),
      recommendationRepository: MockRecommendationRepository(
        preferredCategories: {DealCategory.grocery},
      ),
      userId: 'me',
      hubId: 'colon',
    );
    addTearDown(viewModel.dispose);

    await pumpEventQueue();

    expect(viewModel.isLoading, isFalse);
    expect(viewModel.recommendations.map((r) => r.deal.id), ['grocery']);
  });

  test('excludes a deal the student already holds a slot in', () async {
    final viewModel = RecommendationsViewModel(
      dealRepository: _FakeDealRepository([
        _deal(id: 'joined', category: DealCategory.grocery),
        _deal(id: 'open', category: DealCategory.grocery),
      ]),
      reservationRepository: _FakeReservationRepository(
        heldDealIds: {'joined'},
      ),
      recommendationRepository: MockRecommendationRepository(
        preferredCategories: {DealCategory.grocery},
      ),
      userId: 'me',
      hubId: 'colon',
    );
    addTearDown(viewModel.dispose);

    await pumpEventQueue();

    expect(viewModel.recommendations.map((r) => r.deal.id), ['open']);
  });

  test('dismiss removes the deal and persists it', () async {
    final recommendationRepository = MockRecommendationRepository(
      preferredCategories: {DealCategory.grocery},
    );
    final viewModel = RecommendationsViewModel(
      dealRepository: _FakeDealRepository([
        _deal(id: 'grocery', category: DealCategory.grocery),
      ]),
      reservationRepository: _FakeReservationRepository(),
      recommendationRepository: recommendationRepository,
      userId: 'me',
      hubId: 'colon',
    );
    addTearDown(viewModel.dispose);

    await pumpEventQueue();
    expect(viewModel.recommendations, hasLength(1));

    await viewModel.dismiss('grocery');

    expect(viewModel.recommendations, isEmpty);
    expect(await recommendationRepository.getDismissedDealIds('me'), {
      'grocery',
    });
  });

  test('a failed dismiss restores the deal and reports the error', () async {
    final viewModel = RecommendationsViewModel(
      dealRepository: _FakeDealRepository([
        _deal(id: 'grocery', category: DealCategory.grocery),
      ]),
      reservationRepository: _FakeReservationRepository(),
      recommendationRepository: _FailingDismissRepository(
        preferredCategories: {DealCategory.grocery},
      ),
      userId: 'me',
      hubId: 'colon',
    );
    addTearDown(viewModel.dispose);

    await pumpEventQueue();
    expect(viewModel.recommendations, hasLength(1));

    await viewModel.dismiss('grocery');

    // The card comes back, and the message is left for the screen to surface.
    expect(viewModel.recommendations.map((r) => r.deal.id), ['grocery']);
    expect(viewModel.dismissErrorMessage, isNotNull);
  });

  test('exposes the student preferred categories', () async {
    final viewModel = RecommendationsViewModel(
      dealRepository: _FakeDealRepository(const []),
      reservationRepository: _FakeReservationRepository(),
      recommendationRepository: MockRecommendationRepository(
        preferredCategories: {DealCategory.pantry},
      ),
      userId: 'me',
      hubId: 'colon',
    );
    addTearDown(viewModel.dispose);

    await pumpEventQueue();

    expect(viewModel.preferredCategories, {DealCategory.pantry});
  });

  test('editing preferences updates the live recommendations', () async {
    final recommendationRepository = MockRecommendationRepository();
    final viewModel = RecommendationsViewModel(
      dealRepository: _FakeDealRepository([
        _deal(id: 'drinks', category: DealCategory.drinks),
      ]),
      reservationRepository: _FakeReservationRepository(),
      recommendationRepository: recommendationRepository,
      userId: 'me',
      hubId: 'colon',
    );
    addTearDown(viewModel.dispose);

    await pumpEventQueue();
    expect(viewModel.recommendations, isEmpty);

    await recommendationRepository.setPreferredCategories('me', {
      DealCategory.drinks,
    });
    await pumpEventQueue();

    expect(viewModel.recommendations.map((r) => r.deal.id), ['drinks']);
  });
}

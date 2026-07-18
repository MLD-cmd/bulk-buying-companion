import 'dart:async';

import 'package:bulk_buying_companion/data/repositories/deal_repository.dart';
import 'package:bulk_buying_companion/data/repositories/recommendation_repository.dart';
import 'package:bulk_buying_companion/data/repositories/reservation_repository.dart';
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:bulk_buying_companion/models/reservation.dart';
import 'package:bulk_buying_companion/ui/split_board/recommendations_viewmodel.dart';
import 'package:bulk_buying_companion/ui/split_board/split_board_screen.dart';
import 'package:bulk_buying_companion/ui/split_board/split_board_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Deal _deal(String id, {DealCategory category = DealCategory.grocery}) => Deal(
  id: id,
  hubId: 'colon',
  title: 'Deal $id',
  category: category,
  totalPrice: 400,
  amount: 4,
  unit: DealUnit.kg,
  availableSlots: 3,
  totalSlots: 4,
  pickupLocation: 'Gate',
  createdBy: 'host',
  paidCount: 1,
);

class _FakeDealRepository implements DealRepository {
  _FakeDealRepository(this._deals);

  final List<Deal> _deals;

  @override
  Future<List<Deal>> getDeals(String hubId) async => _deals;

  @override
  Stream<List<Deal>> watchDeals(String hubId) async* {
    yield _deals;
  }

  @override
  Future<Deal> createDeal(DealDraft draft) => throw UnimplementedError();
}

class _FakeReservationRepository
    implements ReservationRepository, BatchReservationRepository {
  @override
  Future<Set<String>> getDealIdsWithSlotFor(
    String userId,
    List<String> dealIds,
  ) async => const <String>{};

  @override
  Future<List<Reservation>> getParticipants(String dealId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingDismissRepository extends MockRecommendationRepository {
  _FailingDismissRepository({super.preferredCategories});

  @override
  Future<void> dismissDeal(String userId, String dealId) async {
    throw const RecommendationFailure('offline');
  }
}

Future<void> _pumpBoard(
  WidgetTester tester, {
  required List<Deal> deals,
  required RecommendationRepository recommendationRepository,
}) async {
  final splitBoard = SplitBoardViewModel(
    dealRepository: _FakeDealRepository(deals),
    hubId: 'colon',
    hubName: 'Colon Street Hub',
  );
  addTearDown(splitBoard.dispose);

  final recommendations = RecommendationsViewModel(
    dealRepository: _FakeDealRepository(deals),
    reservationRepository: _FakeReservationRepository(),
    recommendationRepository: recommendationRepository,
    userId: 'me',
    hubId: 'colon',
  );
  addTearDown(recommendations.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SplitBoardViewModel>.value(value: splitBoard),
        ChangeNotifierProvider<RecommendationsViewModel?>.value(
          value: recommendations,
        ),
      ],
      child: const MaterialApp(home: SplitBoardScreen(hubId: 'colon')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a nudge when the student has no preferred categories', (
    tester,
  ) async {
    await _pumpBoard(
      tester,
      deals: [_deal('rice')],
      recommendationRepository: MockRecommendationRepository(),
    );

    expect(find.byKey(const Key('recommendations-empty-hint')), findsOneWidget);
    expect(
      find.textContaining('Set your preferred categories'),
      findsOneWidget,
    );
  });

  testWidgets('renders the strip when there are picks', (tester) async {
    await _pumpBoard(
      tester,
      deals: [_deal('rice', category: DealCategory.grocery)],
      recommendationRepository: MockRecommendationRepository(
        preferredCategories: {DealCategory.grocery},
      ),
    );

    expect(find.byKey(const Key('recommended-deals-section')), findsOneWidget);
    expect(find.byKey(const Key('recommendations-empty-hint')), findsNothing);
  });

  testWidgets('a failed dismiss surfaces a SnackBar', (tester) async {
    await _pumpBoard(
      tester,
      deals: [_deal('rice', category: DealCategory.grocery)],
      recommendationRepository: _FailingDismissRepository(
        preferredCategories: {DealCategory.grocery},
      ),
    );

    await tester.tap(find.byKey(const Key('recommendation-dismiss-rice')));
    await tester.pump();
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.text("Couldn't dismiss that deal. Please try again."),
      findsOneWidget,
    );
    // The card is restored by the ViewModel, so it is still on screen.
    expect(find.byKey(const Key('recommendation-card-rice')), findsOneWidget);
  });
}

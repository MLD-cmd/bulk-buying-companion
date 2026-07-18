import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_recommendation.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:flutter_test/flutter_test.dart';

Deal _deal({
  required String id,
  DealCategory category = DealCategory.grocery,
  int availableSlots = 3,
  int totalSlots = 4,
  DateTime? closesAt,
  String? createdBy = 'someone-else',
  DateTime? purchasedAt,
  DateTime? cancelledAt,
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
    totalSlots: totalSlots,
    pickupLocation: 'Gate',
    createdBy: createdBy,
    closesAt: closesAt,
    purchasedAt: purchasedAt,
    cancelledAt: cancelledAt,
    // A slot claimed by the host means participants exist; paidCount 1 keeps a
    // full deal from tipping into "ready to purchase".
    paidCount: 1,
  );
}

void main() {
  const recommender = DealRecommender();

  group('DealRecommender', () {
    test('surfaces deals in a preferred category', () {
      final recommendations = recommender.rank(
        deals: [
          _deal(id: 'a', category: DealCategory.grocery),
          _deal(id: 'b', category: DealCategory.household),
        ],
        preferredCategories: {DealCategory.grocery},
      );

      expect(recommendations, hasLength(1));
      expect(recommendations.single.deal.id, 'a');
      expect(recommendations.single.reason, 'Matches your interest in Grocery');
    });

    test('preference outranks join history', () {
      final recommendations = recommender.rank(
        deals: [
          _deal(id: 'preferred', category: DealCategory.grocery),
          _deal(id: 'joined', category: DealCategory.drinks),
        ],
        preferredCategories: {DealCategory.grocery},
        joinedCategoryCounts: const {DealCategory.drinks: 3},
      );

      expect(recommendations.first.deal.id, 'preferred');
    });

    test('recommends a category the student has joined before', () {
      final recommendations = recommender.rank(
        deals: [_deal(id: 'a', category: DealCategory.drinks)],
        preferredCategories: const {},
        joinedCategoryCounts: const {DealCategory.drinks: 2},
      );

      expect(recommendations, hasLength(1));
      expect(
        recommendations.single.reason,
        "You've joined Drinks deals before",
      );
    });

    test('drops deals with no signal at all', () {
      final recommendations = recommender.rank(
        deals: [_deal(id: 'a', category: DealCategory.pantry)],
        preferredCategories: {DealCategory.grocery},
      );

      expect(recommendations, isEmpty);
    });

    test('never recommends dismissed, excluded, or non-open deals', () {
      final recommendations = recommender.rank(
        deals: [
          _deal(id: 'dismissed', category: DealCategory.grocery),
          _deal(id: 'joined', category: DealCategory.grocery),
          _deal(id: 'full', category: DealCategory.grocery, availableSlots: 0),
          _deal(
            id: 'cancelled',
            category: DealCategory.grocery,
            cancelledAt: DateTime(2026, 7, 1),
          ),
          _deal(id: 'ok', category: DealCategory.grocery),
        ],
        preferredCategories: {DealCategory.grocery},
        dismissedDealIds: {'dismissed'},
        excludedDealIds: {'joined'},
      );

      expect(recommendations.map((r) => r.deal.id), ['ok']);
    });

    test('breaks score ties by the sooner deadline', () {
      final recommendations = recommender.rank(
        deals: [
          _deal(
            id: 'later',
            category: DealCategory.grocery,
            closesAt: DateTime(2026, 8, 1),
          ),
          _deal(
            id: 'sooner',
            category: DealCategory.grocery,
            closesAt: DateTime(2026, 7, 20),
          ),
        ],
        preferredCategories: {DealCategory.grocery},
      );

      expect(recommendations.map((r) => r.deal.id), ['sooner', 'later']);
    });

    test('caps the number of recommendations', () {
      const limited = DealRecommender(maxRecommendations: 2);
      final recommendations = limited.rank(
        deals: [
          for (var i = 0; i < 5; i++)
            _deal(
              id: 'deal-$i',
              category: DealCategory.grocery,
              closesAt: DateTime(2026, 7, 20 + i),
            ),
        ],
        preferredCategories: {DealCategory.grocery},
      );

      expect(recommendations, hasLength(2));
    });
  });

  group('joinedCategoryCounts', () {
    test('counts hosted deals and held slots by category', () {
      final counts = joinedCategoryCounts(
        deals: [
          _deal(id: 'hosted', category: DealCategory.grocery, createdBy: 'me'),
          _deal(id: 'held', category: DealCategory.drinks),
          _deal(id: 'other', category: DealCategory.pantry),
        ],
        userId: 'me',
        heldDealIds: {'held'},
      );

      expect(counts, {DealCategory.grocery: 1, DealCategory.drinks: 1});
    });
  });
}

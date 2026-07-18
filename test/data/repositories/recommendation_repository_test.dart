import 'package:bulk_buying_companion/data/repositories/recommendation_repository.dart';
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeGateway implements SupabaseRecommendationGateway {
  _FakeGateway({this.storedCategories = const [], this.throwOnWrite});

  List<String> storedCategories;
  List<String> storedDismissed = const [];
  PostgrestException? throwOnWrite;

  List<String>? lastWrittenCategories;

  @override
  Future<List<String>> getPreferredCategories(String userId) async =>
      storedCategories;

  @override
  Future<void> setPreferredCategories(
    String userId,
    List<String> categories,
  ) async {
    if (throwOnWrite != null) throw throwOnWrite!;
    lastWrittenCategories = categories;
    storedCategories = categories;
  }

  @override
  Future<List<String>> getDismissedDealIds(String userId) async =>
      storedDismissed;

  @override
  Future<void> dismissDeal(String userId, String dealId) async {
    if (throwOnWrite != null) throw throwOnWrite!;
    storedDismissed = [...storedDismissed, dealId];
  }
}

void main() {
  group('MockRecommendationRepository', () {
    test('watch emits current preferences then every saved change', () async {
      final repository = MockRecommendationRepository(
        preferredCategories: {DealCategory.grocery},
      );
      addTearDown(repository.dispose);

      final emissions = <Set<DealCategory>>[];
      final sub = repository
          .watchPreferredCategories('me')
          .listen(emissions.add);
      await Future<void>.delayed(Duration.zero);

      await repository.setPreferredCategories('me', {DealCategory.drinks});
      await Future<void>.delayed(Duration.zero);

      expect(emissions, [
        {DealCategory.grocery},
        {DealCategory.drinks},
      ]);
      await sub.cancel();
    });

    test('records dismissals', () async {
      final repository = MockRecommendationRepository();
      addTearDown(repository.dispose);

      await repository.dismissDeal('me', 'deal-1');

      expect(await repository.getDismissedDealIds('me'), {'deal-1'});
    });
  });

  group('SupabaseRecommendationRepository', () {
    test('maps stored category names to enum values', () async {
      final repository = SupabaseRecommendationRepository(
        gateway: _FakeGateway(storedCategories: ['grocery', 'drinks']),
      );
      addTearDown(repository.dispose);

      expect(await repository.getPreferredCategories('me'), {
        DealCategory.grocery,
        DealCategory.drinks,
      });
    });

    test('ignores category names the app no longer knows', () async {
      final repository = SupabaseRecommendationRepository(
        gateway: _FakeGateway(storedCategories: ['grocery', 'meat']),
      );
      addTearDown(repository.dispose);

      expect(await repository.getPreferredCategories('me'), {
        DealCategory.grocery,
      });
    });

    test('writes category names and notifies watchers', () async {
      final gateway = _FakeGateway();
      final repository = SupabaseRecommendationRepository(gateway: gateway);
      addTearDown(repository.dispose);

      final emissions = <Set<DealCategory>>[];
      final sub = repository
          .watchPreferredCategories('me')
          .listen(emissions.add);
      await Future<void>.delayed(Duration.zero);

      await repository.setPreferredCategories('me', {
        DealCategory.pantry,
        DealCategory.household,
      });
      await Future<void>.delayed(Duration.zero);

      expect(
        gateway.lastWrittenCategories,
        containsAll(['pantry', 'household']),
      );
      expect(emissions.last, {DealCategory.pantry, DealCategory.household});
      await sub.cancel();
    });

    test('translates a permission error into a user-facing message', () async {
      final repository = SupabaseRecommendationRepository(
        gateway: _FakeGateway(
          throwOnWrite: const PostgrestException(
            message: 'denied',
            code: '42501',
          ),
        ),
      );
      addTearDown(repository.dispose);

      expect(
        () => repository.setPreferredCategories('me', {DealCategory.grocery}),
        throwsA(
          isA<RecommendationFailure>().having(
            (failure) => failure.message,
            'message',
            'You do not have permission to update your preferences.',
          ),
        ),
      );
    });
  });
}

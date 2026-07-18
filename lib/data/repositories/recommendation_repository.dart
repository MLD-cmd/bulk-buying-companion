import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/deal.dart';

/// The per-student inputs the recommender needs that are not already in the
/// deal feed: the categories the student opted into, and the deals they
/// dismissed. The ranking itself lives in [DealRecommender]; this only reads
/// and writes the facts it runs on.
///
/// Backed by [MockRecommendationRepository] in tests and
/// [SupabaseRecommendationRepository] in production; callers never depend on
/// the concrete implementation.
abstract class RecommendationRepository {
  Future<Set<DealCategory>> getPreferredCategories(String userId);

  /// Emits the current preferences, then again every time they are saved
  /// through this same repository. The Split Board keeps its recommendations in
  /// step with an edit made on the Profile screen without either screen
  /// knowing about the other.
  Stream<Set<DealCategory>> watchPreferredCategories(String userId);

  Future<void> setPreferredCategories(
    String userId,
    Set<DealCategory> categories,
  );

  Future<Set<String>> getDismissedDealIds(String userId);

  Future<void> dismissDeal(String userId, String dealId);

  /// Frees the broadcast the [watchPreferredCategories] stream is fed from.
  void dispose();
}

/// Raised when preferences or dismissals cannot be read or written. The message
/// is user-facing.
class RecommendationFailure implements Exception {
  const RecommendationFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

DealCategory? _categoryFromName(String value) {
  for (final category in DealCategory.values) {
    if (category.name == value) return category;
  }
  // A category the app no longer knows is not worth failing a whole read over;
  // it simply cannot be matched or shown, so it is dropped.
  return null;
}

/// In-memory stand-in. Preferences and dismissals live only as long as the
/// instance, which is all a test needs.
class MockRecommendationRepository implements RecommendationRepository {
  MockRecommendationRepository({
    Set<DealCategory>? preferredCategories,
    Set<String>? dismissedDealIds,
  }) : _preferred = {...?preferredCategories},
       _dismissed = {...?dismissedDealIds};

  final Set<DealCategory> _preferred;
  final Set<String> _dismissed;
  final _preferenceChanges = StreamController<Set<DealCategory>>.broadcast(
    sync: true,
  );

  @override
  Future<Set<DealCategory>> getPreferredCategories(String userId) async {
    return Set.unmodifiable(_preferred);
  }

  @override
  Stream<Set<DealCategory>> watchPreferredCategories(String userId) async* {
    yield Set.unmodifiable(_preferred);
    yield* _preferenceChanges.stream;
  }

  @override
  Future<void> setPreferredCategories(
    String userId,
    Set<DealCategory> categories,
  ) async {
    _preferred
      ..clear()
      ..addAll(categories);
    if (!_preferenceChanges.isClosed) {
      _preferenceChanges.add(Set.unmodifiable(_preferred));
    }
  }

  @override
  Future<Set<String>> getDismissedDealIds(String userId) async {
    return Set.unmodifiable(_dismissed);
  }

  @override
  Future<void> dismissDeal(String userId, String dealId) async {
    _dismissed.add(dealId);
  }

  @override
  void dispose() {
    _preferenceChanges.close();
  }
}

/// The Supabase reads and writes behind [SupabaseRecommendationRepository],
/// isolated so the repository can be tested without a live Postgrest client.
abstract class SupabaseRecommendationGateway {
  Future<List<String>> getPreferredCategories(String userId);

  Future<void> setPreferredCategories(String userId, List<String> categories);

  Future<List<String>> getDismissedDealIds(String userId);

  Future<void> dismissDeal(String userId, String dealId);
}

class PostgrestSupabaseRecommendationGateway
    implements SupabaseRecommendationGateway {
  PostgrestSupabaseRecommendationGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<List<String>> getPreferredCategories(String userId) async {
    final row = await _client
        .from('profiles')
        .select('preferred_categories')
        .eq('user_id', userId)
        .maybeSingle();
    final value = row?['preferred_categories'];
    return value is List ? value.cast<String>() : const [];
  }

  @override
  Future<void> setPreferredCategories(
    String userId,
    List<String> categories,
  ) async {
    await _client
        .from('profiles')
        .update({'preferred_categories': categories})
        .eq('user_id', userId);
  }

  @override
  Future<List<String>> getDismissedDealIds(String userId) async {
    final rows = await _client
        .from('dismissed_recommendations')
        .select('deal_id')
        .eq('user_id', userId);
    return [
      for (final row in List<Map<String, dynamic>>.from(rows))
        row['deal_id'] as String,
    ];
  }

  @override
  Future<void> dismissDeal(String userId, String dealId) async {
    // Dismissing the same deal twice is the same fact, and the row's primary
    // key is (user_id, deal_id): upsert turns the second dismissal into a
    // no-op instead of a duplicate-key error.
    //
    // ignoreDuplicates plans this as INSERT ... ON CONFLICT DO NOTHING, which
    // only needs INSERT privilege. Without it, Postgrest plans a DO UPDATE,
    // which Postgres requires UPDATE privilege for even when no conflict ever
    // fires -- and this table's grants deliberately have no UPDATE, since a
    // dismissal is written once and never edited.
    await _client
        .from('dismissed_recommendations')
        .upsert({
          'user_id': userId,
          'deal_id': dealId,
        }, ignoreDuplicates: true);
  }
}

class SupabaseRecommendationRepository implements RecommendationRepository {
  SupabaseRecommendationRepository({
    required SupabaseRecommendationGateway gateway,
  }) : _gateway = gateway;

  final SupabaseRecommendationGateway _gateway;
  final _preferenceChanges = StreamController<Set<DealCategory>>.broadcast(
    sync: true,
  );

  @override
  Future<Set<DealCategory>> getPreferredCategories(String userId) async {
    try {
      final names = await _gateway.getPreferredCategories(userId);
      return {for (final name in names) ?_categoryFromName(name)};
    } on PostgrestException catch (error) {
      throw RecommendationFailure(_messageFor(error, _Operation.preferences));
    }
  }

  @override
  Stream<Set<DealCategory>> watchPreferredCategories(String userId) async* {
    yield await getPreferredCategories(userId);
    yield* _preferenceChanges.stream;
  }

  @override
  Future<void> setPreferredCategories(
    String userId,
    Set<DealCategory> categories,
  ) async {
    try {
      await _gateway.setPreferredCategories(userId, [
        for (final category in categories) category.name,
      ]);
      if (!_preferenceChanges.isClosed) {
        _preferenceChanges.add(Set.unmodifiable(categories));
      }
    } on PostgrestException catch (error) {
      throw RecommendationFailure(_messageFor(error, _Operation.preferences));
    }
  }

  @override
  Future<Set<String>> getDismissedDealIds(String userId) async {
    try {
      return (await _gateway.getDismissedDealIds(userId)).toSet();
    } on PostgrestException catch (error) {
      throw RecommendationFailure(_messageFor(error, _Operation.dismissal));
    }
  }

  @override
  Future<void> dismissDeal(String userId, String dealId) async {
    try {
      await _gateway.dismissDeal(userId, dealId);
    } on PostgrestException catch (error) {
      throw RecommendationFailure(_messageFor(error, _Operation.dismissal));
    }
  }

  @override
  void dispose() {
    _preferenceChanges.close();
  }

  /// Distinguishes preference writes from dismissals: the two share a gateway
  /// and an exception type, but not a subject, so one generic sentence cannot
  /// describe both without being wrong about one of them.
  String _messageFor(PostgrestException error, _Operation operation) {
    final subject = switch (operation) {
      _Operation.preferences => 'your preferences',
      _Operation.dismissal => 'that deal',
    };
    // 42501 = insufficient_privilege: RLS rejected the read or write.
    if (error.code == '42501') {
      return 'You do not have permission to update $subject.';
    }
    return switch (operation) {
      _Operation.preferences => 'Could not update your preferences. Please try again.',
      _Operation.dismissal => "Couldn't dismiss that deal. Please try again.",
    };
  }
}

enum _Operation { preferences, dismissal }

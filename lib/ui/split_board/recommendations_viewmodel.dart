import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/deal_repository.dart';
import '../../data/repositories/recommendation_repository.dart';
import '../../data/repositories/reservation_repository.dart';
import '../../models/deal.dart';
import '../../models/deal_recommendation.dart';

/// Drives the "Recommended for you" strip on the Split Board for one student in
/// one hub. It watches the hub's deals and the student's preferences, works out
/// which categories they lean towards from what they have joined, and hands the
/// three inputs to [DealRecommender].
///
/// It keeps its own deal subscription rather than borrowing the board's: the
/// board owns its list for its own filtering and sorting, and reaching across
/// to it would tie two independent screens' states together. The profile does
/// the same for its deal history.
class RecommendationsViewModel extends ChangeNotifier {
  RecommendationsViewModel({
    required DealRepository dealRepository,
    required ReservationRepository reservationRepository,
    required RecommendationRepository recommendationRepository,
    required String userId,
    required String hubId,
    DealRecommender recommender = const DealRecommender(),
  }) : _reservationRepository = reservationRepository,
       _recommendationRepository = recommendationRepository,
       _userId = userId,
       _recommender = recommender {
    _dealsSub = dealRepository
        .watchDeals(hubId)
        .listen(_onDeals, onError: (_) => _onDealsError());
    _preferencesSub = recommendationRepository
        .watchPreferredCategories(userId)
        .listen(_onPreferences, onError: (_) {});
    _loadDismissed();
  }

  final ReservationRepository _reservationRepository;
  final RecommendationRepository _recommendationRepository;
  final String _userId;
  final DealRecommender _recommender;

  StreamSubscription<List<Deal>>? _dealsSub;
  StreamSubscription<Set<DealCategory>>? _preferencesSub;

  List<Deal> _deals = const [];
  Set<DealCategory> _preferred = const {};
  Set<String> _dismissed = const {};
  Set<String> _heldDealIds = const {};
  List<DealRecommendation> _recommendations = const [];
  bool _isLoading = true;
  String? _dismissErrorMessage;
  int _heldGeneration = 0;
  bool _isDisposed = false;

  List<DealRecommendation> get recommendations => _recommendations;
  bool get isLoading => _isLoading;

  /// The categories the student has opted into. Empty for a student who has not
  /// set any yet, which is what the strip reads to tell "no picks because you
  /// have not chosen any categories" apart from "no open deals match".
  Set<DealCategory> get preferredCategories => _preferred;

  /// Set for the moment a dismissal fails to save. The card is restored when
  /// this happens, so the student is never told a deal is gone when it is not.
  String? get dismissErrorMessage => _dismissErrorMessage;

  /// Removes a deal from the recommendations for good. Optimistic: the card
  /// leaves at once, and only comes back if the write fails.
  Future<void> dismiss(String dealId) async {
    if (_isDisposed) return;
    if (_dismissed.contains(dealId)) return;

    _dismissed = {..._dismissed, dealId};
    _dismissErrorMessage = null;
    _recompute();

    try {
      await _recommendationRepository.dismissDeal(_userId, dealId);
    } catch (_) {
      if (_isDisposed) return;
      _dismissed = {..._dismissed}..remove(dealId);
      _dismissErrorMessage = "Couldn't dismiss that deal. Please try again.";
      _recompute();
    }
  }

  Future<void> _loadDismissed() async {
    try {
      final dismissed = await _recommendationRepository.getDismissedDealIds(
        _userId,
      );
      if (_isDisposed) return;
      _dismissed = dismissed;
      _recompute();
    } catch (_) {
      // A failed read of dismissals is not worth blocking recommendations over;
      // the worst case is a dismissed deal reappearing until the next load.
    }
  }

  void _onPreferences(Set<DealCategory> preferred) {
    if (_isDisposed) return;
    _preferred = preferred;
    _recompute();
  }

  Future<void> _onDeals(List<Deal> deals) async {
    if (_isDisposed) return;
    _deals = deals;

    // Only non-hosted deals need asking about: a host always holds their own
    // slot. The read is generation-guarded because a newer deal push can land
    // while it is in flight, and the stale answer must not win.
    final generation = ++_heldGeneration;
    final toCheck = [
      for (final deal in deals)
        if (deal.createdBy != _userId) deal.id,
    ];

    Set<String> held;
    try {
      held = await _heldDealIdsFor(toCheck);
    } catch (_) {
      held = _heldDealIds;
    }
    if (_isDisposed || generation != _heldGeneration) return;

    _heldDealIds = held;
    _isLoading = false;
    _recompute();
  }

  void _onDealsError() {
    if (_isDisposed) return;
    // A dropped stream is a failure to read, not word that there are no deals.
    // Whatever was already recommended stays; loading simply ends.
    _isLoading = false;
    _notifyListeners();
  }

  Future<Set<String>> _heldDealIdsFor(List<String> dealIds) async {
    if (dealIds.isEmpty) return const <String>{};

    final repository = _reservationRepository;
    if (repository is BatchReservationRepository) {
      return (repository as BatchReservationRepository).getDealIdsWithSlotFor(
        _userId,
        dealIds,
      );
    }

    final held = <String>{};
    for (final dealId in dealIds) {
      final participants = await repository.getParticipants(dealId);
      if (participants.any((participant) => participant.userId == _userId)) {
        held.add(dealId);
      }
    }
    return held;
  }

  void _recompute() {
    if (_isDisposed) return;

    // A deal the student hosts or already holds a slot in is one they are in;
    // recommending it would be telling them to join what they joined.
    final excluded = <String>{
      ..._heldDealIds,
      for (final deal in _deals)
        if (deal.createdBy == _userId) deal.id,
    };

    _recommendations = _recommender.rank(
      deals: _deals,
      preferredCategories: _preferred,
      joinedCategoryCounts: joinedCategoryCounts(
        deals: _deals,
        userId: _userId,
        heldDealIds: _heldDealIds,
      ),
      dismissedDealIds: _dismissed,
      excludedDealIds: excluded,
    );
    _notifyListeners();
  }

  void _notifyListeners() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _heldGeneration++;
    _dealsSub?.cancel();
    _preferencesSub?.cancel();
    super.dispose();
  }
}

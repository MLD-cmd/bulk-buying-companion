import 'deal.dart';

/// A deal the ranker chose to surface, paired with why it ranked where it did.
///
/// The [reason] is not decoration: a recommendation a student cannot account
/// for is one they learn to ignore, so every card can say the single fact that
/// earned it its place.
class DealRecommendation {
  const DealRecommendation({
    required this.deal,
    required this.score,
    required this.reason,
  });

  final Deal deal;

  /// Higher is more relevant. Only meaningful relative to the other
  /// recommendations in the same ranking — it is not a percentage.
  final double score;

  /// The dominant signal, in words a student reads: "Matches your interest in
  /// Grocery", "You've joined Drinks deals before", "Filling fast".
  final String reason;
}

/// Ranks a hub's live deals for one student. Pure and synchronous: it is handed
/// the facts — the deals, what the student prefers, what they have joined, what
/// they have dismissed — and returns an ordering. It reads nothing and stores
/// nothing, so the same inputs always give the same list and a unit test can
/// pin the whole behaviour down.
///
/// This is the "AI" of the feature in the plainest sense: a weighted score, not
/// a model. The weights are named and explained rather than tuned, because the
/// point is a student can be told why a deal is there.
class DealRecommender {
  const DealRecommender({
    this.preferredCategoryWeight = 20,
    this.joinedCategoryWeight = 4,
    this.joinedCategoryCap = 3,
    this.fillingFastWeight = 3,
    this.maxRecommendations = 5,
  });

  /// A deal in a category the student explicitly opted into. Set above the most
  /// the implicit signals can add together (join history plus urgency), so an
  /// answered preference always outranks a guess drawn from past behaviour — a
  /// student who says "grocery" should not be shown drinks first because they
  /// once split a case of water.
  final double preferredCategoryWeight;

  /// Per past join in the deal's category. A student who keeps splitting drinks
  /// is telling us something even if they never set a preference — but each
  /// extra join says a little less than the first, so it is capped.
  final double joinedCategoryWeight;

  /// The most past joins in one category that still add to the score. Past this
  /// a single well-worn category would drown out everything else.
  final int joinedCategoryCap;

  /// A nudge for deals that are nearly full. Urgency never earns a deal a place
  /// in the strip on its own — a "Recommended for you" list is about relevance,
  /// not a second copy of the whole board — so it only reorders deals that are
  /// already relevant, and is small next to the category weights.
  final double fillingFastWeight;

  /// How many recommendations to return. A short, confident list beats a long
  /// one the student has to wade through.
  final int maxRecommendations;

  /// Scores and orders [deals] for the student.
  ///
  /// - [preferredCategories]: the categories the student opted into.
  /// - [joinedCategoryCounts]: how many past deals the student joined or hosted
  ///   in each category — the implicit half of "their interests".
  /// - [dismissedDealIds]: deals the student waved away; never shown again.
  /// - [excludedDealIds]: deals the student is already in (their own, or ones
  ///   they hold a slot in) — recommending those would be telling them to join
  ///   what they already joined.
  ///
  /// Only open deals with a slot left are candidates: a full, bought, finished
  /// or cancelled deal is not something a student can act on, so it is not a
  /// recommendation. A deal needs at least one personal signal — a preferred
  /// category or a category the student has joined before — to appear; one that
  /// is merely urgent is left to the board rather than padding the strip.
  List<DealRecommendation> rank({
    required List<Deal> deals,
    required Set<DealCategory> preferredCategories,
    Map<DealCategory, int> joinedCategoryCounts = const {},
    Set<String> dismissedDealIds = const {},
    Set<String> excludedDealIds = const {},
  }) {
    final scored = <DealRecommendation>[];

    for (final deal in deals) {
      if (deal.status != DealStatus.open) continue;
      if (dismissedDealIds.contains(deal.id)) continue;
      if (excludedDealIds.contains(deal.id)) continue;

      final recommendation = _score(
        deal,
        preferredCategories,
        joinedCategoryCounts,
      );
      if (recommendation != null) scored.add(recommendation);
    }

    scored.sort(_byScoreThenUrgency);
    return scored.length > maxRecommendations
        ? scored.sublist(0, maxRecommendations)
        : scored;
  }

  DealRecommendation? _score(
    Deal deal,
    Set<DealCategory> preferredCategories,
    Map<DealCategory, int> joinedCategoryCounts,
  ) {
    var score = 0.0;
    // The reason names the strongest signal, so it is chosen in the same order
    // the weights rank: preference first, then history, then urgency.
    String? reason;

    if (preferredCategories.contains(deal.category)) {
      score += preferredCategoryWeight;
      reason = 'Matches your interest in ${deal.category.label}';
    }

    final joins = joinedCategoryCounts[deal.category] ?? 0;
    if (joins > 0) {
      final counted = joins < joinedCategoryCap ? joins : joinedCategoryCap;
      score += joinedCategoryWeight * counted;
      reason ??= "You've joined ${deal.category.label} deals before";
    }

    // No personal signal — the category is neither preferred nor one they have
    // joined — so the deal is not for the strip, whatever its urgency.
    if (reason == null) return null;

    // Urgency only reorders deals that already earned their place.
    if (deal.isFillingFast) score += fillingFastWeight;

    return DealRecommendation(deal: deal, score: score, reason: reason);
  }

  /// Higher score first. Ties go to the deal that closes sooner — between two
  /// equally relevant deals, the one running out of time is the one worth
  /// acting on now. A deal with no deadline sorts last of the tie. The deal id
  /// is the final tie-break so the order is total and stable.
  int _byScoreThenUrgency(DealRecommendation a, DealRecommendation b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;

    final aCloses = a.deal.closesAt;
    final bCloses = b.deal.closesAt;
    if (aCloses != null && bCloses != null) {
      final byDeadline = aCloses.compareTo(bCloses);
      if (byDeadline != 0) return byDeadline;
    } else if (aCloses != null) {
      return -1;
    } else if (bCloses != null) {
      return 1;
    }

    return a.deal.id.compareTo(b.deal.id);
  }
}

/// Tallies, per category, the deals a student has a stake in — the deals they
/// host and the deals they hold a slot in. This is the "analyse joined deals"
/// signal, kept next to the ranker that consumes it so the two definitions of
/// "a deal the student is in" cannot drift apart.
///
/// [heldDealIds] are the deals the student holds a non-host slot in; a hosted
/// deal ([Deal.createdBy] equal to [userId]) counts too, since organising a
/// buy is the strongest statement of interest there is.
Map<DealCategory, int> joinedCategoryCounts({
  required List<Deal> deals,
  required String userId,
  required Set<String> heldDealIds,
}) {
  final counts = <DealCategory, int>{};
  for (final deal in deals) {
    final isHost = deal.createdBy == userId;
    if (!isHost && !heldDealIds.contains(deal.id)) continue;
    counts.update(deal.category, (value) => value + 1, ifAbsent: () => 1);
  }
  return counts;
}

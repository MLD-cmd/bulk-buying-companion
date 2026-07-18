import 'package:flutter/material.dart';

import '../../../models/deal.dart';
import '../../../models/deal_recommendation.dart';
import '../../shared/app_icon_container.dart';

/// The "Recommended for you" strip at the top of the Split Board.
///
/// Presentational: it is handed the ranked recommendations and reports two
/// intents back — open a deal, dismiss a deal — so the screen keeps ownership
/// of navigation and the ViewModel keeps ownership of the ranking.
class RecommendedDealsSection extends StatelessWidget {
  const RecommendedDealsSection({
    super.key,
    required this.recommendations,
    required this.onOpenDeal,
    required this.onDismiss,
  });

  final List<DealRecommendation> recommendations;
  final ValueChanged<Deal> onOpenDeal;
  final ValueChanged<Deal> onDismiss;

  @override
  Widget build(BuildContext context) {
    // Nothing to recommend is not an error and not a state worth explaining:
    // the strip simply is not there, and the board reads as it always has.
    if (recommendations.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    // At large text sizes a fixed-width row of cards clips; the cards grow with
    // the text, so the strip's height grows with them.
    final cardHeight = 176.0 * (textScale > 1 ? textScale : 1);

    return Column(
      key: const Key('recommended-deals-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text('Recommended for you', style: theme.textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Picked from this hub for what you buy.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: recommendations.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final recommendation = recommendations[index];
              return _RecommendationCard(
                recommendation: recommendation,
                onOpen: () => onOpenDeal(recommendation.deal),
                onDismiss: () => onDismiss(recommendation.deal),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.recommendation,
    required this.onOpen,
    required this.onDismiss,
  });

  final DealRecommendation recommendation;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deal = recommendation.deal;

    return SizedBox(
      width: 250,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          key: Key('recommendation-card-${deal.id}'),
          onTap: onOpen,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppIconContainer(
                      icon: _categoryIcon(deal.category),
                      size: 40,
                      iconSize: 20,
                      semanticLabel: deal.category.label,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          deal.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    ),
                    IconButton(
                      key: Key('recommendation-dismiss-${deal.id}'),
                      onPressed: onDismiss,
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Dismiss ${deal.title}',
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    deal.priceLabel,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _ReasonChip(reason: recommendation.reason),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReasonChip extends StatelessWidget {
  const _ReasonChip({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The lightbulb is decoration and the reason reads as loose text otherwise;
    // one label spoken as "Why recommended: ..." tells a screen reader what the
    // chip is for, the way DealStatusBadge names its own colour-coded pill.
    return Semantics(
      label: 'Why recommended: $reason',
      container: true,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tips_and_updates_outlined,
                size: 13,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _categoryIcon(DealCategory category) {
  return switch (category) {
    DealCategory.grocery => Icons.local_grocery_store_outlined,
    DealCategory.household => Icons.cleaning_services_outlined,
    DealCategory.drinks => Icons.local_drink_outlined,
    DealCategory.pantry => Icons.kitchen_outlined,
  };
}

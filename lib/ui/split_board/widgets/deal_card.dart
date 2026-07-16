import 'package:flutter/material.dart';

import '../../../models/deal.dart';
import '../../shared/app_icon_container.dart';
import 'deal_status_badge.dart';

class DealCard extends StatelessWidget {
  const DealCard({super.key, required this.deal});

  final Deal deal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppIconContainer(
                  icon: _categoryIcon(deal.category),
                  semanticLabel: deal.category.label,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deal.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        deal.category.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              deal.priceLabel,
              key: const Key('deal-card-price'),
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontSize: 23,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${deal.physicalShare.shareLabel} each',
              key: const Key('deal-card-physical-share'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: DealStatusBadge(deal: deal),
            ),
            const SizedBox(height: 14),
            const Divider(),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _Metadata(
                  icon: Icons.group_outlined,
                  label: deal.availableSlotsLabel,
                ),
                _Metadata(
                  icon: Icons.schedule_outlined,
                  label: deal.deadlineLabel,
                ),
              ],
            ),
          ],
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

class _Metadata extends StatelessWidget {
  const _Metadata({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

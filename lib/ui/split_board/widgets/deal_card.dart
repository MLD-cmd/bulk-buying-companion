import 'package:flutter/material.dart';

import '../../../models/deal.dart';

/// Scaffold card for a Split Board deal. Shows the deal title only for now;
/// the deal-detail work fills in price, available slots, pickup location, and
/// status on top of this shell.
class DealCard extends StatelessWidget {
  const DealCard({super.key, required this.deal});

  final Deal deal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: const Icon(Icons.inventory_2_outlined, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              deal.title,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

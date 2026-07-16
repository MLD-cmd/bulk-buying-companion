import 'package:flutter/material.dart';

import '../../../models/deal.dart';
import '../../shared/app_theme.dart';

class DealStatusBadge extends StatelessWidget {
  const DealStatusBadge({super.key, required this.deal});

  final Deal deal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _statusColors(theme);

    return Semantics(
      label: 'Status: ${deal.statusLabel}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          deal.statusLabel,
          style: theme.textTheme.labelSmall?.copyWith(color: colors.foreground),
        ),
      ),
    );
  }

  _BadgeColors _statusColors(ThemeData theme) {
    if (deal.isFillingFast) {
      return theme.brightness == Brightness.light
          ? const _BadgeColors(
              background: AppTheme.warningContainer,
              foreground: AppTheme.warning,
            )
          : _BadgeColors(
              background: theme.colorScheme.tertiaryContainer,
              foreground: theme.colorScheme.onTertiaryContainer,
            );
    }

    return switch (deal.status) {
      DealStatus.open =>
        theme.brightness == Brightness.light
            ? const _BadgeColors(
                background: AppTheme.successContainer,
                foreground: AppTheme.success,
              )
            : _BadgeColors(
                background: theme.colorScheme.primaryContainer,
                foreground: theme.colorScheme.onPrimaryContainer,
              ),
      DealStatus.full || DealStatus.cancelled => _BadgeColors(
        background: theme.colorScheme.errorContainer,
        foreground: theme.colorScheme.onErrorContainer,
      ),
      DealStatus.readyToPurchase || DealStatus.readyForPickup => _BadgeColors(
        background: theme.colorScheme.secondaryContainer,
        foreground: theme.colorScheme.onSecondaryContainer,
      ),
      DealStatus.completed => _BadgeColors(
        background: theme.colorScheme.surfaceContainerHighest,
        foreground: theme.colorScheme.onSurfaceVariant,
      ),
    };
  }
}

class _BadgeColors {
  const _BadgeColors({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}

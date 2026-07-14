import 'package:flutter/material.dart';

import '../../../models/hub.dart';
import '../../shared/app_theme.dart';

class HubCard extends StatelessWidget {
  const HubCard({
    super.key,
    required this.hub,
    required this.isJoined,
    required this.isPendingSwitch,
    required this.showSwitchAction,
    required this.onJoin,
    required this.onRequestSwitch,
    required this.onConfirmSwitch,
    required this.onCancelSwitch,
    this.isBusy = false,
  });

  final Hub hub;
  final bool isJoined;
  final bool isPendingSwitch;
  final bool showSwitchAction;

  /// A join or leave is already in flight. The actions go dead so a second tap
  /// cannot be counted against a membership row that only ever holds one.
  final bool isBusy;

  final VoidCallback onJoin;
  final VoidCallback onRequestSwitch;
  final VoidCallback onConfirmSwitch;
  final VoidCallback onCancelSwitch;

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
            child: const Icon(Icons.home_work_outlined, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        hub.name,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _TypeChip(type: hub.type),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _MemberCountStat(count: hub.memberCount),
                    const SizedBox(width: 6),
                    Text(
                      hub.distanceLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildAction(context),
        ],
      ),
    );
  }

  Widget _buildAction(BuildContext context) {
    if (isJoined) {
      return Chip(
        avatar: const Icon(Icons.check, size: 16, color: AppTheme.good),
        label: const Text('Joined'),
        backgroundColor: AppTheme.goodBg,
        labelStyle: const TextStyle(
          color: AppTheme.good,
          fontWeight: FontWeight.w700,
        ),
        side: BorderSide.none,
      );
    }

    if (isPendingSwitch) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton(
            onPressed: isBusy ? null : onConfirmSwitch,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 36),
            ),
            child: const Text('Yes'),
          ),
          const SizedBox(width: 6),
          OutlinedButton(
            onPressed: isBusy ? null : onCancelSwitch,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 36),
            ),
            child: const Text('Cancel'),
          ),
        ],
      );
    }

    if (showSwitchAction) {
      return OutlinedButton(
        onPressed: isBusy ? null : onRequestSwitch,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          minimumSize: const Size(0, 36),
        ),
        child: const Text('Switch'),
      );
    }

    return FilledButton(
      key: const Key('hub-join-button'),
      onPressed: isBusy ? null : onJoin,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        minimumSize: const Size(0, 36),
      ),
      child: const Text('Join'),
    );
  }
}

class _MemberCountStat extends StatelessWidget {
  const _MemberCountStat({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_outline,
            size: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type});

  final HubType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = type == HubType.dormitory ? 'DORMITORY' : 'AREA HUB';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 0.4,
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

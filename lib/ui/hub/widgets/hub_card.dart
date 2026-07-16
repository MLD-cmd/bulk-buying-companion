import 'package:flutter/material.dart';

import '../../../models/hub.dart';
import '../../shared/app_icon_container.dart';
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
  final bool isBusy;
  final VoidCallback onJoin;
  final VoidCallback onRequestSwitch;
  final VoidCallback onConfirmSwitch;
  final VoidCallback onCancelSwitch;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stackAction = constraints.maxWidth < 390 || textScale > 1.3;
            final summary = _HubSummary(hub: hub);
            final action = _buildAction(context);

            if (stackAction) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  summary,
                  const SizedBox(height: 14),
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: summary),
                const SizedBox(width: 12),
                action,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAction(BuildContext context) {
    final theme = Theme.of(context);

    if (isJoined) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.light
              ? AppTheme.successContainer
              : theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 18,
              color: theme.brightness == Brightness.light
                  ? AppTheme.success
                  : theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 6),
            Text(
              'Joined',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.brightness == Brightness.light
                    ? AppTheme.success
                    : theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      );
    }

    if (isPendingSwitch) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          OutlinedButton(
            onPressed: isBusy ? null : onCancelSwitch,
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: isBusy ? null : onConfirmSwitch,
            child: const Text('Confirm switch'),
          ),
        ],
      );
    }

    if (showSwitchAction) {
      return OutlinedButton(
        onPressed: isBusy ? null : onRequestSwitch,
        child: const Text('Switch'),
      );
    }

    return FilledButton(
      key: const Key('hub-join-button'),
      onPressed: isBusy ? null : onJoin,
      child: const Text('Join'),
    );
  }
}

class _HubSummary extends StatelessWidget {
  const _HubSummary({required this.hub});

  final Hub hub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeLabel = hub.type == HubType.dormitory ? 'Dormitory' : 'Area hub';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIconContainer(
          icon: hub.type == HubType.dormitory
              ? Icons.apartment_outlined
              : Icons.location_city_outlined,
          semanticLabel: typeLabel,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hub.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    typeLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  _Metadata(
                    icon: Icons.people_outline,
                    label: '${hub.memberCount} members',
                  ),
                  if (hub.distanceLabel.trim().isNotEmpty)
                    _Metadata(
                      icon: Icons.near_me_outlined,
                      label: hub.distanceLabel,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
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
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

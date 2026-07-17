import 'package:flutter/material.dart';

import 'app_icon_container.dart';

class AppMessageState extends StatelessWidget {
  const AppMessageState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
    this.retryBusy = false,
  }) : assert(!retryBusy || onRetry != null);

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;
  final bool retryBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIconContainer(icon: icon, size: 52, iconSize: 24),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                _MessageRetry(
                  onRetry: onRetry!,
                  label: retryLabel,
                  busy: retryBusy,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageRetry extends StatelessWidget {
  const _MessageRetry({
    required this.onRetry,
    required this.label,
    required this.busy,
  });

  final VoidCallback onRetry;
  final String label;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton.icon(
      onPressed: busy ? null : onRetry,
      icon: busy
          ? SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : const Icon(Icons.refresh_outlined),
      label: Text(busy ? 'Trying again…' : label),
    );

    if (!busy) return button;
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Trying again',
      child: ExcludeSemantics(child: button),
    );
  }
}

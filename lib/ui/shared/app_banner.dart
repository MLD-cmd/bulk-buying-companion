import 'package:flutter/material.dart';

import 'app_theme.dart';

enum AppBannerTone { error, notice, success }

class AppBanner extends StatelessWidget {
  const AppBanner({
    super.key,
    required this.message,
    required this.tone,
    required this.icon,
    this.actionLabel,
    this.onAction,
    this.actionBusy = false,
  }) : assert(
         (actionLabel == null) == (onAction == null),
         'Provide both an action label and callback, or neither.',
       ),
       assert(
         !actionBusy || (actionLabel != null && onAction != null),
         'A busy banner action requires an action label and callback.',
       );

  const AppBanner.error({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionBusy = false,
  }) : assert(
         (actionLabel == null) == (onAction == null),
         'Provide both an action label and callback, or neither.',
       ),
       assert(
         !actionBusy || (actionLabel != null && onAction != null),
         'A busy banner action requires an action label and callback.',
       ),
       tone = AppBannerTone.error,
       icon = Icons.error_outline;

  const AppBanner.notice({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
    this.actionLabel,
    this.onAction,
    this.actionBusy = false,
  }) : assert(
         (actionLabel == null) == (onAction == null),
         'Provide both an action label and callback, or neither.',
       ),
       assert(
         !actionBusy || (actionLabel != null && onAction != null),
         'A busy banner action requires an action label and callback.',
       ),
       tone = AppBannerTone.notice;

  const AppBanner.success({
    super.key,
    required this.message,
    this.icon = Icons.check_circle_outline,
    this.actionLabel,
    this.onAction,
    this.actionBusy = false,
  }) : assert(
         (actionLabel == null) == (onAction == null),
         'Provide both an action label and callback, or neither.',
       ),
       assert(
         !actionBusy || (actionLabel != null && onAction != null),
         'A busy banner action requires an action label and callback.',
       ),
       tone = AppBannerTone.success;

  final String message;
  final AppBannerTone tone;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool actionBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (background, foreground) = switch (tone) {
      AppBannerTone.error => (
        theme.colorScheme.errorContainer,
        theme.colorScheme.onErrorContainer,
      ),
      AppBannerTone.notice => (
        theme.colorScheme.secondaryContainer,
        theme.colorScheme.onSecondaryContainer,
      ),
      AppBannerTone.success =>
        theme.brightness == Brightness.light
            ? (AppTheme.successContainer, AppTheme.onSuccessContainer)
            : (
                theme.colorScheme.primaryContainer,
                theme.colorScheme.onPrimaryContainer,
              ),
    };

    Widget banner(Widget content) => Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: foreground, size: 20),
              const SizedBox(width: 10),
              Expanded(child: content),
            ],
          ),
        ),
      ),
    );

    Text messageText() => Text(
      message,
      style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
    );

    if (actionLabel == null || onAction == null) {
      return banner(messageText());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackAction =
            constraints.maxWidth < 360 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3;
        final action = _BannerAction(
          label: actionLabel!,
          onPressed: actionBusy ? null : onAction,
          busy: actionBusy,
          foreground: foreground,
        );

        if (stackAction) {
          return banner(
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [messageText(), const SizedBox(height: 4), action],
            ),
          );
        }

        return banner(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: messageText()),
              const SizedBox(width: 8),
              action,
            ],
          ),
        );
      },
    );
  }
}

class _BannerAction extends StatelessWidget {
  const _BannerAction({
    required this.label,
    required this.onPressed,
    required this.busy,
    required this.foreground,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: foreground),
      child: busy
          ? Semantics(
              label: '$label in progress',
              child: ExcludeSemantics(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    color: foreground,
                    strokeWidth: 2.2,
                  ),
                ),
              ),
            )
          : Text(label),
    );
  }
}

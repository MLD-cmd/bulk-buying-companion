import 'package:flutter/material.dart';

import 'app_theme.dart';

enum AppBannerTone { error, notice, success }

class AppBanner extends StatelessWidget {
  const AppBanner({
    super.key,
    required this.message,
    required this.tone,
    required this.icon,
  });

  const AppBanner.error({super.key, required this.message})
    : tone = AppBannerTone.error,
      icon = Icons.error_outline;

  const AppBanner.notice({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
  }) : tone = AppBannerTone.notice;

  const AppBanner.success({
    super.key,
    required this.message,
    this.icon = Icons.check_circle_outline,
  }) : tone = AppBannerTone.success;

  final String message;
  final AppBannerTone tone;
  final IconData icon;

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

    return Semantics(
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
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
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

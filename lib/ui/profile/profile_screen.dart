import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/hub_repository.dart';
import '../../models/hub.dart';
import '../shared/app_banner.dart';
import '../shared/app_icon_container.dart';
import '../shared/app_message_state.dart';
import '../shared/app_theme.dart';
import 'profile_viewmodel.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static Route<void> route() {
    return MaterialPageRoute(
      builder: (context) => ChangeNotifierProvider(
        create: (context) => ProfileViewModel(
          authRepository: context.read<AuthRepository>(),
          hubRepository: context.read<HubRepository>(),
        ),
        child: const ProfileScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: Consumer<ProfileViewModel>(
          builder: (context, viewModel, _) {
            final user = viewModel.user;
            if (user == null) {
              return const AppMessageState(
                icon: Icons.person_off_outlined,
                title: 'Not signed in',
                message: 'Return to login to continue.',
              );
            }

            final theme = Theme.of(context);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: CircleAvatar(
                            key: const Key('profile-avatar'),
                            radius: 38,
                            backgroundColor: theme.colorScheme.primaryContainer,
                            child: Text(
                              _initials(user.displayName ?? user.eduEmail),
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          user.displayName ?? 'Student',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          user.eduEmail,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          'CURRENT HUB',
                          style: theme.textTheme.labelSmall?.copyWith(
                            letterSpacing: 0.7,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _CurrentHubSection(viewModel: viewModel),
                        if (viewModel.signOutErrorMessage != null) ...[
                          const SizedBox(height: 16),
                          AppBanner.error(
                            key: const Key('profile-sign-out-error'),
                            message: viewModel.signOutErrorMessage!,
                          ),
                        ],
                        const SizedBox(height: 20),
                        OutlinedButton.icon(
                          key: const Key('profile-logout-button'),
                          onPressed: viewModel.isSigningOut
                              ? null
                              : () => _signOut(context, viewModel),
                          style: ButtonStyle(
                            foregroundColor: WidgetStatePropertyAll(
                              theme.colorScheme.error,
                            ),
                            side: WidgetStatePropertyAll(
                              BorderSide(color: theme.colorScheme.error),
                            ),
                          ),
                          icon: viewModel.isSigningOut
                              ? SizedBox.square(
                                  key: const Key('logout-progress'),
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: theme.colorScheme.error,
                                  ),
                                )
                              : const Icon(Icons.logout_outlined),
                          label: Text(
                            viewModel.isSigningOut ? 'Logging out…' : 'Log out',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _signOut(
    BuildContext context,
    ProfileViewModel viewModel,
  ) async {
    final didSignOut = await viewModel.signOut();
    if (!didSignOut || !context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  String _initials(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class _CurrentHubSection extends StatelessWidget {
  const _CurrentHubSection({required this.viewModel});

  final ProfileViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final hub = viewModel.currentHub;
    final children = <Widget>[];

    if (hub != null) {
      children.add(_CurrentHubTile(hub: hub));
    }

    if (viewModel.loadErrorMessage != null) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 10));
      children.add(
        AppBanner.error(
          key: const Key('profile-current-hub-error'),
          message: viewModel.loadErrorMessage!,
          actionLabel: 'Try again',
          onAction: viewModel.retryLoad,
          actionBusy: viewModel.isLoading,
        ),
      );
    } else if (viewModel.isLoading) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 10));
      children.add(const _CurrentHubLoading());
    } else if (hub == null) {
      children.add(const _CurrentHubTile(hub: null));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _CurrentHubLoading extends StatelessWidget {
  const _CurrentHubLoading();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const SizedBox.square(
              key: Key('current-hub-progress'),
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Loading your current hub…',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentHubTile extends StatelessWidget {
  const _CurrentHubTile({required this.hub});

  final Hub? hub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (hub == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const AppIconContainer(icon: Icons.home_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "You haven't joined a hub yet.",
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.light
            ? AppTheme.successContainer
            : theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.brightness == Brightness.light
              ? AppTheme.success.withValues(alpha: 0.2)
              : theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          AppIconContainer(
            icon: Icons.check_outlined,
            backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.72),
            foregroundColor: theme.brightness == Brightness.light
                ? AppTheme.success
                : theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hub!.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.brightness == Brightness.light
                        ? AppTheme.onSuccessContainer
                        : theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${hub!.memberCount} members',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.brightness == Brightness.light
                        ? AppTheme.onSuccessContainer
                        : theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

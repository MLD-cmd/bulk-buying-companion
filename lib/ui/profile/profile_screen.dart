import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/deal_repository.dart';
import '../../data/repositories/hub_repository.dart';
import '../../data/repositories/recommendation_repository.dart';
import '../../data/repositories/reservation_repository.dart';
import '../../models/deal.dart';
import '../../models/hub.dart';
import '../shared/app_banner.dart';
import '../shared/app_form_section.dart';
import '../shared/app_icon_container.dart';
import '../shared/app_message_state.dart';
import '../shared/app_theme.dart';
import '../split_board/widgets/deal_status_badge.dart';
import 'profile_viewmodel.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static Route<void> route() {
    return MaterialPageRoute(
      builder: (context) => ChangeNotifierProvider(
        create: (context) => ProfileViewModel(
          authRepository: context.read<AuthRepository>(),
          hubRepository: context.read<HubRepository>(),
          dealRepository: context.read<DealRepository>(),
          reservationRepository: context.read<ReservationRepository>(),
          recommendationRepository: context.read<RecommendationRepository?>(),
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
                        const SizedBox(height: 16),
                        Center(
                          child: OutlinedButton.icon(
                            onPressed: viewModel.isSavingProfile
                                ? null
                                : () => _editProfile(context, viewModel),
                            icon: viewModel.isSavingProfile
                                ? SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: theme.colorScheme.primary,
                                    ),
                                  )
                                : const Icon(Icons.edit_outlined),
                            label: const Text('Edit profile'),
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
                        const SizedBox(height: 18),
                        if (viewModel.preferencesEnabled) ...[
                          _PreferredCategoriesSection(viewModel: viewModel),
                          const SizedBox(height: 12),
                        ],
                        if (viewModel.dealHistoryErrorMessage != null) ...[
                          // Without this the three sections below all read
                          // "will appear here", which says the student has no
                          // deals rather than that we could not read them.
                          AppBanner.error(
                            key: const Key('profile-deal-history-error'),
                            message: viewModel.dealHistoryErrorMessage!,
                            actionLabel: 'Try again',
                            onAction: viewModel.retryLoad,
                            actionBusy: viewModel.isLoading,
                          ),
                          const SizedBox(height: 12),
                        ],
                        _DealHistorySection(
                          title: 'Hosted deals',
                          emptyMessage:
                              "Deals you organize for this hub will appear here.",
                          icon: Icons.storefront_outlined,
                          deals: viewModel.hostedDeals,
                        ),
                        const SizedBox(height: 12),
                        _DealHistorySection(
                          title: 'Joined deals',
                          emptyMessage:
                              'Reservations you join in this hub will appear here.',
                          icon: Icons.group_outlined,
                          deals: viewModel.joinedDeals,
                        ),
                        const SizedBox(height: 12),
                        _DealHistorySection(
                          title: 'Completed deals',
                          emptyMessage:
                              'Completed transactions will appear here.',
                          icon: Icons.task_alt_outlined,
                          deals: viewModel.completedDeals,
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

  Future<void> _editProfile(
    BuildContext context,
    ProfileViewModel viewModel,
  ) async {
    final user = viewModel.user;
    if (user == null) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditProfileDialog(
        initialDisplayName: user.displayName ?? '',
        viewModel: viewModel,
      ),
    );

    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile updated.')));
    }
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
      // The row already says it is loading; liveRegion is what makes a screen
      // reader announce it when the state flips, rather than only on focus.
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const ExcludeSemantics(
                child: SizedBox.square(
                  key: Key('current-hub-progress'),
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
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
      ),
    );
  }
}

class _EditProfileDialog extends StatefulWidget {
  const _EditProfileDialog({
    required this.initialDisplayName,
    required this.viewModel,
  });

  final String initialDisplayName;
  final ProfileViewModel viewModel;

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialDisplayName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listens so a rejected save reports itself here, in the dialog the student
    // is still looking at, rather than behind it.
    return AnimatedBuilder(
      animation: widget.viewModel,
      builder: (context, _) {
        final saving = widget.viewModel.isSavingProfile;
        final error = widget.viewModel.saveErrorMessage;

        return AlertDialog(
          title: const Text('Edit profile'),
          content: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('profile-display-name-field'),
                  controller: _controller,
                  enabled: !saving,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter your full name.';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _save(),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  AppBanner.error(
                    key: const Key('profile-save-error'),
                    message: error,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving ? null : _save,
              child: Text(saving ? 'Saving…' : 'Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final saved = await widget.viewModel.saveDisplayName(_controller.text);
    if (saved && mounted) Navigator.of(context).pop(true);
  }
}

class _PreferredCategoriesSection extends StatelessWidget {
  const _PreferredCategoriesSection({required this.viewModel});

  final ProfileViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = viewModel.preferredCategories;

    return AppFormSection(
      key: const Key('profile-preferences-section'),
      title: 'Preferred categories',
      icon: Icons.tune_outlined,
      children: [
        Text(
          'Deals in these categories are recommended to you first.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (selected.isEmpty)
          Text(
            'No categories chosen yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in DealCategory.values)
                if (selected.contains(category))
                  Chip(
                    label: Text(category.label),
                    visualDensity: VisualDensity.compact,
                  ),
            ],
          ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('profile-preferences-edit-button'),
            onPressed: viewModel.isSavingPreferences
                ? null
                : () => _editPreferences(context, viewModel),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit categories'),
          ),
        ),
      ],
    );
  }

  Future<void> _editPreferences(
    BuildContext context,
    ProfileViewModel viewModel,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditPreferencesDialog(viewModel: viewModel),
    );

    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Preferences updated.')));
    }
  }
}

class _EditPreferencesDialog extends StatefulWidget {
  const _EditPreferencesDialog({required this.viewModel});

  final ProfileViewModel viewModel;

  @override
  State<_EditPreferencesDialog> createState() => _EditPreferencesDialogState();
}

class _EditPreferencesDialogState extends State<_EditPreferencesDialog> {
  late Set<DealCategory> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.viewModel.preferredCategories};
  }

  @override
  Widget build(BuildContext context) {
    // Listens so a rejected save reports itself here, in the dialog the student
    // is still looking at, rather than behind it.
    return AnimatedBuilder(
      animation: widget.viewModel,
      builder: (context, _) {
        final saving = widget.viewModel.isSavingPreferences;
        final error = widget.viewModel.preferencesErrorMessage;

        return AlertDialog(
          title: const Text('Preferred categories'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in DealCategory.values)
                    FilterChip(
                      key: Key('preferences-chip-${category.name}'),
                      label: Text(category.label),
                      selected: _selected.contains(category),
                      onSelected: saving
                          ? null
                          : (isSelected) => setState(() {
                              if (isSelected) {
                                _selected.add(category);
                              } else {
                                _selected.remove(category);
                              }
                            }),
                    ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                AppBanner.error(
                  key: const Key('profile-preferences-error'),
                  message: error,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('profile-preferences-save'),
              onPressed: saving ? null : _save,
              child: Text(saving ? 'Saving…' : 'Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _save() async {
    final saved = await widget.viewModel.savePreferredCategories(_selected);
    if (saved && mounted) Navigator.of(context).pop(true);
  }
}

class _DealHistorySection extends StatelessWidget {
  const _DealHistorySection({
    required this.title,
    required this.emptyMessage,
    required this.icon,
    required this.deals,
  });

  final String title;
  final String emptyMessage;
  final IconData icon;
  final List<Deal> deals;

  @override
  Widget build(BuildContext context) {
    return AppFormSection(
      title: title,
      icon: icon,
      children: [
        if (deals.isEmpty)
          _EmptyHistoryMessage(message: emptyMessage)
        else
          for (final deal in deals) ...[
            _DealHistoryTile(deal: deal),
            if (deal != deals.last) const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _EmptyHistoryMessage extends StatelessWidget {
  const _EmptyHistoryMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      message,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _DealHistoryTile extends StatelessWidget {
  const _DealHistoryTile({required this.deal});

  final Deal deal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(deal.title, style: theme.textTheme.titleSmall),
                ),
                const SizedBox(width: 8),
                DealStatusBadge(deal: deal),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                _HistoryMeta(
                  icon: Icons.payments_outlined,
                  label: deal.priceLabel,
                ),
                _HistoryMeta(
                  icon: Icons.inventory_2_outlined,
                  label: deal.physicalShare.shareLabel,
                ),
                _HistoryMeta(
                  icon: Icons.event_outlined,
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

class _HistoryMeta extends StatelessWidget {
  const _HistoryMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 5),
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

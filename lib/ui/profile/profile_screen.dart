import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/deal_repository.dart';
import '../../data/repositories/hub_repository.dart';
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
            if (viewModel.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

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
                        _CurrentHubTile(hub: viewModel.currentHub),
                        if (viewModel.errorMessage != null) ...[
                          const SizedBox(height: 16),
                          AppBanner.error(message: viewModel.errorMessage!),
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
    return AlertDialog(
      title: const Text('Edit profile'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const Key('profile-display-name-field'),
          controller: _controller,
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final saved = await widget.viewModel.saveDisplayName(_controller.text);
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
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
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.search_outlined),
                  label: const Text('Find a hub'),
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

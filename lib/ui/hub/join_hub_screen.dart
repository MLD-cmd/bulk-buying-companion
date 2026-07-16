import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';
import '../shared/app_banner.dart';
import '../shared/app_icon_container.dart';
import '../shared/app_message_state.dart';
import '../split_board/split_board_screen.dart';
import 'create_hub_screen.dart';
import 'join_hub_viewmodel.dart';
import 'widgets/hub_card.dart';

class JoinHubScreen extends StatelessWidget {
  const JoinHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find your hub'),
        actions: [
          Consumer<JoinHubViewModel>(
            builder: (context, viewModel, _) {
              final hub = viewModel.joinedHub;
              if (hub == null) return const SizedBox.shrink();

              return IconButton(
                icon: const Icon(Icons.notifications_none_outlined),
                tooltip: 'Notifications',
                onPressed: () => Navigator.of(context).push(
                  NotificationsScreen.route(hubId: hub.id, hubName: hub.name),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add_location_alt_outlined),
            tooltip: 'Register a hub',
            onPressed: () => _registerHub(context),
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Profile',
            onPressed: () => Navigator.of(context).push(ProfileScreen.route()),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Consumer<JoinHubViewModel>(
          builder: (context, viewModel, _) {
            if (viewModel.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            return Column(
              children: [
                if (viewModel.joinedHub != null)
                  _CurrentHubBanner(
                    hubName: viewModel.joinedHub!.name,
                    onLeave: viewModel.leave,
                    onOpenSplitBoard: () => Navigator.of(context).push(
                      SplitBoardScreen.route(
                        viewModel.joinedHub!.id,
                        viewModel.joinedHub!.name,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                  child: _SearchField(
                    query: viewModel.searchQuery,
                    onChanged: viewModel.setSearchQuery,
                  ),
                ),
                if (viewModel.canFilterByDistance)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                      child: FilterChip(
                        key: const Key('hub-nearby-filter'),
                        avatar: const Icon(Icons.near_me_outlined, size: 18),
                        label: Text(
                          'Within ${(kNearbyRadiusMeters / 1000).round()} km',
                        ),
                        selected: viewModel.nearbyOnly,
                        onSelected: viewModel.setNearbyOnly,
                      ),
                    ),
                  )
                else if (viewModel.locationFailureMessage != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: AppBanner.notice(
                      message: viewModel.locationFailureMessage!,
                      icon: Icons.location_off_outlined,
                    ),
                  ),
                Expanded(child: _HubList(viewModel: viewModel)),
              ],
            );
          },
        ),
      ),
    );
  }
}

Future<void> _registerHub(BuildContext context) async {
  final viewModel = context.read<JoinHubViewModel>();
  final messenger = ScaffoldMessenger.of(context);

  final hub = await Navigator.of(context).push(CreateHubScreen.route());
  if (hub == null) return;

  await viewModel.refresh();
  messenger.showSnackBar(
    SnackBar(content: Text('${hub.name} is now on the hub list.')),
  );
}

class _SearchField extends StatefulWidget {
  const _SearchField({required this.query, required this.onChanged});

  final String query;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query);
  }

  @override
  void didUpdateWidget(covariant _SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.query) {
      _controller.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('hub-search-field'),
      controller: _controller,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search hubs, buildings, areas…',
        prefixIcon: const Icon(Icons.search_outlined),
        suffixIcon: widget.query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear hub search',
                icon: const Icon(Icons.close),
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                },
              ),
      ),
    );
  }
}

class _CurrentHubBanner extends StatelessWidget {
  const _CurrentHubBanner({
    required this.hubName,
    required this.onLeave,
    required this.onOpenSplitBoard,
  });

  final String hubName;
  final VoidCallback onLeave;
  final VoidCallback onOpenSplitBoard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppIconContainer(
                icon: Icons.home_work_outlined,
                backgroundColor: theme.colorScheme.surface.withValues(
                  alpha: 0.72,
                ),
                foregroundColor: theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CURRENT HUB',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hubName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: onOpenSplitBoard,
                icon: const Icon(Icons.arrow_forward_outlined),
                label: const Text('View deals'),
                style: ButtonStyle(
                  foregroundColor: WidgetStatePropertyAll(
                    theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onLeave,
                icon: const Icon(Icons.logout_outlined),
                label: const Text('Leave hub'),
                style: ButtonStyle(
                  foregroundColor: WidgetStatePropertyAll(
                    theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HubList extends StatelessWidget {
  const _HubList({required this.viewModel});

  final JoinHubViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final hubs = viewModel.filteredHubs;

    if (hubs.isEmpty) {
      return _EmptyState(
        query: viewModel.searchQuery,
        nearbyOnly: viewModel.nearbyOnly,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
      itemCount: hubs.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final hub = hubs[index];
        final isJoined = viewModel.joinedHubId == hub.id;
        final isPending = viewModel.pendingSwitchId == hub.id;
        final showSwitch = !isJoined && viewModel.joinedHubId != null;

        return HubCard(
          hub: hub,
          isJoined: isJoined,
          isPendingSwitch: isPending,
          showSwitchAction: showSwitch,
          isBusy: viewModel.isUpdatingMembership,
          onJoin: () => viewModel.join(hub.id),
          onRequestSwitch: () => viewModel.requestSwitch(hub.id),
          onConfirmSwitch: viewModel.confirmSwitch,
          onCancelSwitch: viewModel.cancelSwitch,
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.query, required this.nearbyOnly});

  final String query;
  final bool nearbyOnly;

  @override
  Widget build(BuildContext context) {
    final hasQuery = query.trim().isNotEmpty;
    final radiusKm = (kNearbyRadiusMeters / 1000).round();

    final String title;
    final String hint;
    if (hasQuery) {
      title = 'No hubs match "$query"';
      hint = nearbyOnly
          ? 'Nothing within $radiusKm km matches. Check the spelling or turn off the distance filter.'
          : 'Check the spelling or register the hub if it is missing.';
    } else if (nearbyOnly) {
      title = 'No hubs nearby';
      hint =
          'Nothing is within $radiusKm km of you. Turn off the distance filter to see every hub.';
    } else {
      title = 'No hubs yet';
      hint = 'Register a hub to get your building on the list.';
    }

    return AppMessageState(
      icon: nearbyOnly && !hasQuery
          ? Icons.near_me_disabled_outlined
          : hasQuery
          ? Icons.search_off_outlined
          : Icons.home_work_outlined,
      title: title,
      message: hint,
    );
  }
}

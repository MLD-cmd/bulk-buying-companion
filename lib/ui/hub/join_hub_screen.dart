import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../profile/profile_screen.dart';
import '../shared/app_banner.dart';
import '../shared/app_icon_container.dart';
import '../shared/app_message_state.dart';
import '../shared/task_help_sheet.dart';
import '../split_board/split_board_screen.dart';
import 'create_hub_screen.dart';
import 'join_hub_viewmodel.dart';
import 'widgets/hub_card.dart';

const _hubContentMaxWidth = 720.0;

class _HubContent extends StatelessWidget {
  const _HubContent({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _hubContentMaxWidth),
        child: child,
      ),
    );
  }
}

class JoinHubScreen extends StatefulWidget {
  const JoinHubScreen({super.key});

  static const _helpLabel = 'How to find and join a hub';

  static const _helpSteps = [
    TaskHelpStep(
      icon: Icons.search_outlined,
      title: 'Search or use distance',
      body: 'Search by hub, building, or area. Filter by distance when shown.',
    ),
    TaskHelpStep(
      icon: Icons.domain_outlined,
      title: 'Review type and details',
      body: 'Check the hub type, members, and distance before choosing.',
    ),
    TaskHelpStep(
      icon: Icons.group_add_outlined,
      title: 'Join or switch',
      body: 'Join a hub, or confirm a switch from your current hub.',
    ),
  ];

  @override
  State<JoinHubScreen> createState() => _JoinHubScreenState();
}

class _JoinHubScreenState extends State<JoinHubScreen> {
  bool _leaveDialogInFlight = false;

  @override
  Widget build(BuildContext context) {
    void showHelp() => showTaskHelpSheet(
      context,
      title: JoinHubScreen._helpLabel,
      steps: JoinHubScreen._helpSteps,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find your hub'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_location_alt_outlined),
            tooltip: 'Register a hub',
            onPressed: () => _registerHub(context),
          ),
          Semantics(
            key: const Key('hub-help-button-semantics'),
            label: JoinHubScreen._helpLabel,
            button: true,
            onTap: showHelp,
            excludeSemantics: true,
            child: IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: JoinHubScreen._helpLabel,
              style: IconButton.styleFrom(minimumSize: const Size.square(48)),
              onPressed: showHelp,
            ),
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
              return Center(
                child: Semantics(
                  key: const Key('join-hub-loading'),
                  liveRegion: true,
                  label: 'Loading hubs',
                  child: ExcludeSemantics(child: CircularProgressIndicator()),
                ),
              );
            }

            if (viewModel.directoryErrorMessage != null &&
                !viewModel.hasDirectoryData) {
              return AppMessageState(
                icon: Icons.cloud_off_outlined,
                title: 'Couldn’t load hubs',
                message: 'Check your connection and try again.',
                onRetry: viewModel.refresh,
              );
            }

            final joinedHub = viewModel.joinedHub;

            return CustomScrollView(
              slivers: [
                if (joinedHub != null)
                  SliverToBoxAdapter(
                    child: _CurrentHubBanner(
                      hubName: joinedHub.name,
                      isBusy: viewModel.isUpdatingMembership,
                      isLeaving: viewModel.isLeaving,
                      onLeave: () => _confirmLeave(
                        context,
                        viewModel,
                        expectedHubId: joinedHub.id,
                        hubName: joinedHub.name,
                      ),
                      onOpenSplitBoard: () => _openSplitBoard(
                        context,
                        viewModel,
                        expectedHubId: joinedHub.id,
                        hubName: joinedHub.name,
                      ),
                    ),
                  ),
                if (viewModel.directoryErrorMessage != null ||
                    viewModel.membershipErrorMessage != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: _HubContent(
                        child: Column(
                          children: [
                            if (viewModel.directoryErrorMessage != null)
                              AppBanner.error(
                                message: viewModel.directoryErrorMessage!,
                                actionLabel: 'Try again',
                                onAction: viewModel.refresh,
                              ),
                            if (viewModel.directoryErrorMessage != null &&
                                viewModel.membershipErrorMessage != null)
                              const SizedBox(height: 8),
                            if (viewModel.membershipErrorMessage != null)
                              AppBanner.error(
                                message: viewModel.membershipErrorMessage!,
                                actionLabel: 'Try again',
                                onAction: viewModel.retryMembership,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                    child: _HubContent(
                      child: _SearchField(
                        query: viewModel.searchQuery,
                        onChanged: viewModel.setSearchQuery,
                      ),
                    ),
                  ),
                ),
                if (viewModel.canFilterByDistance)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                      child: _HubContent(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FilterChip(
                            key: const Key('hub-nearby-filter'),
                            avatar: const Icon(
                              Icons.near_me_outlined,
                              size: 18,
                            ),
                            label: Text(
                              'Within ${(kNearbyRadiusMeters / 1000).round()} km',
                            ),
                            selected: viewModel.nearbyOnly,
                            onSelected: viewModel.setNearbyOnly,
                          ),
                        ),
                      ),
                    ),
                  )
                else if (viewModel.locationFailureMessage != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                      child: _HubContent(
                        child: AppBanner.notice(
                          message: viewModel.locationFailureMessage!,
                          icon: Icons.location_off_outlined,
                          actionLabel: 'Try again',
                          onAction: viewModel.retryLocation,
                        ),
                      ),
                    ),
                  ),
                _HubResultsSliver(viewModel: viewModel),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmLeave(
    BuildContext context,
    JoinHubViewModel viewModel, {
    required String expectedHubId,
    required String hubName,
  }) async {
    if (_leaveDialogInFlight ||
        !mounted ||
        !context.mounted ||
        viewModel.isUpdatingMembership ||
        viewModel.joinedHubId != expectedHubId ||
        viewModel.joinedHub?.id != expectedHubId) {
      return;
    }

    _leaveDialogInFlight = true;
    var membershipContextChanged = false;
    void observeMembership() {
      if (viewModel.isUpdatingMembership ||
          viewModel.joinedHubId != expectedHubId) {
        membershipContextChanged = true;
      }
    }

    viewModel.addListener(observeMembership);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Leave $hubName?'),
          content: const Text(
            'You’ll need to join a hub again before you can open its Split Board.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Stay'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Leave hub'),
            ),
          ],
        ),
      );

      if (!mounted ||
          !context.mounted ||
          confirmed != true ||
          membershipContextChanged ||
          viewModel.isUpdatingMembership ||
          viewModel.joinedHubId != expectedHubId ||
          viewModel.joinedHub?.id != expectedHubId) {
        return;
      }

      await viewModel.leave();
    } finally {
      viewModel.removeListener(observeMembership);
      _leaveDialogInFlight = false;
    }
  }

  void _openSplitBoard(
    BuildContext context,
    JoinHubViewModel viewModel, {
    required String expectedHubId,
    required String hubName,
  }) {
    if (!mounted ||
        !context.mounted ||
        viewModel.isUpdatingMembership ||
        viewModel.joinedHubId != expectedHubId ||
        viewModel.joinedHub?.id != expectedHubId) {
      return;
    }

    Navigator.of(context).push(SplitBoardScreen.route(expectedHubId, hubName));
  }
}

Future<void> _registerHub(BuildContext context) async {
  final viewModel = context.read<JoinHubViewModel>();
  final messenger = ScaffoldMessenger.of(context);

  final hub = await Navigator.of(context).push(CreateHubScreen.route());
  if (hub == null) return;

  await viewModel.refresh();

  // The hub is registered either way — only the directory reload can fail. Say
  // which of the two happened rather than reporting a list that may be stale.
  if (viewModel.directoryErrorMessage != null) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${hub.name} was registered, but the hub list didn’t reload.',
        ),
        action: SnackBarAction(label: 'Retry', onPressed: viewModel.refresh),
      ),
    );
    return;
  }

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
    required this.isBusy,
    required this.isLeaving,
    required this.onLeave,
    required this.onOpenSplitBoard,
  });

  final String hubName;
  final bool isBusy;
  final bool isLeaving;
  final VoidCallback onLeave;
  final VoidCallback onOpenSplitBoard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget identity() => Row(
      key: const Key('current-hub-identity'),
      children: [
        AppIconContainer(
          icon: Icons.home_work_outlined,
          backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.72),
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
    );

    List<Widget> actionButtons() => [
      TextButton.icon(
        onPressed: isBusy ? null : onOpenSplitBoard,
        icon: const Icon(Icons.arrow_forward_outlined),
        label: const Text('View deals'),
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          foregroundColor: theme.colorScheme.onPrimaryContainer,
        ),
      ),
      TextButton.icon(
        onPressed: isBusy ? null : onLeave,
        icon: isLeaving
            ? ExcludeSemantics(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    color: theme.colorScheme.error,
                    strokeWidth: 2.2,
                  ),
                ),
              )
            : const Icon(Icons.logout_outlined),
        label: Text(isLeaving ? 'Leaving…' : 'Leave hub'),
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          foregroundColor: theme.colorScheme.error,
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: _HubContent(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final useCompactRow =
                constraints.maxWidth >= 560 && textScale <= 1.3;
            final actions = actionButtons();

            final content = useCompactRow
                ? Row(
                    children: [
                      Expanded(child: identity()),
                      const SizedBox(width: 12),
                      Row(
                        key: const Key('current-hub-actions'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          actions.first,
                          const SizedBox(width: 4),
                          actions.last,
                        ],
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      identity(),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          key: const Key('current-hub-actions'),
                          alignment: WrapAlignment.end,
                          spacing: 4,
                          runSpacing: 4,
                          children: actions,
                        ),
                      ),
                    ],
                  );

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.18),
                ),
              ),
              child: content,
            );
          },
        ),
      ),
    );
  }
}

class _HubResultsSliver extends StatelessWidget {
  const _HubResultsSliver({required this.viewModel});

  final JoinHubViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final hubs = viewModel.filteredHubs;

    if (hubs.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyState(
          query: viewModel.searchQuery,
          nearbyOnly: viewModel.nearbyOnly,
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
      sliver: SliverList.builder(
        itemCount: hubs.length,
        itemBuilder: (context, index) {
          final hub = hubs[index];
          final isJoined = viewModel.joinedHubId == hub.id;
          final isPending = viewModel.pendingSwitchId == hub.id;
          final showSwitch = !isJoined && viewModel.joinedHubId != null;

          return Padding(
            padding: EdgeInsets.only(bottom: index == hubs.length - 1 ? 0 : 10),
            child: _HubContent(
              child: HubCard(
                hub: hub,
                isJoined: isJoined,
                isPendingSwitch: isPending,
                showSwitchAction: showSwitch,
                isBusy: viewModel.isUpdatingMembership,
                isUpdatingThisHub: viewModel.isUpdatingHub(hub.id),
                busyLabel: showSwitch ? 'Switching…' : 'Joining…',
                onJoin: () => viewModel.join(hub.id),
                onRequestSwitch: () => viewModel.requestSwitch(hub.id),
                onConfirmSwitch: viewModel.confirmSwitch,
                onCancelSwitch: viewModel.cancelSwitch,
              ),
            ),
          );
        },
      ),
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

    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIconContainer(
                icon: nearbyOnly && !hasQuery
                    ? Icons.near_me_disabled_outlined
                    : hasQuery
                    ? Icons.search_off_outlined
                    : Icons.home_work_outlined,
                size: 52,
                iconSize: 24,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

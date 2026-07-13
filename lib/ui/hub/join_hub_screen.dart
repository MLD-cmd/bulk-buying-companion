import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../profile/profile_screen.dart';
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
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: _SearchField(
                    query: viewModel.searchQuery,
                    onChanged: viewModel.setSearchQuery,
                  ),
                ),
                Expanded(
                  child: _HubList(viewModel: viewModel),
                ),
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

class _SearchField extends StatelessWidget {
  const _SearchField({required this.query, required this.onChanged});

  final String query;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search hubs, buildings, areas…',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => onChanged(''),
              ),
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
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
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFDCEFE3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'CURRENT HUB',
                  style: TextStyle(
                    color: Color(0xFF3E7355),
                    fontSize: 10,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  hubName,
                  style: const TextStyle(
                    color: Color(0xFF173E28),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onOpenSplitBoard,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF173E28),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 0),
            ),
            child: const Text(
              'View deals',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: onLeave,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF173E28),
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
            ),
            child: const Text(
              'Leave',
              style: TextStyle(
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w700,
              ),
            ),
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
      return _EmptyState(query: viewModel.searchQuery);
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
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
  const _EmptyState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(
              'No hubs match "$query"',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Check the spelling, or ask your RA to get your hub added.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

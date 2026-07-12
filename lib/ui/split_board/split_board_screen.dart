import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/deal_repository.dart';
import 'split_board_viewmodel.dart';
import 'widgets/deal_card.dart';

class SplitBoardScreen extends StatelessWidget {
  const SplitBoardScreen({super.key, required this.hubId});

  final String hubId;

  static Route<void> route(String hubId, String hubName) {
    return MaterialPageRoute(
      builder: (context) => ChangeNotifierProvider(
        create: (context) => SplitBoardViewModel(
          dealRepository: context.read<DealRepository>(),
          hubId: hubId,
          hubName: hubName,
        ),
        child: SplitBoardScreen(hubId: hubId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<SplitBoardViewModel>(
          builder: (context, viewModel, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Split Board'),
              Text(
                viewModel.hubName,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Consumer<SplitBoardViewModel>(
          builder: (context, viewModel, _) {
            if (viewModel.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            return RefreshIndicator(
              onRefresh: viewModel.refresh,
              child: viewModel.hasError
                  ? const _ErrorState()
                  : viewModel.deals.isEmpty
                      ? const _EmptyState()
                      : _DealList(viewModel: viewModel),
            );
          },
        ),
      ),
    );
  }
}

class _DealList extends StatelessWidget {
  const _DealList({required this.viewModel});

  final SplitBoardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final deals = viewModel.deals;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      itemCount: deals.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) => DealCard(deal: deals[index]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const _CenteredMessage(
      icon: Icons.inventory_2_outlined,
      title: 'No deals yet in this hub',
      message: 'Be the first to post a bulk-buy deal for your hub.',
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState();

  @override
  Widget build(BuildContext context) {
    return const _CenteredMessage(
      icon: Icons.cloud_off_outlined,
      title: "Couldn't load deals",
      message: 'Pull down to try again.',
    );
  }
}

/// Full-height centered message used for the empty and error states. Wrapped
/// in a scroll view so pull-to-refresh still works when there is no list to
/// scroll (RefreshIndicator needs a scrollable child).
class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 40,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

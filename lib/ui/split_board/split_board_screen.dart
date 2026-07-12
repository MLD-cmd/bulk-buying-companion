import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/deal_repository.dart';
import 'split_board_viewmodel.dart';
import 'widgets/deal_card.dart';

class SplitBoardScreen extends StatelessWidget {
  const SplitBoardScreen({super.key, required this.hubId});

  final String hubId;

  static Route<void> route(String hubId) {
    return MaterialPageRoute(
      builder: (context) => ChangeNotifierProvider(
        create: (context) => SplitBoardViewModel(
          dealRepository: context.read<DealRepository>(),
          hubId: hubId,
        ),
        child: SplitBoardScreen(hubId: hubId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Split Board')),
      body: SafeArea(
        child: Consumer<SplitBoardViewModel>(
          builder: (context, viewModel, _) {
            if (viewModel.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            return RefreshIndicator(
              onRefresh: viewModel.refresh,
              child: viewModel.deals.isEmpty
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
    final theme = Theme.of(context);

    // Wrapped in a scroll view so pull-to-refresh still works when the
    // list is empty (RefreshIndicator needs a scrollable child).
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
                      Icons.inventory_2_outlined,
                      size: 40,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No deals yet in this hub',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Be the first to post a bulk-buy deal for your hub.',
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

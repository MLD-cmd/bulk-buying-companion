import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/deal_repository.dart';
import '../../models/deal.dart';
import 'create_deal_screen.dart';
import 'deal_details_screen.dart';
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
      floatingActionButton: Consumer<SplitBoardViewModel>(
        builder: (context, viewModel, _) => FloatingActionButton.extended(
          key: const Key('post-deal-button'),
          onPressed: () => _postDeal(context, hubId, viewModel),
          icon: const Icon(Icons.add),
          label: const Text('Post a deal'),
        ),
      ),
    );
  }
}

Future<void> _postDeal(
  BuildContext context,
  String hubId,
  SplitBoardViewModel viewModel,
) async {
  final messenger = ScaffoldMessenger.of(context);

  final deal = await Navigator.of(
    context,
  ).push(CreateDealScreen.route(hubId, viewModel.hubName));
  if (deal == null) return;

  await viewModel.refresh();
  messenger.showSnackBar(
    SnackBar(content: Text('${deal.title} is now on the Split Board.')),
  );
}

class _DealList extends StatelessWidget {
  const _DealList({required this.viewModel});

  final SplitBoardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final deals = viewModel.filteredDeals;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        _DealFilterBar(viewModel: viewModel),
        const SizedBox(height: 12),
        if (deals.isEmpty)
          const _NoMatchingDealsState()
        else
          for (final deal in deals) ...[
            InkWell(
              key: Key('deal-card-${deal.id}'),
              onTap: () =>
                  Navigator.of(context).push(DealDetailsScreen.route(deal)),
              borderRadius: BorderRadius.circular(8),
              child: DealCard(deal: deal),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _DealFilterBar extends StatefulWidget {
  const _DealFilterBar({required this.viewModel});

  final SplitBoardViewModel viewModel;

  @override
  State<_DealFilterBar> createState() => _DealFilterBarState();
}

class _DealFilterBarState extends State<_DealFilterBar> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: widget.viewModel.searchQuery,
    );
  }

  @override
  void didUpdateWidget(covariant _DealFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_searchController.text != widget.viewModel.searchQuery) {
      _searchController.text = widget.viewModel.searchQuery;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewModel = widget.viewModel;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: viewModel.updateSearchQuery,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Search by product name',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _HubFilterChip(hubName: viewModel.hubName),
                _FilterDropdown<DealCategory?>(
                  width: 164,
                  label: 'Category',
                  icon: Icons.category_outlined,
                  value: viewModel.categoryFilter,
                  items: [
                    const DropdownMenuItem<DealCategory?>(
                      value: null,
                      child: Text('All categories'),
                    ),
                    for (final category in DealCategory.values)
                      DropdownMenuItem<DealCategory?>(
                        value: category,
                        child: Text(category.label),
                      ),
                  ],
                  onChanged: viewModel.updateCategoryFilter,
                ),
                _FilterDropdown<DealStatus?>(
                  width: 154,
                  label: 'Status',
                  icon: Icons.fact_check_outlined,
                  value: viewModel.statusFilter,
                  items: [
                    const DropdownMenuItem<DealStatus?>(
                      value: null,
                      child: Text('All statuses'),
                    ),
                    for (final status in DealStatus.values)
                      DropdownMenuItem<DealStatus?>(
                        value: status,
                        child: Text(status.label),
                      ),
                  ],
                  onChanged: viewModel.updateStatusFilter,
                ),
                _FilterDropdown<DealSortOption>(
                  width: 148,
                  label: 'Sort',
                  icon: Icons.sort_outlined,
                  value: viewModel.sortOption,
                  items: [
                    for (final option in DealSortOption.values)
                      DropdownMenuItem<DealSortOption>(
                        value: option,
                        child: Text(option.label),
                      ),
                  ],
                  onChanged: (option) {
                    if (option != null) {
                      viewModel.updateSortOption(option);
                    }
                  },
                ),
                if (viewModel.hasActiveFilters)
                  TextButton.icon(
                    onPressed: viewModel.clearFilters,
                    icon: const Icon(Icons.close),
                    label: const Text('Clear'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HubFilterChip extends StatelessWidget {
  const _HubFilterChip({required this.hubName});

  final String hubName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 180,
      child: InputDecorator(
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.hub_outlined),
          labelText: 'Hub',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        child: Text(
          hubName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.width,
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final double width;
  final String label;
  final IconData icon;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        items: items,
        onChanged: onChanged,
        isExpanded: true,
        decoration: InputDecoration(
          prefixIcon: Icon(icon),
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

class _NoMatchingDealsState extends StatelessWidget {
  const _NoMatchingDealsState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 12),
      child: Column(
        children: [
          Icon(
            Icons.search_off_outlined,
            size: 36,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          Text(
            'No matching deals',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Adjust the search or filters to see more bulk-buy deals.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
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
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
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

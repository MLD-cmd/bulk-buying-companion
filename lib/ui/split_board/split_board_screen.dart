import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/deal_repository.dart';
import '../../models/deal.dart';
import '../shared/app_icon_container.dart';
import '../shared/app_message_state.dart';
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
              const SizedBox(height: 2),
              Text(
                viewModel.hubName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
                  ? AppMessageState(
                      icon: Icons.cloud_off_outlined,
                      title: "Couldn't load deals",
                      message: 'Check your connection and try again.',
                      onRetry: viewModel.refresh,
                    )
                  : viewModel.deals.isEmpty
                  ? const AppMessageState(
                      icon: Icons.inventory_2_outlined,
                      title: 'No deals yet in this hub',
                      message:
                          'Be the first to post a bulk-buy deal for your hub.',
                    )
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

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          sliver: SliverToBoxAdapter(
            child: _BoardContent(child: _DealFilterBar(viewModel: viewModel)),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 18)),
        if (deals.isEmpty)
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 100),
            sliver: SliverToBoxAdapter(
              child: _BoardContent(child: _NoMatchingDealsState()),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            sliver: SliverList.builder(
              itemCount: deals.length,
              itemBuilder: (context, index) {
                final deal = deals[index];
                return _BoardContent(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      key: Key('deal-card-${deal.id}'),
                      onTap: () async {
                        final updated = await Navigator.of(
                          context,
                        ).push(DealDetailsScreen.route(deal));
                        if (updated != null) viewModel.replaceDeal(updated);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: DealCard(deal: deal),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _BoardContent extends StatelessWidget {
  const _BoardContent({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: child,
      ),
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
      _searchController.value = TextEditingValue(
        text: widget.viewModel.searchQuery,
        selection: TextSelection.collapsed(
          offset: widget.viewModel.searchQuery.length,
        ),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final showInlineFilters =
            constraints.maxWidth >= 720 && textScale <= 1.3;
        final stackSearch = constraints.maxWidth < 330 || textScale > 1.3;
        final search = _SearchControl(
          controller: _searchController,
          query: viewModel.searchQuery,
          onChanged: viewModel.updateSearchQuery,
          onClear: () {
            _searchController.clear();
            viewModel.updateSearchQuery('');
          },
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showInlineFilters)
              search
            else if (stackSearch) ...[
              search,
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: _FiltersButton(viewModel: viewModel),
              ),
            ] else
              Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 10),
                  _FiltersButton(viewModel: viewModel),
                ],
              ),
            if (showInlineFilters) ...[
              const SizedBox(height: 12),
              _InlineFilters(viewModel: viewModel),
            ],
            if (_hasSecondaryFilters(viewModel)) ...[
              const SizedBox(height: 10),
              _ActiveFilters(viewModel: viewModel),
            ],
          ],
        );
      },
    );
  }
}

class _SearchControl extends StatelessWidget {
  const _SearchControl({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('board-search-field'),
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search by product name',
        prefixIcon: const Icon(Icons.search_outlined),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear deal search',
                onPressed: onClear,
                icon: const Icon(Icons.close),
              ),
      ),
    );
  }
}

class _FiltersButton extends StatelessWidget {
  const _FiltersButton({required this.viewModel});

  final SplitBoardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final count = _secondaryFilterCount(viewModel);
    return OutlinedButton.icon(
      key: const Key('board-filters-button'),
      onPressed: () => _showFilters(context, viewModel),
      icon: const Icon(Icons.tune_outlined),
      label: Text(count == 0 ? 'Filters' : 'Filters ($count)'),
    );
  }
}

class _InlineFilters extends StatelessWidget {
  const _InlineFilters({required this.viewModel});

  final SplitBoardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _CategoryDropdown(
            value: viewModel.categoryFilter,
            onChanged: viewModel.updateCategoryFilter,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatusDropdown(
            value: viewModel.statusFilter,
            onChanged: viewModel.updateStatusFilter,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SortDropdown(
            value: viewModel.sortOption,
            onChanged: viewModel.updateSortOption,
          ),
        ),
      ],
    );
  }
}

class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({required this.viewModel});

  final SplitBoardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (viewModel.categoryFilter != null)
          InputChip(
            label: Text(viewModel.categoryFilter!.label),
            onDeleted: () => viewModel.updateCategoryFilter(null),
            deleteButtonTooltipMessage: 'Remove category filter',
          ),
        if (viewModel.statusFilter != null)
          InputChip(
            label: Text(viewModel.statusFilter!.label),
            onDeleted: () => viewModel.updateStatusFilter(null),
            deleteButtonTooltipMessage: 'Remove status filter',
          ),
        if (viewModel.sortOption != DealSortOption.deadline)
          InputChip(
            label: Text('Sort: ${viewModel.sortOption.label}'),
            onDeleted: () =>
                viewModel.updateSortOption(DealSortOption.deadline),
            deleteButtonTooltipMessage: 'Reset sorting',
          ),
      ],
    );
  }
}

Future<void> _showFilters(BuildContext context, SplitBoardViewModel viewModel) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return AnimatedBuilder(
        animation: viewModel,
        builder: (context, _) {
          final theme = Theme.of(context);
          return SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Filter deals', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 6),
                      Text(
                        viewModel.hubName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _CategoryDropdown(
                        value: viewModel.categoryFilter,
                        onChanged: viewModel.updateCategoryFilter,
                      ),
                      const SizedBox(height: 12),
                      _StatusDropdown(
                        value: viewModel.statusFilter,
                        onChanged: viewModel.updateStatusFilter,
                      ),
                      const SizedBox(height: 12),
                      _SortDropdown(
                        value: viewModel.sortOption,
                        onChanged: viewModel.updateSortOption,
                      ),
                      const SizedBox(height: 20),
                      if (_hasSecondaryFilters(viewModel)) ...[
                        TextButton.icon(
                          onPressed: () => _clearSecondaryFilters(viewModel),
                          icon: const Icon(Icons.close),
                          label: const Text('Clear filters'),
                        ),
                        const SizedBox(height: 8),
                      ],
                      FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('Show deals'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

class _CategoryDropdown extends StatelessWidget {
  const _CategoryDropdown({required this.value, required this.onChanged});

  final DealCategory? value;
  final ValueChanged<DealCategory?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<DealCategory?>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Category',
        prefixIcon: Icon(Icons.category_outlined),
      ),
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
      onChanged: onChanged,
    );
  }
}

class _StatusDropdown extends StatelessWidget {
  const _StatusDropdown({required this.value, required this.onChanged});

  final DealStatus? value;
  final ValueChanged<DealStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<DealStatus?>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Status',
        prefixIcon: Icon(Icons.fact_check_outlined),
      ),
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
      onChanged: onChanged,
    );
  }
}

class _SortDropdown extends StatelessWidget {
  const _SortDropdown({required this.value, required this.onChanged});

  final DealSortOption value;
  final ValueChanged<DealSortOption> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<DealSortOption>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Sort by',
        prefixIcon: Icon(Icons.sort_outlined),
      ),
      items: [
        for (final option in DealSortOption.values)
          DropdownMenuItem(value: option, child: Text(option.label)),
      ],
      onChanged: (option) {
        if (option != null) onChanged(option);
      },
    );
  }
}

bool _hasSecondaryFilters(SplitBoardViewModel viewModel) {
  return _secondaryFilterCount(viewModel) > 0;
}

int _secondaryFilterCount(SplitBoardViewModel viewModel) {
  return (viewModel.categoryFilter == null ? 0 : 1) +
      (viewModel.statusFilter == null ? 0 : 1) +
      (viewModel.sortOption == DealSortOption.deadline ? 0 : 1);
}

void _clearSecondaryFilters(SplitBoardViewModel viewModel) {
  viewModel.updateCategoryFilter(null);
  viewModel.updateStatusFilter(null);
  viewModel.updateSortOption(DealSortOption.deadline);
}

class _NoMatchingDealsState extends StatelessWidget {
  const _NoMatchingDealsState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      child: Column(
        children: [
          const AppIconContainer(
            icon: Icons.search_off_outlined,
            size: 52,
            iconSize: 24,
          ),
          const SizedBox(height: 14),
          Text('No matching deals', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Adjust the search or filters to see more bulk-buy deals.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

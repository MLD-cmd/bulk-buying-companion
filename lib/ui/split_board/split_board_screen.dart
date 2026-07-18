import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/deal_repository.dart';
import '../../data/repositories/recommendation_repository.dart';
import '../../data/repositories/reservation_repository.dart';
import '../../models/deal.dart';
import '../shared/app_banner.dart';
import '../shared/app_icon_container.dart';
import '../shared/app_message_state.dart';
import 'create_deal_screen.dart';
import 'deal_details_screen.dart';
import 'recommendations_viewmodel.dart';
import 'split_board_viewmodel.dart';
import 'widgets/deal_card.dart';
import 'widgets/recommended_deals_section.dart';

class SplitBoardScreen extends StatefulWidget {
  const SplitBoardScreen({super.key, required this.hubId});

  final String hubId;

  static Route<void> route(String hubId, String hubName) {
    return MaterialPageRoute(
      builder: (context) => MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (context) => SplitBoardViewModel(
              dealRepository: context.read<DealRepository>(),
              hubId: hubId,
              hubName: hubName,
            ),
          ),
          // Recommendations need a signed-in student and the personalisation
          // repository. The strip is optional everywhere it is read, so a build
          // without either simply shows no recommendations rather than failing.
          ChangeNotifierProvider<RecommendationsViewModel?>(
            create: (context) {
              // Every dependency is read as optional: a build that has not
              // wired auth, reservations, or personalisation — as some widget
              // tests do not — shows no recommendations rather than throwing.
              final userId = context.read<AuthRepository?>()?.currentUser?.uid;
              final reservationRepository = context
                  .read<ReservationRepository?>();
              final recommendationRepository = context
                  .read<RecommendationRepository?>();
              if (userId == null ||
                  reservationRepository == null ||
                  recommendationRepository == null) {
                return null;
              }
              return RecommendationsViewModel(
                dealRepository: context.read<DealRepository>(),
                reservationRepository: reservationRepository,
                recommendationRepository: recommendationRepository,
                userId: userId,
                hubId: hubId,
              );
            },
          ),
        ],
        child: SplitBoardScreen(hubId: hubId),
      ),
    );
  }

  @override
  State<SplitBoardScreen> createState() => _SplitBoardScreenState();
}

class _SplitBoardScreenState extends State<SplitBoardScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
              return Center(
                child: Semantics(
                  key: const Key('split-board-loading'),
                  liveRegion: true,
                  label: 'Loading deals',
                  child: ExcludeSemantics(child: CircularProgressIndicator()),
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: viewModel.refresh,
              child: viewModel.hasError && viewModel.deals.isEmpty
                  ? AppMessageState(
                      icon: Icons.cloud_off_outlined,
                      title: "Couldn't load deals",
                      message: 'Check your connection and try again.',
                      onRetry: viewModel.refresh,
                      retryBusy: viewModel.isRefreshing,
                    )
                  : viewModel.deals.isEmpty
                  ? const AppMessageState(
                      icon: Icons.inventory_2_outlined,
                      title: 'No deals yet in this hub',
                      message:
                          'Be the first to post a bulk-buy deal for your hub.',
                    )
                  : _DealList(
                      viewModel: viewModel,
                      scrollController: _scrollController,
                    ),
            );
          },
        ),
      ),
      floatingActionButton: Consumer<SplitBoardViewModel>(
        builder: (context, viewModel, _) => FloatingActionButton.extended(
          key: const Key('post-deal-button'),
          onPressed: () => _postDeal(context, widget.hubId, viewModel),
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
  final deal = await Navigator.of(
    context,
  ).push(CreateDealScreen.route(hubId, viewModel.hubName));
  if (!context.mounted) return;
  if (deal == null) return;

  await viewModel.refresh();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('${deal.title} is now on the Split Board.')),
  );
}

class _DealList extends StatelessWidget {
  const _DealList({required this.viewModel, required this.scrollController});

  final SplitBoardViewModel viewModel;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final deals = viewModel.filteredDeals;

    return CustomScrollView(
      key: const PageStorageKey<String>('board-scroll-view'),
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (viewModel.refreshErrorMessage != null) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            sliver: SliverToBoxAdapter(
              child: _BoardContent(
                child: AppBanner.error(
                  key: const Key('board-refresh-error'),
                  message: viewModel.refreshErrorMessage!,
                  actionLabel: 'Try again',
                  onAction: viewModel.refresh,
                  actionBusy: viewModel.isRefreshing,
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
        ],
        SliverToBoxAdapter(
          child: _RecommendationsStrip(
            splitBoardViewModel: viewModel,
            scrollController: scrollController,
          ),
        ),
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
                      onTap: () =>
                          _openDeal(context, deal, viewModel, scrollController),
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

/// Opens a deal's details and, if it came back changed, swaps the new copy into
/// the board. Shared by the deal list and the recommendations strip so both
/// keep the board in step after a slot is claimed or released, and both restore
/// the scroll position they were at.
Future<void> _openDeal(
  BuildContext context,
  Deal deal,
  SplitBoardViewModel viewModel,
  ScrollController scrollController,
) async {
  final preservedOffset = scrollController.hasClients
      ? scrollController.offset
      : null;
  final updated = await Navigator.of(
    context,
  ).push(DealDetailsScreen.route(deal));
  if (!context.mounted) return;
  if (updated != null && !identical(updated, deal)) {
    viewModel.replaceDeal(updated);
  }
  if (preservedOffset != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollController.hasClients) return;
        scrollController.jumpTo(
          preservedOffset
              .clamp(
                scrollController.position.minScrollExtent,
                scrollController.position.maxScrollExtent,
              )
              .toDouble(),
        );
      });
    });
  }
}

/// The board's slot for [RecommendedDealsSection]. Reads the recommendations
/// ViewModel as nullable so a Split Board built without one — as the widget
/// tests do — simply renders nothing here.
///
/// It also owns the three states a bare [RecommendedDealsSection] cannot tell
/// apart on its own, because only the ViewModel knows them: still computing,
/// nothing to show because no categories are set, and nothing to show because
/// no open deal matches.
class _RecommendationsStrip extends StatelessWidget {
  const _RecommendationsStrip({
    required this.splitBoardViewModel,
    required this.scrollController,
  });

  final SplitBoardViewModel splitBoardViewModel;
  final ScrollController scrollController;

  static const _padding = EdgeInsets.fromLTRB(20, 8, 20, 4);

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<RecommendationsViewModel?>();
    if (viewModel == null) return const SizedBox.shrink();

    if (viewModel.recommendations.isNotEmpty) {
      return Padding(
        padding: _padding,
        child: _BoardContent(
          child: RecommendedDealsSection(
            recommendations: viewModel.recommendations,
            onOpenDeal: (deal) =>
                _openDeal(context, deal, splitBoardViewModel, scrollController),
            onDismiss: (deal) => _dismiss(context, viewModel, deal),
          ),
        ),
      );
    }

    // Still working out the first set of picks: show the header and a couple of
    // placeholder shapes rather than popping the strip in once it resolves.
    if (viewModel.isLoading) {
      return const Padding(
        padding: _padding,
        child: _BoardContent(child: _RecommendationsLoading()),
      );
    }

    // Settled with nothing to show. If the student has set no categories, point
    // them at where they would. If they have and still nothing matches, there
    // is nothing to say — the board below is the whole answer.
    if (viewModel.preferredCategories.isEmpty) {
      return const Padding(
        padding: _padding,
        child: _BoardContent(child: _RecommendationsHint()),
      );
    }

    return const SizedBox.shrink();
  }

  /// Dismisses, then — if the write failed and the card came back — says why.
  /// The ViewModel has already restored the card by the time the future
  /// completes, so the SnackBar is the only thing left to add.
  Future<void> _dismiss(
    BuildContext context,
    RecommendationsViewModel viewModel,
    Deal deal,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await viewModel.dismiss(deal.id);
    if (!context.mounted) return;
    final error = viewModel.dismissErrorMessage;
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

/// The strip's placeholder while the first recommendations resolve. Mirrors the
/// real section's header and a short row of card-shaped blanks.
class _RecommendationsLoading extends StatelessWidget {
  const _RecommendationsLoading();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final cardHeight = 176.0 * (textScale > 1 ? textScale : 1);

    return Semantics(
      liveRegion: true,
      label: 'Loading recommendations',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('Recommended for you', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: cardHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                clipBehavior: Clip.none,
                itemCount: 2,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) => DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const SizedBox(width: 250),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown once recommendations have settled empty and the student has chosen no
/// categories: a slim nudge towards the profile, where the picks come from.
class _RecommendationsHint extends StatelessWidget {
  const _RecommendationsHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('recommendations-empty-hint'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Set your preferred categories in your profile to get deal picks here.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
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

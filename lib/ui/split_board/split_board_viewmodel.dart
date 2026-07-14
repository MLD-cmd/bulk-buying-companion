import 'package:flutter/foundation.dart';

import '../../data/repositories/deal_repository.dart';
import '../../models/deal.dart';

/// Drives the Split Board feed for a single hub. Loads the hub's deals on
/// construction and exposes [refresh] for pull-to-refresh.
class SplitBoardViewModel extends ChangeNotifier {
  SplitBoardViewModel({
    required DealRepository dealRepository,
    required String hubId,
    required this.hubName,
  }) : _dealRepository = dealRepository,
       _hubId = hubId {
    _load();
  }

  final DealRepository _dealRepository;
  final String _hubId;

  /// Name of the hub whose deals are shown, used in the screen header.
  final String hubName;

  List<Deal> _deals = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _searchQuery = '';
  DealCategory? _categoryFilter;
  DealStatus? _statusFilter;
  DealSortOption _sortOption = DealSortOption.deadline;

  List<Deal> get deals => _deals;
  List<Deal> get filteredDeals {
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    final matchingDeals = _deals.where((deal) {
      final matchesSearch =
          normalizedQuery.isEmpty ||
          deal.title.toLowerCase().contains(normalizedQuery);
      final matchesCategory =
          _categoryFilter == null || deal.category == _categoryFilter;
      final matchesStatus =
          _statusFilter == null || deal.status == _statusFilter;
      return matchesSearch && matchesCategory && matchesStatus;
    }).toList();

    matchingDeals.sort((a, b) {
      return switch (_sortOption) {
        DealSortOption.deadline => _compareDeadlines(a, b),
        DealSortOption.price => _priceValue(a).compareTo(_priceValue(b)),
      };
    });

    return matchingDeals;
  }

  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  String get searchQuery => _searchQuery;
  DealCategory? get categoryFilter => _categoryFilter;
  DealStatus? get statusFilter => _statusFilter;
  DealSortOption get sortOption => _sortOption;
  bool get hasActiveFilters =>
      _searchQuery.trim().isNotEmpty ||
      _categoryFilter != null ||
      _statusFilter != null;

  Future<void> _load() async {
    _isLoading = true;
    _hasError = false;
    notifyListeners();

    try {
      _deals = await _dealRepository.getDeals(_hubId);
    } catch (_) {
      _hasError = true;
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Re-fetches the hub's deals. Wired to both the pull-to-refresh gesture
  /// and the retry action on the error state.
  Future<void> refresh() async {
    try {
      _deals = await _dealRepository.getDeals(_hubId);
      _hasError = false;
    } catch (_) {
      _hasError = true;
    }
    notifyListeners();
  }

  void updateSearchQuery(String query) {
    if (_searchQuery == query) {
      return;
    }
    _searchQuery = query;
    notifyListeners();
  }

  void updateCategoryFilter(DealCategory? category) {
    if (_categoryFilter == category) {
      return;
    }
    _categoryFilter = category;
    notifyListeners();
  }

  void updateStatusFilter(DealStatus? status) {
    if (_statusFilter == status) {
      return;
    }
    _statusFilter = status;
    notifyListeners();
  }

  void updateSortOption(DealSortOption option) {
    if (_sortOption == option) {
      return;
    }
    _sortOption = option;
    notifyListeners();
  }

  /// Swaps in a deal whose slot count changed while the student was looking at
  /// it, so the board does not keep showing the count it was pushed with.
  void replaceDeal(Deal deal) {
    final index = _deals.indexWhere((existing) => existing.id == deal.id);
    if (index == -1) return;

    _deals = [..._deals]..[index] = deal;
    notifyListeners();
  }

  void clearFilters() {
    if (!hasActiveFilters) {
      return;
    }
    _searchQuery = '';
    _categoryFilter = null;
    _statusFilter = null;
    notifyListeners();
  }

  int _compareDeadlines(Deal a, Deal b) {
    final aDeadline = a.closesAt;
    final bDeadline = b.closesAt;
    if (aDeadline == null && bDeadline == null) {
      return 0;
    }
    if (aDeadline == null) {
      return 1;
    }
    if (bDeadline == null) {
      return -1;
    }
    return aDeadline.compareTo(bDeadline);
  }

  double _priceValue(Deal deal) => deal.pricePerShare;
}

enum DealSortOption {
  deadline('Deadline'),
  price('Price');

  const DealSortOption(this.label);

  final String label;
}

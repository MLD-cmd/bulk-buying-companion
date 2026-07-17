import 'dart:async';

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
    // The first emission answers a read issued right here, so it is subject to
    // the same generation check as any other read: a refresh started while it
    // was in flight is newer and must win. Later emissions are live pushes.
    _subscribeGeneration = ++_loadGeneration;
    _subscription = _dealRepository
        .watchDeals(_hubId)
        .listen(_setDeals, onError: (_) => _setError());
  }

  final DealRepository _dealRepository;
  final String _hubId;
  late final StreamSubscription<List<Deal>> _subscription;

  /// Name of the hub whose deals are shown, used in the screen header.
  final String hubName;

  List<Deal> _deals = [];
  bool _isLoading = true;
  bool _hasError = false;
  bool _isRefreshing = false;
  String? _refreshErrorMessage;
  Future<void>? _refreshOperation;
  int _loadGeneration = 0;
  late final int _subscribeGeneration;
  bool _awaitingFirstEmission = true;
  bool _isDisposed = false;
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
      // Completed and cancelled deals are not open business. They stay
      // reachable through the filter, but they do not clutter the board.
      final matchesStatus = _statusFilter == null
          ? !deal.status.isFinished
          : deal.status == _statusFilter;
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
  bool get isRefreshing => _isRefreshing;
  String? get refreshErrorMessage => _refreshErrorMessage;
  String get searchQuery => _searchQuery;
  DealCategory? get categoryFilter => _categoryFilter;
  DealStatus? get statusFilter => _statusFilter;
  DealSortOption get sortOption => _sortOption;
  bool get hasActiveFilters =>
      _searchQuery.trim().isNotEmpty ||
      _categoryFilter != null ||
      _statusFilter != null;

  /// Re-fetches the hub's deals. Wired to both the pull-to-refresh gesture
  /// and the retry action on the error state.
  Future<void> refresh() {
    if (_isDisposed) return Future<void>.value();
    final activeOperation = _refreshOperation;
    if (activeOperation != null) return activeOperation;

    final generation = ++_loadGeneration;
    final completer = Completer<void>();
    _refreshOperation = completer.future;
    _isRefreshing = true;
    _notifyListeners();

    _refresh(
      generation,
    ).then((_) => completer.complete(), onError: completer.completeError);
    return completer.future;
  }

  Future<void> _refresh(int generation) async {
    try {
      final loadedDeals = await _dealRepository.getDeals(_hubId);
      if (!_canCommit(generation)) return;
      _deals = loadedDeals;
      _hasError = false;
      _refreshErrorMessage = null;
    } catch (_) {
      if (!_canCommit(generation)) return;
      if (_deals.isEmpty) {
        _hasError = true;
        _refreshErrorMessage = null;
      } else {
        _hasError = false;
        _refreshErrorMessage =
            'Couldn’t refresh deals. Showing the deals already loaded.';
      }
    } finally {
      if (_canCommit(generation)) {
        _isLoading = false;
        _isRefreshing = false;
        _refreshOperation = null;
        _notifyListeners();
      }
    }
  }

  void updateSearchQuery(String query) {
    if (_isDisposed) return;
    if (_searchQuery == query) {
      return;
    }
    _searchQuery = query;
    _notifyListeners();
  }

  void updateCategoryFilter(DealCategory? category) {
    if (_isDisposed) return;
    if (_categoryFilter == category) {
      return;
    }
    _categoryFilter = category;
    _notifyListeners();
  }

  void updateStatusFilter(DealStatus? status) {
    if (_isDisposed) return;
    if (_statusFilter == status) {
      return;
    }
    _statusFilter = status;
    _notifyListeners();
  }

  void updateSortOption(DealSortOption option) {
    if (_isDisposed) return;
    if (_sortOption == option) {
      return;
    }
    _sortOption = option;
    _notifyListeners();
  }

  /// Swaps in a deal whose slot count changed while the student was looking at
  /// it, so the board does not keep showing the count it was pushed with.
  void replaceDeal(Deal deal) {
    if (_isDisposed) return;
    final index = _deals.indexWhere((existing) => existing.id == deal.id);
    if (index == -1) return;

    _deals = [..._deals]..[index] = deal;
    _notifyListeners();
  }

  void clearFilters() {
    if (_isDisposed) return;
    if (!hasActiveFilters) {
      return;
    }
    _searchQuery = '';
    _categoryFilter = null;
    _statusFilter = null;
    _notifyListeners();
  }

  bool _canCommit(int generation) =>
      !_isDisposed && generation == _loadGeneration;

  void _notifyListeners() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    // Retires any in-flight refresh: _canCommit compares against this.
    _loadGeneration++;
    _subscription.cancel();
    super.dispose();
  }

  void _setDeals(List<Deal> deals) {
    if (_isDisposed) return;
    final wasFirst = _awaitingFirstEmission;
    _awaitingFirstEmission = false;
    // Only the first emission can be stale; a later push is newer than any read
    // already in flight, so it retires them instead of deferring to them.
    if (wasFirst) {
      if (!_canCommit(_subscribeGeneration)) return;
    } else {
      _loadGeneration++;
    }

    _deals = deals;
    _hasError = false;
    // Fresh deals arrived, so "showing the deals already loaded" is no longer
    // true — the stream has overtaken whatever refresh failed.
    _refreshErrorMessage = null;
    _isLoading = false;
    _isRefreshing = false;
    _refreshOperation = null;
    _notifyListeners();
  }

  void _setError() {
    if (_isDisposed) return;
    final wasFirst = _awaitingFirstEmission;
    _awaitingFirstEmission = false;
    if (wasFirst && !_canCommit(_subscribeGeneration)) return;

    // Keeps whatever is already on the board: a dropped stream is a failure to
    // read the deals, not word that there are none.
    if (_deals.isEmpty) _hasError = true;
    _isLoading = false;
    _notifyListeners();
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

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
  })  : _dealRepository = dealRepository,
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

  List<Deal> get deals => _deals;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;

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
}

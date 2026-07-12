import 'package:flutter/foundation.dart';

import '../../data/repositories/deal_repository.dart';
import '../../models/deal.dart';

/// Drives the Split Board feed for a single hub. Loads the hub's deals on
/// construction and exposes [refresh] for pull-to-refresh.
class SplitBoardViewModel extends ChangeNotifier {
  SplitBoardViewModel({
    required DealRepository dealRepository,
    required String hubId,
  })  : _dealRepository = dealRepository,
        _hubId = hubId {
    _load();
  }

  final DealRepository _dealRepository;
  final String _hubId;

  List<Deal> _deals = [];
  bool _isLoading = true;

  List<Deal> get deals => _deals;
  bool get isLoading => _isLoading;

  Future<void> _load() async {
    _isLoading = true;
    notifyListeners();

    _deals = await _dealRepository.getDeals(_hubId);
    _isLoading = false;
    notifyListeners();
  }

  /// Re-fetches the hub's deals. Wired to both the pull-to-refresh gesture
  /// and any manual reload trigger on the screen.
  Future<void> refresh() async {
    _deals = await _dealRepository.getDeals(_hubId);
    notifyListeners();
  }
}

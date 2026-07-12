import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/hub_repository.dart';
import '../../models/app_user.dart';
import '../../models/hub.dart';

class JoinHubViewModel extends ChangeNotifier {
  JoinHubViewModel({
    required AuthRepository authRepository,
    required HubRepository hubRepository,
  }) : _authRepository = authRepository,
       _hubRepository = hubRepository {
    _authSub = _authRepository.authStateChanges.listen(_onAuthChanged);
    final currentUser = _authRepository.currentUser;
    if (currentUser != null) _load(currentUser.uid);
  }

  final AuthRepository _authRepository;
  final HubRepository _hubRepository;
  late final StreamSubscription<AppUser?> _authSub;

  List<Hub> _hubs = [];
  String _searchQuery = '';
  String? _joinedHubId;
  String? _pendingSwitchId;
  bool _isLoading = true;

  List<Hub> get filteredHubs {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _hubs;
    return _hubs.where((hub) {
      return hub.name.toLowerCase().contains(query) ||
          hub.type.name.toLowerCase().contains(query);
    }).toList();
  }

  String get searchQuery => _searchQuery;
  String? get joinedHubId => _joinedHubId;
  String? get pendingSwitchId => _pendingSwitchId;
  bool get isLoading => _isLoading;

  Hub? get joinedHub {
    if (_joinedHubId == null) return null;
    for (final hub in _hubs) {
      if (hub.id == _joinedHubId) return hub;
    }
    return null;
  }

  void _onAuthChanged(AppUser? user) {
    if (user == null) return;
    _load(user.uid);
  }

  Future<void> _load(String userId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final results = await Future.wait([
        _hubRepository.getHubs(),
        _hubRepository.getCurrentHubId(userId),
      ]);

      _hubs = results[0] as List<Hub>;
      _joinedHubId = results[1] as String?;
    } catch (_) {
      _hubs = const [];
      _joinedHubId = null;
      _pendingSwitchId = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Joining when nothing is joined yet commits immediately; switching
  /// away from an existing hub asks for confirmation first via
  /// [requestSwitch] / [confirmSwitch] / [cancelSwitch].
  Future<void> join(String hubId) async {
    final userId = _authRepository.currentUser?.uid;
    if (userId == null) return;
    await _hubRepository.joinHub(userId: userId, hubId: hubId);
    _joinedHubId = hubId;
    notifyListeners();
  }

  void requestSwitch(String hubId) {
    _pendingSwitchId = hubId;
    notifyListeners();
  }

  void cancelSwitch() {
    _pendingSwitchId = null;
    notifyListeners();
  }

  Future<void> confirmSwitch() async {
    final hubId = _pendingSwitchId;
    if (hubId == null) return;
    _pendingSwitchId = null;
    await join(hubId);
  }

  Future<void> leave() async {
    final userId = _authRepository.currentUser?.uid;
    if (userId == null) return;
    await _hubRepository.leaveHub(userId: userId);
    _joinedHubId = null;
    _pendingSwitchId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }
}

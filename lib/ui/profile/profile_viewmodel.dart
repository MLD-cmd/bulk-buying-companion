import 'package:flutter/foundation.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/hub_repository.dart';
import '../../models/app_user.dart';
import '../../models/hub.dart';

class ProfileViewModel extends ChangeNotifier {
  ProfileViewModel({
    required AuthRepository authRepository,
    required HubRepository hubRepository,
  }) : _authRepository = authRepository,
       _hubRepository = hubRepository {
    _load();
  }

  final AuthRepository _authRepository;
  final HubRepository _hubRepository;

  AppUser? _user;
  Hub? _currentHub;
  bool _isLoading = true;

  AppUser? get user => _user;
  Hub? get currentHub => _currentHub;
  bool get isLoading => _isLoading;

  Future<void> signOut() => _authRepository.signOut();

  Future<void> _load() async {
    final user = _authRepository.currentUser;
    _user = user;

    if (user != null) {
      final hubId = await _hubRepository.getCurrentHubId(user.uid);
      if (hubId != null) {
        final hubs = await _hubRepository.getHubs();
        for (final hub in hubs) {
          if (hub.id == hubId) {
            _currentHub = hub;
            break;
          }
        }
      }
    }

    _isLoading = false;
    notifyListeners();
  }
}

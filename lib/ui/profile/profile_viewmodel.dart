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
  bool _isSigningOut = false;
  String? _errorMessage;

  AppUser? get user => _user;
  Hub? get currentHub => _currentHub;
  bool get isLoading => _isLoading;
  bool get isSigningOut => _isSigningOut;
  String? get errorMessage => _errorMessage;

  Future<bool> signOut() async {
    if (_isSigningOut) return false;
    _isSigningOut = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authRepository.signOut();
      return true;
    } on AuthFailure catch (error) {
      _errorMessage = error.message;
      return false;
    } catch (_) {
      _errorMessage = 'Could not log out. Please try again.';
      return false;
    } finally {
      _isSigningOut = false;
      notifyListeners();
    }
  }

  Future<void> _load() async {
    final user = _authRepository.currentUser;
    _user = user;
    _errorMessage = null;

    try {
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
    } catch (_) {
      _currentHub = null;
      _errorMessage = 'Could not load profile. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}

import 'dart:async';

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
    _user = _authRepository.currentUser;
    _activeUid = _user?.uid;
    _load();
    _authSubscription = _authRepository.authStateChanges.listen(
      _handleAuthStateChange,
    );
  }

  final AuthRepository _authRepository;
  final HubRepository _hubRepository;

  AppUser? _user;
  Hub? _currentHub;
  bool _isLoading = true;
  bool _isSigningOut = false;
  String? _loadErrorMessage;
  String? _signOutErrorMessage;
  int _loadGeneration = 0;
  int _identityGeneration = 0;
  int _signOutGeneration = 0;
  String? _activeUid;
  StreamSubscription<AppUser?>? _authSubscription;
  bool _isDisposed = false;

  AppUser? get user => _user;
  Hub? get currentHub => _currentHub;
  bool get isLoading => _isLoading;
  bool get isSigningOut => _isSigningOut;
  String? get loadErrorMessage => _loadErrorMessage;
  String? get signOutErrorMessage => _signOutErrorMessage;

  Future<bool> signOut() async {
    if (_isDisposed || _isSigningOut) return false;
    final generation = ++_signOutGeneration;
    final identityGeneration = _identityGeneration;
    final uid = _activeUid;
    _isSigningOut = true;
    _signOutErrorMessage = null;
    _notifyListeners();

    try {
      await _authRepository.signOut();
      if (_isDisposed) return false;
      return _activeUid == null ||
          _canCommitSignOut(generation, identityGeneration, uid);
    } on AuthFailure catch (error) {
      if (_canCommitSignOut(generation, identityGeneration, uid)) {
        _signOutErrorMessage = error.message;
      }
      return false;
    } catch (_) {
      if (_canCommitSignOut(generation, identityGeneration, uid)) {
        _signOutErrorMessage = 'Could not log out. Please try again.';
      }
      return false;
    } finally {
      if (_canCommitSignOut(generation, identityGeneration, uid)) {
        _isSigningOut = false;
        _notifyListeners();
      }
    }
  }

  Future<void> retryLoad() => _load();

  Future<void> _load() async {
    if (_isDisposed) return;
    final generation = ++_loadGeneration;
    final identityGeneration = _identityGeneration;
    final user = _user;
    final uid = user?.uid;
    _isLoading = true;
    _notifyListeners();

    try {
      Hub? loadedHub;
      if (user != null) {
        final hubId = await _hubRepository.getCurrentHubId(user.uid);
        if (hubId != null) {
          final hubs = await _hubRepository.getHubs();
          for (final hub in hubs) {
            if (hub.id == hubId) {
              loadedHub = hub;
              break;
            }
          }
          if (loadedHub == null) {
            throw StateError('Current hub is missing from the directory.');
          }
        }
      }

      if (!_canCommitLoad(generation, identityGeneration, uid)) return;
      _currentHub = loadedHub;
      _loadErrorMessage = null;
    } catch (_) {
      if (!_canCommitLoad(generation, identityGeneration, uid)) return;
      _loadErrorMessage =
          'Couldn’t load your current hub. Check your connection and try again.';
    } finally {
      if (_canCommitLoad(generation, identityGeneration, uid)) {
        _isLoading = false;
        _notifyListeners();
      }
    }
  }

  void _handleAuthStateChange(AppUser? user) {
    if (_isDisposed) return;
    final uid = user?.uid;
    if (uid == _activeUid) {
      _user = user;
      _notifyListeners();
      return;
    }

    _identityGeneration++;
    _loadGeneration++;
    _signOutGeneration++;
    _activeUid = uid;
    _user = user;
    _currentHub = null;
    _loadErrorMessage = null;
    _signOutErrorMessage = null;
    _isLoading = false;
    _isSigningOut = false;
    _load();
  }

  bool _canCommitLoad(int generation, int identityGeneration, String? uid) {
    return !_isDisposed &&
        generation == _loadGeneration &&
        identityGeneration == _identityGeneration &&
        uid == _activeUid;
  }

  bool _canCommitSignOut(int generation, int identityGeneration, String? uid) {
    return !_isDisposed &&
        generation == _signOutGeneration &&
        identityGeneration == _identityGeneration &&
        uid == _activeUid;
  }

  void _notifyListeners() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _identityGeneration++;
    _loadGeneration++;
    _signOutGeneration++;
    _authSubscription?.cancel();
    super.dispose();
  }
}

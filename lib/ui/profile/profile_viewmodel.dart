import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/deal_repository.dart';
import '../../data/repositories/hub_repository.dart';
import '../../data/repositories/reservation_repository.dart';
import '../../models/app_user.dart';
import '../../models/deal.dart';
import '../../models/hub.dart';

class ProfileViewModel extends ChangeNotifier {
  ProfileViewModel({
    required AuthRepository authRepository,
    required HubRepository hubRepository,
    required DealRepository dealRepository,
    required ReservationRepository reservationRepository,
  }) : _authRepository = authRepository,
       _hubRepository = hubRepository,
       _dealRepository = dealRepository,
       _reservationRepository = reservationRepository {
    _user = _authRepository.currentUser;
    _activeUid = _user?.uid;
    _load();
    _authSubscription = _authRepository.authStateChanges.listen(
      _handleAuthStateChange,
    );
  }

  final AuthRepository _authRepository;
  final HubRepository _hubRepository;
  final DealRepository _dealRepository;
  final ReservationRepository _reservationRepository;

  AppUser? _user;
  Hub? _currentHub;
  List<Deal> _hostedDeals = const [];
  List<Deal> _joinedDeals = const [];
  List<Deal> _completedDeals = const [];
  bool _isLoading = true;
  bool _isSigningOut = false;
  bool _isSavingProfile = false;
  // Kept apart rather than pooled into one message: each belongs to a different
  // action with a different retry, and one failing must not blank the others.
  String? _loadErrorMessage;
  String? _signOutErrorMessage;
  String? _saveErrorMessage;
  String? _dealHistoryErrorMessage;
  int _loadGeneration = 0;
  int _identityGeneration = 0;
  int _signOutGeneration = 0;
  String? _activeUid;
  StreamSubscription<AppUser?>? _authSubscription;
  StreamSubscription<List<Deal>>? _dealHistorySub;
  bool _isDisposed = false;

  AppUser? get user => _user;
  Hub? get currentHub => _currentHub;
  List<Deal> get hostedDeals => _hostedDeals;
  List<Deal> get joinedDeals => _joinedDeals;
  List<Deal> get completedDeals => _completedDeals;
  bool get isLoading => _isLoading;
  bool get isSigningOut => _isSigningOut;
  bool get isSavingProfile => _isSavingProfile;
  String? get loadErrorMessage => _loadErrorMessage;
  String? get signOutErrorMessage => _signOutErrorMessage;
  String? get saveErrorMessage => _saveErrorMessage;
  String? get dealHistoryErrorMessage => _dealHistoryErrorMessage;

  Future<bool> saveDisplayName(String displayName) async {
    if (_isDisposed || _isSavingProfile) return false;

    final trimmed = displayName.trim();
    if (trimmed.isEmpty) {
      _saveErrorMessage = 'Enter your full name.';
      _notifyListeners();
      return false;
    }

    final identityGeneration = _identityGeneration;
    final uid = _activeUid;
    _isSavingProfile = true;
    _saveErrorMessage = null;
    _notifyListeners();

    try {
      final updated = await _authRepository.updateDisplayName(trimmed);
      if (!_isCurrentIdentity(identityGeneration, uid)) return false;
      _user = updated;
      return true;
    } on AuthFailure catch (error) {
      if (_isCurrentIdentity(identityGeneration, uid)) {
        _saveErrorMessage = error.message;
      }
      return false;
    } catch (_) {
      if (_isCurrentIdentity(identityGeneration, uid)) {
        _saveErrorMessage = 'Could not update your profile. Please try again.';
      }
      return false;
    } finally {
      if (_isCurrentIdentity(identityGeneration, uid)) {
        _isSavingProfile = false;
        _notifyListeners();
      }
    }
  }

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
      String? loadedHubId;
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
          loadedHubId = hubId;
        }
      }

      if (!_canCommitLoad(generation, identityGeneration, uid)) return;
      _currentHub = loadedHub;
      _loadErrorMessage = null;
      if (loadedHubId != null && user != null) {
        _startDealHistoryUpdates(
          hubId: loadedHubId,
          userId: user.uid,
          identityGeneration: identityGeneration,
        );
      }
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

  void _startDealHistoryUpdates({
    required String hubId,
    required String userId,
    required int identityGeneration,
  }) {
    _dealHistorySub?.cancel();
    _dealHistorySub = _dealRepository
        .watchDeals(hubId)
        .listen(
          (deals) => unawaited(
            _setDealHistory(
              deals: deals,
              userId: userId,
              identityGeneration: identityGeneration,
            ),
          ),
          onError: (_) => _setDealHistoryError(identityGeneration, userId),
        );
  }

  Future<void> _setDealHistory({
    required List<Deal> deals,
    required String userId,
    required int identityGeneration,
  }) async {
    if (!_isCurrentIdentity(identityGeneration, userId)) return;

    final hosted = <Deal>[];
    final joined = <Deal>[];
    final completed = <Deal>[];

    try {
      for (final deal in deals) {
        final isHost = deal.createdBy == userId;
        final participants = await _reservationRepository.getParticipants(
          deal.id,
        );
        final holdsSlot = participants.any(
          (participant) => participant.userId == userId,
        );
        if (!isHost && !holdsSlot) continue;

        if (deal.status == DealStatus.completed) {
          completed.add(deal);
        } else if (isHost) {
          hosted.add(deal);
        } else {
          joined.add(deal);
        }
      }
    } catch (_) {
      _setDealHistoryError(identityGeneration, userId);
      return;
    }

    if (!_isCurrentIdentity(identityGeneration, userId)) return;
    _hostedDeals = List.unmodifiable(hosted);
    _joinedDeals = List.unmodifiable(joined);
    _completedDeals = List.unmodifiable(completed);
    _dealHistoryErrorMessage = null;
    _notifyListeners();
  }

  void _setDealHistoryError(int identityGeneration, String userId) {
    if (!_isCurrentIdentity(identityGeneration, userId)) return;
    // The lists are left alone: failing to read the history is not the same as
    // having none, and blanking them would tell the student they have none.
    _dealHistoryErrorMessage =
        'Couldn’t load your deal history. Check your connection and try again.';
    _notifyListeners();
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
    // The previous student's history must not survive the switch.
    _dealHistorySub?.cancel();
    _dealHistorySub = null;
    _hostedDeals = const [];
    _joinedDeals = const [];
    _completedDeals = const [];
    _loadErrorMessage = null;
    _signOutErrorMessage = null;
    _saveErrorMessage = null;
    _dealHistoryErrorMessage = null;
    _isLoading = false;
    _isSigningOut = false;
    _isSavingProfile = false;
    _load();
  }

  bool _isCurrentIdentity(int identityGeneration, String? uid) {
    return !_isDisposed &&
        identityGeneration == _identityGeneration &&
        uid == _activeUid;
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
    _dealHistorySub?.cancel();
    super.dispose();
  }
}

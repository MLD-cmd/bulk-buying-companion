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
    _load();
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
  String? _errorMessage;
  bool _isDisposed = false;

  AppUser? get user => _user;
  Hub? get currentHub => _currentHub;
  List<Deal> get hostedDeals => _hostedDeals;
  List<Deal> get joinedDeals => _joinedDeals;
  List<Deal> get completedDeals => _completedDeals;
  bool get isLoading => _isLoading;
  bool get isSigningOut => _isSigningOut;
  bool get isSavingProfile => _isSavingProfile;
  String? get errorMessage => _errorMessage;

  Future<bool> saveDisplayName(String displayName) async {
    if (_isSavingProfile) return false;

    final trimmed = displayName.trim();
    if (trimmed.isEmpty) {
      _errorMessage = 'Enter your full name.';
      _notifyIfAlive();
      return false;
    }

    _isSavingProfile = true;
    _errorMessage = null;
    _notifyIfAlive();

    try {
      _user = await _authRepository.updateDisplayName(trimmed);
      return true;
    } on AuthFailure catch (error) {
      _errorMessage = error.message;
      return false;
    } catch (_) {
      _errorMessage = 'Could not update your profile. Please try again.';
      return false;
    } finally {
      _isSavingProfile = false;
      _notifyIfAlive();
    }
  }

  Future<bool> signOut() async {
    if (_isSigningOut) return false;
    _isSigningOut = true;
    _errorMessage = null;
    _notifyIfAlive();

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
      _notifyIfAlive();
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
          await _loadDealHistory(hubId: hubId, userId: user.uid);
        }
      }
    } catch (_) {
      _currentHub = null;
      _hostedDeals = const [];
      _joinedDeals = const [];
      _completedDeals = const [];
      _errorMessage = 'Could not load profile. Please try again.';
    } finally {
      _isLoading = false;
      _notifyIfAlive();
    }
  }

  Future<void> _loadDealHistory({
    required String hubId,
    required String userId,
  }) async {
    final deals = await _dealRepository.getDeals(hubId);
    final hosted = <Deal>[];
    final joined = <Deal>[];
    final completed = <Deal>[];

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

    _hostedDeals = List.unmodifiable(hosted);
    _joinedDeals = List.unmodifiable(joined);
    _completedDeals = List.unmodifiable(completed);
  }

  void _notifyIfAlive() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/hub_repository.dart';
import '../../data/services/location_service.dart';
import '../../models/app_user.dart';
import '../../models/hub.dart';
import '../../utils/geo.dart';

/// Hubs further than this from the student are hidden while the "Nearby only"
/// filter is on. Campus-scale: far enough to cover the surrounding barangays,
/// tight enough that a hub across the city drops off the list.
const double kNearbyRadiusMeters = 2000;

class JoinHubViewModel extends ChangeNotifier {
  JoinHubViewModel({
    required AuthRepository authRepository,
    required HubRepository hubRepository,
    required LocationService locationService,
  }) : _authRepository = authRepository,
       _hubRepository = hubRepository,
       _locationService = locationService {
    _authSub = _authRepository.authStateChanges.listen(_onAuthChanged);
    final currentUser = _authRepository.currentUser;
    if (currentUser != null) _load(currentUser.uid);
  }

  final AuthRepository _authRepository;
  final HubRepository _hubRepository;
  final LocationService _locationService;
  late final StreamSubscription<AppUser?> _authSub;

  List<Hub> _hubs = [];
  String _searchQuery = '';
  String? _joinedHubId;
  String? _pendingSwitchId;
  String? _locationFailureMessage;
  bool _isLoading = true;
  bool _nearbyOnly = false;

  List<Hub> get filteredHubs {
    var hubs = _hubs;

    if (_nearbyOnly) {
      // A hub with no coordinates cannot be proven to be out of range, so it
      // stays on the list rather than disappearing on a filter it never met.
      hubs = hubs
          .where(
            (hub) =>
                hub.distanceMeters == null ||
                hub.distanceMeters! <= kNearbyRadiusMeters,
          )
          .toList();
    }

    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return hubs;

    return hubs.where((hub) {
      return hub.name.toLowerCase().contains(query) ||
          hub.type.name.toLowerCase().contains(query);
    }).toList();
  }

  String get searchQuery => _searchQuery;
  String? get joinedHubId => _joinedHubId;
  String? get pendingSwitchId => _pendingSwitchId;
  bool get isLoading => _isLoading;
  String? get locationFailureMessage => _locationFailureMessage;
  bool get nearbyOnly => _nearbyOnly;

  /// Without a location fix every distance is null, so the filter would have
  /// nothing to act on — the UI hides the control instead of offering a no-op.
  bool get canFilterByDistance =>
      _hubs.any((hub) => hub.distanceMeters != null);

  void setNearbyOnly(bool value) {
    if (_nearbyOnly == value) return;
    _nearbyOnly = value;
    notifyListeners();
  }

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
      await _replaceDistancesWithCurrentLocation();
    } catch (_) {
      _hubs = const [];
      _joinedHubId = null;
      _pendingSwitchId = null;
      _locationFailureMessage = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _replaceDistancesWithCurrentLocation() async {
    if (!_hubs.any((hub) => hub.hasCoordinates)) return;

    try {
      final coordinates = await _locationService.getCurrentPosition();
      _locationFailureMessage = null;
      _hubs = _sortedByDistance(
        _hubs.map((hub) {
          if (!hub.hasCoordinates) return hub;
          final meters = haversineMeters(
            startLatitude: coordinates.latitude,
            startLongitude: coordinates.longitude,
            endLatitude: hub.latitude!,
            endLongitude: hub.longitude!,
          );
          return hub.copyWith(
            distanceLabel: _formatDistance(meters),
            distanceMeters: meters,
          );
        }).toList(),
      );
    } on LocationFailure catch (failure) {
      _locationFailureMessage = failure.message;
      _nearbyOnly = false;
    } catch (_) {
      _locationFailureMessage =
          'Could not read your current location. Showing saved distances.';
      _nearbyOnly = false;
    }
  }

  /// Nearest first. Hubs with no coordinates have no distance to sort on, so
  /// they keep their directory order at the end of the list instead of being
  /// treated as infinitely far away.
  List<Hub> _sortedByDistance(List<Hub> hubs) {
    final measured = hubs.where((hub) => hub.distanceMeters != null).toList()
      ..sort((a, b) => a.distanceMeters!.compareTo(b.distanceMeters!));
    final unmeasured = hubs.where((hub) => hub.distanceMeters == null);

    return [...measured, ...unmeasured];
  }

  /// Re-reads the hub directory, e.g. after the student registers a new hub.
  Future<void> refresh() async {
    final userId = _authRepository.currentUser?.uid;
    if (userId == null) return;
    await _load(userId);
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

String _formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';

  final kilometers = meters / 1000;
  if (kilometers < 10) return '${kilometers.toStringAsFixed(1)} km';
  return '${kilometers.round()} km';
}

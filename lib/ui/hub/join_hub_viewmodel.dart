import 'dart:async';
import 'dart:math';

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

enum _MembershipAction { join, leave }

class _MembershipRetry {
  const _MembershipRetry({
    required this.action,
    required this.userId,
    required this.identityGeneration,
    this.hubId,
  });

  final _MembershipAction action;
  final String userId;
  final int identityGeneration;
  final String? hubId;
}

class _LocationOutcome {
  const _LocationOutcome({
    required this.hubs,
    this.failureMessage,
    this.disableNearbyFilter = false,
    this.hasDistanceUpdate = false,
  });

  final List<Hub> hubs;
  final String? failureMessage;
  final bool disableNearbyFilter;
  final bool hasDistanceUpdate;
}

class JoinHubViewModel extends ChangeNotifier {
  JoinHubViewModel({
    required AuthRepository authRepository,
    required HubRepository hubRepository,
    required LocationService locationService,
  }) : _authRepository = authRepository,
       _hubRepository = hubRepository,
       _locationService = locationService {
    _authSub = _authRepository.authStateChanges.listen(_onAuthChanged);
    _onAuthChanged(_authRepository.currentUser);
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
  String? _directoryErrorMessage;
  String? _membershipErrorMessage;
  String? _updatingHubId;
  bool _isLoading = true;
  bool _nearbyOnly = false;
  bool _isUpdatingMembership = false;
  bool _isLeaving = false;
  bool _identityInitialized = false;
  bool _isDisposed = false;
  String? _activeUserId;
  int _identityGeneration = 0;
  int _loadGeneration = 0;
  int _locationGeneration = 0;
  int _membershipGeneration = 0;
  int? _activeLoadGeneration;
  _MembershipRetry? _failedMembershipRetry;

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
  String? get directoryErrorMessage => _directoryErrorMessage;
  String? get membershipErrorMessage => _membershipErrorMessage;
  String? get updatingHubId => _updatingHubId;
  bool get nearbyOnly => _nearbyOnly;
  bool get isLeaving => _isLeaving;
  bool get hasDirectoryData => _hubs.isNotEmpty;
  bool get canRetryMembership => _failedMembershipRetry != null;

  bool isUpdatingHub(String hubId) => _updatingHubId == hubId;

  /// True while a join or leave is in flight. The hub actions disable
  /// themselves on it, so the guard in [join] is a backstop rather than the
  /// only thing standing between a double tap and a wrong count.
  bool get isUpdatingMembership => _isUpdatingMembership;

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
    if (_isDisposed) return;

    final userId = user?.uid;
    if (_identityInitialized && userId == _activeUserId) return;

    _identityInitialized = true;
    _activeUserId = userId;
    _identityGeneration += 1;
    _loadGeneration += 1;
    _locationGeneration += 1;
    _membershipGeneration += 1;
    _activeLoadGeneration = null;

    _hubs = const [];
    _joinedHubId = null;
    _pendingSwitchId = null;
    _directoryErrorMessage = null;
    _locationFailureMessage = null;
    _membershipErrorMessage = null;
    _failedMembershipRetry = null;
    _updatingHubId = null;
    _nearbyOnly = false;
    _isUpdatingMembership = false;
    _isLeaving = false;
    _isLoading = userId != null;
    notifyListeners();

    if (userId != null) unawaited(_load(userId));
  }

  Future<void> _load(String userId) async {
    if (!_isCurrentIdentity(userId) || _isUpdatingMembership) return;

    final identityGeneration = _identityGeneration;
    final loadGeneration = ++_loadGeneration;
    final locationGeneration = ++_locationGeneration;
    _activeLoadGeneration = loadGeneration;
    final hasCachedDirectory = _hubs.isNotEmpty;
    _directoryErrorMessage = null;
    _isLoading = !hasCachedDirectory;
    notifyListeners();

    try {
      final results = await Future.wait([
        _hubRepository.getHubs(),
        _hubRepository.getCurrentHubId(userId),
      ]);
      if (!_isCurrentLoad(userId, identityGeneration, loadGeneration)) return;

      final stagedHubs = List<Hub>.of(results[0] as List<Hub>);
      final stagedJoinedHubId = results[1] as String?;
      final locationOutcome = await _measureDistances(stagedHubs);
      if (!_isCurrentLoad(userId, identityGeneration, loadGeneration) ||
          _locationGeneration != locationGeneration) {
        return;
      }

      _hubs = locationOutcome.hubs;
      _joinedHubId = stagedJoinedHubId;
      _directoryErrorMessage = null;
      _locationFailureMessage = locationOutcome.failureMessage;
      if (locationOutcome.disableNearbyFilter) _nearbyOnly = false;
      _activeLoadGeneration = null;
      _isLoading = false;
      notifyListeners();
    } catch (_) {
      if (!_isCurrentLoad(userId, identityGeneration, loadGeneration)) return;

      _directoryErrorMessage =
          'Couldn’t load hubs. Check your connection and try again.';
      _activeLoadGeneration = null;
      _isLoading = false;
      notifyListeners();
    }
  }

  bool _isCurrentIdentity(String userId, [int? identityGeneration]) {
    return !_isDisposed &&
        _activeUserId == userId &&
        (identityGeneration == null ||
            _identityGeneration == identityGeneration);
  }

  bool _isCurrentLoad(
    String userId,
    int identityGeneration,
    int loadGeneration,
  ) {
    return _isCurrentIdentity(userId, identityGeneration) &&
        _loadGeneration == loadGeneration &&
        _activeLoadGeneration == loadGeneration;
  }

  Future<_LocationOutcome> _measureDistances(List<Hub> hubs) async {
    if (!hubs.any((hub) => hub.hasCoordinates)) {
      return _LocationOutcome(hubs: hubs);
    }

    try {
      final coordinates = await _locationService.getCurrentPosition();
      final measuredHubs = _sortedByDistance(
        hubs.map((hub) {
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
      return _LocationOutcome(hubs: measuredHubs, hasDistanceUpdate: true);
    } on LocationFailure catch (failure) {
      return _LocationOutcome(
        hubs: hubs,
        failureMessage: failure.message,
        disableNearbyFilter: true,
      );
    } catch (_) {
      return _LocationOutcome(
        hubs: hubs,
        failureMessage:
            'Could not read your current location. Showing saved distances.',
        disableNearbyFilter: true,
      );
    }
  }

  Future<void> retryLocation() async {
    final userId = _activeUserId;
    if (userId == null ||
        _isUpdatingMembership ||
        _activeLoadGeneration != null) {
      return;
    }

    final identityGeneration = _identityGeneration;
    final locationGeneration = ++_locationGeneration;
    final directorySnapshot = List<Hub>.of(_hubs);
    _locationFailureMessage = null;
    notifyListeners();

    final outcome = await _measureDistances(directorySnapshot);
    if (!_isCurrentIdentity(userId, identityGeneration) ||
        _locationGeneration != locationGeneration ||
        _activeLoadGeneration != null) {
      return;
    }

    if (outcome.hasDistanceUpdate) {
      _hubs = _mergeDistanceFields(_hubs, outcome.hubs);
    }
    _locationFailureMessage = outcome.failureMessage;
    if (outcome.disableNearbyFilter) _nearbyOnly = false;
    notifyListeners();
  }

  List<Hub> _mergeDistanceFields(List<Hub> current, List<Hub> measured) {
    final measuredById = {for (final hub in measured) hub.id: hub};
    final merged = current.map((hub) {
      final distanceSource = measuredById[hub.id];
      if (distanceSource == null) return hub;
      return Hub(
        id: hub.id,
        name: hub.name,
        type: hub.type,
        memberCount: hub.memberCount,
        distanceLabel: distanceSource.distanceLabel,
        latitude: hub.latitude,
        longitude: hub.longitude,
        distanceMeters: distanceSource.distanceMeters,
      );
    }).toList();
    return _sortedByDistance(merged);
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
    final userId = _activeUserId;
    if (userId == null || _isUpdatingMembership) return;
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
    final userId = _activeUserId;
    if (userId == null) return;
    // A second tap while the first is still in flight would read the same
    // stale _joinedHubId and count the same student twice. The backend upsert
    // is keyed on user_id, so it never creates a second membership — only the
    // local count would drift, and it would stay wrong until a full reload.
    if (_isUpdatingMembership) return;

    final identityGeneration = _identityGeneration;
    final membershipGeneration = ++_membershipGeneration;
    _invalidateReadsForMembership();
    _membershipErrorMessage = null;
    _failedMembershipRetry = null;
    _isUpdatingMembership = true;
    _updatingHubId = hubId;
    _isLeaving = false;
    notifyListeners();

    try {
      final previousHubId = _joinedHubId;
      await _hubRepository.joinHub(userId: userId, hubId: hubId);
      if (!_isCurrentMembership(
        userId,
        identityGeneration,
        membershipGeneration,
      )) {
        return;
      }

      _joinedHubId = hubId;
      // The membership row just moved server-side; mirror that locally rather
      // than waiting on a full reload for the member counts to catch up.
      if (previousHubId == hubId) return;
      if (previousHubId != null) _adjustMemberCount(previousHubId, -1);
      _adjustMemberCount(hubId, 1);
    } catch (_) {
      if (!_isCurrentMembership(
        userId,
        identityGeneration,
        membershipGeneration,
      )) {
        return;
      }

      _membershipErrorMessage =
          'Couldn’t join this hub. Your current hub has not changed. '
          'Check your connection and try again.';
      _failedMembershipRetry = _MembershipRetry(
        action: _MembershipAction.join,
        userId: userId,
        identityGeneration: identityGeneration,
        hubId: hubId,
      );
    } finally {
      if (_isCurrentMembership(
        userId,
        identityGeneration,
        membershipGeneration,
      )) {
        _isUpdatingMembership = false;
        _updatingHubId = null;
        notifyListeners();
      }
    }
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
    final userId = _activeUserId;
    if (userId == null) return;
    // Same reasoning as [join]: a double tap would decrement the count twice
    // against a single membership row.
    if (_isUpdatingMembership) return;

    final identityGeneration = _identityGeneration;
    final membershipGeneration = ++_membershipGeneration;
    _invalidateReadsForMembership();
    _membershipErrorMessage = null;
    _failedMembershipRetry = null;
    _isUpdatingMembership = true;
    _updatingHubId = null;
    _isLeaving = true;
    notifyListeners();

    try {
      final hubId = _joinedHubId;
      await _hubRepository.leaveHub(userId: userId);
      if (!_isCurrentMembership(
        userId,
        identityGeneration,
        membershipGeneration,
      )) {
        return;
      }

      if (hubId != null) _adjustMemberCount(hubId, -1);
      _joinedHubId = null;
      _pendingSwitchId = null;
    } catch (_) {
      if (!_isCurrentMembership(
        userId,
        identityGeneration,
        membershipGeneration,
      )) {
        return;
      }

      _membershipErrorMessage =
          'Couldn’t leave the hub. You are still a member. '
          'Check your connection and try again.';
      _failedMembershipRetry = _MembershipRetry(
        action: _MembershipAction.leave,
        userId: userId,
        identityGeneration: identityGeneration,
      );
    } finally {
      if (_isCurrentMembership(
        userId,
        identityGeneration,
        membershipGeneration,
      )) {
        _isUpdatingMembership = false;
        _isLeaving = false;
        notifyListeners();
      }
    }
  }

  Future<void> retryMembership() {
    final retry = _failedMembershipRetry;
    if (retry == null ||
        !_isCurrentIdentity(retry.userId, retry.identityGeneration)) {
      return Future<void>.value();
    }

    return switch (retry.action) {
      _MembershipAction.join => join(retry.hubId!),
      _MembershipAction.leave => leave(),
    };
  }

  void _invalidateReadsForMembership() {
    _loadGeneration += 1;
    _locationGeneration += 1;
    _activeLoadGeneration = null;
    _isLoading = false;
  }

  bool _isCurrentMembership(
    String userId,
    int identityGeneration,
    int membershipGeneration,
  ) {
    return _isCurrentIdentity(userId, identityGeneration) &&
        _membershipGeneration == membershipGeneration;
  }

  /// Applies [delta] to the given hub's local member count, clamped so a
  /// stale count can never dip below zero.
  void _adjustMemberCount(String hubId, int delta) {
    _hubs = _hubs.map((hub) {
      if (hub.id != hubId) return hub;
      return hub.copyWith(memberCount: max(0, hub.memberCount + delta));
    }).toList();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _activeUserId = null;
    _identityGeneration += 1;
    _loadGeneration += 1;
    _locationGeneration += 1;
    _membershipGeneration += 1;
    _activeLoadGeneration = null;
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

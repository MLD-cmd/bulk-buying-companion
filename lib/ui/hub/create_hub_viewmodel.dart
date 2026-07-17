import 'package:flutter/foundation.dart';

import '../../data/repositories/hub_repository.dart';
import '../../data/services/location_service.dart';
import '../../models/hub.dart';
import '../../utils/geo.dart';

/// Two hubs closer together than this are assumed to be the same place
/// registered twice — a dormitory and the area hub around it are never
/// realistically this close on a campus.
const double kDuplicateHubRadiusMeters = 100;

class CreateHubViewModel extends ChangeNotifier {
  CreateHubViewModel({
    required HubRepository hubRepository,
    required LocationService locationService,
  }) : _hubRepository = hubRepository,
       _locationService = locationService {
    _loadExistingHubs();
  }

  final HubRepository _hubRepository;
  final LocationService _locationService;

  List<Hub> _existingHubs = const [];
  bool _isLocating = false;
  bool _isSubmitting = false;
  String? _locationError;
  String? _errorMessage;
  Coordinates? _capturedLocation;
  bool _disposed = false;
  bool _duplicateCheckUnavailable = false;

  List<Hub> get existingHubs => _existingHubs;
  bool get isLocating => _isLocating;
  bool get isSubmitting => _isSubmitting;
  String? get locationError => _locationError;
  String? get errorMessage => _errorMessage;

  /// True when the hub directory could not be read, so [duplicateErrorFor] is
  /// checking against nothing. Registration still works — the database rejects
  /// a true duplicate — but the student should know the check is degraded.
  bool get duplicateCheckUnavailable => _duplicateCheckUnavailable;

  /// Set when "Use my current location" succeeds, so the screen can push the
  /// values into its coordinate fields. The student can still edit them.
  Coordinates? get capturedLocation => _capturedLocation;

  Future<void> _loadExistingHubs() async {
    late final List<Hub> hubs;
    var failed = false;
    try {
      hubs = await _hubRepository.getHubs();
    } catch (_) {
      // A failed directory load only weakens duplicate detection; it must not
      // block registration. The database's primary key is the real guard.
      hubs = const [];
      failed = true;
    }
    if (_disposed) return;
    _existingHubs = hubs;
    _duplicateCheckUnavailable = failed;
    notifyListeners();
  }

  /// Retries the directory load behind [duplicateCheckUnavailable].
  Future<void> retryDuplicateCheck() async {
    if (_disposed || _isSubmitting) return;
    await _loadExistingHubs();
  }

  String? validateName(String? value) {
    final name = (value ?? '').trim();
    if (name.isEmpty) return 'Enter the hub name.';
    if (name.length < 3) return 'Hub name is too short.';
    if (hubSlug(name).isEmpty) return 'Hub name needs at least one letter.';
    return null;
  }

  String? validateLatitude(String? value) =>
      _validateCoordinate(value, label: 'Latitude', limit: 90);

  String? validateLongitude(String? value) =>
      _validateCoordinate(value, label: 'Longitude', limit: 180);

  String? _validateCoordinate(
    String? value, {
    required String label,
    required double limit,
  }) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Enter a ${label.toLowerCase()}.';
    final parsed = double.tryParse(text);
    if (parsed == null) return '$label must be a number.';
    if (parsed < -limit || parsed > limit) {
      return '$label must be between -$limit and $limit.';
    }
    return null;
  }

  /// Subtask 4: reject a hub that already exists, either by name or by sitting
  /// on top of one that is already registered. Returns null when the draft is
  /// safe to save.
  String? duplicateErrorFor(HubDraft draft) {
    final slug = hubSlug(draft.name);

    for (final hub in _existingHubs) {
      if (hubSlug(hub.name) == slug) {
        return 'A hub named "${hub.name}" is already registered.';
      }
    }

    for (final hub in _existingHubs) {
      if (!hub.hasCoordinates) continue;
      final meters = haversineMeters(
        startLatitude: draft.latitude,
        startLongitude: draft.longitude,
        endLatitude: hub.latitude!,
        endLongitude: hub.longitude!,
      );
      if (meters <= kDuplicateHubRadiusMeters) {
        return '"${hub.name}" is already registered about '
            '${meters.round()} m from here.';
      }
    }

    return null;
  }

  Future<void> useMyLocation() async {
    if (_disposed || _isLocating) return;
    _isLocating = true;
    _locationError = null;
    notifyListeners();

    try {
      final location = await _locationService.getCurrentPosition();
      if (_disposed) return;
      _capturedLocation = location;
    } on LocationFailure catch (error) {
      if (_disposed) return;
      _locationError = error.message;
    } catch (_) {
      if (_disposed) return;
      _locationError =
          'Could not read your location. Enter the coordinates below instead.';
    } finally {
      if (!_disposed) {
        _isLocating = false;
        notifyListeners();
      }
    }
  }

  /// Returns the registered hub, or null when the draft was rejected. The
  /// reason is exposed on [errorMessage].
  Future<Hub?> submit(HubDraft draft) async {
    if (_disposed || _isSubmitting) return null;

    final duplicate = duplicateErrorFor(draft);
    if (duplicate != null) {
      _errorMessage = duplicate;
      notifyListeners();
      return null;
    }

    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final hub = await _hubRepository.createHub(draft);
      return _disposed ? null : hub;
    } on HubFailure catch (error) {
      if (_disposed) return null;
      _errorMessage = error.message;
      return null;
    } catch (_) {
      if (_disposed) return null;
      _errorMessage = 'Could not register the hub. Please try again.';
      return null;
    } finally {
      if (!_disposed) {
        _isSubmitting = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}

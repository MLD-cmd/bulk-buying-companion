import 'dart:async';

import 'package:bulk_buying_companion/data/repositories/auth_repository.dart';
import 'package:bulk_buying_companion/data/repositories/hub_repository.dart';
import 'package:bulk_buying_companion/data/services/location_service.dart';
import 'package:bulk_buying_companion/models/app_user.dart';
import 'package:bulk_buying_companion/models/hub.dart';
import 'package:bulk_buying_companion/ui/hub/join_hub_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('requests location and replaces fake hub distances', () async {
    final locationService = _FakeLocationService(
      result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
    );
    final viewModel = JoinHubViewModel(
      authRepository: _SignedInAuthRepository(),
      hubRepository: _HubRepositoryWithDirectory(
        hubs: const [
          Hub(
            id: 'near',
            name: 'Near Hub',
            type: HubType.dormitory,
            memberCount: 3,
            distanceLabel: '999 m',
            latitude: 10.2954,
            longitude: 123.8969,
          ),
          Hub(
            id: 'north',
            name: 'North Hub',
            type: HubType.areaHub,
            memberCount: 7,
            distanceLabel: '888 m',
            latitude: 10.2963,
            longitude: 123.8969,
          ),
        ],
      ),
      locationService: locationService,
    );

    await pumpEventQueue();

    expect(locationService.calls, 1);
    expect(viewModel.locationFailureMessage, isNull);
    expect(viewModel.filteredHubs.map((hub) => hub.distanceLabel), [
      '0 m',
      '100 m',
    ]);
  });

  test(
    'keeps fallback distance labels when location permission is denied',
    () async {
      final locationService = _FakeLocationService(
        failure: const LocationFailure('Location permission denied.'),
      );
      final viewModel = JoinHubViewModel(
        authRepository: _SignedInAuthRepository(),
        hubRepository: _HubRepositoryWithDirectory(
          hubs: const [
            Hub(
              id: 'fallback',
              name: 'Fallback Hub',
              type: HubType.dormitory,
              memberCount: 2,
              distanceLabel: 'Saved distance',
              latitude: 10.2954,
              longitude: 123.8969,
            ),
          ],
        ),
        locationService: locationService,
      );

      await pumpEventQueue();

      expect(locationService.calls, 1);
      expect(viewModel.locationFailureMessage, 'Location permission denied.');
      expect(viewModel.filteredHubs.single.distanceLabel, 'Saved distance');
    },
  );

  test('sorts hubs nearest first and keeps unmeasurable hubs last', () async {
    final viewModel = JoinHubViewModel(
      authRepository: _SignedInAuthRepository(),
      hubRepository: _HubRepositoryWithDirectory(hubs: _unsortedDirectory),
      locationService: _FakeLocationService(
        result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
      ),
    );

    await pumpEventQueue();

    expect(viewModel.filteredHubs.map((hub) => hub.id), [
      'near',
      'north',
      'far',
      'unknown',
    ]);
  });

  test('drops hubs beyond the radius when the nearby filter is on', () async {
    final viewModel = JoinHubViewModel(
      authRepository: _SignedInAuthRepository(),
      hubRepository: _HubRepositoryWithDirectory(hubs: _unsortedDirectory),
      locationService: _FakeLocationService(
        result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
      ),
    );

    await pumpEventQueue();
    expect(viewModel.canFilterByDistance, isTrue);

    viewModel.setNearbyOnly(true);

    // 'far' sits ~6 km out, past kNearbyRadiusMeters. 'unknown' has no
    // coordinates, so it cannot be ruled out and stays on the list.
    expect(viewModel.filteredHubs.map((hub) => hub.id), [
      'near',
      'north',
      'unknown',
    ]);
  });

  test('combines the nearby filter with the search query', () async {
    final viewModel = JoinHubViewModel(
      authRepository: _SignedInAuthRepository(),
      hubRepository: _HubRepositoryWithDirectory(hubs: _unsortedDirectory),
      locationService: _FakeLocationService(
        result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
      ),
    );

    await pumpEventQueue();

    viewModel.setNearbyOnly(true);
    viewModel.setSearchQuery('hub');

    expect(viewModel.filteredHubs.map((hub) => hub.id), [
      'near',
      'north',
      'unknown',
    ]);

    viewModel.setSearchQuery('far');
    expect(viewModel.filteredHubs, isEmpty);
  });

  test('offers no distance filter without a location fix', () async {
    final viewModel = JoinHubViewModel(
      authRepository: _SignedInAuthRepository(),
      hubRepository: _HubRepositoryWithDirectory(hubs: _unsortedDirectory),
      locationService: _FakeLocationService(
        failure: const LocationFailure('Location permission denied.'),
      ),
    );

    await pumpEventQueue();

    expect(viewModel.canFilterByDistance, isFalse);
    expect(viewModel.nearbyOnly, isFalse);
    expect(viewModel.filteredHubs, hasLength(4));
  });

  test('stops loading when hub data fails to load', () async {
    final viewModel = JoinHubViewModel(
      authRepository: _SignedInAuthRepository(),
      hubRepository: _FailingHubRepository(),
      locationService: _FakeLocationService(
        result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
      ),
    );

    await pumpEventQueue();

    expect(viewModel.isLoading, isFalse);
    expect(viewModel.filteredHubs, isEmpty);
  });
}

/// Deliberately not in distance order, so a passing sort test cannot be the
/// directory order leaking through. Distances from 10.2954 / 123.8969:
/// near 0 m, north ~100 m, far ~6 km, unknown unmeasurable.
const _unsortedDirectory = [
  Hub(
    id: 'far',
    name: 'Far Hub',
    type: HubType.areaHub,
    memberCount: 4,
    distanceLabel: '1 m',
    latitude: 10.3500,
    longitude: 123.8969,
  ),
  Hub(
    id: 'north',
    name: 'North Hub',
    type: HubType.areaHub,
    memberCount: 7,
    distanceLabel: '888 m',
    latitude: 10.2963,
    longitude: 123.8969,
  ),
  Hub(
    id: 'near',
    name: 'Near Hub',
    type: HubType.dormitory,
    memberCount: 3,
    distanceLabel: '999 m',
    latitude: 10.2954,
    longitude: 123.8969,
  ),
  Hub(
    id: 'unknown',
    name: 'Unknown Hub',
    type: HubType.dormitory,
    memberCount: 1,
    distanceLabel: 'Distance unavailable',
  ),
];

class _SignedInAuthRepository implements AuthRepository {
  @override
  Stream<AppUser?> get authStateChanges => const Stream.empty();

  @override
  AppUser? get currentUser =>
      const AppUser(uid: 'user-1', eduEmail: 'student@example.com');

  @override
  Future<AppUser> signIn({required String email, required String password}) {
    throw UnimplementedError();
  }

  @override
  Future<AuthRegistrationResult> register({
    required String displayName,
    required String email,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> signOut() async {}

  @override
  void dispose() {}
}

class _FailingHubRepository implements HubRepository {
  @override
  Future<List<Hub>> getHubs() {
    throw StateError('hub table unavailable');
  }

  @override
  Future<Hub> createHub(HubDraft draft) {
    throw StateError('hub table unavailable');
  }

  @override
  Future<String?> getCurrentHubId(String userId) {
    throw StateError('membership table unavailable');
  }

  @override
  Future<void> joinHub({required String userId, required String hubId}) async {}

  @override
  Future<void> leaveHub({required String userId}) async {}
}

class _HubRepositoryWithDirectory implements HubRepository {
  _HubRepositoryWithDirectory({required List<Hub> hubs}) : _hubs = hubs;

  final List<Hub> _hubs;

  @override
  Future<List<Hub>> getHubs() async => _hubs;

  @override
  Future<Hub> createHub(HubDraft draft) {
    throw UnimplementedError();
  }

  @override
  Future<String?> getCurrentHubId(String userId) async => null;

  @override
  Future<void> joinHub({required String userId, required String hubId}) async {}

  @override
  Future<void> leaveHub({required String userId}) async {}
}

class _FakeLocationService implements LocationService {
  _FakeLocationService({this.result, this.failure});

  final Coordinates? result;
  final LocationFailure? failure;
  int calls = 0;

  @override
  Future<Coordinates> getCurrentPosition() async {
    calls += 1;
    final failure = this.failure;
    if (failure != null) throw failure;
    return result!;
  }
}

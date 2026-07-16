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

  test('bumps the local member count when joining a hub', () async {
    final viewModel = JoinHubViewModel(
      authRepository: _SignedInAuthRepository(),
      hubRepository: _HubRepositoryWithDirectory(hubs: _unsortedDirectory),
      locationService: _FakeLocationService(
        result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
      ),
    );

    await pumpEventQueue();

    await viewModel.join('near');

    expect(viewModel.joinedHubId, 'near');
    expect(viewModel.joinedHub?.memberCount, 4);
  });

  test(
    'moves the member count from the old hub to the new one on switch',
    () async {
      final viewModel = JoinHubViewModel(
        authRepository: _SignedInAuthRepository(),
        hubRepository: _HubRepositoryWithDirectory(hubs: _unsortedDirectory),
        locationService: _FakeLocationService(
          result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
        ),
      );

      await pumpEventQueue();

      await viewModel.join('near');
      expect(viewModel.joinedHub?.memberCount, 4);

      viewModel.requestSwitch('north');
      await viewModel.confirmSwitch();

      expect(viewModel.joinedHubId, 'north');
      expect(viewModel.joinedHub?.memberCount, 8);
      expect(
        viewModel.filteredHubs
            .firstWhere((hub) => hub.id == 'near')
            .memberCount,
        3,
      );
    },
  );

  test('drops the local member count when leaving a hub', () async {
    final viewModel = JoinHubViewModel(
      authRepository: _SignedInAuthRepository(),
      hubRepository: _HubRepositoryWithDirectory(hubs: _unsortedDirectory),
      locationService: _FakeLocationService(
        result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
      ),
    );

    await pumpEventQueue();

    await viewModel.join('near');
    await viewModel.leave();

    expect(viewModel.joinedHubId, isNull);
    expect(
      viewModel.filteredHubs.firstWhere((hub) => hub.id == 'near').memberCount,
      3,
    );
  });

  test('a double-tapped join counts the student once, not twice', () async {
    // The backend upsert is keyed on user_id, so a second tap rewrites the same
    // membership row and never creates a second one. Only the local count can
    // drift — and it did, because both calls read the same stale _joinedHubId
    // before either await resolved.
    final hubRepository = _BlockingHubRepository(hubs: _unsortedDirectory);
    final viewModel = JoinHubViewModel(
      authRepository: _SignedInAuthRepository(),
      hubRepository: hubRepository,
      locationService: _FakeLocationService(
        result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
      ),
    );

    await pumpEventQueue();
    hubRepository.blockJoins();

    // Two taps, the second landing while the first is still in flight.
    final first = viewModel.join('near');
    final second = viewModel.join('near');
    expect(viewModel.isUpdatingMembership, isTrue);

    hubRepository.releaseJoins();
    await Future.wait([first, second]);

    expect(
      hubRepository.joinCalls,
      1,
      reason: 'the second tap must be a no-op',
    );
    expect(viewModel.joinedHub?.memberCount, 4, reason: 'was 3 before joining');
    expect(viewModel.isUpdatingMembership, isFalse);
  });

  test('a double-tapped leave decrements the count once', () async {
    final hubRepository = _BlockingHubRepository(hubs: _unsortedDirectory);
    final viewModel = JoinHubViewModel(
      authRepository: _SignedInAuthRepository(),
      hubRepository: hubRepository,
      locationService: _FakeLocationService(
        result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
      ),
    );

    await pumpEventQueue();
    await viewModel.join('near');
    expect(viewModel.joinedHub?.memberCount, 4);

    hubRepository.blockLeaves();
    final first = viewModel.leave();
    final second = viewModel.leave();
    hubRepository.releaseLeaves();
    await Future.wait([first, second]);

    expect(hubRepository.leaveCalls, 1);
    expect(
      viewModel.filteredHubs.firstWhere((hub) => hub.id == 'near').memberCount,
      3,
      reason: 'back to where it started, not 2',
    );
  });

  test('the membership flag is cleared even when the join fails', () async {
    final viewModel = JoinHubViewModel(
      authRepository: _SignedInAuthRepository(),
      hubRepository: _JoinFailingHubRepository(hubs: _unsortedDirectory),
      locationService: _FakeLocationService(
        result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
      ),
    );

    await pumpEventQueue();

    await expectLater(viewModel.join('near'), throwsStateError);

    // A failed join must not wedge the button permanently.
    expect(viewModel.isUpdatingMembership, isFalse);
    expect(viewModel.joinedHubId, isNull);
    expect(
      viewModel.filteredHubs.firstWhere((hub) => hub.id == 'near').memberCount,
      3,
      reason: 'nothing was joined, so nothing should have been counted',
    );
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

/// Lets a join or leave be held mid-flight, so a second call can land while the
/// first is still awaiting — which is the whole bug.
class _BlockingHubRepository implements HubRepository {
  _BlockingHubRepository({required List<Hub> hubs}) : _hubs = hubs;

  final List<Hub> _hubs;
  Completer<void>? _joinGate;
  Completer<void>? _leaveGate;

  int joinCalls = 0;
  int leaveCalls = 0;

  void blockJoins() => _joinGate = Completer<void>();
  void releaseJoins() => _joinGate?.complete();
  void blockLeaves() => _leaveGate = Completer<void>();
  void releaseLeaves() => _leaveGate?.complete();

  @override
  Future<List<Hub>> getHubs() async => _hubs;

  @override
  Future<Hub> createHub(HubDraft draft) => throw UnimplementedError();

  @override
  Future<String?> getCurrentHubId(String userId) async => null;

  @override
  Future<void> joinHub({required String userId, required String hubId}) async {
    joinCalls += 1;
    final gate = _joinGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> leaveHub({required String userId}) async {
    leaveCalls += 1;
    final gate = _leaveGate;
    if (gate != null) await gate.future;
  }
}

class _JoinFailingHubRepository implements HubRepository {
  _JoinFailingHubRepository({required List<Hub> hubs}) : _hubs = hubs;

  final List<Hub> _hubs;

  @override
  Future<List<Hub>> getHubs() async => _hubs;

  @override
  Future<Hub> createHub(HubDraft draft) => throw UnimplementedError();

  @override
  Future<String?> getCurrentHubId(String userId) async => null;

  @override
  Future<void> joinHub({required String userId, required String hubId}) {
    throw StateError('membership table unavailable');
  }

  @override
  Future<void> leaveHub({required String userId}) async {}
}

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

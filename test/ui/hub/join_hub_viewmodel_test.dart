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

  test(
    'retryLocation clears the old error while retrying and replaces distances',
    () async {
      final locationService = _FakeLocationService(
        failure: const LocationFailure('Location permission denied.'),
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
              distanceLabel: 'Saved distance',
              latitude: 10.2954,
              longitude: 123.8969,
            ),
          ],
        ),
        locationService: locationService,
      );

      await pumpEventQueue();
      expect(viewModel.locationFailureMessage, 'Location permission denied.');

      locationService
        ..failure = null
        ..result = const Coordinates(latitude: 10.2954, longitude: 123.8969)
        ..block();
      var notifications = 0;
      viewModel.addListener(() => notifications += 1);

      final retry = viewModel.retryLocation();

      expect(viewModel.locationFailureMessage, isNull);
      expect(notifications, 1);

      locationService.release();
      await retry;

      expect(locationService.calls, 2);
      expect(viewModel.filteredHubs.single.distanceLabel, '0 m');
      expect(viewModel.locationFailureMessage, isNull);
      expect(notifications, 2);
    },
  );

  test(
    'failed location retry keeps saved distances and disables nearby filtering',
    () async {
      final locationService = _FakeLocationService(
        result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
      );
      final viewModel = JoinHubViewModel(
        authRepository: _SignedInAuthRepository(),
        hubRepository: _HubRepositoryWithDirectory(hubs: _unsortedDirectory),
        locationService: locationService,
      );

      await pumpEventQueue();
      final savedDistances = {
        for (final hub in viewModel.filteredHubs) hub.id: hub.distanceLabel,
      };
      viewModel.setNearbyOnly(true);
      locationService.failure = const LocationFailure('Location unavailable.');

      await viewModel.retryLocation();

      expect(viewModel.locationFailureMessage, 'Location unavailable.');
      expect(viewModel.nearbyOnly, isFalse);
      expect({
        for (final hub in viewModel.filteredHubs) hub.id: hub.distanceLabel,
      }, savedDistances);
    },
  );

  test(
    'stale location retry cannot overwrite a newer successful retry',
    () async {
      final locationService = _QueuedLocationService(
        initialResult: const Coordinates(
          latitude: 10.2954,
          longitude: 123.8969,
        ),
      );
      final viewModel = JoinHubViewModel(
        authRepository: _SignedInAuthRepository(),
        hubRepository: _HubRepositoryWithDirectory(hubs: _unsortedDirectory),
        locationService: locationService,
      );

      await pumpEventQueue();
      viewModel.setNearbyOnly(true);

      final staleRetry = viewModel.retryLocation();
      final latestRetry = viewModel.retryLocation();
      expect(locationService.pendingRequests, 2);

      locationService.succeed(
        1,
        const Coordinates(latitude: 10.2963, longitude: 123.8969),
      );
      await latestRetry;

      expect(viewModel.locationFailureMessage, isNull);
      expect(viewModel.nearbyOnly, isTrue);
      expect(
        viewModel.filteredHubs
            .firstWhere((hub) => hub.id == 'north')
            .distanceLabel,
        '0 m',
      );

      locationService.fail(0, const LocationFailure('Stale location failure.'));
      await staleRetry;

      expect(viewModel.locationFailureMessage, isNull);
      expect(viewModel.nearbyOnly, isTrue);
      expect(
        viewModel.filteredHubs
            .firstWhere((hub) => hub.id == 'north')
            .distanceLabel,
        '0 m',
      );
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

  test(
    'initial directory failure is distinct from a successful empty directory',
    () async {
      final failedViewModel = JoinHubViewModel(
        authRepository: _SignedInAuthRepository(),
        hubRepository: _FailingHubRepository(),
        locationService: _FakeLocationService(
          result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
        ),
      );
      final emptyViewModel = JoinHubViewModel(
        authRepository: _SignedInAuthRepository(),
        hubRepository: _HubRepositoryWithDirectory(hubs: const []),
        locationService: _FakeLocationService(
          result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
        ),
      );

      await pumpEventQueue();

      expect(failedViewModel.isLoading, isFalse);
      expect(failedViewModel.hasDirectoryData, isFalse);
      expect(failedViewModel.filteredHubs, isEmpty);
      expect(
        failedViewModel.directoryErrorMessage,
        'Couldn’t load hubs. Check your connection and try again.',
      );
      expect(emptyViewModel.isLoading, isFalse);
      expect(emptyViewModel.hasDirectoryData, isFalse);
      expect(emptyViewModel.filteredHubs, isEmpty);
      expect(emptyViewModel.directoryErrorMessage, isNull);
    },
  );

  test(
    'failed refresh preserves cached directory state and a retry replaces it',
    () async {
      final repository = _ControlledHubRepository(
        hubs: _unsortedDirectory,
        currentHubId: 'near',
      );
      final viewModel = JoinHubViewModel(
        authRepository: _SignedInAuthRepository(),
        hubRepository: repository,
        locationService: _FakeLocationService(
          result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
        ),
      );

      await pumpEventQueue();
      viewModel.setSearchQuery('hub');
      viewModel.setNearbyOnly(true);
      final cachedHubs = viewModel.filteredHubs;

      repository.failDirectory = true;
      final failedRefresh = viewModel.refresh();

      expect(viewModel.isLoading, isFalse);
      await failedRefresh;

      expect(
        viewModel.directoryErrorMessage,
        'Couldn’t load hubs. Check your connection and try again.',
      );
      expect(viewModel.hasDirectoryData, isTrue);
      expect(viewModel.joinedHubId, 'near');
      expect(viewModel.searchQuery, 'hub');
      expect(viewModel.nearbyOnly, isTrue);
      expect(viewModel.filteredHubs, cachedHubs);

      repository
        ..failDirectory = false
        ..hubs = const [
          Hub(
            id: 'replacement',
            name: 'Replacement Hub',
            type: HubType.areaHub,
            memberCount: 12,
            distanceLabel: 'Saved replacement distance',
            latitude: 10.2954,
            longitude: 123.8969,
          ),
        ]
        ..currentHubId = 'replacement';

      await viewModel.refresh();

      expect(viewModel.directoryErrorMessage, isNull);
      expect(viewModel.joinedHubId, 'replacement');
      expect(viewModel.searchQuery, 'hub');
      expect(viewModel.nearbyOnly, isTrue);
      expect(viewModel.filteredHubs.map((hub) => hub.id), ['replacement']);
      expect(viewModel.filteredHubs.single.distanceLabel, '0 m');
    },
  );

  test(
    'stale refresh failure cannot add an error after newer success',
    () async {
      final repository = _QueuedDirectoryHubRepository(
        initialHubs: _unsortedDirectory,
        initialHubId: 'near',
      );
      final viewModel = JoinHubViewModel(
        authRepository: _SignedInAuthRepository(),
        hubRepository: repository,
        locationService: _FakeLocationService(
          result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
        ),
      );
      addTearDown(repository.releaseAll);

      await pumpEventQueue();
      final staleRefresh = viewModel.refresh();
      final latestRefresh = viewModel.refresh();
      expect(repository.pendingRefreshes, 2);

      repository.succeedRefresh(
        1,
        hubs: const [
          Hub(
            id: 'newest',
            name: 'Newest Hub',
            type: HubType.areaHub,
            memberCount: 9,
            distanceLabel: 'Saved newest distance',
            latitude: 10.2954,
            longitude: 123.8969,
          ),
        ],
        joinedHubId: 'newest',
      );
      await latestRefresh;

      repository.failRefresh(0);
      await staleRefresh;

      expect(viewModel.directoryErrorMessage, isNull);
      expect(viewModel.joinedHubId, 'newest');
      expect(viewModel.filteredHubs.map((hub) => hub.id), ['newest']);
    },
  );

  test('stale refresh success cannot replace a newer failure state', () async {
    final repository = _QueuedDirectoryHubRepository(
      initialHubs: _unsortedDirectory,
      initialHubId: 'near',
    );
    final viewModel = JoinHubViewModel(
      authRepository: _SignedInAuthRepository(),
      hubRepository: repository,
      locationService: _FakeLocationService(
        result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
      ),
    );
    addTearDown(repository.releaseAll);

    await pumpEventQueue();
    final staleRefresh = viewModel.refresh();
    final latestRefresh = viewModel.refresh();

    repository.failRefresh(1);
    await latestRefresh;
    expect(
      viewModel.directoryErrorMessage,
      'Couldn’t load hubs. Check your connection and try again.',
    );

    repository.succeedRefresh(
      0,
      hubs: const [
        Hub(
          id: 'stale',
          name: 'Stale Hub',
          type: HubType.dormitory,
          memberCount: 99,
          distanceLabel: 'Stale distance',
        ),
      ],
      joinedHubId: 'stale',
    );
    await staleRefresh;

    expect(
      viewModel.directoryErrorMessage,
      'Couldn’t load hubs. Check your connection and try again.',
    );
    expect(viewModel.joinedHubId, 'near');
    expect(viewModel.filteredHubs.map((hub) => hub.id), [
      'near',
      'north',
      'far',
      'unknown',
    ]);
  });

  test(
    'membership mutation invalidates a pending refresh and blocks another',
    () async {
      final repository = _QueuedDirectoryHubRepository(
        initialHubs: _unsortedDirectory,
        initialHubId: 'near',
      );
      final viewModel = JoinHubViewModel(
        authRepository: _SignedInAuthRepository(),
        hubRepository: repository,
        locationService: _FakeLocationService(
          result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
        ),
      );
      addTearDown(repository.releaseAll);

      await pumpEventQueue();
      final staleRefresh = viewModel.refresh();
      repository.blockNextJoin();
      final joinFuture = viewModel.join('north');
      final ignoredRefresh = viewModel.refresh();
      await pumpEventQueue();

      expect(repository.pendingRefreshes, 1);

      repository.releaseJoin();
      await joinFuture;
      await ignoredRefresh;
      expect(viewModel.joinedHubId, 'north');
      expect(_memberCount(viewModel, 'near'), 2);
      expect(_memberCount(viewModel, 'north'), 8);

      repository.succeedRefresh(
        0,
        hubs: _unsortedDirectory,
        joinedHubId: 'near',
      );
      await staleRefresh;

      expect(viewModel.joinedHubId, 'north');
      expect(_memberCount(viewModel, 'near'), 2);
      expect(_memberCount(viewModel, 'north'), 8);
    },
  );

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
    expect(viewModel.updatingHubId, 'near');
    expect(viewModel.isUpdatingHub('near'), isTrue);
    expect(viewModel.isUpdatingHub('north'), isFalse);
    expect(viewModel.isLeaving, isFalse);

    hubRepository.releaseJoins();
    await Future.wait([first, second]);

    expect(
      hubRepository.joinCalls,
      1,
      reason: 'the second tap must be a no-op',
    );
    expect(viewModel.joinedHub?.memberCount, 4, reason: 'was 3 before joining');
    expect(viewModel.isUpdatingMembership, isFalse);
    expect(viewModel.updatingHubId, isNull);
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
    expect(viewModel.isUpdatingMembership, isTrue);
    expect(viewModel.isLeaving, isTrue);
    expect(viewModel.updatingHubId, isNull);
    hubRepository.releaseLeaves();
    await Future.wait([first, second]);

    expect(hubRepository.leaveCalls, 1);
    expect(
      viewModel.filteredHubs.firstWhere((hub) => hub.id == 'near').memberCount,
      3,
      reason: 'back to where it started, not 2',
    );
    expect(viewModel.isLeaving, isFalse);
  });

  test('failed join is caught, preserves state, and exposes a retry', () async {
    final repository = _ControlledHubRepository(
      hubs: _unsortedDirectory,
      failJoin: true,
    );
    final viewModel = JoinHubViewModel(
      authRepository: _SignedInAuthRepository(),
      hubRepository: repository,
      locationService: _FakeLocationService(
        result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
      ),
    );

    await pumpEventQueue();

    await expectLater(viewModel.join('near'), completes);

    expect(viewModel.isUpdatingMembership, isFalse);
    expect(viewModel.updatingHubId, isNull);
    expect(viewModel.joinedHubId, isNull);
    expect(
      viewModel.filteredHubs.firstWhere((hub) => hub.id == 'near').memberCount,
      3,
      reason: 'nothing was joined, so nothing should have been counted',
    );
    expect(
      viewModel.membershipErrorMessage,
      'Couldn’t join this hub. Your current hub has not changed. '
      'Check your connection and try again.',
    );
    expect(viewModel.canRetryMembership, isTrue);
  });

  test(
    'failed confirmed switch preserves both counts and retries the target once',
    () async {
      final repository = _ControlledHubRepository(
        hubs: _unsortedDirectory,
        currentHubId: 'near',
        failJoin: true,
      )..blockJoins();
      final viewModel = JoinHubViewModel(
        authRepository: _SignedInAuthRepository(),
        hubRepository: repository,
        locationService: _FakeLocationService(
          result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
        ),
      );

      await pumpEventQueue();
      viewModel.requestSwitch('north');
      final switchFuture = viewModel.confirmSwitch();

      expect(viewModel.isUpdatingMembership, isTrue);
      expect(viewModel.updatingHubId, 'north');
      expect(viewModel.isUpdatingHub('north'), isTrue);
      expect(viewModel.isUpdatingHub('near'), isFalse);
      expect(viewModel.isLeaving, isFalse);

      repository.releaseJoins();
      await expectLater(switchFuture, completes);

      expect(viewModel.joinedHubId, 'near');
      expect(_memberCount(viewModel, 'near'), 3);
      expect(_memberCount(viewModel, 'north'), 7);
      expect(repository.joinedHubIds, ['north']);
      expect(viewModel.canRetryMembership, isTrue);

      repository
        ..failJoin = false
        ..blockJoins();
      final retryFuture = viewModel.retryMembership();

      expect(viewModel.membershipErrorMessage, isNull);
      expect(viewModel.canRetryMembership, isFalse);
      expect(viewModel.updatingHubId, 'north');
      expect(viewModel.isUpdatingMembership, isTrue);
      repository.releaseJoins();
      await retryFuture;

      expect(repository.joinedHubIds, ['north', 'north']);
      expect(viewModel.joinedHubId, 'north');
      expect(_memberCount(viewModel, 'near'), 2);
      expect(_memberCount(viewModel, 'north'), 8);
      expect(viewModel.membershipErrorMessage, isNull);
      expect(viewModel.canRetryMembership, isFalse);
      expect(viewModel.isUpdatingMembership, isFalse);
      expect(viewModel.updatingHubId, isNull);
    },
  );

  test(
    'failed leave is caught, preserves membership, and retries leave once',
    () async {
      final repository = _ControlledHubRepository(
        hubs: _unsortedDirectory,
        currentHubId: 'near',
        failLeave: true,
      )..blockLeaves();
      final viewModel = JoinHubViewModel(
        authRepository: _SignedInAuthRepository(),
        hubRepository: repository,
        locationService: _FakeLocationService(
          result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
        ),
      );

      await pumpEventQueue();
      final leaveFuture = viewModel.leave();

      expect(viewModel.isUpdatingMembership, isTrue);
      expect(viewModel.isLeaving, isTrue);
      expect(viewModel.updatingHubId, isNull);

      repository.releaseLeaves();
      await expectLater(leaveFuture, completes);

      expect(viewModel.joinedHubId, 'near');
      expect(_memberCount(viewModel, 'near'), 3);
      expect(
        viewModel.membershipErrorMessage,
        'Couldn’t leave the hub. You are still a member. '
        'Check your connection and try again.',
      );
      expect(viewModel.canRetryMembership, isTrue);
      expect(viewModel.isLeaving, isFalse);

      repository
        ..failLeave = false
        ..blockLeaves();
      final retryFuture = viewModel.retryMembership();

      expect(viewModel.membershipErrorMessage, isNull);
      expect(viewModel.canRetryMembership, isFalse);
      expect(viewModel.isLeaving, isTrue);
      repository.releaseLeaves();
      await retryFuture;

      expect(repository.leaveCalls, 2);
      expect(viewModel.joinedHubId, isNull);
      expect(_memberCount(viewModel, 'near'), 2);
      expect(viewModel.membershipErrorMessage, isNull);
      expect(viewModel.canRetryMembership, isFalse);
      expect(viewModel.isUpdatingMembership, isFalse);
      expect(viewModel.isLeaving, isFalse);
    },
  );

  test('retryMembership is a no-op when there is no failed intent', () async {
    final repository = _ControlledHubRepository(hubs: _unsortedDirectory);
    final viewModel = JoinHubViewModel(
      authRepository: _SignedInAuthRepository(),
      hubRepository: repository,
      locationService: _FakeLocationService(
        result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
      ),
    );

    await pumpEventQueue();
    await viewModel.retryMembership();

    expect(repository.joinedHubIds, isEmpty);
    expect(repository.leaveCalls, 0);
    expect(viewModel.isUpdatingMembership, isFalse);
  });

  test(
    'auth transition clears failed retry state and prevents cross-account retry',
    () async {
      final authRepository = _ControlledAuthRepository(initialUser: _userA);
      final repository = _ControlledHubRepository(
        hubs: _unsortedDirectory,
        failJoin: true,
      );
      final viewModel = JoinHubViewModel(
        authRepository: authRepository,
        hubRepository: repository,
        locationService: _FakeLocationService(
          result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
        ),
      );
      addTearDown(() async {
        repository.releaseAllMembership();
        await pumpEventQueue();
        viewModel.dispose();
        authRepository.dispose();
      });

      await pumpEventQueue();
      await viewModel.join('near');
      viewModel.requestSwitch('north');
      expect(viewModel.canRetryMembership, isTrue);

      authRepository.emit(null);

      expect(viewModel.hasDirectoryData, isFalse);
      expect(viewModel.joinedHubId, isNull);
      expect(viewModel.pendingSwitchId, isNull);
      expect(viewModel.membershipErrorMessage, isNull);
      expect(viewModel.canRetryMembership, isFalse);
      expect(viewModel.isUpdatingMembership, isFalse);
      expect(viewModel.updatingHubId, isNull);
      expect(viewModel.isLeaving, isFalse);

      repository.currentHubId = 'north';
      authRepository.emit(_userB);
      await pumpEventQueue();
      await viewModel.retryMembership();

      expect(viewModel.joinedHubId, 'north');
      expect(repository.joinedUserIds, ['user-a']);
      expect(viewModel.membershipErrorMessage, isNull);
      expect(viewModel.canRetryMembership, isFalse);
    },
  );

  test(
    'auth transition during join isolates state and busy finalizers by account',
    () async {
      final authRepository = _ControlledAuthRepository(initialUser: _userA);
      final repository = _ControlledHubRepository(
        hubs: _unsortedDirectory,
        currentHubId: 'near',
      )..blockJoins();
      final viewModel = JoinHubViewModel(
        authRepository: authRepository,
        hubRepository: repository,
        locationService: _FakeLocationService(
          result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
        ),
      );
      addTearDown(() async {
        repository.releaseAllMembership();
        await pumpEventQueue();
        viewModel.dispose();
        authRepository.dispose();
      });

      await pumpEventQueue();
      final userAJoin = viewModel.join('north');

      repository.currentHubId = 'near';
      authRepository.emit(_userB);
      await pumpEventQueue();
      repository.blockJoins();
      final userBJoin = viewModel.join('far');

      expect(viewModel.isUpdatingMembership, isTrue);
      expect(viewModel.updatingHubId, 'far');

      repository.releaseJoin(0);
      await userAJoin;

      expect(viewModel.joinedHubId, 'near');
      expect(viewModel.isUpdatingMembership, isTrue);
      expect(viewModel.updatingHubId, 'far');
      expect(_memberCount(viewModel, 'near'), 3);
      expect(_memberCount(viewModel, 'north'), 7);

      repository.releaseJoin(1);
      await userBJoin;

      expect(repository.joinedUserIds, ['user-a', 'user-b']);
      expect(viewModel.joinedHubId, 'far');
      expect(_memberCount(viewModel, 'near'), 2);
      expect(_memberCount(viewModel, 'north'), 7);
      expect(_memberCount(viewModel, 'far'), 5);
      expect(viewModel.isUpdatingMembership, isFalse);
      expect(viewModel.updatingHubId, isNull);
    },
  );

  test(
    'auth transition during leave isolates state and busy finalizers by account',
    () async {
      final authRepository = _ControlledAuthRepository(initialUser: _userA);
      final repository = _ControlledHubRepository(
        hubs: _unsortedDirectory,
        currentHubId: 'near',
      )..blockLeaves();
      final viewModel = JoinHubViewModel(
        authRepository: authRepository,
        hubRepository: repository,
        locationService: _FakeLocationService(
          result: const Coordinates(latitude: 10.2954, longitude: 123.8969),
        ),
      );
      addTearDown(() async {
        repository.releaseAllMembership();
        await pumpEventQueue();
        viewModel.dispose();
        authRepository.dispose();
      });

      await pumpEventQueue();
      final userALeave = viewModel.leave();

      repository.currentHubId = 'north';
      authRepository.emit(_userB);
      await pumpEventQueue();
      repository.blockLeaves();
      final userBLeave = viewModel.leave();

      expect(viewModel.joinedHubId, 'north');
      expect(viewModel.isUpdatingMembership, isTrue);
      expect(viewModel.isLeaving, isTrue);

      repository.releaseLeave(0);
      await userALeave;

      expect(viewModel.joinedHubId, 'north');
      expect(viewModel.isUpdatingMembership, isTrue);
      expect(viewModel.isLeaving, isTrue);
      expect(_memberCount(viewModel, 'near'), 3);
      expect(_memberCount(viewModel, 'north'), 7);

      repository.releaseLeave(1);
      await userBLeave;

      expect(repository.leftUserIds, ['user-a', 'user-b']);
      expect(viewModel.joinedHubId, isNull);
      expect(_memberCount(viewModel, 'near'), 3);
      expect(_memberCount(viewModel, 'north'), 6);
      expect(viewModel.isUpdatingMembership, isFalse);
      expect(viewModel.isLeaving, isFalse);
    },
  );
}

int _memberCount(JoinHubViewModel viewModel, String hubId) =>
    viewModel.filteredHubs.firstWhere((hub) => hub.id == hubId).memberCount;

const _userA = AppUser(uid: 'user-a', eduEmail: 'a@example.com');
const _userB = AppUser(uid: 'user-b', eduEmail: 'b@example.com');

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

class _ControlledHubRepository implements HubRepository {
  _ControlledHubRepository({
    required this.hubs,
    this.currentHubId,
    this.failJoin = false,
    this.failLeave = false,
  });

  List<Hub> hubs;
  String? currentHubId;
  bool failDirectory = false;
  bool failJoin;
  bool failLeave;
  bool _gateNextJoin = false;
  bool _gateNextLeave = false;
  final List<Completer<void>> _joinGates = [];
  final List<Completer<void>> _leaveGates = [];

  final List<String> joinedHubIds = [];
  final List<String> joinedUserIds = [];
  final List<String> leftUserIds = [];
  int leaveCalls = 0;

  void blockJoins() => _gateNextJoin = true;
  void releaseJoins() {
    for (var index = 0; index < _joinGates.length; index += 1) {
      if (!_joinGates[index].isCompleted) {
        releaseJoin(index);
        return;
      }
    }
  }

  void releaseJoin(int index) {
    final gate = _joinGates[index];
    if (!gate.isCompleted) gate.complete();
  }

  void blockLeaves() => _gateNextLeave = true;
  void releaseLeaves() {
    for (var index = 0; index < _leaveGates.length; index += 1) {
      if (!_leaveGates[index].isCompleted) {
        releaseLeave(index);
        return;
      }
    }
  }

  void releaseLeave(int index) {
    final gate = _leaveGates[index];
    if (!gate.isCompleted) gate.complete();
  }

  void releaseAllMembership() {
    for (final gate in [..._joinGates, ..._leaveGates]) {
      if (!gate.isCompleted) gate.complete();
    }
  }

  @override
  Future<List<Hub>> getHubs() async {
    if (failDirectory) throw StateError('hub table unavailable');
    return hubs;
  }

  @override
  Future<Hub> createHub(HubDraft draft) => throw UnimplementedError();

  @override
  Future<String?> getCurrentHubId(String userId) async => currentHubId;

  @override
  Future<void> joinHub({required String userId, required String hubId}) async {
    joinedHubIds.add(hubId);
    joinedUserIds.add(userId);
    Completer<void>? gate;
    if (_gateNextJoin) {
      _gateNextJoin = false;
      gate = Completer<void>();
      _joinGates.add(gate);
    }
    if (gate != null) await gate.future;
    if (failJoin) throw StateError('membership table unavailable');
  }

  @override
  Future<void> leaveHub({required String userId}) async {
    leaveCalls += 1;
    leftUserIds.add(userId);
    Completer<void>? gate;
    if (_gateNextLeave) {
      _gateNextLeave = false;
      gate = Completer<void>();
      _leaveGates.add(gate);
    }
    if (gate != null) await gate.future;
    if (failLeave) throw StateError('membership table unavailable');
  }
}

class _QueuedDirectoryHubRepository implements HubRepository {
  _QueuedDirectoryHubRepository({
    required this.initialHubs,
    required this.initialHubId,
  });

  final List<Hub> initialHubs;
  final String? initialHubId;
  final List<_DirectoryRequest> _refreshes = [];
  int _hubCalls = 0;
  int _membershipCalls = 0;
  Completer<void>? _joinGate;

  int get pendingRefreshes => _refreshes.length;

  void succeedRefresh(
    int index, {
    required List<Hub> hubs,
    required String? joinedHubId,
  }) {
    final request = _refreshes[index];
    if (!request.hubs.isCompleted) request.hubs.complete(hubs);
    if (!request.joinedHubId.isCompleted) {
      request.joinedHubId.complete(joinedHubId);
    }
  }

  void failRefresh(int index) {
    final request = _refreshes[index];
    if (!request.hubs.isCompleted) {
      request.hubs.completeError(StateError('hub table unavailable'));
    }
    if (!request.joinedHubId.isCompleted) {
      request.joinedHubId.complete(null);
    }
  }

  void blockNextJoin() => _joinGate = Completer<void>();
  void releaseJoin() {
    final gate = _joinGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  void releaseAll() {
    releaseJoin();
    for (final request in _refreshes) {
      if (!request.hubs.isCompleted) request.hubs.complete(initialHubs);
      if (!request.joinedHubId.isCompleted) {
        request.joinedHubId.complete(initialHubId);
      }
    }
  }

  @override
  Future<List<Hub>> getHubs() {
    final call = _hubCalls++;
    if (call == 0) return Future<List<Hub>>.value(initialHubs);

    final request = _DirectoryRequest();
    _refreshes.add(request);
    return request.hubs.future;
  }

  @override
  Future<String?> getCurrentHubId(String userId) {
    final call = _membershipCalls++;
    if (call == 0) return Future<String?>.value(initialHubId);
    return _refreshes[call - 1].joinedHubId.future;
  }

  @override
  Future<void> joinHub({required String userId, required String hubId}) async {
    final gate = _joinGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> leaveHub({required String userId}) async {}

  @override
  Future<Hub> createHub(HubDraft draft) => throw UnimplementedError();
}

class _DirectoryRequest {
  final hubs = Completer<List<Hub>>();
  final joinedHubId = Completer<String?>();
}

class _ControlledAuthRepository implements AuthRepository {
  _ControlledAuthRepository({required AppUser? initialUser})
    : _currentUser = initialUser;

  final _controller = StreamController<AppUser?>.broadcast(sync: true);
  AppUser? _currentUser;

  void emit(AppUser? user) {
    _currentUser = user;
    _controller.add(user);
  }

  @override
  Stream<AppUser?> get authStateChanges => _controller.stream;

  @override
  AppUser? get currentUser => _currentUser;

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
  Future<void> signOut() async => emit(null);

  @override
  void dispose() => _controller.close();
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

  Coordinates? result;
  LocationFailure? failure;
  Completer<void>? _gate;
  int calls = 0;

  void block() => _gate = Completer<void>();
  void release() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<Coordinates> getCurrentPosition() async {
    calls += 1;
    final gate = _gate;
    if (gate != null) await gate.future;
    final failure = this.failure;
    if (failure != null) throw failure;
    return result!;
  }
}

class _QueuedLocationService implements LocationService {
  _QueuedLocationService({required this.initialResult});

  final Coordinates initialResult;
  final List<Completer<Coordinates>> _requests = [];
  int _calls = 0;

  int get pendingRequests => _requests.length;

  void succeed(int index, Coordinates coordinates) {
    _requests[index].complete(coordinates);
  }

  void fail(int index, LocationFailure failure) {
    _requests[index].completeError(failure);
  }

  @override
  Future<Coordinates> getCurrentPosition() {
    final call = _calls++;
    if (call == 0) return Future<Coordinates>.value(initialResult);

    final request = Completer<Coordinates>();
    _requests.add(request);
    return request.future;
  }
}

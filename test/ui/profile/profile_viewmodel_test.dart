import 'dart:async';

import 'package:bulk_buying_companion/data/repositories/auth_repository.dart';
import 'package:bulk_buying_companion/data/repositories/hub_repository.dart';
import 'package:bulk_buying_companion/models/app_user.dart';
import 'package:bulk_buying_companion/models/hub.dart';
import 'package:bulk_buying_companion/ui/profile/profile_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports successful logout and exposes progress', () async {
    final authRepository = _DelayedSignOutRepository();
    final viewModel = ProfileViewModel(
      authRepository: authRepository,
      hubRepository: _EmptyHubRepository(),
    );

    final operation = viewModel.signOut();
    expect(viewModel.isSigningOut, isTrue);
    authRepository.completer.complete();

    expect(await operation, isTrue);
    expect(viewModel.isSigningOut, isFalse);
    expect(viewModel.signOutErrorMessage, isNull);
  });

  test('prevents duplicate logout requests', () async {
    final authRepository = _DelayedSignOutRepository();
    final viewModel = ProfileViewModel(
      authRepository: authRepository,
      hubRepository: _EmptyHubRepository(),
    );

    final first = viewModel.signOut();
    final second = viewModel.signOut();

    expect(await second, isFalse);
    expect(authRepository.signOutCalls, 1);
    authRepository.completer.complete();
    await first;
  });

  test('displays repository logout failures', () async {
    final authRepository = _DelayedSignOutRepository();
    final viewModel = ProfileViewModel(
      authRepository: authRepository,
      hubRepository: _EmptyHubRepository(),
    );

    final operation = viewModel.signOut();
    authRepository.completer.completeError(
      const AuthFailure('Check your internet connection and try again.'),
    );

    expect(await operation, isFalse);
    expect(
      viewModel.signOutErrorMessage,
      'Check your internet connection and try again.',
    );
    expect(viewModel.isSigningOut, isFalse);
  });

  test('displays a safe fallback for unexpected logout failures', () async {
    final authRepository = _DelayedSignOutRepository();
    final viewModel = ProfileViewModel(
      authRepository: authRepository,
      hubRepository: _EmptyHubRepository(),
    );

    final operation = viewModel.signOut();
    authRepository.completer.completeError(StateError('internal detail'));

    expect(await operation, isFalse);
    expect(
      viewModel.signOutErrorMessage,
      'Could not log out. Please try again.',
    );
  });

  test('hub lookup failure is not confirmed as no membership', () async {
    final viewModel = ProfileViewModel(
      authRepository: _DelayedSignOutRepository(),
      hubRepository: _FailingHubRepository(),
    );

    await Future<void>.delayed(Duration.zero);

    expect(viewModel.isLoading, isFalse);
    expect(viewModel.currentHub, isNull);
    expect(
      viewModel.loadErrorMessage,
      'Couldn’t load your current hub. Check your connection and try again.',
    );
  });

  test(
    'retry keeps the load error visible until it restores the hub',
    () async {
      final retryMembership = Completer<String?>();
      final repository = _SequencedHubRepository(
        membershipResponses: [
          () async => throw StateError('offline'),
          () => retryMembership.future,
        ],
        hubs: const [_colonHub],
      );
      final viewModel = ProfileViewModel(
        authRepository: _DelayedSignOutRepository(),
        hubRepository: repository,
      );
      await pumpEventQueue();

      final retry = viewModel.retryLoad();

      expect(viewModel.isLoading, isTrue);
      expect(
        viewModel.loadErrorMessage,
        'Couldn’t load your current hub. Check your connection and try again.',
      );
      retryMembership.complete('colon');
      await retry;
      expect(viewModel.isLoading, isFalse);
      expect(viewModel.currentHub, same(_colonHub));
      expect(viewModel.loadErrorMessage, isNull);
    },
  );

  test('failed retry keeps a previously loaded hub visible', () async {
    final repository = _SequencedHubRepository(
      membershipResponses: [
        () async => 'colon',
        () async => throw StateError('offline'),
      ],
      hubs: const [_colonHub],
    );
    final viewModel = ProfileViewModel(
      authRepository: _DelayedSignOutRepository(),
      hubRepository: repository,
    );
    await pumpEventQueue();
    final cachedHub = viewModel.currentHub;

    await viewModel.retryLoad();

    expect(viewModel.currentHub, same(cachedHub));
    expect(
      viewModel.loadErrorMessage,
      'Couldn’t load your current hub. Check your connection and try again.',
    );
  });

  test('missing membership hub in directory is a load failure', () async {
    final viewModel = ProfileViewModel(
      authRepository: _DelayedSignOutRepository(),
      hubRepository: _SequencedHubRepository(
        membershipResponses: [() async => 'missing-hub'],
        hubs: const [_colonHub],
      ),
    );
    await pumpEventQueue();

    expect(viewModel.currentHub, isNull);
    expect(
      viewModel.loadErrorMessage,
      'Couldn’t load your current hub. Check your connection and try again.',
    );
  });

  test('load and sign-out failures remain independent', () async {
    final authRepository = _SequencedSignOutRepository([
      () async => throw const AuthFailure('Please check your connection.'),
      () async {},
    ]);
    final hubRepository = _SequencedHubRepository(
      membershipResponses: [
        () async => throw StateError('offline'),
        () async => null,
      ],
    );
    final viewModel = ProfileViewModel(
      authRepository: authRepository,
      hubRepository: hubRepository,
    );
    await pumpEventQueue();
    final loadError = viewModel.loadErrorMessage;

    expect(await viewModel.signOut(), isFalse);
    expect(viewModel.loadErrorMessage, loadError);
    expect(viewModel.signOutErrorMessage, 'Please check your connection.');

    await viewModel.retryLoad();
    expect(viewModel.loadErrorMessage, isNull);
    expect(viewModel.signOutErrorMessage, 'Please check your connection.');
    expect(viewModel.currentHub, isNull);

    expect(await viewModel.signOut(), isTrue);
    expect(viewModel.signOutErrorMessage, isNull);
  });

  test('an older retry cannot replace the newest load result', () async {
    final olderMembership = Completer<String?>();
    final newerMembership = Completer<String?>();
    final repository = _SequencedHubRepository(
      membershipResponses: [
        () async => 'colon',
        () => olderMembership.future,
        () => newerMembership.future,
      ],
      hubs: const [_colonHub, _burgosHub],
    );
    final viewModel = ProfileViewModel(
      authRepository: _DelayedSignOutRepository(),
      hubRepository: repository,
    );
    await pumpEventQueue();

    final olderRetry = viewModel.retryLoad();
    final newerRetry = viewModel.retryLoad();
    newerMembership.complete('burgos');
    await newerRetry;
    expect(viewModel.currentHub, same(_burgosHub));

    olderMembership.complete('colon');
    await olderRetry;
    expect(viewModel.currentHub, same(_burgosHub));
  });

  test('auth UID changes isolate identity and stale hub results', () async {
    final userALoad = Completer<String?>();
    final authRepository = _MutableAuthRepository(
      const AppUser(uid: 'user-a', eduEmail: 'a@example.com'),
    );
    final hubRepository = _SequencedHubRepository(
      membershipResponses: [() => userALoad.future, () async => 'burgos'],
      hubs: const [_colonHub, _burgosHub],
    );
    final viewModel = ProfileViewModel(
      authRepository: authRepository,
      hubRepository: hubRepository,
    );

    authRepository.emit(
      const AppUser(uid: 'user-b', eduEmail: 'b@example.com'),
    );
    await pumpEventQueue();

    expect(viewModel.user?.uid, 'user-b');
    expect(viewModel.currentHub, same(_burgosHub));
    expect(hubRepository.membershipCalls, 2);

    authRepository.emit(
      const AppUser(uid: 'user-b', eduEmail: 'b@example.com'),
    );
    await pumpEventQueue();
    expect(hubRepository.membershipCalls, 2);

    userALoad.complete('colon');
    await pumpEventQueue();
    expect(viewModel.user?.uid, 'user-b');
    expect(viewModel.currentHub, same(_burgosHub));

    expect(await viewModel.signOut(), isTrue);
    expect(viewModel.user, isNull);
    expect(viewModel.currentHub, isNull);
    expect(viewModel.loadErrorMessage, isNull);
    expect(viewModel.signOutErrorMessage, isNull);
    expect(viewModel.isLoading, isFalse);
    expect(viewModel.isSigningOut, isFalse);

    viewModel.dispose();
    authRepository.dispose();
  });

  test(
    'completion after dispose does not notify or commit profile state',
    () async {
      final membership = Completer<String?>();
      final authRepository = _MutableAuthRepository(
        const AppUser(uid: 'user-a', eduEmail: 'a@example.com'),
      );
      final viewModel = ProfileViewModel(
        authRepository: authRepository,
        hubRepository: _SequencedHubRepository(
          membershipResponses: [() => membership.future],
          hubs: const [_colonHub],
        ),
      );
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      viewModel.dispose();
      membership.complete('colon');
      await pumpEventQueue();

      expect(notifications, 0);
      authRepository.dispose();
    },
  );
}

const _colonHub = Hub(
  id: 'colon',
  name: 'Colon Street Hub',
  type: HubType.areaHub,
  memberCount: 31,
  distanceLabel: '400 m',
);

const _burgosHub = Hub(
  id: 'burgos',
  name: 'P. Burgos Boarding House',
  type: HubType.dormitory,
  memberCount: 18,
  distanceLabel: '300 m',
);

class _DelayedSignOutRepository implements AuthRepository {
  final completer = Completer<void>();
  int signOutCalls = 0;

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
  Future<void> signOut() {
    signOutCalls++;
    return completer.future;
  }

  @override
  void dispose() {}
}

class _EmptyHubRepository implements HubRepository {
  @override
  Future<String?> getCurrentHubId(String userId) async => null;

  @override
  Future<List<Hub>> getHubs() async => const [];

  @override
  Future<Hub> createHub(HubDraft draft) {
    throw UnimplementedError();
  }

  @override
  Future<void> joinHub({required String userId, required String hubId}) async {}

  @override
  Future<void> leaveHub({required String userId}) async {}
}

class _SequencedSignOutRepository implements AuthRepository {
  _SequencedSignOutRepository(this._responses);

  final List<Future<void> Function()> _responses;
  int _nextResponse = 0;

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
  Future<void> signOut() => _responses[_nextResponse++]();

  @override
  void dispose() {}
}

class _SequencedHubRepository implements HubRepository {
  _SequencedHubRepository({
    required this.membershipResponses,
    this.hubs = const [],
  });

  final List<Future<String?> Function()> membershipResponses;
  final List<Hub> hubs;
  int _nextMembership = 0;
  int get membershipCalls => _nextMembership;

  @override
  Future<String?> getCurrentHubId(String userId) =>
      membershipResponses[_nextMembership++]();

  @override
  Future<List<Hub>> getHubs() async => hubs;

  @override
  Future<Hub> createHub(HubDraft draft) {
    throw UnimplementedError();
  }

  @override
  Future<void> joinHub({required String userId, required String hubId}) async {}

  @override
  Future<void> leaveHub({required String userId}) async {}
}

class _MutableAuthRepository implements AuthRepository {
  _MutableAuthRepository(this._currentUser);

  final StreamController<AppUser?> _controller =
      StreamController<AppUser?>.broadcast(sync: true);
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

class _FailingHubRepository implements HubRepository {
  @override
  Future<String?> getCurrentHubId(String userId) {
    throw StateError('membership table unavailable');
  }

  @override
  Future<List<Hub>> getHubs() {
    throw StateError('hub table unavailable');
  }

  @override
  Future<Hub> createHub(HubDraft draft) {
    throw StateError('hub table unavailable');
  }

  @override
  Future<void> joinHub({required String userId, required String hubId}) async {}

  @override
  Future<void> leaveHub({required String userId}) async {}
}

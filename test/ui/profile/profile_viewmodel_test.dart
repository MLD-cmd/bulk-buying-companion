import 'dart:async';

import 'package:bulk_buying_companion/data/repositories/auth_repository.dart';
import 'package:bulk_buying_companion/data/repositories/deal_repository.dart';
import 'package:bulk_buying_companion/data/repositories/hub_repository.dart';
import 'package:bulk_buying_companion/data/repositories/reservation_repository.dart';
import 'package:bulk_buying_companion/models/app_user.dart';
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:bulk_buying_companion/models/hub.dart';
import 'package:bulk_buying_companion/models/reservation.dart';
import 'package:bulk_buying_companion/ui/profile/profile_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports successful logout and exposes progress', () async {
    final authRepository = _DelayedSignOutRepository();
    final viewModel = ProfileViewModel(
      authRepository: authRepository,
      hubRepository: _EmptyHubRepository(),
      dealRepository: const _EmptyDealRepository(),
      reservationRepository: const _EmptyReservationRepository(),
    );

    final operation = viewModel.signOut();
    expect(viewModel.isSigningOut, isTrue);
    authRepository.completer.complete();

    expect(await operation, isTrue);
    expect(viewModel.isSigningOut, isFalse);
    expect(viewModel.errorMessage, isNull);
  });

  test('prevents duplicate logout requests', () async {
    final authRepository = _DelayedSignOutRepository();
    final viewModel = ProfileViewModel(
      authRepository: authRepository,
      hubRepository: _EmptyHubRepository(),
      dealRepository: const _EmptyDealRepository(),
      reservationRepository: const _EmptyReservationRepository(),
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
      dealRepository: const _EmptyDealRepository(),
      reservationRepository: const _EmptyReservationRepository(),
    );

    final operation = viewModel.signOut();
    authRepository.completer.completeError(
      const AuthFailure('Check your internet connection and try again.'),
    );

    expect(await operation, isFalse);
    expect(
      viewModel.errorMessage,
      'Check your internet connection and try again.',
    );
    expect(viewModel.isSigningOut, isFalse);
  });

  test('displays a safe fallback for unexpected logout failures', () async {
    final authRepository = _DelayedSignOutRepository();
    final viewModel = ProfileViewModel(
      authRepository: authRepository,
      hubRepository: _EmptyHubRepository(),
      dealRepository: const _EmptyDealRepository(),
      reservationRepository: const _EmptyReservationRepository(),
    );

    final operation = viewModel.signOut();
    authRepository.completer.completeError(StateError('internal detail'));

    expect(await operation, isFalse);
    expect(viewModel.errorMessage, 'Could not log out. Please try again.');
  });

  test('stops loading and reports an error when hub lookup fails', () async {
    final viewModel = ProfileViewModel(
      authRepository: _DelayedSignOutRepository(),
      hubRepository: _FailingHubRepository(),
      dealRepository: const _EmptyDealRepository(),
      reservationRepository: const _EmptyReservationRepository(),
    );

    await Future<void>.delayed(Duration.zero);

    expect(viewModel.isLoading, isFalse);
    expect(viewModel.errorMessage, 'Could not load profile. Please try again.');
  });

  test('loads hosted, joined, and completed deal history', () async {
    final viewModel = ProfileViewModel(
      authRepository: _ProfileAuthRepository(),
      hubRepository: _SingleHubRepository(),
      dealRepository: _DealHistoryRepository([
        _deal(id: 'hosted-active', createdBy: 'user-1', title: 'Hosted Rice'),
        _deal(id: 'joined-active', createdBy: 'host-2', title: 'Joined Water'),
        _deal(
          id: 'completed',
          createdBy: 'host-3',
          title: 'Completed Coffee',
          purchasedAt: DateTime(2026, 7, 16),
          collectedCount: 2,
        ),
      ]),
      reservationRepository: _ReservationHistoryRepository({
        'hosted-active': [
          _reservation('hosted-active', 'user-1', isHost: true),
        ],
        'joined-active': [
          _reservation('joined-active', 'host-2', isHost: true),
          _reservation('joined-active', 'user-1'),
        ],
        'completed': [
          _reservation('completed', 'host-3', isHost: true),
          _reservation(
            'completed',
            'user-1',
            collectedAt: DateTime(2026, 7, 16),
          ),
        ],
      }),
    );

    await pumpEventQueue();

    expect(viewModel.currentHub?.name, 'Colon Street Hub');
    expect(viewModel.hostedDeals.map((deal) => deal.title), ['Hosted Rice']);
    expect(viewModel.joinedDeals.map((deal) => deal.title), ['Joined Water']);
    expect(viewModel.completedDeals.map((deal) => deal.title), [
      'Completed Coffee',
    ]);
  });

  test('updates deal history when the hub deal stream changes', () async {
    final dealRepository = _LiveDealHistoryRepository([
      _deal(id: 'hosted-active', createdBy: 'user-1', title: 'Hosted Rice'),
    ]);
    final reservationRepository = _ReservationHistoryRepository({
      'hosted-active': [_reservation('hosted-active', 'user-1', isHost: true)],
      'joined-active': [
        _reservation('joined-active', 'host-2', isHost: true),
        _reservation('joined-active', 'user-1'),
      ],
    });
    final viewModel = ProfileViewModel(
      authRepository: _ProfileAuthRepository(),
      hubRepository: _SingleHubRepository(),
      dealRepository: dealRepository,
      reservationRepository: reservationRepository,
    );
    await pumpEventQueue();

    expect(viewModel.hostedDeals.map((deal) => deal.title), ['Hosted Rice']);
    expect(viewModel.joinedDeals, isEmpty);

    dealRepository.emit([
      _deal(id: 'hosted-active', createdBy: 'user-1', title: 'Hosted Rice'),
      _deal(id: 'joined-active', createdBy: 'host-2', title: 'Joined Water'),
    ]);
    await pumpEventQueue();

    expect(viewModel.hostedDeals.map((deal) => deal.title), ['Hosted Rice']);
    expect(viewModel.joinedDeals.map((deal) => deal.title), ['Joined Water']);
  });

  test('saves a changed display name through the auth repository', () async {
    final authRepository = _ProfileAuthRepository();
    final viewModel = ProfileViewModel(
      authRepository: authRepository,
      hubRepository: _SingleHubRepository(),
      dealRepository: const _EmptyDealRepository(),
      reservationRepository: const _EmptyReservationRepository(),
    );
    await pumpEventQueue();

    final saved = await viewModel.saveDisplayName(' Updated Student ');

    expect(saved, isTrue);
    expect(authRepository.lastDisplayName, 'Updated Student');
    expect(viewModel.user?.displayName, 'Updated Student');
    expect(viewModel.errorMessage, isNull);
  });
}

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
  Future<AppUser> updateDisplayName(String displayName) {
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

class _SingleHubRepository extends _EmptyHubRepository {
  @override
  Future<String?> getCurrentHubId(String userId) async => 'colon';

  @override
  Future<List<Hub>> getHubs() async => const [
    Hub(
      id: 'colon',
      name: 'Colon Street Hub',
      type: HubType.areaHub,
      memberCount: 31,
      distanceLabel: '400 m',
    ),
  ];
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

class _ProfileAuthRepository implements AuthRepository {
  AppUser _user = const AppUser(
    uid: 'user-1',
    eduEmail: 'student@example.com',
    displayName: 'Sample Student',
  );
  String? lastDisplayName;

  @override
  Stream<AppUser?> get authStateChanges => const Stream.empty();

  @override
  AppUser? get currentUser => _user;

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
  Future<AppUser> updateDisplayName(String displayName) async {
    lastDisplayName = displayName;
    _user = AppUser(
      uid: _user.uid,
      eduEmail: _user.eduEmail,
      displayName: displayName,
      hubId: _user.hubId,
    );
    return _user;
  }

  @override
  Future<void> signOut() async {}

  @override
  void dispose() {}
}

class _DealHistoryRepository implements DealRepository {
  const _DealHistoryRepository(this.deals);

  final List<Deal> deals;

  @override
  Future<Deal> createDeal(DealDraft draft) {
    throw UnimplementedError();
  }

  @override
  Future<List<Deal>> getDeals(String hubId) async => deals;

  @override
  Stream<List<Deal>> watchDeals(String hubId) async* {
    yield await getDeals(hubId);
  }
}

class _LiveDealHistoryRepository implements DealRepository {
  _LiveDealHistoryRepository(this.deals);

  List<Deal> deals;
  final _controller = StreamController<List<Deal>>();

  void emit(List<Deal> value) {
    deals = value;
    _controller.add(value);
  }

  @override
  Future<Deal> createDeal(DealDraft draft) {
    throw UnimplementedError();
  }

  @override
  Future<List<Deal>> getDeals(String hubId) async => deals;

  @override
  Stream<List<Deal>> watchDeals(String hubId) async* {
    yield deals;
    yield* _controller.stream;
  }
}

class _EmptyDealRepository implements DealRepository {
  const _EmptyDealRepository();

  @override
  Future<Deal> createDeal(DealDraft draft) {
    throw UnimplementedError();
  }

  @override
  Future<List<Deal>> getDeals(String hubId) async => const [];

  @override
  Stream<List<Deal>> watchDeals(String hubId) async* {
    yield await getDeals(hubId);
  }
}

class _ReservationHistoryRepository implements ReservationRepository {
  const _ReservationHistoryRepository(this.participantsByDeal);

  final Map<String, List<Reservation>> participantsByDeal;

  @override
  Future<List<Reservation>> getParticipants(String dealId) async =>
      participantsByDeal[dealId] ?? const [];

  @override
  Future<Deal> reserveSlot(String dealId) {
    throw UnimplementedError();
  }

  @override
  Future<Deal> cancelReservation(String dealId) {
    throw UnimplementedError();
  }

  @override
  Future<Deal> setPaid(String dealId, String userId, {required bool paid}) {
    throw UnimplementedError();
  }

  @override
  Future<Deal> setCollected(
    String dealId,
    String userId, {
    required bool collected,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Deal> markPurchased(String dealId) {
    throw UnimplementedError();
  }

  @override
  Future<Deal> cancelDeal(String dealId) {
    throw UnimplementedError();
  }
}

class _EmptyReservationRepository extends _ReservationHistoryRepository {
  const _EmptyReservationRepository() : super(const {});
}

Deal _deal({
  required String id,
  required String createdBy,
  required String title,
  DateTime? purchasedAt,
  int collectedCount = 0,
}) {
  return Deal(
    id: id,
    hubId: 'colon',
    title: title,
    createdBy: createdBy,
    hostName: 'Host Student',
    category: DealCategory.grocery,
    totalPrice: 300,
    amount: 3,
    unit: DealUnit.kg,
    availableSlots: 0,
    totalSlots: 2,
    pickupLocation: 'Campus Gate',
    purchasedAt: purchasedAt,
    paidCount: 2,
    collectedCount: collectedCount,
  );
}

Reservation _reservation(
  String dealId,
  String userId, {
  bool isHost = false,
  DateTime? collectedAt,
}) {
  return Reservation(
    dealId: dealId,
    userId: userId,
    isHost: isHost,
    reservedAt: DateTime(2026, 7, 16),
    collectedAt: collectedAt,
  );
}

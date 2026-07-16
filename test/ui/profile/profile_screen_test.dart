import 'package:bulk_buying_companion/data/repositories/auth_repository.dart';
import 'package:bulk_buying_companion/data/repositories/deal_repository.dart';
import 'package:bulk_buying_companion/data/repositories/hub_repository.dart';
import 'package:bulk_buying_companion/data/repositories/reservation_repository.dart';
import 'package:bulk_buying_companion/models/app_user.dart';
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:bulk_buying_companion/models/reservation.dart';
import 'package:bulk_buying_companion/ui/profile/profile_screen.dart';
import 'package:bulk_buying_companion/ui/profile/profile_viewmodel.dart';
import 'package:bulk_buying_companion/ui/shared/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('profile contains only supported identity and hub actions', (
    tester,
  ) async {
    final authRepository = MockAuthRepository();
    await authRepository.signIn(
      email: 'student@usjr.edu.ph',
      password: 'Student123',
    );
    final hubRepository = MockHubRepository();
    await hubRepository.joinHub(
      userId: authRepository.currentUser!.uid,
      hubId: 'colon',
    );
    final viewModel = ProfileViewModel(
      authRepository: authRepository,
      hubRepository: hubRepository,
      dealRepository: _DealHistoryRepository([
        _deal(
          id: 'hosted',
          createdBy: authRepository.currentUser!.uid,
          title: 'Hosted Rice',
        ),
        _deal(id: 'joined', createdBy: 'host-2', title: 'Joined Water'),
        _deal(
          id: 'completed',
          createdBy: 'host-3',
          title: 'Completed Coffee',
          purchasedAt: DateTime(2026, 7, 16),
          collectedCount: 2,
        ),
      ]),
      reservationRepository: _ReservationHistoryRepository({
        'hosted': [
          _reservation('hosted', authRepository.currentUser!.uid, isHost: true),
        ],
        'joined': [
          _reservation('joined', 'host-2', isHost: true),
          _reservation('joined', authRepository.currentUser!.uid),
        ],
        'completed': [
          _reservation('completed', 'host-3', isHost: true),
          _reservation(
            'completed',
            authRepository.currentUser!.uid,
            collectedAt: DateTime(2026, 7, 16),
          ),
        ],
      }),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-avatar')), findsOneWidget);
    expect(find.text('CURRENT HUB'), findsOneWidget);
    expect(find.byKey(const Key('profile-logout-button')), findsOneWidget);
    expect(find.text('Hosted deals'), findsOneWidget);
    expect(find.text('Hosted Rice'), findsOneWidget);
    expect(find.text('Joined deals'), findsOneWidget);
    expect(find.text('Joined Water'), findsOneWidget);
    expect(find.text('Completed deals'), findsOneWidget);
    expect(find.text('Completed Coffee'), findsOneWidget);
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Notifications'), findsNothing);
    expect(find.text('Verified student'), findsNothing);
  });

  testWidgets('profile editing updates the displayed student name', (
    tester,
  ) async {
    final authRepository = _EditableAuthRepository();
    final viewModel = ProfileViewModel(
      authRepository: authRepository,
      hubRepository: MockHubRepository(),
      dealRepository: const _DealHistoryRepository([]),
      reservationRepository: const _ReservationHistoryRepository({}),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('profile-display-name-field')),
      'Updated Student',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(authRepository.lastDisplayName, 'Updated Student');
    expect(find.text('Updated Student'), findsOneWidget);
  });
}

class _EditableAuthRepository implements AuthRepository {
  AppUser _user = const AppUser(
    uid: 'demo-student',
    eduEmail: 'student@usjr.edu.ph',
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

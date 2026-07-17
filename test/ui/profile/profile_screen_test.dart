import 'dart:async';

import 'package:bulk_buying_companion/data/repositories/auth_repository.dart';
import 'package:bulk_buying_companion/data/repositories/hub_repository.dart';
import 'package:bulk_buying_companion/models/app_user.dart';
import 'package:bulk_buying_companion/models/hub.dart';
import 'package:bulk_buying_companion/ui/profile/profile_screen.dart';
import 'package:bulk_buying_companion/ui/profile/profile_viewmodel.dart';
import 'package:bulk_buying_companion/ui/shared/app_banner.dart';
import 'package:bulk_buying_companion/ui/shared/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:bulk_buying_companion/data/repositories/deal_repository.dart';
import 'package:bulk_buying_companion/data/repositories/reservation_repository.dart';
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/models/deal_unit.dart';
import 'package:bulk_buying_companion/models/reservation.dart';

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

  testWidgets('profile no-hub state does not repeat discovery navigation', (
    tester,
  ) async {
    final authRepository = MockAuthRepository();
    await authRepository.signIn(
      email: 'student@usjr.edu.ph',
      password: 'Student123',
    );
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

    expect(find.text("You haven't joined a hub yet."), findsOneWidget);
    expect(find.text('Find a hub'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('initial hub load uses the compact loading tile', (tester) async {
    final initialMembership = Completer<String?>();
    final viewModel = ProfileViewModel(
      authRepository: _SignedInAuthRepository(),
      hubRepository: _ProfileHubRepository(
        membershipResponses: [() => initialMembership.future],
      ),
      dealRepository: const _DealHistoryRepository([]),
      reservationRepository: const _ReservationHistoryRepository({}),
    );

    await _pumpProfile(tester, viewModel);
    await tester.pump();

    expect(find.byKey(const Key('current-hub-progress')), findsOneWidget);
    expect(find.byKey(const Key('profile-current-hub-error')), findsNothing);
    expect(find.text('Sample Student'), findsOneWidget);
    expect(find.byKey(const Key('profile-logout-button')), findsOneWidget);

    initialMembership.complete(null);
    await tester.pumpAndSettle();
    expect(find.text("You haven't joined a hub yet."), findsOneWidget);
  });

  testWidgets('compact hub loading stays usable at 320dp and 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final initialMembership = Completer<String?>();
    final viewModel = ProfileViewModel(
      authRepository: _SignedInAuthRepository(),
      hubRepository: _ProfileHubRepository(
        membershipResponses: [() => initialMembership.future],
      ),
      dealRepository: const _DealHistoryRepository([]),
      reservationRepository: const _ReservationHistoryRepository({}),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const ProfileScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Sample Student'), findsOneWidget);
    expect(find.text('Loading your current hub…'), findsOneWidget);
    expect(find.byKey(const Key('current-hub-progress')), findsOneWidget);
    expect(find.byKey(const Key('profile-logout-button')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.byKey(const Key('profile-logout-button')));
    await tester.pump();
    expect(tester.takeException(), isNull);

    initialMembership.complete(null);
    await tester.pump();
    viewModel.dispose();
  });

  testWidgets('hub load failure keeps identity and logout with retry recovery', (
    tester,
  ) async {
    final retryMembership = Completer<String?>();
    final viewModel = ProfileViewModel(
      authRepository: _SignedInAuthRepository(),
      hubRepository: _ProfileHubRepository(
        membershipResponses: [
          () async => throw StateError('offline'),
          () => retryMembership.future,
        ],
      ),
      dealRepository: const _DealHistoryRepository([]),
      reservationRepository: const _ReservationHistoryRepository({}),
    );

    await _pumpProfile(tester, viewModel);
    await tester.pumpAndSettle();

    expect(find.text('Sample Student'), findsOneWidget);
    expect(find.text('student@usjr.edu.ph'), findsOneWidget);
    expect(find.byKey(const Key('profile-logout-button')), findsOneWidget);
    expect(find.text("You haven't joined a hub yet."), findsNothing);
    expect(
      find.text(
        'Couldn’t load your current hub. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    final errorBanner = tester.widget<AppBanner>(find.byType(AppBanner));
    expect(errorBanner.actionLabel, 'Try again');
    expect(errorBanner.onAction, isNotNull);

    await tester.tap(find.text('Try again'));
    await tester.pump();

    final busyBanner = find.byKey(const Key('profile-current-hub-error'));
    expect(busyBanner, findsOneWidget);
    expect(
      find.text(
        'Couldn’t load your current hub. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(tester.widget<AppBanner>(busyBanner).actionBusy, isTrue);
    expect(
      tester
          .widget<TextButton>(
            find.descendant(of: busyBanner, matching: find.byType(TextButton)),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.descendant(
        of: busyBanner,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('current-hub-progress')), findsNothing);
    expect(find.text('Sample Student'), findsOneWidget);
    expect(find.byKey(const Key('profile-logout-button')), findsOneWidget);
    retryMembership.complete('colon');
    await tester.pumpAndSettle();

    expect(find.text('Colon Street Hub'), findsOneWidget);
    expect(find.byType(AppBanner), findsNothing);
  });

  testWidgets('cached hub remains visible beside retryable load failure', (
    tester,
  ) async {
    final viewModel = ProfileViewModel(
      authRepository: _SignedInAuthRepository(),
      hubRepository: _ProfileHubRepository(
        membershipResponses: [
          () async => 'colon',
          () async => throw StateError('offline'),
        ],
      ),
      dealRepository: const _DealHistoryRepository([]),
      reservationRepository: const _ReservationHistoryRepository({}),
    );
    await _pumpProfile(tester, viewModel);
    await tester.pumpAndSettle();

    await viewModel.retryLoad();
    await tester.pump();

    expect(find.text('Colon Street Hub'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byKey(const Key('profile-logout-button')), findsOneWidget);
  });

  testWidgets('load and sign-out errors render independently', (tester) async {
    final viewModel = ProfileViewModel(
      authRepository: _SignedInAuthRepository(failSignOut: true),
      hubRepository: _ProfileHubRepository(
        membershipResponses: [() async => throw StateError('offline')],
      ),
      dealRepository: const _DealHistoryRepository([]),
      reservationRepository: const _ReservationHistoryRepository({}),
    );
    await _pumpProfile(tester, viewModel);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profile-logout-button')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Couldn’t load your current hub. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Could not log out. Please try again.'), findsOneWidget);
    expect(find.byType(AppBanner), findsNWidgets(2));
  });

  testWidgets('provider disposal is safe during an initial profile load', (
    tester,
  ) async {
    final initialMembership = Completer<String?>();
    await _pumpProfileLauncher(
      tester,
      authRepository: _SignedInAuthRepository(),
      hubRepository: _ProfileHubRepository(
        membershipResponses: [() => initialMembership.future],
      ),
    );

    await tester.tap(find.text('Open profile'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('current-hub-progress')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    initialMembership.complete('colon');
    await tester.pump();
    await tester.pump();

    expect(find.text('Open profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('provider disposal is safe during retry and delayed sign-out', (
    tester,
  ) async {
    final retryMembership = Completer<String?>();
    final signOut = Completer<void>();
    await _pumpProfileLauncher(
      tester,
      authRepository: _SignedInAuthRepository(signOutGate: signOut),
      hubRepository: _ProfileHubRepository(
        membershipResponses: [
          () async => throw StateError('offline'),
          () => retryMembership.future,
        ],
      ),
    );

    await tester.tap(find.text('Open profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('profile-logout-button')));
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();
    retryMembership.complete('colon');
    signOut.complete();
    await tester.pump();
    await tester.pump();

    expect(find.text('Open profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpProfile(WidgetTester tester, ProfileViewModel viewModel) {
  return tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: viewModel,
      child: MaterialApp(theme: AppTheme.light(), home: const ProfileScreen()),
    ),
  );
}

Future<void> _pumpProfileLauncher(
  WidgetTester tester, {
  required AuthRepository authRepository,
  required HubRepository hubRepository,
}) {
  return tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<AuthRepository>.value(value: authRepository),
        Provider<HubRepository>.value(value: hubRepository),
        // ProfileScreen.route builds its ViewModel from these too.
        Provider<DealRepository>.value(value: const _DealHistoryRepository([])),
        Provider<ReservationRepository>.value(
          value: const _ReservationHistoryRepository({}),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  Navigator.of(context).push(ProfileScreen.route()),
              child: const Text('Open profile'),
            ),
          ),
        ),
      ),
    ),
  );
}

const _profileHub = Hub(
  id: 'colon',
  name: 'Colon Street Hub',
  type: HubType.areaHub,
  memberCount: 31,
  distanceLabel: '400 m',
);

class _SignedInAuthRepository implements AuthRepository {
  _SignedInAuthRepository({this.failSignOut = false, this.signOutGate});

  final bool failSignOut;
  final Completer<void>? signOutGate;

  @override
  Stream<AppUser?> get authStateChanges => const Stream.empty();

  @override
  AppUser? get currentUser => const AppUser(
    uid: 'user-1',
    eduEmail: 'student@usjr.edu.ph',
    displayName: 'Sample Student',
  );

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
  Future<void> signOut() async {
    if (failSignOut) throw StateError('backend detail');
    await signOutGate?.future;
  }

  @override
  void dispose() {}

  @override
  Future<AppUser> updateDisplayName(String displayName) {
    throw UnimplementedError();
  }
}

class _ProfileHubRepository implements HubRepository {
  _ProfileHubRepository({required this.membershipResponses});

  final List<Future<String?> Function()> membershipResponses;
  int _nextMembership = 0;

  @override
  Future<String?> getCurrentHubId(String userId) =>
      membershipResponses[_nextMembership++]();

  @override
  Future<List<Hub>> getHubs() async => const [_profileHub];

  @override
  Future<Hub> createHub(HubDraft draft) {
    throw UnimplementedError();
  }

  @override
  Future<void> joinHub({required String userId, required String hubId}) async {}

  @override
  Future<void> leaveHub({required String userId}) async {}
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

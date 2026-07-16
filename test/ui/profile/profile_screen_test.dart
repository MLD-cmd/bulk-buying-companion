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
    expect(find.text('Edit profile'), findsNothing);
    expect(find.text('Notifications'), findsNothing);
    expect(find.text('Verified student'), findsNothing);
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

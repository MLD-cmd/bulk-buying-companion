import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bulk_buying_companion/data/repositories/auth_repository.dart';
import 'package:bulk_buying_companion/data/repositories/hub_repository.dart';
import 'package:bulk_buying_companion/data/services/location_service.dart';
import 'package:bulk_buying_companion/main.dart';
import 'package:bulk_buying_companion/models/app_user.dart';
import 'package:bulk_buying_companion/ui/hub/widgets/hub_card.dart';

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    AuthRepository? repository,
    HubRepository? hubRepository,
    LocationService? locationService,
  }) {
    return tester.pumpWidget(
      BulkBuyingCompanionApp(
        authRepository: repository ?? MockAuthRepository(),
        hubRepository: hubRepository,
        locationService: locationService ?? const _StubLocationService(),
      ),
    );
  }

  /// Taps Join on a named hub. The list is sorted by distance, so the card at
  /// a given position depends on where [_StubLocationService] puts the student
  /// — a test that cares which hub it joined has to say so.
  Future<void> joinHubNamed(WidgetTester tester, String name) async {
    final card = find.ancestor(
      of: find.text(name),
      matching: find.byType(HubCard),
    );
    await tester.tap(find.descendant(of: card, matching: find.text('Join')));
    await tester.pumpAndSettle();
  }

  Future<void> signIn(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'student@usjr.edu.ph',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      'Student123',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();
  }

  testWidgets('app opens on the login screen', (tester) async {
    await pumpApp(tester);

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
    expect(find.text('Find your hub'), findsNothing);
  });

  testWidgets('authentication stays usable at narrow width and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpApp(tester);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pump();

    expect(find.byKey(const Key('auth-brand-mark')), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('student can switch to registration', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.byKey(const Key('auth-name-field')), findsOneWidget);
    expect(
      find.byKey(const Key('auth-confirm-password-field')),
      findsOneWidget,
    );
  });

  testWidgets('login displays email and password errors', (tester) async {
    await pumpApp(tester);

    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'not-an-email',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      'weak',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pump();

    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.textContaining('at least 8 characters'), findsOneWidget);
  });

  testWidgets('login displays an incorrect credentials error', (tester) async {
    await pumpApp(tester);

    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'student@usjr.edu.ph',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      'WrongPass1',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pump();

    expect(find.text('Incorrect email or password.'), findsOneWidget);
  });

  testWidgets('student can register with any valid email', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('auth-name-field')),
      'Jay Student',
    );
    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'jay@gmail.com',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      'StrongPass1',
    );
    await tester.enterText(
      find.byKey(const Key('auth-confirm-password-field')),
      'StrongPass1',
    );
    final createAccountButton = find.widgetWithText(
      FilledButton,
      'Create account',
    );
    await tester.ensureVisible(createAccountButton);
    await tester.tap(createAccountButton);
    await tester.pumpAndSettle();

    expect(find.text('Find your hub'), findsOneWidget);
  });

  testWidgets('registration displays an email confirmation notice', (
    tester,
  ) async {
    await pumpApp(tester, repository: _ConfirmationAuthRepository());
    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('auth-name-field')),
      'Jay Student',
    );
    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'jay@gmail.com',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      'StrongPass1',
    );
    await tester.enterText(
      find.byKey(const Key('auth-confirm-password-field')),
      'StrongPass1',
    );
    final createAccountButton = find.widgetWithText(
      FilledButton,
      'Create account',
    );
    await tester.ensureVisible(createAccountButton);
    await tester.tap(createAccountButton);
    await tester.pump();

    expect(
      find.text('Check your email to confirm your account, then log in.'),
      findsOneWidget,
    );
  });

  testWidgets('registration requires matching passwords', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('auth-name-field')),
      'Jay Student',
    );
    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'jay@college.edu',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      'StrongPass1',
    );
    await tester.enterText(
      find.byKey(const Key('auth-confirm-password-field')),
      'Different1',
    );
    final createAccountButton = find.widgetWithText(
      FilledButton,
      'Create account',
    );
    await tester.ensureVisible(createAccountButton);
    await tester.tap(createAccountButton);
    await tester.pump();

    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(find.text('Find your hub'), findsNothing);
  });

  testWidgets('Join Hub screen loads and lists hubs', (tester) async {
    await pumpApp(tester);
    await signIn(tester);

    expect(find.text('Find your hub'), findsOneWidget);
    expect(find.text('Magallanes Residence'), findsOneWidget);
  });

  testWidgets('Search filters the hub list', (tester) async {
    await pumpApp(tester);
    await signIn(tester);

    await tester.enterText(find.byType(TextField), 'colon');
    await tester.pump();

    expect(find.text('Colon Street Hub'), findsOneWidget);
    expect(find.text('Magallanes Residence'), findsNothing);
  });

  testWidgets('hub list is sorted nearest first', (tester) async {
    await pumpApp(tester);
    await signIn(tester);

    final names = tester
        .widgetList<HubCard>(find.byType(HubCard))
        .map((card) => card.hub.name)
        .toList();

    // Colon Street Hub is the closest seeded hub to _StubLocationService;
    // Magallanes Residence is first in the directory but not the nearest.
    expect(names.first, 'Colon Street Hub');
    expect(
      names.indexOf('Colon Street Hub'),
      lessThan(names.indexOf('Magallanes Residence')),
    );
  });

  testWidgets('the radius filter hides hubs beyond it', (tester) async {
    await pumpApp(tester);
    await signIn(tester);

    expect(find.byType(HubCard), findsNWidgets(5));

    await tester.tap(find.byKey(const Key('hub-nearby-filter')));
    await tester.pumpAndSettle();

    // Every seeded hub sits ~3 km from the stub position, past the 2 km radius.
    expect(find.byType(HubCard), findsNothing);
    expect(find.text('No hubs nearby'), findsOneWidget);

    await tester.tap(find.byKey(const Key('hub-nearby-filter')));
    await tester.pumpAndSettle();

    expect(find.byType(HubCard), findsNWidgets(5));
  });

  testWidgets('Joining a hub shows the current-hub banner', (tester) async {
    await pumpApp(tester);
    await signIn(tester);

    await tester.tap(find.text('Join').first);
    await tester.pumpAndSettle();

    expect(find.text('CURRENT HUB'), findsOneWidget);
    expect(find.text('Joined'), findsOneWidget);
  });

  testWidgets('joined hub persists after app restart', (tester) async {
    final authRepository = MockAuthRepository();
    final hubRepository = MockHubRepository();
    await pumpApp(
      tester,
      repository: authRepository,
      hubRepository: hubRepository,
    );
    await signIn(tester);

    await tester.tap(find.text('Join').first);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpApp(
      tester,
      repository: authRepository,
      hubRepository: hubRepository,
    );
    await tester.pumpAndSettle();

    expect(find.text('CURRENT HUB'), findsOneWidget);
    expect(find.text('Joined'), findsOneWidget);
  });

  testWidgets('Split Board opens from the hub banner and lists deals', (
    tester,
  ) async {
    await pumpApp(tester);
    await signIn(tester);

    await joinHubNamed(tester, 'Magallanes Residence');
    await tester.tap(find.text('View deals'));
    await tester.pumpAndSettle();

    expect(find.text('Split Board'), findsOneWidget);
    expect(find.text('Egg Tray (30s) — Split 3 ways'), findsOneWidget);
  });

  testWidgets('student registers a hub and it lands on the hub list', (
    tester,
  ) async {
    await pumpApp(tester, locationService: const _StubLocationService());
    await signIn(tester);

    expect(find.text('Escario Heights'), findsNothing);

    await tester.tap(find.byIcon(Icons.add_location_alt_outlined));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('hub-name-field')),
      'Escario Heights',
    );
    // Fill the coordinates from the device instead of typing them.
    await tester.tap(find.byKey(const Key('hub-use-location-button')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextFormField>(find.byKey(const Key('hub-latitude-field'))),
      isNotNull,
    );

    await tester.tap(find.byKey(const Key('hub-submit-button')));
    await tester.pumpAndSettle();

    // Back on Find your hub, with the new hub in the directory.
    expect(find.text('Find your hub'), findsOneWidget);
    expect(find.text('Escario Heights'), findsOneWidget);
  });

  testWidgets('registering a hub that already exists is refused', (
    tester,
  ) async {
    await pumpApp(tester, locationService: const _StubLocationService());
    await signIn(tester);

    await tester.tap(find.byIcon(Icons.add_location_alt_outlined));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('hub-name-field')),
      'Colon Street Hub',
    );
    await tester.enterText(
      find.byKey(const Key('hub-latitude-field')),
      '10.3200',
    );
    await tester.enterText(
      find.byKey(const Key('hub-longitude-field')),
      '123.9100',
    );
    await tester.tap(find.byKey(const Key('hub-submit-button')));
    await tester.pumpAndSettle();

    // Still on the form, with the reason shown.
    expect(find.text('Register a hub'), findsOneWidget);
    expect(
      find.text('A hub named "Colon Street Hub" is already registered.'),
      findsOneWidget,
    );
  });

  testWidgets('Profile screen shows the joined hub after joining', (
    tester,
  ) async {
    await pumpApp(tester);
    await signIn(tester);

    await joinHubNamed(tester, 'Magallanes Residence');

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Magallanes Residence'), findsOneWidget);
    expect(find.textContaining("haven't joined"), findsNothing);
  });

  testWidgets('Profile screen shows empty state before joining', (
    tester,
  ) async {
    await pumpApp(tester);
    await signIn(tester);

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();

    expect(find.textContaining("haven't joined"), findsOneWidget);
  });

  testWidgets('student can log out from profile', (tester) async {
    await pumpApp(tester);
    await signIn(tester);

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Find your hub'), findsNothing);
  });

  testWidgets('profile displays logout failures and remains open', (
    tester,
  ) async {
    await pumpApp(tester, repository: _FailingSignOutRepository());
    await signIn(tester);

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pump();

    expect(find.text('Profile'), findsOneWidget);
    expect(
      find.text('Check your internet connection and try again.'),
      findsOneWidget,
    );
    expect(find.text('Welcome back'), findsNothing);
  });
}

class _StubLocationService implements LocationService {
  const _StubLocationService();

  @override
  Future<Coordinates> getCurrentPosition() async {
    // Somewhere clear of every seeded mock hub.
    return const Coordinates(latitude: 10.3200, longitude: 123.9100);
  }
}

class _ConfirmationAuthRepository implements AuthRepository {
  @override
  Stream<AppUser?> get authStateChanges => const Stream.empty();

  @override
  AppUser? get currentUser => null;

  @override
  Future<AppUser> signIn({required String email, required String password}) {
    throw UnimplementedError();
  }

  @override
  Future<AuthRegistrationResult> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    return AuthRegistrationResult(
      user: AppUser(uid: 'pending-user', eduEmail: email),
      requiresEmailConfirmation: true,
    );
  }

  @override
  Future<void> signOut() async {}

  @override
  void dispose() {}
}

class _FailingSignOutRepository extends MockAuthRepository {
  @override
  Future<void> signOut() {
    throw const AuthFailure('Check your internet connection and try again.');
  }
}

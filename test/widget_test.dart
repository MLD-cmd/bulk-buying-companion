import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bulk_buying_companion/data/repositories/auth_repository.dart';
import 'package:bulk_buying_companion/data/repositories/hub_repository.dart';
import 'package:bulk_buying_companion/main.dart';
import 'package:bulk_buying_companion/models/app_user.dart';

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    AuthRepository? repository,
    HubRepository? hubRepository,
  }) {
    return tester.pumpWidget(
      BulkBuyingCompanionApp(
        authRepository: repository ?? MockAuthRepository(),
        hubRepository: hubRepository,
      ),
    );
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

  testWidgets('app opens on the login stub', (tester) async {
    await pumpApp(tester);

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Use demo account'), findsOneWidget);
    expect(find.text('Find your hub'), findsNothing);
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
    await tester.pumpWidget(const BulkBuyingCompanionApp());
    await signIn(tester);

    await tester.tap(find.text('Join').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('View deals'));
    await tester.pumpAndSettle();

    expect(find.text('Split Board'), findsOneWidget);
    expect(find.text('Egg Tray (30s) — Split 3 ways'), findsOneWidget);
  });

  testWidgets('Profile screen shows the joined hub after joining', (
    tester,
  ) async {
    await pumpApp(tester);
    await signIn(tester);

    await tester.tap(find.text('Join').first);
    await tester.pumpAndSettle();

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

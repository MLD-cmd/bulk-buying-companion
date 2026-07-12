import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bulk_buying_companion/main.dart';

void main() {
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
    await tester.pumpWidget(const BulkBuyingCompanionApp());

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Use demo account'), findsOneWidget);
    expect(find.text('Find your hub'), findsNothing);
  });

  testWidgets('student can switch to registration', (tester) async {
    await tester.pumpWidget(const BulkBuyingCompanionApp());

    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.byKey(const Key('auth-name-field')), findsOneWidget);
    expect(
      find.byKey(const Key('auth-confirm-password-field')),
      findsOneWidget,
    );
  });

  testWidgets('login displays school email and password errors', (
    tester,
  ) async {
    await tester.pumpWidget(const BulkBuyingCompanionApp());

    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'student@gmail.com',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      'weak',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pump();

    expect(
      find.text('Use your .edu or approved school email.'),
      findsOneWidget,
    );
    expect(find.textContaining('at least 8 characters'), findsOneWidget);
  });

  testWidgets('login displays an incorrect credentials error', (tester) async {
    await tester.pumpWidget(const BulkBuyingCompanionApp());

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

  testWidgets('student can register with a school email', (tester) async {
    await tester.pumpWidget(const BulkBuyingCompanionApp());
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

  testWidgets('registration requires matching passwords', (tester) async {
    await tester.pumpWidget(const BulkBuyingCompanionApp());
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
    await tester.pumpWidget(const BulkBuyingCompanionApp());
    await signIn(tester);

    expect(find.text('Find your hub'), findsOneWidget);
    expect(find.text('Magallanes Residence'), findsOneWidget);
  });

  testWidgets('Search filters the hub list', (tester) async {
    await tester.pumpWidget(const BulkBuyingCompanionApp());
    await signIn(tester);

    await tester.enterText(find.byType(TextField), 'colon');
    await tester.pump();

    expect(find.text('Colon Street Hub'), findsOneWidget);
    expect(find.text('Magallanes Residence'), findsNothing);
  });

  testWidgets('Joining a hub shows the current-hub banner', (tester) async {
    await tester.pumpWidget(const BulkBuyingCompanionApp());
    await signIn(tester);

    await tester.tap(find.text('Join').first);
    await tester.pumpAndSettle();

    expect(find.text('CURRENT HUB'), findsOneWidget);
    expect(find.text('Joined'), findsOneWidget);
  });

  testWidgets('Profile screen shows the joined hub after joining', (
    tester,
  ) async {
    await tester.pumpWidget(const BulkBuyingCompanionApp());
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
    await tester.pumpWidget(const BulkBuyingCompanionApp());
    await signIn(tester);

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();

    expect(find.textContaining("haven't joined"), findsOneWidget);
  });

  testWidgets('student can log out from profile', (tester) async {
    await tester.pumpWidget(const BulkBuyingCompanionApp());
    await signIn(tester);

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Find your hub'), findsNothing);
  });
}

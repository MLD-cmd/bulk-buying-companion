import 'package:bulk_buying_companion/data/repositories/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('email validation', () {
    test('accepts institutional and ordinary valid email addresses', () {
      expect(EmailValidator.isValid('learner@college.edu'), isTrue);
      expect(EmailValidator.isValid('student@usjr.edu.ph'), isTrue);
      expect(EmailValidator.isValid('student@gmail.com'), isTrue);
    });

    test('rejects malformed email addresses', () {
      expect(EmailValidator.isValid('not-an-email'), isFalse);
      expect(EmailValidator.isValid('first last@college.edu'), isFalse);
      expect(EmailValidator.isValid('.@college.edu'), isFalse);
      expect(EmailValidator.isValid('student@.edu'), isFalse);
    });
  });

  group('password validation', () {
    test('requires length, upper-case, lower-case, and a number', () {
      expect(PasswordValidator.errorFor('short'), isNotNull);
      expect(PasswordValidator.errorFor('alllowercase1'), isNotNull);
      expect(PasswordValidator.errorFor('ALLUPPERCASE1'), isNotNull);
      expect(PasswordValidator.errorFor('NoNumbersHere'), isNotNull);
      expect(PasswordValidator.errorFor('StrongPass1'), isNull);
    });
  });

  group('MockAuthRepository', () {
    late MockAuthRepository repository;

    setUp(() => repository = MockAuthRepository());
    tearDown(() => repository.dispose());

    test('starts signed out and registers a student', () async {
      expect(repository.currentUser, isNull);

      final result = await repository.register(
        displayName: 'Jay Student',
        email: 'jay@college.edu',
        password: 'StrongPass1',
      );

      expect(result.user.displayName, 'Jay Student');
      expect(result.user.eduEmail, 'jay@college.edu');
      expect(result.requiresEmailConfirmation, isFalse);
      expect(repository.currentUser, same(result.user));
    });

    test('reports invalid credentials', () async {
      expect(
        () => repository.signIn(
          email: 'student@usjr.edu.ph',
          password: 'WrongPass1',
        ),
        throwsA(
          isA<AuthFailure>().having(
            (error) => error.message,
            'message',
            'Incorrect email or password.',
          ),
        ),
      );
    });

    test('publishes sign-in and sign-out state changes', () async {
      final states = <String?>[];
      final subscription = repository.authStateChanges.listen(
        (user) => states.add(user?.eduEmail),
      );

      await repository.signIn(
        email: 'student@usjr.edu.ph',
        password: 'Student123',
      );
      await repository.signOut();
      await Future<void>.delayed(Duration.zero);

      expect(states, ['student@usjr.edu.ph', null]);
      await subscription.cancel();
    });

    test('logs back in to an account registered during the session', () async {
      await repository.register(
        displayName: 'Jay Student',
        email: 'jay@college.edu',
        password: 'StrongPass1',
      );
      await repository.signOut();

      final user = await repository.signIn(
        email: 'jay@college.edu',
        password: 'StrongPass1',
      );

      expect(user.displayName, 'Jay Student');
    });

    test(
      'updates the signed-in display name and publishes the change',
      () async {
        final states = <String?>[];
        final subscription = repository.authStateChanges.listen(
          (user) => states.add(user?.displayName),
        );
        await repository.signIn(
          email: 'student@usjr.edu.ph',
          password: 'Student123',
        );

        final user = await repository.updateDisplayName(' Updated Student ');
        await Future<void>.delayed(Duration.zero);

        expect(user.displayName, 'Updated Student');
        expect(repository.currentUser?.displayName, 'Updated Student');
        expect(states, ['Sample Student', 'Updated Student']);
        await subscription.cancel();
      },
    );
  });
}

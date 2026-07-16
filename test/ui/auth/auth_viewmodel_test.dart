import 'dart:async';

import 'package:bulk_buying_companion/data/repositories/auth_repository.dart';
import 'package:bulk_buying_companion/models/app_user.dart';
import 'package:bulk_buying_companion/ui/auth/auth_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ignores duplicate submissions and mode changes while submitting', () {
    final repository = _DelayedAuthRepository();
    final viewModel = AuthViewModel(authRepository: repository);

    viewModel.submit(
      displayName: '',
      email: 'student@college.edu',
      password: 'StrongPass1',
    );
    viewModel.submit(
      displayName: '',
      email: 'student@college.edu',
      password: 'StrongPass1',
    );
    viewModel.setMode(AuthMode.register);

    expect(repository.signInCalls, 1);
    expect(viewModel.mode, AuthMode.login);
  });

  test('does not notify after disposal when a submission completes', () async {
    final repository = _DelayedAuthRepository();
    final viewModel = AuthViewModel(authRepository: repository);

    final operation = viewModel.submit(
      displayName: '',
      email: 'student@college.edu',
      password: 'StrongPass1',
    );
    viewModel.dispose();
    repository.completer.completeError(const AuthFailure('No connection.'));

    await expectLater(operation, completes);
  });

  test('shows an email confirmation notice after registration', () async {
    final repository = _DelayedAuthRepository();
    final viewModel = AuthViewModel(authRepository: repository)
      ..setMode(AuthMode.register);
    final operation = viewModel.submit(
      displayName: 'Jay Student',
      email: 'student@gmail.com',
      password: 'StrongPass1',
    );
    repository.registerCompleter.complete(
      const AuthRegistrationResult(
        user: AppUser(
          uid: 'new-user',
          eduEmail: 'student@gmail.com',
          displayName: 'Jay Student',
        ),
        requiresEmailConfirmation: true,
      ),
    );

    await operation;

    expect(
      viewModel.noticeMessage,
      'Check your email to confirm your account, then log in.',
    );
    expect(viewModel.errorMessage, isNull);
  });

  test('clears stale notices when changing mode', () async {
    final repository = _DelayedAuthRepository();
    final viewModel = AuthViewModel(authRepository: repository)
      ..setMode(AuthMode.register);
    final operation = viewModel.submit(
      displayName: 'Jay Student',
      email: 'student@gmail.com',
      password: 'StrongPass1',
    );
    repository.registerCompleter.complete(
      const AuthRegistrationResult(
        user: AppUser(uid: 'new-user', eduEmail: 'student@gmail.com'),
        requiresEmailConfirmation: true,
      ),
    );
    await operation;

    viewModel.setMode(AuthMode.login);

    expect(viewModel.noticeMessage, isNull);
  });
}

class _DelayedAuthRepository implements AuthRepository {
  final completer = Completer<AppUser>();
  final registerCompleter = Completer<AuthRegistrationResult>();
  int signInCalls = 0;

  @override
  Stream<AppUser?> get authStateChanges => const Stream.empty();

  @override
  AppUser? get currentUser => null;

  @override
  Future<AppUser> signIn({required String email, required String password}) {
    signInCalls++;
    return completer.future;
  }

  @override
  Future<AuthRegistrationResult> register({
    required String displayName,
    required String email,
    required String password,
  }) => registerCompleter.future;

  @override
  Future<AppUser> updateDisplayName(String displayName) {
    throw UnimplementedError();
  }

  @override
  Future<void> signOut() async {}

  @override
  void dispose() {}
}

import 'dart:async';

import '../../models/app_user.dart';

class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class EmailValidator {
  EmailValidator._();

  static bool isValid(String value) {
    final email = value.trim().toLowerCase();
    final parts = email.split('@');
    if (parts.length != 2 || parts.first.isEmpty || parts.last.isEmpty) {
      return false;
    }

    final localPart = parts.first;
    if (localPart.startsWith('.') ||
        localPart.endsWith('.') ||
        localPart.contains('..') ||
        !RegExp(r"^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+$").hasMatch(localPart)) {
      return false;
    }

    final domain = parts.last;
    final labels = domain.split('.');
    if (labels.length < 2 ||
        labels.any(
          (label) =>
              label.isEmpty ||
              label.length > 63 ||
              !RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(label),
        )) {
      return false;
    }

    return true;
  }
}

class PasswordValidator {
  PasswordValidator._();

  static const requirement =
      'Use at least 8 characters with upper-case, lower-case, and a number.';

  static String? errorFor(String value) {
    final isStrong =
        value.length >= 8 &&
        RegExp('[A-Z]').hasMatch(value) &&
        RegExp('[a-z]').hasMatch(value) &&
        RegExp('[0-9]').hasMatch(value);
    return isStrong ? null : requirement;
  }
}

/// Identity contract the rest of the app depends on.
abstract class AuthRepository {
  Stream<AppUser?> get authStateChanges;

  AppUser? get currentUser;

  Future<AppUser> signIn({required String email, required String password});

  Future<AuthRegistrationResult> register({
    required String displayName,
    required String email,
    required String password,
  });

  Future<void> signOut();

  void dispose();
}

class AuthRegistrationResult {
  const AuthRegistrationResult({
    required this.user,
    required this.requiresEmailConfirmation,
  });

  final AppUser user;
  final bool requiresEmailConfirmation;
}

/// In-memory authentication used until a remote auth provider is connected.
class MockAuthRepository implements AuthRepository {
  MockAuthRepository() {
    _accounts['student@usjr.edu.ph'] = const _MockAccount(
      user: AppUser(
        uid: 'demo-student',
        eduEmail: 'student@usjr.edu.ph',
        displayName: 'Sample Student',
      ),
      password: 'Student123',
    );
  }

  final _controller = StreamController<AppUser?>.broadcast(sync: true);
  final Map<String, _MockAccount> _accounts = {};
  AppUser? _user;
  int _nextUserId = 1;

  @override
  Stream<AppUser?> get authStateChanges => _controller.stream;

  @override
  AppUser? get currentUser => _user;

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final account = _accounts[normalizedEmail];
    if (account == null || account.password != password) {
      throw const AuthFailure('Incorrect email or password.');
    }

    _setUser(account.user);
    return account.user;
  }

  @override
  Future<AuthRegistrationResult> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (!EmailValidator.isValid(normalizedEmail)) {
      throw const AuthFailure('Enter a valid email address.');
    }
    final passwordError = PasswordValidator.errorFor(password);
    if (passwordError != null) throw AuthFailure(passwordError);
    if (_accounts.containsKey(normalizedEmail)) {
      throw const AuthFailure('An account already exists for this email.');
    }

    final user = AppUser(
      uid: 'mock-user-${_nextUserId++}',
      eduEmail: normalizedEmail,
      displayName: displayName.trim(),
    );
    _accounts[normalizedEmail] = _MockAccount(user: user, password: password);
    _setUser(user);
    return AuthRegistrationResult(user: user, requiresEmailConfirmation: false);
  }

  @override
  Future<void> signOut() async => _setUser(null);

  void _setUser(AppUser? user) {
    _user = user;
    _controller.add(user);
  }

  @override
  void dispose() => _controller.close();
}

class _MockAccount {
  const _MockAccount({required this.user, required this.password});

  final AppUser user;
  final String password;
}

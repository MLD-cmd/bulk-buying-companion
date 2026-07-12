import 'dart:async';

import 'package:bulk_buying_companion/data/repositories/auth_repository.dart';
import 'package:bulk_buying_companion/data/repositories/hub_repository.dart';
import 'package:bulk_buying_companion/models/app_user.dart';
import 'package:bulk_buying_companion/models/hub.dart';
import 'package:bulk_buying_companion/ui/profile/profile_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports successful logout and exposes progress', () async {
    final authRepository = _DelayedSignOutRepository();
    final viewModel = ProfileViewModel(
      authRepository: authRepository,
      hubRepository: _EmptyHubRepository(),
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
    );

    await Future<void>.delayed(Duration.zero);

    expect(viewModel.isLoading, isFalse);
    expect(viewModel.errorMessage, 'Could not load profile. Please try again.');
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

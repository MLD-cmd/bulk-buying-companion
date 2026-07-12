import 'dart:async';

import 'package:bulk_buying_companion/data/repositories/auth_repository.dart';
import 'package:bulk_buying_companion/data/repositories/hub_repository.dart';
import 'package:bulk_buying_companion/models/app_user.dart';
import 'package:bulk_buying_companion/models/hub.dart';
import 'package:bulk_buying_companion/ui/hub/join_hub_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stops loading when hub data fails to load', () async {
    final viewModel = JoinHubViewModel(
      authRepository: _SignedInAuthRepository(),
      hubRepository: _FailingHubRepository(),
    );

    await Future<void>.delayed(Duration.zero);

    expect(viewModel.isLoading, isFalse);
    expect(viewModel.filteredHubs, isEmpty);
  });
}

class _SignedInAuthRepository implements AuthRepository {
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
  Future<void> signOut() async {}

  @override
  void dispose() {}
}

class _FailingHubRepository implements HubRepository {
  @override
  Future<List<Hub>> getHubs() {
    throw StateError('hub table unavailable');
  }

  @override
  Future<String?> getCurrentHubId(String userId) {
    throw StateError('membership table unavailable');
  }

  @override
  Future<void> joinHub({required String userId, required String hubId}) async {}

  @override
  Future<void> leaveHub({required String userId}) async {}
}

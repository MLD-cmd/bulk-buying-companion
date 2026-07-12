import '../../models/app_user.dart';

/// Identity contract the rest of the app depends on.
///
/// JT wires the real implementation (Firebase/Supabase) behind this
/// interface for the Student Registration & Login card. Every other
/// feature — including Join Hub — only ever talks to [AuthRepository],
/// never to a concrete auth SDK, so swapping [MockAuthRepository] for
/// a real one requires no changes outside this file.
abstract class AuthRepository {
  /// Emits the signed-in user, or null when signed out.
  Stream<AppUser?> get authStateChanges;

  AppUser? get currentUser;

  Future<void> signOut();
}

/// Stands in for real auth until the Registration & Login card lands.
/// Always reports one fake signed-in student.
class MockAuthRepository implements AuthRepository {
  MockAuthRepository()
      : _user = const AppUser(
          uid: 'mock-user-1',
          eduEmail: 'student@usjr.edu.ph',
          displayName: 'Sample Student',
        ) {
    _controller = Stream<AppUser?>.value(_user).asBroadcastStream();
  }

  AppUser? _user;
  late final Stream<AppUser?> _controller;

  @override
  Stream<AppUser?> get authStateChanges => _controller;

  @override
  AppUser? get currentUser => _user;

  @override
  Future<void> signOut() async {
    _user = null;
  }
}

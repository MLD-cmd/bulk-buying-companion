import '../../models/app_user.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_repository.dart';

class SupabaseAuthIdentity {
  const SupabaseAuthIdentity({
    required this.id,
    required this.email,
    this.metadata = const {},
  });

  final String id;
  final String email;
  final Map<String, dynamic> metadata;
}

class SupabaseAuthGatewayResponse {
  const SupabaseAuthGatewayResponse({
    required this.identity,
    required this.hasSession,
  });

  final SupabaseAuthIdentity identity;
  final bool hasSession;
}

class SupabaseAuthGatewayException implements Exception {
  const SupabaseAuthGatewayException({
    required this.message,
    this.statusCode,
    this.isNetworkFailure = false,
  });

  final String message;
  final String? statusCode;
  final bool isNetworkFailure;
}

abstract class SupabaseAuthGateway {
  SupabaseAuthIdentity? get currentUser;

  Stream<SupabaseAuthIdentity?> get authStateChanges;

  Future<SupabaseAuthGatewayResponse> signInWithPassword({
    required String email,
    required String password,
  });

  Future<SupabaseAuthGatewayResponse> signUp({
    required String email,
    required String password,
    required String displayName,
  });

  Future<void> signOut();
}

class GoTrueSupabaseAuthGateway implements SupabaseAuthGateway {
  GoTrueSupabaseAuthGateway(this._client);

  final GoTrueClient _client;

  @override
  SupabaseAuthIdentity? get currentUser => _mapUser(_client.currentUser);

  @override
  Stream<SupabaseAuthIdentity?> get authStateChanges =>
      _client.onAuthStateChange.map((state) => _mapUser(state.session?.user));

  @override
  Future<SupabaseAuthGatewayResponse> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.signInWithPassword(
        email: email,
        password: password,
      );
      return _mapResponse(response);
    } on AuthException catch (error) {
      throw _mapException(error);
    }
  }

  @override
  Future<SupabaseAuthGatewayResponse> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final response = await _client.signUp(
        email: email,
        password: password,
        data: {'display_name': displayName},
      );
      return _mapResponse(response);
    } on AuthException catch (error) {
      throw _mapException(error);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.signOut();
    } on AuthException catch (error) {
      throw _mapException(error);
    }
  }

  SupabaseAuthGatewayResponse _mapResponse(AuthResponse response) {
    final identity = _mapUser(response.user);
    if (identity == null) {
      throw const SupabaseAuthGatewayException(
        message: 'Supabase returned no user for this authentication request.',
      );
    }
    return SupabaseAuthGatewayResponse(
      identity: identity,
      hasSession: response.session != null,
    );
  }

  SupabaseAuthIdentity? _mapUser(User? user) {
    final email = user?.email;
    if (user == null || email == null || email.isEmpty) return null;
    return SupabaseAuthIdentity(
      id: user.id,
      email: email,
      metadata: user.userMetadata ?? const {},
    );
  }

  SupabaseAuthGatewayException _mapException(AuthException error) {
    return SupabaseAuthGatewayException(
      message: error.message,
      statusCode: error.statusCode,
      isNetworkFailure: error is AuthRetryableFetchException,
    );
  }
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository({required SupabaseAuthGateway gateway})
    : _gateway = gateway;

  final SupabaseAuthGateway _gateway;

  @override
  Stream<AppUser?> get authStateChanges =>
      _gateway.authStateChanges.map(_mapIdentity);

  @override
  AppUser? get currentUser => _mapIdentity(_gateway.currentUser);

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _gateway.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      return _mapIdentity(response.identity)!;
    } on SupabaseAuthGatewayException catch (error) {
      throw AuthFailure(_messageFor(error));
    }
  }

  @override
  Future<AuthRegistrationResult> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _gateway.signUp(
        email: email.trim().toLowerCase(),
        password: password,
        displayName: displayName.trim(),
      );
      return AuthRegistrationResult(
        user: _mapIdentity(response.identity)!,
        requiresEmailConfirmation: !response.hasSession,
      );
    } on SupabaseAuthGatewayException catch (error) {
      throw AuthFailure(_messageFor(error));
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _gateway.signOut();
    } on SupabaseAuthGatewayException catch (error) {
      throw AuthFailure(_messageFor(error));
    }
  }

  AppUser? _mapIdentity(SupabaseAuthIdentity? identity) {
    if (identity == null) return null;
    final displayName = identity.metadata['display_name'];
    return AppUser(
      uid: identity.id,
      eduEmail: identity.email,
      displayName: displayName is String && displayName.trim().isNotEmpty
          ? displayName.trim()
          : null,
    );
  }

  String _messageFor(SupabaseAuthGatewayException error) {
    final message = error.message.toLowerCase();
    if (error.isNetworkFailure) {
      return 'Check your internet connection and try again.';
    }
    if (error.statusCode == '429' || message.contains('rate limit')) {
      return 'Too many attempts. Please wait and try again.';
    }
    if (message.contains('invalid login credentials')) {
      return 'Incorrect email or password.';
    }
    if (message.contains('already registered') ||
        message.contains('already exists')) {
      return 'An account already exists for this email.';
    }
    if (message.contains('invalid email')) {
      return 'Enter a valid email address.';
    }
    return 'Authentication is unavailable. Please try again.';
  }

  @override
  void dispose() {}
}

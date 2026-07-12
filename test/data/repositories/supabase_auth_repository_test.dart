import 'dart:async';

import 'package:bulk_buying_companion/data/repositories/auth_repository.dart';
import 'package:bulk_buying_companion/data/repositories/supabase_auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('SupabaseAuthRepository', () {
    late _FakeSupabaseAuthGateway gateway;
    late SupabaseAuthRepository repository;

    setUp(() {
      gateway = _FakeSupabaseAuthGateway();
      repository = SupabaseAuthRepository(gateway: gateway);
    });

    tearDown(() {
      repository.dispose();
      gateway.dispose();
    });

    test('maps the current Supabase identity to an app user', () {
      gateway.user = const SupabaseAuthIdentity(
        id: 'user-1',
        email: 'student@gmail.com',
        metadata: {'display_name': 'Jay Student'},
      );

      final user = repository.currentUser;

      expect(user?.uid, 'user-1');
      expect(user?.eduEmail, 'student@gmail.com');
      expect(user?.displayName, 'Jay Student');
    });

    test('maps auth state changes', () async {
      final states = <String?>[];
      final subscription = repository.authStateChanges.listen(
        (user) => states.add(user?.uid),
      );

      gateway.emit(
        const SupabaseAuthIdentity(id: 'user-2', email: 'learner@college.edu'),
      );
      gateway.emit(null);
      await Future<void>.delayed(Duration.zero);

      expect(states, ['user-2', null]);
      await subscription.cancel();
    });

    test('signs in with normalized credentials', () async {
      gateway.nextResponse = const SupabaseAuthGatewayResponse(
        identity: SupabaseAuthIdentity(
          id: 'user-3',
          email: 'student@gmail.com',
        ),
        hasSession: true,
      );

      final user = await repository.signIn(
        email: ' Student@Gmail.com ',
        password: 'StrongPass1',
      );

      expect(gateway.lastEmail, 'student@gmail.com');
      expect(gateway.lastPassword, 'StrongPass1');
      expect(user.uid, 'user-3');
    });

    test(
      'registers with display name metadata and reports confirmation',
      () async {
        gateway.nextResponse = const SupabaseAuthGatewayResponse(
          identity: SupabaseAuthIdentity(
            id: 'user-4',
            email: 'new@example.com',
          ),
          hasSession: false,
        );

        final result = await repository.register(
          displayName: ' Jay Student ',
          email: ' New@Example.com ',
          password: 'StrongPass1',
        );

        expect(gateway.lastEmail, 'new@example.com');
        expect(gateway.lastDisplayName, 'Jay Student');
        expect(result.user.uid, 'user-4');
        expect(result.requiresEmailConfirmation, isTrue);
      },
    );

    test('translates gateway errors into readable auth failures', () async {
      final cases = <SupabaseAuthGatewayException, String>{
        const SupabaseAuthGatewayException(
          message: 'Invalid login credentials',
          statusCode: '400',
        ): 'Incorrect email or password.',
        const SupabaseAuthGatewayException(
          message: 'User already registered',
          statusCode: '422',
        ): 'An account already exists for this email.',
        const SupabaseAuthGatewayException(
          message: 'Email rate limit exceeded',
          statusCode: '429',
        ): 'Too many attempts. Please wait and try again.',
        const SupabaseAuthGatewayException(
          message: 'SocketException',
          isNetworkFailure: true,
        ): 'Check your internet connection and try again.',
      };

      for (final entry in cases.entries) {
        gateway.nextError = entry.key;

        await expectLater(
          repository.signIn(email: 'student@gmail.com', password: 'Password1'),
          throwsA(
            isA<AuthFailure>().having(
              (error) => error.message,
              'message',
              entry.value,
            ),
          ),
        );
      }
    });

    test('signs out through the gateway', () async {
      await repository.signOut();

      expect(gateway.signOutCalls, 1);
    });
  });

  group('GoTrueSupabaseAuthGateway', () {
    late _FakeGoTrueClient client;
    late GoTrueSupabaseAuthGateway gateway;

    setUp(() {
      client = _FakeGoTrueClient();
      gateway = GoTrueSupabaseAuthGateway(client);
    });

    tearDown(() => client.dispose());

    test('maps GoTrue users and auth state changes', () async {
      client.user = _supabaseUser;
      expect(gateway.currentUser?.metadata['display_name'], 'Jay Student');

      final states = <String?>[];
      final subscription = gateway.authStateChanges.listen(
        (identity) => states.add(identity?.id),
      );
      client.emit(AuthState(AuthChangeEvent.signedIn, _session));
      client.emit(const AuthState(AuthChangeEvent.signedOut, null));
      await Future<void>.delayed(Duration.zero);

      expect(states, ['supabase-user', null]);
      await subscription.cancel();
    });

    test('forwards sign in, sign up metadata, and sign out', () async {
      client.response = AuthResponse(session: _session);

      final signIn = await gateway.signInWithPassword(
        email: 'student@example.com',
        password: 'Password1',
      );
      final signUp = await gateway.signUp(
        email: 'student@example.com',
        password: 'Password1',
        displayName: 'Jay Student',
      );
      await gateway.signOut();

      expect(signIn.identity.id, 'supabase-user');
      expect(signIn.hasSession, isTrue);
      expect(signUp.identity.id, 'supabase-user');
      expect(client.lastMetadata, {'display_name': 'Jay Student'});
      expect(client.signOutCalls, 1);
    });

    test('converts retryable fetch errors into network failures', () async {
      client.error = AuthRetryableFetchException();

      await expectLater(
        gateway.signInWithPassword(
          email: 'student@example.com',
          password: 'Password1',
        ),
        throwsA(
          isA<SupabaseAuthGatewayException>().having(
            (error) => error.isNetworkFailure,
            'isNetworkFailure',
            isTrue,
          ),
        ),
      );
    });
  });
}

const _supabaseUser = User(
  id: 'supabase-user',
  appMetadata: {},
  userMetadata: {'display_name': 'Jay Student'},
  aud: 'authenticated',
  email: 'student@example.com',
  createdAt: '2026-07-12T00:00:00Z',
);

final _session = Session(
  accessToken: 'token',
  tokenType: 'bearer',
  user: _supabaseUser,
);

class _FakeSupabaseAuthGateway implements SupabaseAuthGateway {
  final _controller = StreamController<SupabaseAuthIdentity?>.broadcast(
    sync: true,
  );

  SupabaseAuthIdentity? user;
  SupabaseAuthGatewayResponse? nextResponse;
  SupabaseAuthGatewayException? nextError;
  String? lastEmail;
  String? lastPassword;
  String? lastDisplayName;
  int signOutCalls = 0;

  @override
  SupabaseAuthIdentity? get currentUser => user;

  @override
  Stream<SupabaseAuthIdentity?> get authStateChanges => _controller.stream;

  void emit(SupabaseAuthIdentity? identity) => _controller.add(identity);

  @override
  Future<SupabaseAuthGatewayResponse> signInWithPassword({
    required String email,
    required String password,
  }) async {
    lastEmail = email;
    lastPassword = password;
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
    return nextResponse!;
  }

  @override
  Future<SupabaseAuthGatewayResponse> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    lastEmail = email;
    lastPassword = password;
    lastDisplayName = displayName;
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
    return nextResponse!;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
  }

  void dispose() => _controller.close();
}

class _FakeGoTrueClient extends GoTrueClient {
  _FakeGoTrueClient() : super(autoRefreshToken: false);

  final _controller = StreamController<AuthState>.broadcast(sync: true);
  User? user;
  AuthResponse response = AuthResponse();
  AuthException? error;
  Map<String, dynamic>? lastMetadata;
  int signOutCalls = 0;

  @override
  User? get currentUser => user;

  @override
  Stream<AuthState> get onAuthStateChange => _controller.stream;

  void emit(AuthState state) => _controller.add(state);

  @override
  Future<AuthResponse> signInWithPassword({
    String? email,
    String? phone,
    required String password,
    String? captchaToken,
  }) async {
    if (error case final error?) throw error;
    return response;
  }

  @override
  Future<AuthResponse> signUp({
    String? email,
    String? phone,
    required String password,
    String? emailRedirectTo,
    Map<String, dynamic>? data,
    String? captchaToken,
    OtpChannel channel = OtpChannel.sms,
  }) async {
    lastMetadata = data;
    if (error case final error?) throw error;
    return response;
  }

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.local}) async {
    signOutCalls++;
    if (error case final error?) throw error;
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }
}

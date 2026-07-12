import 'package:flutter/foundation.dart';

import '../../data/repositories/auth_repository.dart';

enum AuthMode { login, register }

class AuthViewModel extends ChangeNotifier {
  AuthViewModel({required AuthRepository authRepository})
    : _authRepository = authRepository;

  final AuthRepository _authRepository;

  AuthMode _mode = AuthMode.login;
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  bool _isDisposed = false;
  String? _errorMessage;
  String? _noticeMessage;

  AuthMode get mode => _mode;
  bool get isSubmitting => _isSubmitting;
  bool get obscurePassword => _obscurePassword;
  bool get obscureConfirmation => _obscureConfirmation;
  String? get errorMessage => _errorMessage;
  String? get noticeMessage => _noticeMessage;

  void setMode(AuthMode mode) {
    if (_isSubmitting || _mode == mode) return;
    _mode = mode;
    _errorMessage = null;
    _noticeMessage = null;
    notifyListeners();
  }

  void togglePasswordVisibility() {
    _obscurePassword = !_obscurePassword;
    notifyListeners();
  }

  void toggleConfirmationVisibility() {
    _obscureConfirmation = !_obscureConfirmation;
    notifyListeners();
  }

  Future<void> submit({
    required String displayName,
    required String email,
    required String password,
  }) async {
    if (_isSubmitting || _isDisposed) return;
    _isSubmitting = true;
    _errorMessage = null;
    _noticeMessage = null;
    notifyListeners();

    try {
      if (_mode == AuthMode.login) {
        await _authRepository.signIn(email: email, password: password);
      } else {
        final result = await _authRepository.register(
          displayName: displayName,
          email: email,
          password: password,
        );
        if (result.requiresEmailConfirmation && !_isDisposed) {
          _noticeMessage =
              'Check your email to confirm your account, then log in.';
        }
      }
    } on AuthFailure catch (error) {
      if (!_isDisposed) _errorMessage = error.message;
    } catch (_) {
      if (!_isDisposed) {
        _errorMessage = 'Authentication is unavailable. Please try again.';
      }
    } finally {
      if (!_isDisposed) {
        _isSubmitting = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

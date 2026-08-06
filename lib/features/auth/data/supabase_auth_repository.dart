import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/auth_failure.dart';
import '../application/auth_models.dart';
import '../application/auth_repository.dart';
import 'auth_service.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository(ref.watch(authServiceProvider));
});

final class SupabaseAuthRepository implements AuthRepository {
  const SupabaseAuthRepository(this._service);

  final AuthService _service;

  @override
  AuthSession? get currentSession => _toAuthSession(_service.currentSession);

  @override
  Stream<AuthSession?> sessionChanges() async* {
    try {
      await for (final session in _service.sessionChanges()) {
        yield _toAuthSession(session);
      }
    } on Object catch (error, stackTrace) {
      throw AuthFailure(
        'Your session could not be refreshed. Please sign in again.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> login({required String email, required String password}) {
    return _guard<void>(_AuthOperation.login, () async {
      await _service.login(email: email, password: password);
    });
  }

  @override
  Future<RegistrationResult> register({
    required String email,
    required String password,
  }) {
    return _guard(_AuthOperation.register, () async {
      final response = await _service.register(
        email: email,
        password: password,
      );
      return RegistrationResult(
        requiresEmailConfirmation: response.session == null,
      );
    });
  }

  @override
  Future<void> requestPasswordReset({required String email}) {
    return _guard(
      _AuthOperation.passwordReset,
      () => _service.requestPasswordReset(email: email),
    );
  }

  @override
  Future<void> logout() {
    return _guard(_AuthOperation.logout, _service.logout);
  }

  Future<T> _guard<T>(
    _AuthOperation operation,
    Future<T> Function() callback,
  ) async {
    try {
      return await callback();
    } on AuthException catch (error, stackTrace) {
      throw AuthFailure(
        _safeMessage(operation, error),
        cause: error,
        stackTrace: stackTrace,
      );
    } on Object catch (error, stackTrace) {
      throw AuthFailure(
        _fallbackMessage(operation),
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  static AuthSession? _toAuthSession(Session? session) {
    if (session == null) return null;
    return AuthSession(userId: session.user.id, email: session.user.email);
  }

  static String _safeMessage(_AuthOperation operation, AuthException error) {
    if (error.statusCode == '429') {
      return 'Too many attempts. Please wait a moment and try again.';
    }

    return switch (operation) {
      _AuthOperation.login when error.code == 'email_not_confirmed' =>
        'Confirm your email address before signing in.',
      _AuthOperation.login => 'Email or password is incorrect.',
      _AuthOperation.register when error.code == 'weak_password' =>
        'That password does not meet the account security requirements.',
      _AuthOperation.register =>
        'Unable to create the account. Check your details or try signing in.',
      _AuthOperation.passwordReset =>
        'Unable to send the reset request. Please try again shortly.',
      _AuthOperation.logout => 'Unable to sign out. Please try again.',
    };
  }

  static String _fallbackMessage(_AuthOperation operation) {
    return switch (operation) {
      _AuthOperation.login =>
        'Unable to sign in. Check your connection and try again.',
      _AuthOperation.register =>
        'Unable to create the account. Please try again shortly.',
      _AuthOperation.passwordReset =>
        'Unable to send the reset request. Please try again shortly.',
      _AuthOperation.logout => 'Unable to sign out. Please try again.',
    };
  }
}

enum _AuthOperation { login, register, passwordReset, logout }

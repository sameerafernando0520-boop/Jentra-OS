import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/supabase_auth_repository.dart';
import 'auth_models.dart';

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthActionResult?>(
      AuthController.new,
    );

final class AuthController extends AsyncNotifier<AuthActionResult?> {
  @override
  FutureOr<AuthActionResult?> build() => null;

  Future<AuthActionResult?> login({
    required String email,
    required String password,
  }) {
    return _run(() async {
      await ref
          .read(authRepositoryProvider)
          .login(email: email.trim(), password: password);
      return const AuthActionResult(action: AuthActionType.login);
    });
  }

  Future<AuthActionResult?> register({
    required String email,
    required String password,
  }) {
    return _run(() async {
      final registration = await ref
          .read(authRepositoryProvider)
          .register(email: email.trim(), password: password);
      return AuthActionResult(
        action: AuthActionType.register,
        requiresEmailConfirmation: registration.requiresEmailConfirmation,
      );
    });
  }

  Future<AuthActionResult?> requestPasswordReset({required String email}) {
    return _run(() async {
      await ref
          .read(authRepositoryProvider)
          .requestPasswordReset(email: email.trim());
      return const AuthActionResult(action: AuthActionType.passwordReset);
    });
  }

  Future<AuthActionResult?> signInWithGoogle() {
    return _run(() async {
      await ref.read(authRepositoryProvider).signInWithGoogle();
      return const AuthActionResult(action: AuthActionType.login);
    });
  }

  Future<AuthActionResult?> logout() {
    return _run(() async {
      await ref.read(authRepositoryProvider).logout();
      return const AuthActionResult(action: AuthActionType.logout);
    });
  }

  Future<AuthActionResult?> _run(
    Future<AuthActionResult> Function() operation,
  ) async {
    state = const AsyncLoading();
    try {
      final result = await operation();
      state = AsyncData(result);
      return result;
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return null;
    }
  }
}

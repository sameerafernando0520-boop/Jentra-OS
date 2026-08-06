import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_providers.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(supabaseServiceProvider).client);
});

/// Low-level Supabase Auth adapter.
///
/// Repositories consume this service; widgets never access it directly.
final class AuthService {
  const AuthService(this._client);

  final SupabaseClient _client;

  Session? get currentSession => _client.auth.currentSession;

  Future<AuthResponse> login({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<AuthResponse> register({
    required String email,
    required String password,
  }) {
    return _client.auth.signUp(email: email, password: password);
  }

  Future<void> requestPasswordReset({required String email}) {
    return _client.auth.resetPasswordForEmail(email);
  }

  Future<void> logout() => _client.auth.signOut();

  Stream<Session?> sessionChanges() {
    late StreamController<Session?> controller;
    StreamSubscription<AuthState>? subscription;

    controller = StreamController<Session?>(
      onListen: () {
        controller.add(currentSession);
        subscription = _client.auth.onAuthStateChange.listen(
          (authState) => controller.add(authState.session),
          onError: (Object error, StackTrace stackTrace) {
            controller.addError(error, stackTrace);
          },
          onDone: controller.close,
        );
      },
      onCancel: () => subscription?.cancel(),
    );

    return controller.stream;
  }
}

import 'auth_models.dart';

abstract interface class AuthRepository {
  AuthSession? get currentSession;

  Stream<AuthSession?> sessionChanges();

  Future<void> login({required String email, required String password});

  Future<RegistrationResult> register({
    required String email,
    required String password,
  });

  Future<void> requestPasswordReset({required String email});

  Future<void> logout();
}

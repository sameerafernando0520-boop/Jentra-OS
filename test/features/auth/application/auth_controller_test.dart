import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_os/features/auth/application/auth_controller.dart';
import 'package:jentra_os/features/auth/application/auth_models.dart';
import 'package:jentra_os/features/auth/application/auth_repository.dart';
import 'package:jentra_os/features/auth/data/supabase_auth_repository.dart';

void main() {
  test('login delegates to the repository and reports success', () async {
    final repository = _FakeAuthRepository();
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final result = await container
        .read(authControllerProvider.notifier)
        .login(email: ' owner@example.com ', password: 'Secure123');

    expect(result?.action, AuthActionType.login);
    expect(repository.lastEmail, 'owner@example.com');
    expect(repository.lastPassword, 'Secure123');
    expect(container.read(authControllerProvider).hasError, isFalse);
  });

  test('register reports when confirmation is required', () async {
    final repository = _FakeAuthRepository(requiresConfirmation: true);
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final result = await container
        .read(authControllerProvider.notifier)
        .register(email: 'owner@example.com', password: 'Secure123');

    expect(result?.action, AuthActionType.register);
    expect(result?.requiresEmailConfirmation, isTrue);
  });
}

final class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.requiresConfirmation = false});

  final bool requiresConfirmation;
  String? lastEmail;
  String? lastPassword;

  @override
  AuthSession? get currentSession => null;

  @override
  Future<void> login({required String email, required String password}) async {
    lastEmail = email;
    lastPassword = password;
  }

  @override
  Future<void> logout() async {}

  @override
  Future<RegistrationResult> register({
    required String email,
    required String password,
  }) async {
    lastEmail = email;
    lastPassword = password;
    return RegistrationResult(requiresEmailConfirmation: requiresConfirmation);
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    lastEmail = email;
  }

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Stream<AuthSession?> sessionChanges() => const Stream.empty();
}

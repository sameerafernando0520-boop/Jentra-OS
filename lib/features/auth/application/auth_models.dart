final class AuthSession {
  const AuthSession({required this.userId, this.email});

  final String userId;
  final String? email;
}

final class RegistrationResult {
  const RegistrationResult({required this.requiresEmailConfirmation});

  final bool requiresEmailConfirmation;
}

enum AuthActionType { login, register, passwordReset, logout }

final class AuthActionResult {
  const AuthActionResult({
    required this.action,
    this.requiresEmailConfirmation = false,
  });

  final AuthActionType action;
  final bool requiresEmailConfirmation;
}

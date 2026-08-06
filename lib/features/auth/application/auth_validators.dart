abstract final class AuthValidators {
  static final _emailPattern = RegExp(
    r'^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$',
    caseSensitive: false,
  );

  static String? email(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) {
      return 'Enter your email address.';
    }
    if (!_emailPattern.hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static String? loginPassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) {
      return 'Enter your password.';
    }
    if (password.length < 6) {
      return 'Password must contain at least 6 characters.';
    }
    return null;
  }

  static String? registrationPassword(String? value) {
    final password = value ?? '';
    if (password.length < 8) {
      return 'Use at least 8 characters.';
    }
    if (!RegExp('[a-z]').hasMatch(password) ||
        !RegExp('[A-Z]').hasMatch(password) ||
        !RegExp('[0-9]').hasMatch(password)) {
      return 'Include uppercase, lowercase, and a number.';
    }
    return null;
  }

  static String? passwordConfirmation(String? value, String password) {
    if ((value ?? '').isEmpty) {
      return 'Confirm your password.';
    }
    if (value != password) {
      return 'Passwords do not match.';
    }
    return null;
  }
}

import 'package:flutter/material.dart';

import '../../application/auth_failure.dart';

abstract final class AuthFeedback {
  static void showError(BuildContext context, Object? error) {
    final message = error is AuthFailure
        ? error.userMessage
        : 'Authentication could not be completed. Please try again.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

import 'package:flutter/material.dart';

import '../../application/customer_failure.dart';

abstract final class CustomerFeedback {
  static String userMessage(Object error) {
    if (error case CustomerFailure(:final userMessage)) return userMessage;
    return 'We could not complete the customer action. Please try again.';
  }

  static void showError(BuildContext context, Object error) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(userMessage(error))));
  }

  static void showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

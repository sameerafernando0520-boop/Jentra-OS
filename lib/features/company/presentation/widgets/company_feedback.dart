import 'package:flutter/material.dart';

import '../../application/company_failure.dart';

/// Keeps implementation details from database and network failures out of the
/// presentation layer while still giving the user an actionable message.
abstract final class CompanyFeedback {
  static String userMessage(Object error) {
    if (error case CompanyFailure(:final userMessage)) {
      return userMessage;
    }

    return 'We could not complete that company action. Please try again.';
  }

  static void showError(BuildContext context, Object error) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(userMessage(error))));
  }
}

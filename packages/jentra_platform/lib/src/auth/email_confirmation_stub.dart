import 'package:supabase_flutter/supabase_flutter.dart';

import 'email_confirmation.dart';

/// Other platforms use their existing Supabase deep-link integration.
Future<AuthResponse> createAccountAndConfirm(
  SupabaseClient client, {
  required String email,
  required String password,
  EmailConfirmationCancellation? cancellation,
  void Function()? onEmailSent,
  void Function()? onExchangeStarted,
}) => sendEmailConfirmation(
  client,
  cancellation: cancellation,
  onEmailSent: onEmailSent,
  send: () => client.auth.signUp(email: email, password: password),
);

Future<AuthResponse> resendAndConfirmEmail(
  SupabaseClient client, {
  required String email,
  EmailConfirmationCancellation? cancellation,
  void Function()? onEmailSent,
  void Function()? onExchangeStarted,
}) => sendEmailConfirmation(
  client,
  cancellation: cancellation,
  onEmailSent: onEmailSent,
  send: () async {
    await client.auth.resend(type: OtpType.signup, email: email);
    return AuthResponse();
  },
);

Future<AuthResponse> sendEmailConfirmation(
  SupabaseClient client, {
  required Future<AuthResponse> Function() send,
  EmailConfirmationCancellation? cancellation,
  void Function()? onEmailSent,
}) async {
  requireEmailConfirmationSignedOut(client);
  if (cancellation?.isCancelled ?? false) {
    throw const EmailConfirmationException(EmailConfirmationFailure.cancelled);
  }
  try {
    final response = await send();
    if (response.session == null) {
      if (cancellation?.isCancelled ?? false) {
        throw const EmailConfirmationException(
          EmailConfirmationFailure.cancelled,
        );
      }
      onEmailSent?.call();
    }
    return response;
  } on Object catch (error) {
    throw EmailConfirmationException(emailConfirmationFailure(error));
  }
}

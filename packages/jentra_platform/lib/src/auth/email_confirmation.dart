import 'package:supabase_flutter/supabase_flutter.dart';

import 'google_sign_in.dart';

typedef EmailConfirmationCancellation = GoogleSignInCancellation;

enum EmailConfirmationFailure {
  emailNotConfirmed,
  expired,
  invalidLink,
  rateLimited,
  signupUnavailable,
  weakPassword,
  callbackUnavailable,
  cancelled,
  exchangeFailed,
  alreadySignedIn,
  failed,
}

/// A fixed category that never contains an email, token, or provider message.
final class EmailConfirmationException implements Exception {
  const EmailConfirmationException(this.failure);

  final EmailConfirmationFailure failure;

  @override
  String toString() => 'EmailConfirmationException(${failure.name})';
}

EmailConfirmationFailure emailConfirmationFailure(Object error) {
  if (error is EmailConfirmationException) return error.failure;
  if (error is! AuthException) return EmailConfirmationFailure.failed;
  return switch (error.code) {
    'email_not_confirmed' => EmailConfirmationFailure.emailNotConfirmed,
    'otp_expired' ||
    'flow_state_expired' ||
    'flow_state_not_found' => EmailConfirmationFailure.expired,
    'over_email_send_rate_limit' ||
    'over_request_rate_limit' => EmailConfirmationFailure.rateLimited,
    'signup_disabled' ||
    'email_provider_disabled' ||
    'email_address_not_authorized' =>
      EmailConfirmationFailure.signupUnavailable,
    'weak_password' => EmailConfirmationFailure.weakPassword,
    'bad_code_verifier' => EmailConfirmationFailure.exchangeFailed,
    _ => EmailConfirmationFailure.failed,
  };
}

void requireEmailConfirmationSignedOut(SupabaseClient client) {
  if (client.auth.currentSession != null) {
    throw const EmailConfirmationException(
      EmailConfirmationFailure.alreadySignedIn,
    );
  }
}

/// Verifies the original email link directly, without navigating to its URL.
/// The input and its bearer token stay transient and are never logged here.
Future<AuthResponse> confirmSignupEmailFromLink(
  SupabaseClient client, {
  required String link,
}) async {
  requireEmailConfirmationSignedOut(client);
  String token;
  try {
    final rest = Uri.parse(client.rest.url);
    final text = link.trim();
    final uri = text.length <= 8192 ? Uri.tryParse(text) : null;
    if (rest.scheme != 'https' ||
        rest.userInfo.isNotEmpty ||
        rest.path != '/rest/v1' ||
        rest.hasQuery ||
        rest.hasFragment ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host != rest.host ||
        uri.port != rest.port ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.path != '/auth/v1/verify') {
      throw const FormatException();
    }
    final params = uri.queryParametersAll;
    final tokens = params['token'];
    final types = params['type'];
    if (tokens == null ||
        tokens.length != 1 ||
        tokens.single.isEmpty ||
        tokens.single.length > 2048 ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(tokens.single) ||
        types == null ||
        types.length != 1 ||
        types.single != 'signup' ||
        params.values.any((values) => values.length != 1) ||
        params.keys.any(
          (key) => !const {'token', 'type', 'redirect_to'}.contains(key),
        )) {
      throw const FormatException();
    }
    token = tokens.single;
  } on Object {
    throw const EmailConfirmationException(
      EmailConfirmationFailure.invalidLink,
    );
  }
  try {
    // A token hash must not be combined with email or redirectTo. Supabase
    // consumes the confirmation token and returns the authenticated session.
    final response = await client.auth.verifyOTP(
      type: OtpType.signup,
      tokenHash: token,
    );
    if (response.session == null) {
      throw const EmailConfirmationException(
        EmailConfirmationFailure.exchangeFailed,
      );
    }
    return response;
  } on Object catch (error) {
    throw EmailConfirmationException(emailConfirmationFailure(error));
  }
}

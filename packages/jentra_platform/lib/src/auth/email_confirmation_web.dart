import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;
import 'browser_auth_return.dart';
import 'email_confirmation.dart';
import 'email_confirmation_stub.dart' as fallback;

Future<AuthResponse> createAccountAndConfirm(
  SupabaseClient client, {
  required String email,
  required String password,
  EmailConfirmationCancellation? cancellation,
  void Function()? onEmailSent,
  void Function()? onExchangeStarted,
}) => fallback.createAccountAndConfirm(
  client,
  email: email,
  password: password,
  cancellation: cancellation,
  onEmailSent: onEmailSent,
  onExchangeStarted: onExchangeStarted,
  emailRedirectTo: browserVerificationRedirect(
    Uri.parse(web.window.location.href),
  ),
);

Future<AuthResponse> resendAndConfirmEmail(
  SupabaseClient client, {
  required String email,
  EmailConfirmationCancellation? cancellation,
  void Function()? onEmailSent,
  void Function()? onExchangeStarted,
}) => fallback.resendAndConfirmEmail(
  client,
  email: email,
  cancellation: cancellation,
  onEmailSent: onEmailSent,
  onExchangeStarted: onExchangeStarted,
  emailRedirectTo: browserVerificationRedirect(
    Uri.parse(web.window.location.href),
  ),
);

import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'email_confirmation.dart';
import 'email_confirmation_stub.dart' as fallback;
import 'google_loopback.dart';
import 'google_sign_in.dart';

Future<AuthResponse> createAccountAndConfirm(
  SupabaseClient client, {
  required String email,
  required String password,
  EmailConfirmationCancellation? cancellation,
  void Function()? onEmailSent,
  void Function()? onExchangeStarted,
  bool? useLoopback,
  int port = 56327,
  Duration timeout = const Duration(minutes: 15),
}) {
  if (!(useLoopback ?? Platform.isWindows)) {
    return fallback.createAccountAndConfirm(
      client,
      email: email,
      password: password,
      cancellation: cancellation,
      onEmailSent: onEmailSent,
      onExchangeStarted: onExchangeStarted,
    );
  }
  return _confirmViaLoopback(
    client,
    cancellation: cancellation,
    onEmailSent: onEmailSent,
    onExchangeStarted: onExchangeStarted,
    port: port,
    timeout: timeout,
    send: (callback) => client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: callback.toString(),
    ),
  );
}

Future<AuthResponse> resendAndConfirmEmail(
  SupabaseClient client, {
  required String email,
  EmailConfirmationCancellation? cancellation,
  void Function()? onEmailSent,
  void Function()? onExchangeStarted,
  bool? useLoopback,
  int port = 56327,
  Duration timeout = const Duration(minutes: 15),
}) {
  if (!(useLoopback ?? Platform.isWindows)) {
    return fallback.resendAndConfirmEmail(
      client,
      email: email,
      cancellation: cancellation,
      onEmailSent: onEmailSent,
      onExchangeStarted: onExchangeStarted,
    );
  }
  return _confirmViaLoopback(
    client,
    cancellation: cancellation,
    onEmailSent: onEmailSent,
    onExchangeStarted: onExchangeStarted,
    port: port,
    timeout: timeout,
    send: (callback) async {
      await client.auth.resend(
        email: email,
        type: OtpType.signup,
        emailRedirectTo: callback.toString(),
      );
      return AuthResponse();
    },
  );
}

Future<AuthResponse> _confirmViaLoopback(
  SupabaseClient client, {
  required Future<AuthResponse> Function(Uri callback) send,
  required int port,
  required Duration timeout,
  EmailConfirmationCancellation? cancellation,
  void Function()? onEmailSent,
  void Function()? onExchangeStarted,
}) async {
  requireEmailConfirmationSignedOut(client);
  AuthResponse? sentResponse;
  AuthResponse? confirmedResponse;
  var exchangeStarted = false;
  EmailConfirmationException? sendFailure;
  EmailConfirmationException? exchangeFailure;
  try {
    await GoogleLoopbackSignIn(
      port: port,
      timeout: timeout,
      cancellation: cancellation,
      onExchangeStarted: () {
        exchangeStarted = true;
        onExchangeStarted?.call();
      },
      isCompleteAfterLaunch: () => sentResponse?.session != null,
      launch: (callback) async {
        try {
          sentResponse = await send(callback);
          if (sentResponse?.session == null &&
              !exchangeStarted &&
              !(cancellation?.isCancelled ?? false)) {
            onEmailSent?.call();
          }
          return true;
        } on Object catch (error) {
          sendFailure = EmailConfirmationException(
            emailConfirmationFailure(error),
          );
          throw sendFailure!;
        }
      },
      exchange: (code) async {
        try {
          requireEmailConfirmationSignedOut(client);
          final result = await client.auth.exchangeCodeForSession(code);
          if (result.session.user.id.isEmpty) {
            throw const EmailConfirmationException(
              EmailConfirmationFailure.exchangeFailed,
            );
          }
          confirmedResponse = AuthResponse(session: result.session);
        } on Object catch (error) {
          exchangeFailure = EmailConfirmationException(
            error is AuthException || error is EmailConfirmationException
                ? emailConfirmationFailure(error)
                : EmailConfirmationFailure.exchangeFailed,
          );
          throw exchangeFailure!;
        }
      },
    ).run();
    final response = confirmedResponse ?? sentResponse;
    if (response?.session == null) {
      throw const EmailConfirmationException(
        EmailConfirmationFailure.exchangeFailed,
      );
    }
    return response!;
  } on GoogleSignInException catch (error) {
    throw switch (error.failure) {
      GoogleSignInFailure.cancelled => const EmailConfirmationException(
        EmailConfirmationFailure.cancelled,
      ),
      GoogleSignInFailure.callbackUnavailable ||
      GoogleSignInFailure.alreadyPending => const EmailConfirmationException(
        EmailConfirmationFailure.callbackUnavailable,
      ),
      GoogleSignInFailure.exchangeFailed =>
        exchangeFailure ??
            const EmailConfirmationException(
              EmailConfirmationFailure.exchangeFailed,
            ),
      _ =>
        sendFailure ??
            const EmailConfirmationException(EmailConfirmationFailure.failed),
    };
  } on TimeoutException {
    rethrow;
  } on Object catch (error) {
    throw EmailConfirmationException(emailConfirmationFailure(error));
  }
}

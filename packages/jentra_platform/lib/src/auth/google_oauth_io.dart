import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'google_loopback.dart';
import 'google_provider_settings.dart';
import 'google_sign_in.dart';

Future<bool> signInWithGoogle(
  SupabaseClient client, {
  String? redirectTo,
  GoogleSignInCancellation? cancellation,
  void Function()? onExchangeStarted,
  http.Client? settingsHttpClient,
}) async {
  await requireGoogleProvider(
    client,
    cancellation: cancellation,
    httpClient: settingsHttpClient,
  );
  if (!Platform.isWindows || redirectTo != null) {
    try {
      final launched = await client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectTo,
        authScreenLaunchMode: LaunchMode.externalApplication,
        queryParams: const {'prompt': 'select_account'},
      );
      if (!launched) {
        throw const GoogleSignInException(
          GoogleSignInFailure.browserUnavailable,
        );
      }
      return launched;
    } on GoogleSignInException {
      rethrow;
    } on Object {
      throw const GoogleSignInException(GoogleSignInFailure.browserUnavailable);
    }
  }
  return GoogleLoopbackSignIn(
    cancellation: cancellation,
    onExchangeStarted: onExchangeStarted,
    launch: (callback) => client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: callback.toString(),
      authScreenLaunchMode: LaunchMode.externalApplication,
      queryParams: const {'prompt': 'select_account'},
    ),
    exchange: (code) async {
      final response = await client.auth.exchangeCodeForSession(code);
      if (response.session.user.id.isEmpty) {
        throw StateError('GOOGLE_SESSION_REQUIRED');
      }
    },
  ).run();
}

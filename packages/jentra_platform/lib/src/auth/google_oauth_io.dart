import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'google_loopback.dart';
import 'google_provider_settings.dart';

Future<bool> signInWithGoogle(
  SupabaseClient client, {
  String? redirectTo,
}) async {
  if (!Platform.isWindows || redirectTo != null) {
    return client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: redirectTo,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }
  return GoogleLoopbackSignIn(
    launch: (callback) async {
      final url = await client.auth.getOAuthSignInUrl(
        provider: OAuthProvider.google,
        redirectTo: callback.toString(),
      );
      if (!await googleProviderEnabled(
        Uri.parse(url.url),
        client.auth.headers['apikey'] ?? '',
      )) {
        throw const AuthException(
          'Google sign-in is not enabled for this project.',
        );
      }
      return client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: callback.toString(),
        authScreenLaunchMode: LaunchMode.externalApplication,
        queryParams: const {'prompt': 'select_account'},
      );
    },
    exchange: (code) async {
      final response = await client.auth.exchangeCodeForSession(code);
      if (response.session.user.id.isEmpty) {
        throw StateError('GOOGLE_SESSION_REQUIRED');
      }
    },
  ).run();
}

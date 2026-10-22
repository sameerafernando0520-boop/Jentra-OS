import 'package:supabase_flutter/supabase_flutter.dart';

import 'google_provider_settings.dart';
import 'google_sign_in.dart';

Future<bool> signInWithGoogle(
  SupabaseClient client, {
  String? redirectTo,
  GoogleSignInCancellation? cancellation,
  void Function()? onExchangeStarted,
}) async {
  await requireGoogleProvider(client, cancellation: cancellation);
  try {
    final launched = await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: redirectTo,
      authScreenLaunchMode: LaunchMode.externalApplication,
      queryParams: const {'prompt': 'select_account'},
    );
    if (!launched) {
      throw const GoogleSignInException(GoogleSignInFailure.browserUnavailable);
    }
    return launched;
  } on GoogleSignInException {
    rethrow;
  } on Object {
    throw const GoogleSignInException(GoogleSignInFailure.browserUnavailable);
  }
}

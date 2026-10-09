import 'package:supabase_flutter/supabase_flutter.dart';

Future<bool> signInWithGoogle(SupabaseClient client, {String? redirectTo}) =>
    client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: redirectTo,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );

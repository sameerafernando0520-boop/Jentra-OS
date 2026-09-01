import 'package:supabase_flutter/supabase_flutter.dart';

import 'runtime_config.dart';

final class SupabasePlatform {
  const SupabasePlatform._();

  static Future<SupabaseClient?> initialize(RuntimeConfig config) async {
    if (!config.isSupabaseConfigured) return null;
    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabasePublishableKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    return Supabase.instance.client;
  }
}

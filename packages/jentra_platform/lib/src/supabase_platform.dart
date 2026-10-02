import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

import 'runtime_config.dart';
import 'wave3_observability.dart';

final class SupabasePlatform {
  const SupabasePlatform._();

  static Future<SupabaseClient?> initialize(RuntimeConfig config) async {
    if (!config.isSupabaseConfigured) return null;
    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabasePublishableKey,
      httpClient: Wave3ObservedHttpClient(http.Client()),
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    return Supabase.instance.client;
  }
}

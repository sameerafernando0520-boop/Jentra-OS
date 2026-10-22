import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import 'runtime_config.dart';
import 'wave3_observability.dart';
import 'auth/pkce_exchange_http_client.dart';

final class SupabasePlatform {
  const SupabasePlatform._();

  static Future<SupabaseClient?> initialize(
    RuntimeConfig config, {
    bool isRelease = kReleaseMode,
  }) async {
    if (config.startupMode(isRelease: isRelease) ==
        RuntimeStartupMode.preview) {
      return null;
    }
    try {
      await Supabase.initialize(
        url: config.supabaseOrigin,
        publishableKey: config.supabasePublishableKey,
        httpClient: Wave3ObservedHttpClient(
          PkceExchangeHttpClient(
            http.Client(),
            tokenUri: Uri.parse('${config.supabaseOrigin}/auth/v1/token'),
          ),
        ),
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
      );
      return Supabase.instance.client;
    } on Object {
      throw const RuntimeStartupException(
        RuntimeStartupFailure.initializationFailed,
      );
    }
  }
}

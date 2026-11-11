import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import 'runtime_config.dart';
import 'wave3_observability.dart';
import 'auth/pkce_exchange_http_client.dart';
import 'auth/browser_auth_return.dart';
import 'auth/browser_auth_return_native.dart'
    if (dart.library.js_interop) 'auth/browser_auth_return_web.dart';

final class SupabasePlatform {
  const SupabasePlatform._();

  static Future<SupabaseClient?> initialize(
    RuntimeConfig config, {
    bool isRelease = kReleaseMode,
    bool operatorSession = false,
  }) async {
    if (config.startupMode(isRelease: isRelease) ==
        RuntimeStartupMode.preview) {
      return null;
    }
    try {
      final pending = operatorSession ? null : captureBrowserAuthReturn();
      await Supabase.initialize(
        url: config.supabaseOrigin,
        publishableKey: config.supabasePublishableKey,
        httpClient: Wave3ObservedHttpClient(
          PkceExchangeHttpClient(
            http.Client(),
            tokenUri: Uri.parse('${config.supabaseOrigin}/auth/v1/token'),
          ),
        ),
        authOptions: FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          persistSession: !operatorSession,
          detectSessionInUri: !operatorSession && !kIsWeb,
        ),
      );
      if (kIsWeb && pending != null) {
        await completeBrowserAuthReturn(Supabase.instance.client, pending);
      }
      return Supabase.instance.client;
    } on Object {
      throw const RuntimeStartupException(
        RuntimeStartupFailure.initializationFailed,
      );
    }
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env_config.dart';

/// Shared gateway to Supabase clients.
///
/// Feature repositories depend on this service; presentation widgets do not.
final class SupabaseService {
  const SupabaseService(this.client);

  /// Initializes Supabase once, before the root Flutter widget is mounted.
  static Future<SupabaseService> initialize(EnvConfig config) async {
    final supabase = await Supabase.initialize(
      url: config.supabaseUrl,
      // `publishableKey` is the current API parameter and also accepts a
      // client-safe legacy anonymous key.
      publishableKey: config.supabaseAnonKey,
    );
    return SupabaseService(supabase.client);
  }

  final SupabaseClient client;
}

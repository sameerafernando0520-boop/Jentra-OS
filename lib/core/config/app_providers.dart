import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/services/supabase_service.dart';
import '../errors/app_exception.dart';
import 'env_config.dart';

final envConfigProvider = Provider<EnvConfig>(
  (ref) => throw const AppConfigurationException(
    'EnvConfig must be provided during bootstrap.',
  ),
);

final supabaseClientProvider = Provider<SupabaseClient?>((ref) => null);

final startupFailureProvider = Provider<AppException?>((ref) => null);

final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) {
    throw const AppConfigurationException(
      'Supabase is unavailable. Check the public environment configuration.',
    );
  }
  return SupabaseService(client);
});

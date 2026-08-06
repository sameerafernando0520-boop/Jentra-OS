import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/services/supabase_service.dart';
import '../errors/app_exception.dart';
import 'env_config.dart';

final class AppBootstrapResult {
  const AppBootstrapResult({this.supabaseClient, this.failure});

  final SupabaseClient? supabaseClient;
  final AppException? failure;
}

abstract final class AppBootstrap {
  static Future<AppBootstrapResult> initialize(EnvConfig config) async {
    if (!config.isSupabaseConfigured) {
      return const AppBootstrapResult();
    }

    try {
      final supabase = await SupabaseService.initialize(config);
      return AppBootstrapResult(supabaseClient: supabase.client);
    } on Object catch (error, stackTrace) {
      return AppBootstrapResult(
        failure: AppConfigurationException(
          'Supabase could not be initialized.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}

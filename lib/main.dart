import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/app_bootstrap.dart';
import 'core/config/app_providers.dart';
import 'core/config/env_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = EnvConfig.fromEnvironment();
  final bootstrap = await AppBootstrap.initialize(config);

  runApp(
    ProviderScope(
      overrides: [
        envConfigProvider.overrideWithValue(config),
        supabaseClientProvider.overrideWithValue(bootstrap.supabaseClient),
        startupFailureProvider.overrideWithValue(bootstrap.failure),
      ],
      child: const JentraOSApp(),
    ),
  );
}

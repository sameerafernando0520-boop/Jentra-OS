import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_platform/jentra_platform.dart';

import 'src/app.dart';
import 'src/app_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = RuntimeConfig.fromEnvironment();
  final client = await SupabasePlatform.initialize(config);
  final gateway = client == null ? null : SupabaseFoundationGateway(client);

  runApp(
    ProviderScope(
      overrides: [
        runtimeConfigProvider.overrideWithValue(config),
        foundationGatewayProvider.overrideWithValue(gateway),
      ],
      child: const JentraApp(),
    ),
  );
}

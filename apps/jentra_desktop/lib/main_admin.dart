import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_platform/jentra_platform.dart';

import 'src/app_providers.dart';
import 'src/features/platform_control/admin_app.dart';
import 'src/features/platform_control/platform_organization_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = RuntimeConfig.fromEnvironment();
  final client =
      config.supabaseUrl.isEmpty && config.supabasePublishableKey.isEmpty
      ? null
      : await SupabasePlatform.initialize(config, operatorSession: true);
  runApp(
    ProviderScope(
      overrides: [
        runtimeConfigProvider.overrideWithValue(config),
        foundationGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseFoundationGateway(client),
        ),
        platformOrganizationGatewayProvider.overrideWithValue(
          client == null ? null : PlatformOrganizationGateway(client),
        ),
      ],
      child: const JentraAdministratorApp(),
    ),
  );
}

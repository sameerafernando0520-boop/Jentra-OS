import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_platform/jentra_platform.dart';

import 'src/app_providers.dart';
import 'src/features/platform_control/admin_app.dart';
import 'src/features/platform_control/platform_organization_screen.dart';
import 'src/startup_error_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await launchAdministrator();
}

/// Starts the J panel. A configuration or connection failure shows the
/// startup error screen; it must never leave a blank window without sign-in.
Future<void> launchAdministrator({
  RuntimeConfig? configuration,
  bool isRelease = kReleaseMode,
}) async {
  final config = configuration ?? RuntimeConfig.fromEnvironment();
  try {
    // Returns null only for a debug preview; a release without its
    // connection throws missingConnection instead of hiding the sign-in.
    final client = await SupabasePlatform.initialize(
      config,
      isRelease: isRelease,
      operatorSession: true,
    );
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
  } on Object catch (error) {
    runApp(
      JentraStartupErrorApp(
        failure: error is RuntimeStartupException
            ? error.failure
            : RuntimeStartupFailure.initializationFailed,
        onRetry: () =>
            launchAdministrator(configuration: config, isRelease: isRelease),
      ),
    );
  }
}

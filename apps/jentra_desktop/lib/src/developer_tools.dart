import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_providers.dart';

/// Component references belong only to an offline developer debug session.
/// Every installed release, including a preview release, excludes these tools.
bool developerToolsAvailable({
  required bool isDebugBuild,
  required bool connected,
  required bool production,
}) => isDebugBuild && !connected && !production;

final developerToolsEnabledProvider = Provider<bool>(
  (ref) => developerToolsAvailable(
    isDebugBuild: kDebugMode,
    connected: ref.watch(foundationGatewayProvider) != null,
    production: ref.watch(runtimeConfigProvider).isProduction,
  ),
);

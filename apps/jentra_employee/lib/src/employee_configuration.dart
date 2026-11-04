import 'package:jentra_platform/runtime_configuration.dart';

class EmployeeConfiguration {
  const EmployeeConfiguration({
    required this.url,
    required this.publishableKey,
  });
  const EmployeeConfiguration.fromEnvironment()
    : url = const String.fromEnvironment('SUPABASE_URL'),
      publishableKey = const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  final String url, publishableKey;
  bool get isValid {
    if (publishableKey.startsWith('sb_publishable_') &&
        !RegExp(r'^sb_publishable_[A-Za-z0-9_-]{8,}$')
            .hasMatch(publishableKey)) {
      return false;
    }
    try {
      return RuntimeConfig(
            environment: 'development',
            supabaseUrl: url,
            supabasePublishableKey: publishableKey,
          ).startupMode(isRelease: true) ==
          RuntimeStartupMode.connected;
    } on RuntimeStartupException {
      return false;
    }
  }
}

import 'package:jentra_platform/runtime_configuration.dart';

/// Uses the same public-key, secure-origin and project binding as Jentra OS.
final class SalesConfiguration {
  const SalesConfiguration({required this.url, required this.publishableKey});
  const SalesConfiguration.fromEnvironment()
    : url = const String.fromEnvironment(
        'SUPABASE_URL',
        defaultValue: defaultUrl,
      ),
      publishableKey = const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const defaultUrl = 'https://xpdoufauvrbdmxgngetv.supabase.co';
  final String url, publishableKey;
  bool get isValid {
    if (publishableKey.startsWith('sb_publishable_') &&
        !RegExp(r'^sb_publishable_[A-Za-z0-9_-]{8,}$').hasMatch(publishableKey)) {
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

  // A malformed deployment cannot crash encrypted preview-storage construction.
  String get storageProjectUrl => isValid ? url : defaultUrl;
}

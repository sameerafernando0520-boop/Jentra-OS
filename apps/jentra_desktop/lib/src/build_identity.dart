import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_platform/jentra_platform.dart';

/// Public release metadata. Credentials and account data never belong here.
final class DesktopBuildIdentity {
  const DesktopBuildIdentity({
    this.version = const String.fromEnvironment('JENTRA_BUILD_VERSION'),
    this.revision = const String.fromEnvironment('JENTRA_BUILD_REVISION'),
    this.builtAtUtc = const String.fromEnvironment('JENTRA_BUILD_TIME_UTC'),
    this.channel = const String.fromEnvironment('JENTRA_RELEASE_CHANNEL'),
    this.projectRef = const String.fromEnvironment('JENTRA_CONFIG_PROJECT_REF'),
    this.sourceSha256 = const String.fromEnvironment(
      'JENTRA_BUILD_SOURCE_SHA256',
    ),
  });

  final String version, revision, builtAtUtc, channel, projectRef, sourceSha256;

  String get versionLabel => version.isEmpty ? 'Local build' : version;
  String get revisionLabel => revision.isEmpty ? 'Unrecorded' : revision;
  String get channelLabel => channel.isEmpty ? 'Local' : channel;

  Map<String, String> diagnostics(RuntimeConfig config) => {
    'Application': 'Jentra OS',
    'Version': versionLabel,
    'Release channel': channelLabel,
    'Environment': config.environment,
    'Revision': revisionLabel,
    'Built at (UTC)': builtAtUtc.isEmpty ? 'Unrecorded' : builtAtUtc,
    'Source snapshot': sourceSha256.isEmpty ? 'Unrecorded' : sourceSha256,
    'Configured workspace': config.isSupabaseConfigured
        ? Uri.parse(config.supabaseUrl).host
        : 'Offline preview',
  };
}

final desktopBuildIdentityProvider = Provider<DesktopBuildIdentity>(
  (ref) => const DesktopBuildIdentity(),
);

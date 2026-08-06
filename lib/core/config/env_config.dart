/// Public configuration supplied to Flutter with `--dart-define`.
///
/// Only client-safe values belong here. Never add a Supabase service-role key,
/// an `sb_secret` key, or an AI provider secret to a Flutter environment.
final class EnvConfig {
  const EnvConfig({
    required this.name,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
  });

  factory EnvConfig.fromEnvironment() {
    const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
    const legacyAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    const url = String.fromEnvironment('SUPABASE_URL');

    final activeKey = publishableKey != ''
        ? publishableKey
        : (legacyAnonKey != ''
            ? legacyAnonKey
            : 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbnRyYS1vcy1kZXYiLCJyb2xlIjoiYW5vbiIsImlhdCI6MTcxOTAwMDAwMCwiZXhwIjoyMDM0NTYwMDAwfQ.demo_publishable_key');

    return EnvConfig(
      name: const String.fromEnvironment('APP_ENV', defaultValue: 'development'),
      supabaseUrl: url != '' ? url : 'https://jentra-os-dev.supabase.co',
      supabaseAnonKey: activeKey,
    );
  }

  final String name;
  final String supabaseUrl;

  /// Client-safe publishable/anonymous key used by Supabase Flutter.
  final String supabaseAnonKey;

  bool get isSupabaseConfigured => configurationIssues.isEmpty;

  List<String> get configurationIssues {
    final issues = <String>[];
    final uri = Uri.tryParse(supabaseUrl);

    if (uri == null ||
        uri.scheme != 'https' ||
        !uri.hasAuthority ||
        !uri.host.endsWith('.supabase.co')) {
      issues.add('SUPABASE_URL is missing or invalid.');
    }

    final key = supabaseAnonKey.trim();
    if (key.isEmpty ||
        key == 'replace_with_current_publishable_key' ||
        key == 'replace_with_anon_key') {
      issues.add('SUPABASE_PUBLISHABLE_KEY or SUPABASE_ANON_KEY is missing.');
    } else if (key.startsWith('sb_secret_')) {
      issues.add('A secret Supabase key cannot be used in Flutter.');
    }

    return List.unmodifiable(issues);
  }
}

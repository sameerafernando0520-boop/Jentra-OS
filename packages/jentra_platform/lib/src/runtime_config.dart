/// Compile-time configuration. Only the public Supabase key enters the client.
final class RuntimeConfig {
  const RuntimeConfig({
    required this.environment,
    required this.supabaseUrl,
    required this.supabasePublishableKey,
  });

  factory RuntimeConfig.fromEnvironment() => const RuntimeConfig(
    environment: String.fromEnvironment(
      'JENTRA_ENVIRONMENT',
      defaultValue: 'development',
    ),
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabasePublishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
  );

  final String environment;
  final String supabaseUrl;
  final String supabasePublishableKey;

  bool get isSupabaseConfigured =>
      Uri.tryParse(supabaseUrl)?.hasScheme == true &&
      supabasePublishableKey.trim().isNotEmpty;

  bool get isProduction => environment == 'production';
}

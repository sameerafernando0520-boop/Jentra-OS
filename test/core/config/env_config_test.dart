import 'package:flutter_test/flutter_test.dart';
import 'package:i_book/core/config/env_config.dart';

void main() {
  group('EnvConfig', () {
    test('accepts a valid client-safe Supabase configuration', () {
      const config = EnvConfig(
        name: 'test',
        supabaseUrl: 'https://example.supabase.co',
        supabaseAnonKey: 'sb_publishable_example',
      );

      expect(config.isSupabaseConfigured, isTrue);
      expect(config.configurationIssues, isEmpty);
    });

    test('rejects missing configuration', () {
      const config = EnvConfig(
        name: 'test',
        supabaseUrl: '',
        supabaseAnonKey: '',
      );

      expect(config.isSupabaseConfigured, isFalse);
      expect(config.configurationIssues, hasLength(2));
    });

    test('rejects a secret key', () {
      const config = EnvConfig(
        name: 'test',
        supabaseUrl: 'https://example.supabase.co',
        supabaseAnonKey: 'sb_secret_not_allowed',
      );

      expect(config.isSupabaseConfigured, isFalse);
      expect(
        config.configurationIssues,
        contains('A secret Supabase key cannot be used in Flutter.'),
      );
    });
  });
}

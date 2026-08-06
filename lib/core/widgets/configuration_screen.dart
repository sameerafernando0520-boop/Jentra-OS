import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/components/brand_mark.dart';
import '../config/app_providers.dart';

final class ConfigurationScreen extends ConsumerWidget {
  const ConfigurationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(envConfigProvider);
    final startupFailure = ref.watch(startupFailureProvider);
    final issues = [
      ...config.configurationIssues,
      if (startupFailure != null) startupFailure.message,
    ];

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const BrandMark(),
                      const SizedBox(height: 28),
                      Text(
                        'Environment setup required',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      for (final issue in issues)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('- $issue'),
                        ),
                      const SizedBox(height: 16),
                      const Text(
                        'Run with public configuration values:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      const SelectableText(
                        'flutter run --dart-define=SUPABASE_URL=<url> '
                        '--dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key>',
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Never pass a service-role key or an AI provider secret '
                        'to a Flutter build.',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_providers.dart';
import '../build_identity.dart';

Future<void> showDesktopBuildInformation(BuildContext context) =>
    showDialog<void>(
      context: context,
      builder: (_) => const DesktopBuildInformationDialog(),
    );

class DesktopBuildInformationDialog extends ConsumerWidget {
  const DesktopBuildInformationDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final values = ref
        .watch(desktopBuildIdentityProvider)
        .diagnostics(ref.watch(runtimeConfigProvider));
    return AlertDialog(
      title: const Text('About Jentra OS'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Use this build information to check which installed app you are running.',
              ),
              const SizedBox(height: 16),
              for (final entry in values.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.key,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      SelectableText(entry.value),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(
                text: values.entries
                    .map((entry) => '${entry.key}: ${entry.value}')
                    .join('\n'),
              ),
            );
            if (context.mounted) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(content: Text('Build information copied.')),
              );
            }
          },
          icon: const Icon(Icons.copy_outlined),
          label: const Text('Copy build information'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

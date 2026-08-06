import 'package:flutter/material.dart';

import '../constants/app_module.dart';

/// Temporary presentation boundary for modules that are scheduled but not yet
/// implemented. Feature-specific widgets will replace this without changing
/// the shell or route contract.
final class ModulePlaceholderScreen extends StatelessWidget {
  const ModulePlaceholderScreen({required this.module, super.key});

  final AppModule module;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(module.icon, size: 48),
              const SizedBox(height: 16),
              Text(
                module.label,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Architecture boundary is ready. Feature implementation will '
                'follow the development roadmap.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

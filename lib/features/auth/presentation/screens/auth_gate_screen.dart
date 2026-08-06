import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/components/brand_mark.dart';
import '../../application/auth_destination_provider.dart';

final class AuthGateScreen extends ConsumerStatefulWidget {
  const AuthGateScreen({super.key});

  @override
  ConsumerState<AuthGateScreen> createState() => _AuthGateScreenState();
}

final class _AuthGateScreenState extends ConsumerState<AuthGateScreen> {
  bool _navigationScheduled = false;

  void _scheduleNavigation(AuthDestination destination) {
    if (_navigationScheduled) return;
    _navigationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(destination.route);
    });
  }

  @override
  Widget build(BuildContext context) {
    final destination = ref.watch(authDestinationProvider);
    destination.whenData(_scheduleNavigation);

    return Scaffold(
      body: Center(
        child: destination.when(
          loading: () => const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandMark(),
              SizedBox(height: 24),
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Opening your workspace…'),
            ],
          ),
          data: (_) => const SizedBox.shrink(),
          error: (error, stackTrace) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 48),
                const SizedBox(height: 16),
                Text(
                  'We could not open your workspace.',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text('Check your connection and try again.'),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () {
                    _navigationScheduled = false;
                    ref.invalidate(authDestinationProvider);
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

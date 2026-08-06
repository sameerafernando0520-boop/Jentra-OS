import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/application/auth_controller.dart';
import '../../../auth/application/auth_models.dart';
import '../../../auth/presentation/widgets/auth_feedback.dart';

/// Keeps account switching available while onboarding screens are outside the
/// main application shell.
final class CompanySignOutButton extends ConsumerWidget {
  const CompanySignOutButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<AuthActionResult?>>(authControllerProvider, (
      previous,
      next,
    ) {
      if (next.hasError && !identical(previous?.error, next.error)) {
        AuthFeedback.showError(context, next.error);
      }
    });

    final authState = ref.watch(authControllerProvider);
    return IconButton(
      tooltip: 'Sign out',
      onPressed: authState.isLoading
          ? null
          : ref.read(authControllerProvider.notifier).logout,
      icon: authState.isLoading
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.logout),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import '../../app_providers.dart';

/// Dialog routes also invalidate sensitive content when their originating scope changes.
class QuotationScopeGuard extends ConsumerWidget {
  const QuotationScopeGuard({
    required this.scope,
    required this.capabilities,
    required this.child,
    super.key,
  });
  final TenantContext scope;
  final Set<String> capabilities;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(businessCapabilitiesProvider);
    final active =
        ref.watch(activeTenantContextProvider) == scope &&
        !current.isLoading &&
        !current.hasError &&
        current.value != null &&
        current.value!.length == capabilities.length &&
        current.value!.containsAll(capabilities);
    return active
        ? child
        : AlertDialog(
            title: const Text('Business scope or access changed'),
            content: const Text(
              'Close this dialog and reopen the quotation in your current scope.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
  }
}

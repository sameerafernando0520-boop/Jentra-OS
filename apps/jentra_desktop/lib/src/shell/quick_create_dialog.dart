import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_domain/jentra_domain.dart';

import '../app_providers.dart';

/// Opens an implemented workspace; creating a record remains an explicit action
/// there, so existing drafts and the destination's scope guards are preserved.
class QuickCreateDialog extends ConsumerWidget {
  const QuickCreateDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(businessCapabilitiesProvider);
    final scope = ref.watch(activeTenantContextProvider);
    final permissions = access.isLoading || access.hasError
        ? const <String>{}
        : access.value ?? const <String>{};
    final actions = [
      if (permissions.contains(BusinessSetupResource.parties.viewPermission) &&
          permissions.contains(BusinessSetupResource.parties.managePermission))
        (
          label: 'Customer',
          description: 'Open customer setup, then create a party.',
          icon: Icons.person_add_alt,
          route: '/setup?resource=parties',
        ),
      if (permissions.contains('sales.quotations.view') &&
          permissions.contains('sales.quotations.manage'))
        (
          label: 'Quotation',
          description: 'Open Sales, then create or recover a quotation.',
          icon: Icons.description_outlined,
          route: '/sales',
        ),
      if (permissions.contains('sales.invoices.view') &&
          permissions.contains('sales.invoices.manage'))
        (
          label: 'Invoice draft',
          description: 'Open Invoices, then create or recover a draft.',
          icon: Icons.receipt_long_outlined,
          route: '/receivables?kind=sales_invoice',
        ),
    ];
    return AlertDialog(
      title: const Text('Quick create'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (access.isLoading)
                const LinearProgressIndicator()
              else if (access.hasError)
                TextButton(
                  onPressed: () => ref.invalidate(businessCapabilitiesProvider),
                  child: const Text('Retry access check'),
                )
              else if (scope == null || !scope.hasOperationalScope)
                const Text('Choose a business, legal entity and branch first.')
              else if (actions.isEmpty)
                const Text('Your current role has no available create actions.')
              else ...[
                const Text('Choose a workspace to create a record.'),
                const SizedBox(height: 12),
                for (final action in actions)
                  ListTile(
                    leading: Icon(action.icon),
                    title: Text(action.label),
                    subtitle: Text(action.description),
                    trailing: const Icon(Icons.arrow_forward),
                    onTap: () {
                      final router = GoRouter.of(context);
                      Navigator.pop(context);
                      router.go(action.route);
                    },
                  ),
              ],
            ],
          ),
        ),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../company/application/company_state.dart';
import '../../../company/presentation/widgets/company_context_gate.dart';
import '../../application/customer_models.dart';
import '../../application/customer_state.dart';
import '../widgets/customer_feedback.dart';

final class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({required this.customerId, super.key});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(selectedCompanyProvider);
    if (company == null) {
      return const CompanyRouteRedirect(location: '/company/select');
    }

    final customer = ref.watch(customerDetailProvider(customerId));
    return customer.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _DetailError(
        message: CustomerFeedback.userMessage(error),
        onRetry: () => ref.invalidate(customerDetailProvider(customerId)),
      ),
      data: (value) => _CustomerDetailContent(
        key: ValueKey('customer-detail-${value.id}'),
        customer: value,
        currencyCode: company.currencyCode,
      ),
    );
  }
}

final class _CustomerDetailContent extends ConsumerWidget {
  const _CustomerDetailContent({
    required this.customer,
    required this.currencyCode,
    super.key,
  });

  final Customer customer;
  final String currencyCode;

  Future<void> _changeStatus(BuildContext context, WidgetRef ref) async {
    final activate = !customer.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(activate ? 'Reactivate customer?' : 'Deactivate customer?'),
        content: Text(
          activate
              ? '${customer.title} will appear in active customer lists again.'
              : '${customer.title} will be hidden from active lists. Historical records will be preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(activate ? 'Reactivate' : 'Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref
          .read(customerMutationProvider.notifier)
          .setCustomerActive(customer.id, activate);
      if (context.mounted) {
        CustomerFeedback.showSuccess(
          context,
          activate ? 'Customer reactivated.' : 'Customer deactivated.',
        );
      }
    } on Object catch (error) {
      if (context.mounted) CustomerFeedback.showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mutation = ref.watch(customerMutationProvider);
    final busy = mutation.isLoading;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back to customers',
                    onPressed: () => context.go('/crm'),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer.title,
                          style: Theme.of(context).textTheme.headlineSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          customer.isActive
                              ? 'Active customer'
                              : 'Inactive customer',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  PopupMenuButton<String>(
                    enabled: !busy,
                    tooltip: 'Customer actions',
                    onSelected: (value) {
                      if (value == 'edit') {
                        context.go('/crm/customers/${customer.id}/edit');
                      } else if (value == 'status') {
                        _changeStatus(context, ref);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Edit customer'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'status',
                        child: ListTile(
                          leading: Icon(
                            customer.isActive
                                ? Icons.archive_outlined
                                : Icons.unarchive_outlined,
                          ),
                          title: Text(
                            customer.isActive ? 'Deactivate' : 'Reactivate',
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide =
                      constraints.maxWidth >= AppConstants.desktopBreakpoint;
                  final details = Column(
                    children: [
                      _ContactCard(customer: customer),
                      const SizedBox(height: 16),
                      _CommercialCard(
                        customer: customer,
                        currencyCode: currencyCode,
                      ),
                    ],
                  );
                  final balance = _BalancePlaceholder(
                    currencyCode: currencyCode,
                  );
                  if (!wide) {
                    return Column(
                      children: [details, const SizedBox(height: 16), balance],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: details),
                      const SizedBox(width: 16),
                      Expanded(child: balance),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Contact information',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            _DetailRow(
              icon: Icons.business_outlined,
              label: 'Legal name',
              value: customer.name,
            ),
            _DetailRow(
              icon: Icons.email_outlined,
              label: 'Email',
              value: customer.email ?? 'Not provided',
            ),
            _DetailRow(
              icon: Icons.phone_android_outlined,
              label: 'Mobile',
              value: customer.mobile ?? 'Not provided',
            ),
            _DetailRow(
              icon: Icons.phone_outlined,
              label: 'Phone',
              value: customer.phone ?? 'Not provided',
            ),
            _DetailRow(
              icon: Icons.numbers_outlined,
              label: 'Tax number',
              value: customer.taxNumber ?? 'Not provided',
            ),
            if (customer.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in customer.tags) Chip(label: Text(tag)),
                ],
              ),
            ],
            if (customer.notes != null) ...[
              const Divider(height: 32),
              Text('Notes', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              Text(customer.notes!),
            ],
          ],
        ),
      ),
    );
  }
}

final class _CommercialCard extends StatelessWidget {
  const _CommercialCard({required this.customer, required this.currencyCode});

  final Customer customer;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Commercial settings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            _DetailRow(
              icon: Icons.credit_score_outlined,
              label: 'Credit limit',
              value: _formatMoney(currencyCode, customer.creditLimit),
            ),
            _DetailRow(
              icon: Icons.event_available_outlined,
              label: 'Payment terms',
              value: customer.paymentTermsDays == null
                  ? 'Company default'
                  : '${customer.paymentTermsDays} days',
            ),
            _DetailRow(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Opening balance',
              value: _formatMoney(currencyCode, customer.openingBalance),
            ),
          ],
        ),
      ),
    );
  }
}

final class _BalancePlaceholder extends StatelessWidget {
  const _BalancePlaceholder({required this.currencyCode});

  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.account_balance_outlined,
              color: colors.primary,
              size: 30,
            ),
            const SizedBox(height: 14),
            Text(
              'Customer balance',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _formatMoney(currencyCode, 0),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Balance calculation will connect when Finance is implemented.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

final class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 2),
                SelectableText(value),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _DetailError extends StatelessWidget {
  const _DetailError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_off_outlined, size: 46),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              children: [
                OutlinedButton(
                  onPressed: () => context.go('/crm'),
                  child: const Text('Back to customers'),
                ),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatMoney(String currencyCode, double value) {
  final fixed = value.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final grouped = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '${value < 0 ? '-' : ''}${currencyCode.toUpperCase()} $grouped.${parts.last}';
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../company/application/company_state.dart';
import '../../../company/presentation/widgets/company_context_gate.dart';
import '../../application/customer_models.dart';
import '../../application/customer_state.dart';
import '../widgets/customer_feedback.dart';
import '../widgets/customer_form.dart';

final class EditCustomerScreen extends ConsumerWidget {
  const EditCustomerScreen({required this.customerId, super.key});

  final String customerId;

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    CustomerInput input,
  ) async {
    try {
      await ref
          .read(customerMutationProvider.notifier)
          .updateCustomer(customerId, input);
      if (!context.mounted) return;
      CustomerFeedback.showSuccess(context, 'Customer updated.');
      context.go('/crm/customers/$customerId');
    } on Object catch (error) {
      if (context.mounted) CustomerFeedback.showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(selectedCompanyProvider);
    if (company == null) {
      return const CompanyRouteRedirect(location: '/company/select');
    }

    final customer = ref.watch(customerDetailProvider(customerId));
    final mutation = ref.watch(customerMutationProvider);
    return customer.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                CustomerFeedback.userMessage(error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () =>
                    ref.invalidate(customerDetailProvider(customerId)),
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
      data: (value) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Back to customer',
                      onPressed: mutation.isLoading
                          ? null
                          : () => context.go('/crm/customers/$customerId'),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Edit customer',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 3),
                          Text(value.title),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                CustomerForm(
                  key: ValueKey('edit-customer-form-${value.id}'),
                  initialCustomer: value,
                  submitLabel: 'Save changes',
                  isSubmitting: mutation.isLoading,
                  onSubmit: (input) => _save(context, ref, input),
                  onCancel: () => context.go('/crm/customers/$customerId'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

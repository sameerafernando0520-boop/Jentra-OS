import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../company/application/company_state.dart';
import '../../../company/presentation/widgets/company_context_gate.dart';
import '../../application/customer_models.dart';
import '../../application/customer_state.dart';
import '../widgets/customer_feedback.dart';
import '../widgets/customer_form.dart';

final class CreateCustomerScreen extends ConsumerWidget {
  const CreateCustomerScreen({super.key});

  Future<void> _create(
    BuildContext context,
    WidgetRef ref,
    CustomerInput input,
  ) async {
    try {
      final customer = await ref
          .read(customerMutationProvider.notifier)
          .createCustomer(input);
      if (!context.mounted) return;
      CustomerFeedback.showSuccess(context, 'Customer created.');
      context.go('/crm/customers/${customer.id}');
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
    final mutation = ref.watch(customerMutationProvider);

    return SingleChildScrollView(
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
                    tooltip: 'Back to customers',
                    onPressed: mutation.isLoading
                        ? null
                        : () => context.go('/crm'),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add customer',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 3),
                        Text('Create a customer for ${company.name}.'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              CustomerForm(
                submitLabel: 'Create customer',
                isSubmitting: mutation.isLoading,
                onSubmit: (input) => _create(context, ref, input),
                onCancel: () => context.go('/crm'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

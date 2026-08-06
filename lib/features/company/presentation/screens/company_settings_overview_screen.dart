import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/company_models.dart';
import '../../application/company_state.dart';
import '../widgets/company_feedback.dart';

final class CompanySettingsOverviewScreen extends ConsumerWidget {
  const CompanySettingsOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(selectedCompanyProvider);
    if (company == null) {
      return const _NoCompanySelectedView();
    }

    final settings = ref.watch(companySettingsProvider(company.id));
    return settings.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _SettingsErrorView(
        message: CompanyFeedback.userMessage(error),
        onRetry: () => ref.invalidate(companySettingsProvider(company.id)),
      ),
      data: (settings) =>
          _SettingsContent(company: company, settings: settings),
    );
  }
}

final class _SettingsContent extends StatelessWidget {
  const _SettingsContent({required this.company, required this.settings});

  final Company company;
  final CompanySettingsOverview settings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final legalName = company.legalName?.trim();

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final identity = Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: colors.primaryContainer,
                          foregroundColor: colors.onPrimaryContainer,
                          child: const Icon(Icons.business_outlined, size: 30),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                company.name,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              if (legalName != null &&
                                  legalName.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  legalName,
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Text(
                                'Read-only company setup overview',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(color: colors.primary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );

                    final selectorButton = OutlinedButton.icon(
                      onPressed: () => context.go('/company/select'),
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Switch company'),
                    );

                    if (constraints.maxWidth < 620) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          identity,
                          const SizedBox(height: 20),
                          selectorButton,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: identity),
                        const SizedBox(width: 24),
                        selectorButton,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 28),
                Text(
                  'Workspace details',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Wrap(
                      spacing: 36,
                      runSpacing: 20,
                      children: [
                        _WorkspaceDetail(
                          icon: Icons.badge_outlined,
                          label: 'Your role',
                          value: company.membershipRole,
                        ),
                        _WorkspaceDetail(
                          icon: Icons.payments_outlined,
                          label: 'Base currency',
                          value: company.currencyCode,
                        ),
                        _WorkspaceDetail(
                          icon: Icons.public_outlined,
                          label: 'Country',
                          value: company.countryCode,
                        ),
                        _WorkspaceDetail(
                          icon: Icons.schedule_outlined,
                          label: 'Timezone',
                          value: company.timezone,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Document numbering',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'The next sequence values configured for this company.',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 900
                        ? 3
                        : constraints.maxWidth >= 560
                        ? 2
                        : 1;
                    final documents = [
                      _DocumentSequence(
                        label: 'Invoice',
                        icon: Icons.receipt_long_outlined,
                        prefix: settings.invoicePrefix,
                        nextNumber: settings.nextInvoiceNumber,
                      ),
                      _DocumentSequence(
                        label: 'Quotation',
                        icon: Icons.request_quote_outlined,
                        prefix: settings.quotationPrefix,
                        nextNumber: settings.nextQuotationNumber,
                      ),
                      _DocumentSequence(
                        label: 'Sales order',
                        icon: Icons.shopping_cart_checkout_outlined,
                        prefix: settings.salesOrderPrefix,
                        nextNumber: settings.nextSalesOrderNumber,
                      ),
                      _DocumentSequence(
                        label: 'Purchase order',
                        icon: Icons.inventory_outlined,
                        prefix: settings.purchaseOrderPrefix,
                        nextNumber: settings.nextPurchaseOrderNumber,
                      ),
                      _DocumentSequence(
                        label: 'Bill',
                        icon: Icons.description_outlined,
                        prefix: settings.billPrefix,
                        nextNumber: settings.nextBillNumber,
                      ),
                    ];

                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: documents.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: columns == 1 ? 3.1 : 2.25,
                      ),
                      itemBuilder: (context, index) => documents[index],
                    );
                  },
                ),
                const SizedBox(height: 28),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: colors.secondaryContainer,
                          foregroundColor: colors.onSecondaryContainer,
                          child: const Icon(Icons.calendar_month_outlined),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Default payment terms',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${settings.defaultPaymentTermsDays} days',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Editing company setup will be enabled with the settings '
                  'permissions module. These values currently reflect the '
                  'secured database configuration.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _WorkspaceDetail extends StatelessWidget {
  const _WorkspaceDetail({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 205,
      child: Row(
        children: [
          Icon(icon, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _DocumentSequence extends StatelessWidget {
  const _DocumentSequence({
    required this.label,
    required this.icon,
    required this.prefix,
    required this.nextNumber,
  });

  final String label;
  final IconData icon;
  final String prefix;
  final int nextNumber;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final preview = '$prefix${nextNumber.toString().padLeft(5, '0')}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(icon, color: colors.primary, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: colors.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _SettingsErrorView extends StatelessWidget {
  const _SettingsErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.settings_suggest_outlined,
                size: 44,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Company settings unavailable',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _NoCompanySelectedView extends StatelessWidget {
  const _NoCompanySelectedView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.business_outlined, size: 44),
              const SizedBox(height: 16),
              Text(
                'Select a company first',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Company settings cannot be loaded without an active company '
                'context.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => context.go('/company/select'),
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Choose company'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

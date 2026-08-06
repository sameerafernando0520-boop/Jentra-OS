import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/components/brand_mark.dart';
import '../../application/company_models.dart';
import '../../application/company_state.dart';
import '../widgets/company_context_gate.dart';
import '../widgets/company_feedback.dart';
import '../widgets/company_sign_out_button.dart';

final class CompanySelectorScreen extends ConsumerWidget {
  const CompanySelectorScreen({super.key});

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(companyControllerProvider.notifier).refreshCompanies();
    } catch (error) {
      if (context.mounted) CompanyFeedback.showError(context, error);
    }
  }

  Future<void> _selectCompany(
    BuildContext context,
    WidgetRef ref,
    Company company,
  ) async {
    try {
      await ref.read(companyControllerProvider.notifier).selectCompany(company);
      if (context.mounted) context.go('/dashboard');
    } catch (error) {
      if (context.mounted) CompanyFeedback.showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(companyControllerProvider);

    return Scaffold(
      body: SafeArea(
        child: state.when(
          loading: () => const _SelectorLoadingView(),
          error: (error, _) => _SelectorErrorView(
            message: CompanyFeedback.userMessage(error),
            onRetry: () => _refresh(context, ref),
          ),
          data: (companyState) {
            if (!companyState.hasCompanies) {
              return const CompanyRouteRedirect(
                location: '/company/onboarding',
              );
            }

            return _SelectorContent(
              companies: companyState.companies,
              selectedCompany: companyState.selectedCompany,
              isSubmitting: companyState.isSubmitting,
              onRefresh: () => _refresh(context, ref),
              onSelect: (company) => _selectCompany(context, ref, company),
              onCreateCompany: () => context.go('/company/create'),
            );
          },
        ),
      ),
    );
  }
}

final class _SelectorContent extends StatelessWidget {
  const _SelectorContent({
    required this.companies,
    required this.selectedCompany,
    required this.isSubmitting,
    required this.onRefresh,
    required this.onSelect,
    required this.onCreateCompany,
  });

  final List<Company> companies;
  final Company? selectedCompany;
  final bool isSubmitting;
  final Future<void> Function() onRefresh;
  final Future<void> Function(Company company) onSelect;
  final VoidCallback onCreateCompany;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: BrandMark()),
                  IconButton.filledTonal(
                    tooltip: 'Refresh companies',
                    onPressed: isSubmitting ? null : onRefresh,
                    icon: const Icon(Icons.refresh),
                  ),
                  const SizedBox(width: 4),
                  const CompanySignOutButton(),
                ],
              ),
              const SizedBox(height: 36),
              Text(
                'Choose a company',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your dashboard and every business query will use this '
                'company until you switch again.',
                style: TextStyle(color: colors.onSurfaceVariant, height: 1.45),
              ),
              if (isSubmitting) ...[
                const SizedBox(height: 20),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 24),
              for (var index = 0; index < companies.length; index++) ...[
                _CompanyChoiceCard(
                  company: companies[index],
                  selected: selectedCompany?.id == companies[index].id,
                  enabled: !isSubmitting,
                  onPressed: () => onSelect(companies[index]),
                ),
                if (index != companies.length - 1) const SizedBox(height: 12),
              ],
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: isSubmitting ? null : onCreateCompany,
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('Create another company'),
              ),
              const SizedBox(height: 16),
              Text(
                'Only active memberships returned by the secured database '
                'are shown.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _CompanyChoiceCard extends StatelessWidget {
  const _CompanyChoiceCard({
    required this.company,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final Company company;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final legalName = company.legalName?.trim();

    return Card(
      color: selected ? colors.primaryContainer.withValues(alpha: 0.45) : null,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: selected
                    ? colors.primary
                    : colors.secondaryContainer,
                foregroundColor: selected
                    ? colors.onPrimary
                    : colors.onSecondaryContainer,
                child: Text(
                  company.name.trim().isEmpty
                      ? '?'
                      : company.name.trim()[0].toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      company.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (legalName != null && legalName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        legalName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _ChoiceMetadata(
                          icon: Icons.badge_outlined,
                          label: company.membershipRole,
                        ),
                        _ChoiceMetadata(
                          icon: Icons.payments_outlined,
                          label: company.currencyCode,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (selected)
                Tooltip(
                  message: 'Current company',
                  child: Icon(Icons.check_circle, color: colors.primary),
                )
              else
                Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

final class _ChoiceMetadata extends StatelessWidget {
  const _ChoiceMetadata({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: colors.onSurfaceVariant),
        const SizedBox(width: 5),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

final class _SelectorLoadingView extends StatelessWidget {
  const _SelectorLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandMark(),
          SizedBox(height: 28),
          CircularProgressIndicator(),
          SizedBox(height: 14),
          Text('Loading your companies...'),
        ],
      ),
    );
  }
}

final class _SelectorErrorView extends StatelessWidget {
  const _SelectorErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

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
                Icons.business_outlined,
                size: 44,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 18),
              Text(
                'Companies unavailable',
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

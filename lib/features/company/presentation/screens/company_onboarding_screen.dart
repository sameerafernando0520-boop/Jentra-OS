import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/components/brand_mark.dart';
import '../../application/company_state.dart';
import '../widgets/company_context_gate.dart';
import '../widgets/company_feedback.dart';
import '../widgets/company_sign_out_button.dart';

final class CompanyOnboardingScreen extends ConsumerWidget {
  const CompanyOnboardingScreen({super.key});

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(companyControllerProvider.notifier).refreshCompanies();
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
          loading: () => const _OnboardingLoadingView(),
          error: (error, _) => _OnboardingErrorView(
            message: CompanyFeedback.userMessage(error),
            onRetry: () => _refresh(context, ref),
          ),
          data: (companyState) {
            if (companyState.hasCompanies) {
              return const CompanyRouteRedirect(location: '/company/select');
            }

            return _OnboardingContent(
              isRefreshing: companyState.isSubmitting,
              onCreateCompany: () => context.go('/company/create'),
              onRefresh: () => _refresh(context, ref),
            );
          },
        ),
      ),
    );
  }
}

final class _OnboardingContent extends StatelessWidget {
  const _OnboardingContent({
    required this.isRefreshing,
    required this.onCreateCompany,
    required this.onRefresh,
  });

  final bool isRefreshing;
  final VoidCallback onCreateCompany;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Expanded(child: BrandMark()),
                  CompanySignOutButton(),
                ],
              ),
              const SizedBox(height: 40),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 760;
                  final introduction = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'ONE LAST STEP',
                          style: textTheme.labelMedium?.copyWith(
                            color: colors.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Set up your company workspace',
                        style: textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.12,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Jentra OS keeps every customer, invoice, stock movement, '
                        'and report inside the company you select.',
                        style: textTheme.bodyLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 28),
                      FilledButton.icon(
                        onPressed: isRefreshing ? null : onCreateCompany,
                        icon: const Icon(Icons.add_business_outlined),
                        label: const Text('Create company'),
                      ),
                    ],
                  );

                  final invitation = Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.mark_email_read_outlined,
                            color: colors.primary,
                            size: 32,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Joining an existing company?',
                            style: textTheme.titleLarge,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Once an administrator activates your membership, '
                            'the company will appear here. Refresh after you '
                            'accept the invitation.',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            onPressed: isRefreshing ? null : onRefresh,
                            icon: isRefreshing
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh),
                            label: Text(
                              isRefreshing
                                  ? 'Checking memberships'
                                  : 'Refresh memberships',
                            ),
                          ),
                        ],
                      ),
                    ),
                  );

                  if (!isWide) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        introduction,
                        const SizedBox(height: 28),
                        invitation,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(flex: 6, child: introduction),
                      const SizedBox(width: 56),
                      Expanded(flex: 5, child: invitation),
                    ],
                  );
                },
              ),
              const SizedBox(height: 36),
              Text(
                'Company access is enforced by your membership and database '
                'security policies.',
                style: textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _OnboardingLoadingView extends StatelessWidget {
  const _OnboardingLoadingView();

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
          Text('Checking company memberships...'),
        ],
      ),
    );
  }
}

final class _OnboardingErrorView extends StatelessWidget {
  const _OnboardingErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandMark(),
                  const SizedBox(height: 28),
                  Text(
                    'We could not check your companies',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

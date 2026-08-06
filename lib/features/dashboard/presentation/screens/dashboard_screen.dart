import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../company/application/company_models.dart';
import '../../../company/application/company_state.dart';
import '../../../company/presentation/widgets/company_context_gate.dart';
import '../../application/dashboard_failure.dart';
import '../../application/dashboard_models.dart';
import '../../application/dashboard_state.dart';

final class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(selectedCompanyProvider);

    // The shell already has CompanyContextGate. Keep this feature boundary so
    // the dashboard also fails closed when mounted elsewhere or in tests.
    if (company == null) {
      return const CompanyRouteRedirect(location: '/company/select');
    }

    final dashboard = ref.watch(dashboardControllerProvider);
    return dashboard.when(
      loading: () => _DashboardLoadingView(company: company),
      error: (error, _) => _DashboardErrorView(
        company: company,
        message: _userMessage(error),
        onRetry: () =>
            ref.read(dashboardControllerProvider.notifier).refreshDashboard(),
      ),
      data: (state) => _DashboardWorkspace(
        key: ValueKey('dashboard-company-${company.id}'),
        company: company,
        state: state,
        onRefresh: () =>
            ref.read(dashboardControllerProvider.notifier).refreshDashboard(),
      ),
    );
  }
}

final class _DashboardWorkspace extends StatelessWidget {
  const _DashboardWorkspace({
    required this.company,
    required this.state,
    required this.onRefresh,
    super.key,
  });

  final Company company;
  final DashboardState state;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final snapshot = state.snapshot;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppConstants.contentMaxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.isRefreshing) const LinearProgressIndicator(),
                if (state.isRefreshing) const SizedBox(height: 12),
                _GreetingSection(
                  companyName: company.name,
                  generatedAt: snapshot.generatedAt,
                  onRefresh: state.isRefreshing ? null : onRefresh,
                ),
                const SizedBox(height: 28),
                const _SectionTitle(
                  title: 'Quick actions',
                  subtitle: 'Start a common business task.',
                ),
                const SizedBox(height: 12),
                const _QuickActions(),
                const SizedBox(height: 28),
                const _SectionTitle(
                  title: 'Business overview',
                  subtitle: 'A current snapshot for the selected company.',
                ),
                const SizedBox(height: 12),
                _KpiGrid(
                  kpis: snapshot.kpis,
                  currencyCode: company.currencyCode,
                ),
                const SizedBox(height: 28),
                const _SectionTitle(
                  title: 'Recent activity',
                  subtitle: 'Latest changes across your workspace.',
                ),
                const SizedBox(height: 12),
                _RecentActivityCard(activities: snapshot.recentActivity),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _GreetingSection extends StatelessWidget {
  const _GreetingSection({
    required this.companyName,
    required this.generatedAt,
    required this.onRefresh,
  });

  final String companyName;
  final DateTime generatedAt;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greetingFor(DateTime.now()),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  companyName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Your company workspace is ready.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onPrimaryContainer.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Refresh dashboard',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

final class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

final class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    const actions = <_QuickAction>[
      _QuickAction('Add Customer', Icons.person_add_alt_1_outlined, '/crm'),
      _QuickAction('Create Invoice', Icons.receipt_long_outlined, '/sales'),
      _QuickAction('Add Product', Icons.add_box_outlined, '/inventory'),
      _QuickAction('Record Expense', Icons.payments_outlined, '/finance'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 4
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        final width = (constraints.maxWidth - (12 * (columns - 1))) / columns;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final action in actions)
              SizedBox(
                width: width,
                child: OutlinedButton.icon(
                  onPressed: () => context.go(action.route),
                  icon: Icon(action.icon),
                  label: Text(action.label),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    minimumSize: const Size.fromHeight(58),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

final class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.kpis, required this.currencyCode});

  final DashboardKpis kpis;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final cards = <_KpiData>[
      _KpiData(
        label: 'Today Sales',
        value: _formatMoney(currencyCode, kpis.todaySales),
        icon: Icons.today_outlined,
      ),
      _KpiData(
        label: 'This Month Sales',
        value: _formatMoney(currencyCode, kpis.monthSales),
        icon: Icons.calendar_month_outlined,
      ),
      _KpiData(
        label: 'Outstanding Invoices',
        value: _formatMoney(currencyCode, kpis.outstandingInvoices),
        supportingText:
            '${kpis.outstandingInvoiceCount} ${kpis.outstandingInvoiceCount == 1 ? 'invoice' : 'invoices'}',
        icon: Icons.pending_actions_outlined,
      ),
      _KpiData(
        label: 'Cash Balance',
        value: _formatMoney(currencyCode, kpis.cashBalance),
        icon: Icons.account_balance_wallet_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1080
            ? 4
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        final width = (constraints.maxWidth - (16 * (columns - 1))) / columns;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final card in cards)
              SizedBox(
                width: width,
                child: _KpiCard(data: card),
              ),
          ],
        );
      },
    );
  }
}

final class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data});

  final _KpiData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                data.icon,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data.label, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      data.value,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (data.supportingText != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      data.supportingText!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({required this.activities});

  final List<DashboardActivity> activities;

  @override
  Widget build(BuildContext context) {
    if (activities.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            children: [
              Icon(
                Icons.history_outlined,
                size: 40,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                'No recent activity yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'Activity will appear here as your team works in i Book.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: activities.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final activity = activities[index];
          return ListTile(
            leading: const Icon(Icons.history_outlined),
            title: Text(activity.title),
            subtitle: activity.description.isEmpty
                ? null
                : Text(activity.description),
            trailing: Text(_formatActivityDate(activity.occurredAt)),
          );
        },
      ),
    );
  }
}

final class _DashboardLoadingView extends StatelessWidget {
  const _DashboardLoadingView({required this.company});

  final Company company;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: 'Loading ${company.name} dashboard',
        child: const CircularProgressIndicator(),
      ),
    );
  }
}

final class _DashboardErrorView extends StatelessWidget {
  const _DashboardErrorView({
    required this.company,
    required this.message,
    required this.onRetry,
  });

  final Company company;
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 42,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${company.name} dashboard is unavailable',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
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
        ),
      ),
    );
  }
}

final class _QuickAction {
  const _QuickAction(this.label, this.icon, this.route);

  final String label;
  final IconData icon;
  final String route;
}

final class _KpiData {
  const _KpiData({
    required this.label,
    required this.value,
    required this.icon,
    this.supportingText,
  });

  final String label;
  final String value;
  final String? supportingText;
  final IconData icon;
}

String _greetingFor(DateTime now) {
  if (now.hour < 12) return 'Good morning';
  if (now.hour < 17) return 'Good afternoon';
  return 'Good evening';
}

String _formatMoney(String currencyCode, double value) {
  final fixed = value.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final grouped = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final sign = value < 0 ? '-' : '';
  return '$sign${currencyCode.toUpperCase()} $grouped.${parts.last}';
}

String _formatActivityDate(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month/${local.year}';
}

String _userMessage(Object error) {
  if (error case DashboardFailure(:final userMessage)) return userMessage;
  return 'We could not load the dashboard. Please try again.';
}

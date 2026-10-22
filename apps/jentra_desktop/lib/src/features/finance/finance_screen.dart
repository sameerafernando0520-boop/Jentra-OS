import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';

import '../../app_providers.dart';
import '../operations/operational_controller.dart';
import '../operations/operational_metric_card.dart';

/// Uses the existing scoped read model; financial calculations remain on the
/// server and amounts from different currencies are never combined here.
final financeOverviewProvider =
    FutureProvider.autoDispose<Map<String, Object?>>((ref) async {
      final scope = ref.watch(activeTenantContextProvider);
      final access = ref.watch(businessCapabilitiesProvider);
      final gateway = ref.watch(operationalGatewayProvider);
      final connection = ref.watch(connectivityStateProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          access.isLoading ||
          access.hasError ||
          connection.isLoading ||
          connection.hasError ||
          connection.value != ConnectivityState.online ||
          !_workflows.any((flow) => flow.allowed(access.value ?? {}))) {
        return const {};
      }
      return gateway.dashboard(scope);
    });

class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(businessCapabilitiesProvider);
    final scope = ref.watch(activeTenantContextProvider);
    final connection = ref.watch(connectivityStateProvider);
    final gateway = ref.watch(operationalGatewayProvider);
    final online =
        !connection.isLoading &&
        !connection.hasError &&
        connection.value == ConnectivityState.online;
    final capabilities = access.value ?? const <String>{};
    final workflows = _workflows
        .where((flow) => flow.allowed(capabilities))
        .toList();

    void refresh() {
      ref.invalidate(businessCapabilitiesProvider);
      ref.invalidate(financeOverviewProvider);
    }

    if (access.isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          semanticsLabel: 'Checking finance access',
        ),
      );
    }
    if (access.hasError) {
      return _FinanceState(
        icon: Icons.lock_reset_outlined,
        title: 'Finance access could not be checked',
        description: 'Reconnect and check your access to this business again.',
        action: JentraPrimaryButton(label: 'Check access', onPressed: refresh),
      );
    }
    if (gateway == null) {
      return const _FinanceState(
        icon: Icons.cloud_off_outlined,
        title: 'Connect your workspace',
        description: 'Finance needs a connected workspace. Open the configured Jentra OS app and sign in to your business.',
      );
    }
    if (scope == null || !scope.hasOperationalScope) {
      return const _FinanceState(
        icon: Icons.business_outlined,
        title: 'Choose your finance workspace',
        description: 'Select a business, legal entity and branch in the top bar to open its finance work.',
      );
    }
    if (workflows.isEmpty) {
      return _FinanceState(
        icon: Icons.lock_outline,
        title: 'Finance access is required',
        description: 'Ask a business administrator for finance access in this branch. If your access has changed, check it again.',
        action: JentraPrimaryButton(label: 'Check access', onPressed: refresh),
      );
    }

    final overview = ref.watch(financeOverviewProvider);
    return ListView(
      padding: EdgeInsets.all(
        MediaQuery.sizeOf(context).width < 700
            ? JentraSpacing.x4
            : JentraSpacing.x6,
      ),
      children: [
        JentraSectionHeader(
          title: 'Finance',
          description: 'Collect customer balances, settle suppliers and prepare the close for your selected branch.',
          trailing: IconButton(
            tooltip: 'Refresh finance',
            onPressed: online ? refresh : null,
            icon: const Icon(Icons.refresh),
          ),
        ),
        const SizedBox(height: JentraSpacing.x5),
        if (!online)
          const _FinanceNotice(
            'You are offline. Current balances and queues are hidden until you reconnect. Saved drafts remain in their workspaces.',
          )
        else
          overview.when(
            skipLoadingOnRefresh: false,
            skipLoadingOnReload: false,
            loading: () => const LinearProgressIndicator(
              semanticsLabel: 'Loading current finance position',
            ),
            error: (_, _) => JentraPanel(
              child: JentraEmptyState(
                icon: Icons.sync_problem_outlined,
                title: 'Your finance position could not be loaded',
                description: 'Check the connection and refresh. You can still open the workspaces below to verify their latest records.',
                action: JentraPrimaryButton(
                  label: 'Try again',
                  onPressed: () => ref.invalidate(financeOverviewProvider),
                ),
              ),
            ),
            data: (data) => _FinancePosition(
              data: data,
              capabilities: capabilities,
              workflows: workflows,
            ),
          ),
        const SizedBox(height: JentraSpacing.x6),
        for (final section in const [
          'Daily work',
          'Reconcile and close',
          'Reports and planning',
        ])
          if (workflows.any((flow) => flow.section == section)) ...[
            JentraSectionHeader(title: section),
            const SizedBox(height: JentraSpacing.x3),
            _FinanceGrid(
              children: [
                for (final flow in workflows.where(
                  (flow) => flow.section == section,
                ))
                  _WorkflowCard(workflow: flow),
              ],
            ),
            const SizedBox(height: JentraSpacing.x6),
          ],
      ],
    );
  }
}

class _FinancePosition extends StatelessWidget {
  const _FinancePosition({
    required this.data,
    required this.capabilities,
    required this.workflows,
  });
  final Map<String, Object?> data;
  final Set<String> capabilities;
  final List<_FinanceWorkflow> workflows;

  @override
  Widget build(BuildContext context) {
    final queues = [
      for (final card in data['cards'] as List? ?? const [])
        if (card is Map && _queueWorkflows.containsKey(card['kind']))
          if (workflows.any((flow) => flow.id == _queueWorkflows[card['kind']]))
            card,
    ];
    final metrics = [
      for (final metric in data['metrics'] as List? ?? const [])
        if (metric is Map &&
            _metricPermissions.containsKey(metric['kind']) &&
            _metricPermissions[metric['kind']]!.every(capabilities.contains))
          metric,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data['generated_at'] case final String time)
          Text(
            'Updated ${_updated(time)}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: context.jentraColors.textSecondary),
          ),
        if (queues.isNotEmpty) ...[
          const SizedBox(height: JentraSpacing.x4),
          const JentraSectionHeader(
            title: 'Work in progress',
            description: 'Current drafts and documents awaiting their next step. Open a queue to review each record.',
          ),
          const SizedBox(height: JentraSpacing.x3),
          _FinanceGrid(
            children: [
              for (final queue in queues)
                _FinanceQueueCard(
                  workflow: workflows.firstWhere(
                    (flow) => flow.id == _queueWorkflows[queue['kind']],
                  ),
                  count: '${queue['count']}',
                  label: _queueLabels[queue['kind']]!,
                ),
            ],
          ),
        ],
        if (metrics.isNotEmpty) ...[
          const SizedBox(height: JentraSpacing.x5),
          const JentraSectionHeader(
            title: 'Financial position',
            description: 'Dated balances and saved reviews. Amounts are shown in their original currencies.',
          ),
          const SizedBox(height: JentraSpacing.x3),
          _FinanceGrid(
            children: [
              for (final metric in metrics)
                OperationalMetricCard(metric: metric),
            ],
          ),
        ],
        if (queues.isEmpty && metrics.isEmpty)
          const JentraPanel(
            child: JentraEmptyState(
              icon: Icons.account_balance_outlined,
              title: 'Start with your finance workspaces',
              description: 'There are no finance summaries available for your current access. Open a workspace below to review its records.',
            ),
          ),
      ],
    );
  }
}

class _FinanceQueueCard extends StatelessWidget {
  const _FinanceQueueCard({
    required this.workflow,
    required this.count,
    required this.label,
  });
  final _FinanceWorkflow workflow;
  final String count, label;

  @override
  Widget build(BuildContext context) => JentraPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: JentraSpacing.x2),
        Text(count, style: Theme.of(context).textTheme.headlineLarge),
        TextButton.icon(
          onPressed: () => context.push(workflow.path),
          icon: const Icon(Icons.arrow_forward, size: 18),
          label: Text('Review ${label.toLowerCase()}'),
        ),
      ],
    ),
  );
}

class _WorkflowCard extends StatelessWidget {
  const _WorkflowCard({required this.workflow});
  final _FinanceWorkflow workflow;

  @override
  Widget build(BuildContext context) => JentraPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(workflow.icon, color: context.jentraColors.textSecondary),
        const SizedBox(height: JentraSpacing.x3),
        Text(workflow.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: JentraSpacing.x2),
        Text(workflow.description),
        const SizedBox(height: JentraSpacing.x3),
        OutlinedButton.icon(
          onPressed: () => context.push(workflow.path),
          icon: const Icon(Icons.arrow_forward, size: 18),
          label: Text('Open ${workflow.title.toLowerCase()}'),
        ),
      ],
    ),
  );
}

class _FinanceGrid extends StatelessWidget {
  const _FinanceGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
      final columns = (constraints.maxWidth / (360 * scale)).floor().clamp(
        1,
        3,
      );
      final width =
          (constraints.maxWidth - JentraSpacing.x4 * (columns - 1)) / columns;
      return Wrap(
        spacing: JentraSpacing.x4,
        runSpacing: JentraSpacing.x4,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class _FinanceState extends StatelessWidget {
  const _FinanceState({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });
  final IconData icon;
  final String title, description;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(JentraSpacing.x6),
      child: JentraEmptyState(
        icon: icon,
        title: title,
        description: description,
        action: action,
      ),
    ),
  );
}

class _FinanceNotice extends StatelessWidget {
  const _FinanceNotice(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: JentraPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ExcludeSemantics(child: Icon(Icons.cloud_off_outlined)),
          const SizedBox(width: JentraSpacing.x3),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}

String _updated(String value) {
  final date = DateTime.tryParse(value)?.toUtc();
  return date == null
      ? value
      : '${DateFormat('d MMM y HH:mm').format(date)} UTC';
}

class _FinanceWorkflow {
  const _FinanceWorkflow({
    required this.id,
    required this.title,
    required this.description,
    required this.path,
    required this.icon,
    required this.section,
    this.all = const [],
    this.any = const [],
  });
  final String id, title, description, path, section;
  final IconData icon;
  final List<String> all, any;

  bool allowed(Set<String> capabilities) =>
      all.every(capabilities.contains) &&
      (any.isEmpty || any.any(capabilities.contains));
}

const _workflows = [
  _FinanceWorkflow(
    id: 'receivables',
    title: 'Receivables',
    description:
        'Review customer ageing and generate dated customer statements.',
    path: '/receivables',
    icon: Icons.account_balance_outlined,
    section: 'Daily work',
    all: ['finance.receivables.view'],
  ),
  _FinanceWorkflow(
    id: 'receipts',
    title: 'Customer receipts',
    description:
        'Record receipts, allocate balances and review customer credits.',
    path: '/receivables?kind=customer_receipt',
    icon: Icons.south_west_outlined,
    section: 'Daily work',
    any: [
      'finance.receipts.view',
      'finance.receipts.manage',
      'finance.receipts.post',
    ],
  ),
  _FinanceWorkflow(
    id: 'payments',
    title: 'Supplier payments',
    description:
        'Prepare payments, review approvals and allocate supplier balances.',
    path: '/procurement/payments',
    icon: Icons.north_east_outlined,
    section: 'Daily work',
    any: [
      'finance.payments.manage',
      'finance.payments.post',
      'finance.payments.allocate',
      'finance.payments.reverse',
    ],
  ),
  _FinanceWorkflow(
    id: 'bills',
    title: 'Supplier bills',
    description: 'Check receipt matching, resolve exceptions and review supplier invoices.',
    path: '/procurement/bills',
    icon: Icons.receipt_long_outlined,
    section: 'Daily work',
    any: [
      'procurement.bills.view',
      'procurement.bills.manage',
      'procurement.bills.post',
    ],
  ),
  _FinanceWorkflow(
    id: 'journals',
    title: 'Manual journals',
    description: 'Prepare balanced entries and follow their approval and posting history.',
    path: '/finance/journals',
    icon: Icons.menu_book_outlined,
    section: 'Daily work',
    all: ['finance.view'],
  ),
  _FinanceWorkflow(
    id: 'bank',
    title: 'Bank reconciliation',
    description:
        'Import statements, match transactions and investigate differences.',
    path: '/finance/bank',
    icon: Icons.account_balance_wallet_outlined,
    section: 'Reconcile and close',
    all: ['finance.view'],
  ),
  _FinanceWorkflow(
    id: 'controls',
    title: 'Control reconciliation',
    description:
        'Compare receivables, payables and unbilled receipts with the ledger.',
    path: '/finance/controls',
    icon: Icons.balance_outlined,
    section: 'Reconcile and close',
    all: ['finance.view', 'finance.controls.reconcile'],
  ),
  _FinanceWorkflow(
    id: 'close',
    title: 'Close review',
    description:
        'Review control differences and inventory blockers before closing.',
    path: '/finance/close-review',
    icon: Icons.fact_check_outlined,
    section: 'Reconcile and close',
    all: [
      'finance.view',
      'finance.controls.reconcile',
      'inventory.stock.view',
      'inventory.cost.view',
    ],
  ),
  _FinanceWorkflow(
    id: 'periods',
    title: 'Periods and foreign exchange',
    description:
        'Review fiscal periods, currency revaluation and closing actions.',
    path: '/finance/periods',
    icon: Icons.event_repeat_outlined,
    section: 'Reconcile and close',
    all: ['finance.view'],
  ),
  _FinanceWorkflow(
    id: 'statements',
    title: 'Financial statements',
    description: 'Generate a trial balance, profit and loss, balance sheet or cash flow.',
    path: '/finance/statements',
    icon: Icons.table_chart_outlined,
    section: 'Reports and planning',
    all: ['finance.view'],
  ),
  _FinanceWorkflow(
    id: 'budgets',
    title: 'Budgets and variance',
    description: 'Build budget revisions and compare saved actuals with the approved plan.',
    path: '/finance/budgets',
    icon: Icons.stacked_bar_chart_outlined,
    section: 'Reports and planning',
    all: ['finance.view'],
  ),
  _FinanceWorkflow(
    id: 'tax',
    title: 'Tax review',
    description:
        'Review tax summaries and trace amounts to the original transactions.',
    path: '/finance/tax',
    icon: Icons.request_quote_outlined,
    section: 'Reports and planning',
    all: ['finance.view'],
  ),
  _FinanceWorkflow(
    id: 'dimensions',
    title: 'Financial dimensions',
    description: 'Maintain cost centres and financial project dimensions.',
    path: '/finance/dimensions',
    icon: Icons.category_outlined,
    section: 'Reports and planning',
    all: ['finance.view', 'finance.dimensions.manage'],
  ),
  _FinanceWorkflow(
    id: 'cashflow',
    title: 'Cash-flow mappings',
    description: 'Classify accounts for the indirect cash-flow statement.',
    path: '/finance/cash-flow-mappings',
    icon: Icons.alt_route_outlined,
    section: 'Reports and planning',
    all: ['finance.view', 'finance.cash_flow.configure'],
  ),
];

const _queueWorkflows = {
  'customer_receipt': 'receipts',
  'supplier_bill': 'bills',
  'payment_proposal': 'payments',
  'manual_journal': 'journals',
  'budget': 'budgets',
  'bank_statement': 'bank',
  'bank_match': 'bank',
};
const _queueLabels = {
  'customer_receipt': 'Customer receipts',
  'supplier_bill': 'Supplier bills',
  'payment_proposal': 'Payment proposals',
  'manual_journal': 'Manual journals',
  'budget': 'Budget versions',
  'bank_statement': 'Bank statements',
  'bank_match': 'Bank matches',
};
const _metricPermissions = {
  'ar_aging': ['finance.receivables.view'],
  'ap_aging': ['finance.payments.manage'],
  'cash_bank': ['finance.view'],
  'periods': ['finance.view'],
  'budgets': ['finance.view'],
  'bill_exceptions': ['finance.view', 'procurement.bills.view'],
  'close_review': [
    'finance.view',
    'finance.controls.reconcile',
    'inventory.stock.view',
    'inventory.cost.view',
  ],
};

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_providers.dart';
import 'financial_statement_controller.dart';

class FinancialStatementScreen extends ConsumerWidget {
  const FinancialStatementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(businessCapabilitiesProvider);
    if (access.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (access.hasError) {
      return Center(
        child: TextButton(
          onPressed: () => ref.invalidate(businessCapabilitiesProvider),
          child: const Text('Retry access check'),
        ),
      );
    }
    final controller = ref.watch(financialStatementControllerProvider);
    return controller == null
        ? const Center(child: Text('Choose a branch with finance access.'))
        : FinancialStatementWorkspace(
            key: ValueKey(controller),
            controller: controller,
            canConfigureCashFlow:
                access.value?.contains('finance.cash_flow.configure') ?? false,
          );
  }
}

class FinancialStatementWorkspace extends StatelessWidget {
  const FinancialStatementWorkspace({
    super.key,
    required this.controller,
    this.canConfigureCashFlow = false,
  });
  final FinancialStatementController controller;
  final bool canConfigureCashFlow;

  static const labels = {
    'trial_balance': 'Trial balance',
    'profit_loss': 'Profit & loss',
    'balance_sheet': 'Balance sheet',
    'cash_flow': 'Indirect cash flow',
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      if (!c.verified || c.denied) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                c.error ??
                    'Connect to verify finance access and restore the encrypted report request.',
              ),
              if (c.busy) const CircularProgressIndicator(),
              TextButton(
                onPressed: c.online && !c.busy ? c.initialize : null,
                child: const Text('Verify access'),
              ),
            ],
          ),
        );
      }
      final textScale = MediaQuery.textScalerOf(
        context,
      ).scale(1).clamp(1.0, 1.7);
      final width = 270.0 * textScale;
      final selectedPeriod = c.selectedPeriod;
      final comparisons = c.periods
          .where(
            (row) =>
                selectedPeriod != null &&
                (row['end_date'] as String).compareTo(
                      selectedPeriod['start_date'] as String,
                    ) <
                    0,
          )
          .toList();
      Widget metric(String label, Object? amount) => SizedBox(
        width: width,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                SelectableText('${amount ?? '—'}'),
              ],
            ),
          ),
        ),
      );
      final summary = c.summary;
      final comparative = summary['comparative'] is Map
          ? summary['comparative'] as Map
          : null;
      final cashFlow = summary['cash_flow'] is Map
          ? summary['cash_flow'] as Map
          : null;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Financial statements',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Saved statements freeze posted journal lines and account balances at generation.',
            ),
            if (canConfigureCashFlow)
              TextButton.icon(
                onPressed: c.pending
                    ? null
                    : () => context.go('/finance/cash-flow-mappings'),
                icon: const Icon(Icons.alt_route_outlined),
                label: const Text('Configure cash-flow mappings'),
              ),
            if (c.error != null) ...[
              const SizedBox(height: 12),
              Text(
                c.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (c.message != null) ...[
              const SizedBox(height: 12),
              Text(c.message!),
            ],
            if (c.busy) const LinearProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              'Generate a report',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 20,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: width,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('kind-${c.form['id']}'),
                    initialValue: c.form['kind'] as String?,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Statement'),
                    items: [
                      for (final entry in labels.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: c.locked
                        ? null
                        : (value) => c.field('kind', value),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('period-${c.form['id']}'),
                    initialValue:
                        c.periods.any((row) => row['id'] == c.form['period_id'])
                        ? c.form['period_id'] as String?
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Fiscal period',
                    ),
                    items: [
                      for (final period in c.periods)
                        DropdownMenuItem(
                          value: period['id'] as String,
                          child: Text(period['name'] as String? ?? 'Period'),
                        ),
                    ],
                    onChanged: c.locked
                        ? null
                        : (value) => c.field('period_id', value),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: TextFormField(
                    key: ValueKey(
                      'date-${c.form['id']}-${c.form['period_id']}',
                    ),
                    initialValue: c.form['as_of'] as String? ?? '',
                    enabled: !c.locked,
                    decoration: const InputDecoration(
                      labelText: 'As of (YYYY-MM-DD)',
                    ),
                    onChanged: (value) => c.field('as_of', value.trim()),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(
                      'comparison-${c.form['id']}-${c.form['period_id']}',
                    ),
                    initialValue:
                        comparisons.any(
                          (row) => row['id'] == c.form['comparative_period_id'],
                        )
                        ? c.form['comparative_period_id'] as String?
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Comparison (optional)',
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None')),
                      for (final period in comparisons)
                        DropdownMenuItem(
                          value: period['id'] as String,
                          child: Text(period['name'] as String? ?? 'Period'),
                        ),
                    ],
                    onChanged: c.locked
                        ? null
                        : (value) => c.field('comparative_period_id', value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: c.online && !c.locked ? c.generate : null,
                  child: const Text('Generate report'),
                ),
                OutlinedButton(
                  onPressed: c.online && !c.busy && !c.pending ? c.save : null,
                  child: const Text('Save encrypted draft'),
                ),
                OutlinedButton(
                  onPressed: c.online && !c.busy && !c.pending
                      ? c.newReport
                      : null,
                  child: const Text('New report'),
                ),
                if (c.pending)
                  FilledButton.tonal(
                    onPressed: c.online && !c.busy ? c.retry : null,
                    child: const Text('Retry sealed request'),
                  ),
                TextButton(
                  onPressed: c.online && !c.busy ? c.refresh : null,
                  child: const Text('Refresh evidence'),
                ),
              ],
            ),
            if (c.periodCursor != null)
              TextButton(
                onPressed: c.busy ? null : c.morePeriods,
                child: const Text('More periods'),
              ),
            const SizedBox(height: 24),
            Text(
              'Saved reports',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (c.reports.isEmpty)
              const Text('No saved reports in this entity.'),
            for (final report in c.reports)
              ListTile(
                title: Text(
                  '${labels[report['kind']] ?? report['kind']} · ${report['as_of']}',
                ),
                subtitle: Text(
                  '${report['base_currency_code']} · ${report['account_count']} accounts · ${report['journal_count']} journal lines${report['status'] == 'blocked' ? ' · blocked' : ''}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: c.online && !c.busy && !c.pending
                    ? () => c.open(report['id'] as String)
                    : null,
              ),
            if (c.reportCursor != null)
              TextButton(
                onPressed: c.busy ? null : c.moreReports,
                child: const Text('More reports'),
              ),
            if (summary.isNotEmpty) ...[
              const Divider(height: 40),
              Text(
                '${labels[summary['kind']] ?? summary['kind']} · ${summary['as_of']}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Frozen ${summary['generated_at']} · base ${summary['base_currency_code']} · ${summary['journal_count']} source lines',
              ),
              const SizedBox(height: 4),
              Text(
                'Tenant ${summary['tenant_id']} · entity ${summary['legal_entity_id']} · requested branch ${summary['branch_id']}',
              ),
              Text(
                'Period ${summary['period_start']} to ${summary['period_end']}${summary['comparative_period_id'] == null ? '' : ' · comparison ${summary['comparative_start']} to ${summary['comparative_end']}'}',
              ),
              if (summary['status'] == 'blocked') ...[
                const SizedBox(height: 8),
                Text(
                  'Blocked: classify moving accounts and reconcile cash before close.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                if (cashFlow != null)
                  Text(
                    '${cashFlow['unmapped_count']} unmapped accounts · ${cashFlow['no_mapped_cash'] == true ? 'no mapped cash account · ' : ''}difference ${cashFlow['difference']}',
                  ),
                if (comparative != null && comparative['status'] == 'blocked')
                  Text(
                    'Comparison blocked: ${comparative['unmapped_count']} unmapped accounts · difference ${comparative['difference']}',
                  ),
                if (cashFlow != null)
                  for (final row
                      in (cashFlow['unmapped_accounts'] as List? ?? []))
                    Text(
                      '${(row as Map)['code']} · ${row['name']} · ${row['unclassified_movement']}',
                    ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: switch (summary['kind']) {
                  'profit_loss' => [
                    metric('Revenue', summary['revenue']),
                    metric('Expenses', summary['expenses']),
                    metric('Net profit', summary['net_profit']),
                    if (comparative != null)
                      metric('Comparison profit', comparative['net_profit']),
                  ],
                  'balance_sheet' => [
                    metric('Assets', summary['assets']),
                    metric('Liabilities', summary['liabilities']),
                    metric('Equity', summary['equity']),
                    metric('Current earnings', summary['current_earnings']),
                    metric('Difference', summary['difference']),
                    if (comparative != null)
                      metric(
                        'Comparison difference',
                        comparative['difference'],
                      ),
                  ],
                  'cash_flow' => [
                    metric('Period profit', cashFlow?['period_profit']),
                    metric(
                      'Noncash adjustments',
                      cashFlow?['noncash_adjustments'],
                    ),
                    metric(
                      'Working capital',
                      cashFlow?['working_capital_change'],
                    ),
                    metric('Operating cash', cashFlow?['operating_cash']),
                    metric('Investing cash', cashFlow?['investing_cash']),
                    metric('Financing cash', cashFlow?['financing_cash']),
                    metric('Net cash change', cashFlow?['net_cash_change']),
                    metric('Opening cash', cashFlow?['opening_cash']),
                    metric('Closing cash', cashFlow?['closing_cash']),
                    metric('Difference', cashFlow?['difference']),
                    if (comparative != null)
                      metric(
                        'Comparison net cash',
                        comparative['net_cash_change'],
                      ),
                  ],
                  _ => [
                    metric('Period debit', summary['period_debit']),
                    metric('Period credit', summary['period_credit']),
                    metric('Closing debit', summary['closing_debit']),
                    metric('Closing credit', summary['closing_credit']),
                    metric('Difference', summary['difference']),
                  ],
                },
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'accounts', label: Text('Accounts')),
                      ButtonSegment(
                        value: 'journals',
                        label: Text('Journal lines'),
                      ),
                    ],
                    selected: {c.section},
                    onSelectionChanged: c.busy
                        ? null
                        : (value) => c.chooseSection(value.first),
                  ),
                  if (c.accountId != null)
                    TextButton(
                      onPressed: c.busy
                          ? null
                          : () => c.chooseSection('accounts'),
                      child: const Text('All accounts'),
                    ),
                ],
              ),
              for (final row in c.rows)
                ListTile(
                  isThreeLine: true,
                  title: Text(
                    c.section == 'accounts'
                        ? '${row['code']} · ${row['name']}'
                        : '${row['document_number']} · ${row['posting_date']}',
                  ),
                  subtitle: Text(
                    c.section == 'accounts'
                        ? '${row['account_type']}${summary['kind'] == 'cash_flow' ? ' · ${row['cash_flow_category']}' : ''} · amount ${row['amount']} · closing ${row['closing_balance']}${row['comparative_amount'] == null ? '' : ' · comparison ${row['comparative_amount']}'}'
                        : 'Account ${row['account_id']} · debit ${row['base_debit']} · credit ${row['base_credit']} · ${row['source_type']}',
                  ),
                  trailing: c.section == 'accounts'
                      ? const Icon(Icons.account_tree_outlined)
                      : null,
                  onTap: c.section == 'accounts' && !c.busy
                      ? () => c.chooseSection(
                          'journals',
                          account: row['account_id'] as String,
                        )
                      : null,
                ),
              if (c.rows.isEmpty)
                Text(
                  c.section == 'accounts'
                      ? 'No posting accounts in this report.'
                      : 'No frozen journal lines for this selection.',
                ),
              if (c.nextOffset != null)
                TextButton(
                  onPressed: c.busy ? null : c.moreLines,
                  child: const Text('More frozen lines'),
                ),
            ],
          ],
        ),
      );
    },
  );
}

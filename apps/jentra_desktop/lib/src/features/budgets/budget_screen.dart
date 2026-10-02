import '../shared/report_wait.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';

import '../../app_providers.dart';
import 'budget_controller.dart';
import '../report_export/report_export_screen.dart';
import '../financial_dimensions/financial_dimension_controller.dart';
import '../financial_dimensions/financial_dimension_screen.dart';

class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

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
    final controller = ref.watch(budgetControllerProvider);
    return controller == null
        ? const Center(child: Text('Choose a branch with finance access.'))
        : BudgetWorkspace(
            key: ValueKey(controller),
            controller: controller,
            financialDimensions: ref.watch(financialDimensionGatewayProvider),
            allowExport:
                access.value?.contains('finance.reports.export') ?? false,
          );
  }
}

class BudgetWorkspace extends StatelessWidget {
  const BudgetWorkspace({
    super.key,
    required this.controller,
    this.allowExport = false,
    this.financialDimensions,
  });
  final BudgetController controller;
  final bool allowExport;
  final FinancialDimensionGateway? financialDimensions;

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
                c.error ?? 'Connect to verify access and restore encrypted budget requests.',
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
      final width =
          260.0 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.7);
      final status = c.form['status'];
      final editable =
          c.canManage &&
          !c.locked &&
          const {'local', 'draft', 'revision'}.contains(status);
      final canDecide =
          c.canApprove &&
          !c.locked &&
          status == 'submitted' &&
          c.form['created_by'] != c.scope.actorId &&
          c.form['submitted_by'] != c.scope.actorId;
      final lines = c.form['lines'] is List
          ? c.form['lines'] as List
          : const [];
      final selectedBudget = c.selectedBudget;
      Widget metric(String label, Object? value) => SizedBox(
        width: width,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                SelectableText('${value ?? '—'}'),
              ],
            ),
          ),
        ),
      );
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Budgets & variance',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Approve a version before comparing it with posted journals. Each variance report keeps its original figures and source lines.',
            ),
            const SizedBox(height: 8),
            Text(
              financialDimensions == null
                  ? 'Budgets use account, entity, branch, period and currency. Cost centre and project budgets become available when those governed dimensions are configured.'
                  : 'Choose governed cost centres and project tags for disjoint account plans. An unassigned dimension includes every value; overlapping plans are rejected.',
            ),
            if (c.error != null) ...[
              const SizedBox(height: 12),
              Text(
                c.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (c.message != null) Text(c.message!),
            if (c.reportWait.active)
              ReportWaitIndicator(
                state: c.reportWait,
                onCancel: c.cancelReportWait,
              )
            else if (c.busy)
              const LinearProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              'Budget version',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Status: $status · version ${c.form['version'] ?? 0}${c.form['revision'] == null ? '' : ' · revision ${c.form['revision']}'}',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (c.canManage)
                  OutlinedButton.icon(
                    onPressed: c.locked ? null : c.newBudget,
                    icon: const Icon(Icons.add),
                    label: const Text('New budget'),
                  ),
                if (c.canManage && status == 'approved')
                  OutlinedButton(
                    onPressed: c.locked ? null : c.revise,
                    child: const Text('Start revision'),
                  ),
                OutlinedButton(
                  onPressed: c.busy || c.pending || c.variancePending
                      ? null
                      : c.saveEncrypted,
                  child: const Text('Save encrypted drafts'),
                ),
                if (c.pending)
                  FilledButton.tonal(
                    onPressed: c.online && !c.busy ? c.retryBudget : null,
                    child: const Text('Retry sealed budget request'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: width,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('budget-period-${c.form['id']}'),
                    initialValue: c.form['period_id'] as String?,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Period (or full year)',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Full year'),
                      ),
                      for (final row in c.periods)
                        DropdownMenuItem(
                          value: row['id'] as String,
                          child: Text('${row['name']} · ${row['start_date']}'),
                        ),
                    ],
                    onChanged: editable && status == 'local'
                        ? (value) =>
                              c.field('period_id', value == '' ? null : value)
                        : null,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: TextFormField(
                    key: ValueKey('budget-year-${c.form['id']}'),
                    initialValue: '${c.form['budget_year'] ?? ''}',
                    enabled: editable && status == 'local',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Budget year'),
                    onChanged: (value) =>
                        c.field('budget_year', int.tryParse(value)),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('budget-branch-${c.form['id']}'),
                    isExpanded: true,
                    initialValue: c.form['branch_id'] == null
                        ? 'entity'
                        : 'branch',
                    decoration: const InputDecoration(
                      labelText: 'Branch scope',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'branch',
                        child: Text('Selected branch'),
                      ),
                      DropdownMenuItem(
                        value: 'entity',
                        child: Text('Whole legal entity'),
                      ),
                    ],
                    onChanged: editable && status == 'local'
                        ? (value) => c.field(
                            'branch_id',
                            value == 'entity' ? null : c.scope.branchId,
                          )
                        : null,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: TextFormField(
                    key: ValueKey('budget-currency-${c.form['id']}'),
                    initialValue: c.form['currency_code'] as String? ?? '',
                    enabled: editable && status == 'local',
                    maxLength: 3,
                    decoration: InputDecoration(
                      labelText: 'Currency code',
                      helperText: 'Entity base: ${c.baseCurrency ?? '—'}',
                    ),
                    onChanged: (value) =>
                        c.field('currency_code', value.trim().toUpperCase()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: width * 2,
              child: TextFormField(
                key: ValueKey(
                  'budget-reason-${c.form['id']}-${c.form['status']}',
                ),
                initialValue: c.form['reason'] as String? ?? '',
                enabled: (editable || canDecide) && !c.locked,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Reason for this action',
                ),
                onChanged: c.decisionReason,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Account amounts',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (var i = 0; i < lines.length; i++)
              Builder(
                builder: (context) {
                  final line = lines[i] as Map;
                  final account = c.accounts
                      .where((row) => row['id'] == line['account_id'])
                      .firstOrNull;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: width,
                          child: Text(
                            account == null
                                ? '${line['account_id']}'
                                : '${account['code']} · ${account['name']}',
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: TextFormField(
                            key: ValueKey('amount-${line['id']}'),
                            initialValue: '${line['amount']}',
                            enabled: editable,
                            decoration: const InputDecoration(
                              labelText: 'Exact amount',
                            ),
                            onChanged: (value) => c.amount(i, value),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove account',
                          onPressed: editable ? () => c.removeLine(i) : null,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        for (final kind in ['cost_centre', 'project']) ...[
                          if ((line['dimension_snapshot'] as Map?)?[kind] !=
                              null)
                            Text(
                              '${((line['dimension_snapshot'] as Map)[kind] as Map)['code']} · ${((line['dimension_snapshot'] as Map)[kind] as Map)['name']}',
                            ),
                          if (editable && financialDimensions != null)
                            FinancialDimensionButton(
                              scope: c.scope,
                              gateway: financialDimensions!,
                              kind: kind,
                              entityOnly: c.form['branch_id'] == null,
                              label: kind == 'cost_centre'
                                  ? 'Choose cost centre'
                                  : 'Choose project tag',
                              enabled: c.online && !c.locked,
                              onSelected: (row) =>
                                  c.financialDimension(i, kind, row),
                            ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            if (editable) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: width * 1.5,
                child: TextField(
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Search posting accounts',
                  ),
                  onSubmitted: c.searchAccounts,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final account in c.accounts)
                    ActionChip(
                      label: Text('${account['code']} · ${account['name']}'),
                      onPressed:
                          financialDimensions == null &&
                              lines.any(
                                (x) =>
                                    (x as Map)['account_id'] == account['id'],
                              )
                          ? null
                          : () => c.addLine(
                              account['id'] as String,
                              allowDuplicate: financialDimensions != null,
                            ),
                    ),
                  if (c.accountCursor != null)
                    TextButton(
                      onPressed: c.busy ? null : c.moreAccounts,
                      child: const Text('More accounts'),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (c.canManage && status == 'local')
                  FilledButton(
                    onPressed: c.online && editable
                        ? () => c.act('create')
                        : null,
                    child: const Text('Create draft'),
                  ),
                if (c.canManage && status == 'revision')
                  FilledButton(
                    onPressed: c.online && editable
                        ? () => c.act('revise')
                        : null,
                    child: const Text('Create revision'),
                  ),
                if (c.canManage && status == 'draft') ...[
                  OutlinedButton(
                    onPressed: c.online && editable
                        ? () => c.act('save')
                        : null,
                    child: const Text('Save version'),
                  ),
                  FilledButton(
                    onPressed: c.online && editable
                        ? () => c.act('submit')
                        : null,
                    child: const Text('Submit for approval'),
                  ),
                ],
                if (canDecide) ...[
                  FilledButton(
                    onPressed: c.online ? () => c.act('approve') : null,
                    child: const Text('Approve version'),
                  ),
                  OutlinedButton(
                    onPressed: c.online ? () => c.act('reject') : null,
                    child: const Text('Reject version'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Budget versions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final row in c.budgets)
              ListTile(
                title: Text(
                  '${row['budget_year']} · ${row['currency_code']} · revision ${row['revision']}',
                ),
                subtitle: Text(
                  '${row['status']} · ${row['budget_branch_id'] == null ? 'legal entity' : 'selected branch'} · ${(row['lines'] as List).length} accounts',
                ),
                selected: row['id'] == c.form['id'],
                onTap: c.pending || c.busy
                    ? null
                    : () => c.openBudget(row['id'] as String),
              ),
            if (c.budgetCursor != null)
              TextButton(
                onPressed: c.busy ? null : c.moreBudgets,
                child: const Text('More budgets'),
              ),
            const SizedBox(height: 24),
            Text(
              'Posted actuals vs budget',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: width * 1.5,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('variance-budget-${c.varianceForm['id']}'),
                    initialValue: selectedBudget?['id'] as String?,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Approved budget version',
                    ),
                    items: [
                      for (final row in c.budgets)
                        if (row['status'] == 'approved')
                          DropdownMenuItem(
                            value: row['id'] as String,
                            child: Text(
                              '${row['budget_year']} · ${row['currency_code']} · revision ${row['revision']}',
                            ),
                          ),
                    ],
                    onChanged:
                        c.varianceLocked ||
                            c.varianceForm['status'] == 'generated'
                        ? null
                        : (value) => c.varianceField('budget_id', value),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: TextFormField(
                    key: ValueKey('variance-date-${c.varianceForm['id']}'),
                    initialValue: c.varianceForm['as_of'] as String? ?? '',
                    enabled:
                        !c.varianceLocked &&
                        c.varianceForm['status'] != 'generated',
                    decoration: const InputDecoration(
                      labelText: 'As of (YYYY-MM-DD)',
                    ),
                    onChanged: (value) => c.varianceField('as_of', value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed:
                      c.online &&
                          !c.varianceLocked &&
                          c.varianceForm['status'] != 'generated' &&
                          selectedBudget != null
                      ? c.generate
                      : null,
                  child: const Text('Generate frozen variance'),
                ),
                OutlinedButton(
                  onPressed: c.varianceLocked ? null : c.newVariance,
                  child: const Text('New variance'),
                ),
                if (c.variancePending)
                  FilledButton.tonal(
                    onPressed: c.online && !c.busy ? c.retryVariance : null,
                    child: const Text('Retry sealed variance request'),
                  ),
                TextButton(
                  onPressed: c.online && !c.busy ? c.refresh : null,
                  child: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Saved variance reports',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final row in c.reports)
              ListTile(
                title: Text('${row['as_of']} · ${row['currency_code']}'),
                subtitle: Text(
                  'Actual ${row['actual_total']} · budget ${row['budget_total']} · variance ${row['variance_total']}',
                ),
                selected: row['id'] == c.selectedReportId,
                onTap: c.busy ? null : () => c.openReport(row['id'] as String),
              ),
            if (c.reportCursor != null)
              TextButton(
                onPressed: c.busy ? null : c.moreReports,
                child: const Text('More reports'),
              ),
            if (c.summary.isNotEmpty) ...[
              if (allowExport)
                ReportExportLink(
                  sourceType: 'budget',
                  sourceId: c.summary['id'] as String,
                  section: c.section,
                  filters: {'budget_line_id': c.budgetLineId},
                  enabled: c.online && c.verified && !c.busy,
                ),
              const SizedBox(height: 24),
              Text(
                'Frozen variance at ${c.summary['as_of']}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                'Basis: ${c.summary['currency_basis'] == 'base_all_posted' ? 'All posted amounts in base currency' : 'Matching transaction currency only'} · ${c.summary['currency_code']} · ${c.summary['journal_count']} posted journal ${c.summary['journal_count'] == 1 ? 'line' : 'lines'}',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  metric('Budget', c.summary['budget_total']),
                  metric('Actual', c.summary['actual_total']),
                  metric('Variance', c.summary['variance_total']),
                  metric(
                    'Variance %',
                    c.summary['variance_percent'] == null
                        ? null
                        : '${c.summary['variance_percent']}%',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Accounts'),
                    selected: c.section == 'lines',
                    onSelected: (_) => c.chooseSection('lines'),
                  ),
                  ChoiceChip(
                    label: const Text('Posted journal lines'),
                    selected: c.section == 'journals',
                    onSelected: (_) => c.chooseSection('journals'),
                  ),
                  if (c.budgetLineId != null)
                    TextButton(
                      onPressed: () => c.chooseSection('lines'),
                      child: const Text('Clear account filter'),
                    ),
                ],
              ),
              for (final row in c.rows)
                ListTile(
                  title: Text(
                    c.section == 'lines'
                        ? '${row['code']} · ${row['name']}'
                        : '${row['posting_date']} · ${row['document_number']}',
                  ),
                  subtitle: Text(
                    c.section == 'lines'
                        ? 'Budget ${row['budget_amount']} · actual ${row['actual_amount']} · variance ${row['variance']}'
                        : '${row['source_type']} · ${row['source_id']} · debit ${row['base_debit']} · credit ${row['base_credit']}',
                  ),
                  trailing: c.section == 'lines'
                      ? const Icon(Icons.chevron_right)
                      : null,
                  onTap: c.section == 'lines'
                      ? () => c.chooseSection(
                          'journals',
                          lineId: row['id'] as String,
                        )
                      : null,
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

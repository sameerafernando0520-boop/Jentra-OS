import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import 'tax_summary_controller.dart';

class TaxSummaryScreen extends ConsumerWidget {
  const TaxSummaryScreen({super.key});

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
    final controller = ref.watch(taxSummaryControllerProvider);
    return controller == null
        ? const Center(child: Text('Choose a branch with finance access.'))
        : TaxSummaryWorkspace(
            key: ValueKey(controller),
            controller: controller,
          );
  }
}

class TaxSummaryWorkspace extends StatelessWidget {
  const TaxSummaryWorkspace({super.key, required this.controller});
  final TaxSummaryController controller;
  static const sourceLabels = {
    'sales_invoice': 'Sales invoice',
    'sales_return': 'Sales return',
    'supplier_bill': 'Supplier bill',
    'purchase_return': 'Purchase return',
    'manual_journal': 'Governed journal',
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
                    'Connect to verify finance access and restore the encrypted tax request.',
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
      final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.7);
      final fieldWidth = 270.0 * scale;
      final s = c.summary;
      Widget amount(String label, Object? value) => SizedBox(
        width: fieldWidth,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 5),
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
              'Tax review',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Non-certified summary of posted source lines and their tax journals. Statutory review is required before filing.',
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
              'Generate a tax review',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 20,
              children: [
                SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('tax-period-${c.form['id']}'),
                    initialValue:
                        c.periods.any((p) => p['id'] == c.form['period_id'])
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
                  width: fieldWidth,
                  child: TextFormField(
                    key: ValueKey(
                      'tax-date-${c.form['id']}-${c.form['period_id']}',
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
                  width: fieldWidth,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('tax-branch-${c.form['id']}'),
                    initialValue: c.form['branch_filter_id'] as String?,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Branch scope',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Entire legal entity'),
                      ),
                      DropdownMenuItem(
                        value: c.scope.branchId,
                        child: const Text('Selected branch'),
                      ),
                    ],
                    onChanged: c.locked
                        ? null
                        : (value) => c.field('branch_filter_id', value),
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
                  child: const Text('Generate review'),
                ),
                OutlinedButton(
                  onPressed: c.online && !c.busy && !c.pending ? c.save : null,
                  child: const Text('Save encrypted draft'),
                ),
                OutlinedButton(
                  onPressed: c.online && !c.busy && !c.pending
                      ? c.newReport
                      : null,
                  child: const Text('New review'),
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
              'Saved reviews',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (c.reports.isEmpty)
              const Text('No saved reviews in this branch.'),
            for (final report in c.reports)
              ListTile(
                title: Text('Tax review · ${report['as_of']}'),
                subtitle: Text(
                  '${report['base_currency_code']} · ${report['line_count']} source lines · ${report['blocked_count']} needing review',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: c.online && !c.busy && !c.pending
                    ? () => c.open(report['id'] as String)
                    : null,
              ),
            if (c.reportCursor != null)
              TextButton(
                onPressed: c.busy ? null : c.moreReports,
                child: const Text('More reviews'),
              ),
            if (s.isNotEmpty) ...[
              const Divider(height: 40),
              Text(
                'Saved tax review · ${s['as_of']}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                '${s['notice']}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 6),
              Text(
                'Period ${s['period_start']} to ${s['period_end']} · frozen ${s['generated_at']} · base ${s['base_currency_code']}',
              ),
              Text(
                'Tenant ${s['tenant_id']} · entity ${s['legal_entity_id']} · requested branch ${s['branch_id']} · ${s['branch_filter_id'] == null ? 'all branches' : 'selected branch'}',
              ),
              if ((s['blocked_count'] as int? ?? 0) > 0)
                Text(
                  'Blocked: ${s['blocked_count']} lines have missing or mismatched provenance. Their tax is excluded from classified totals.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  amount('Output tax · base', s['output_tax_base']),
                  amount('Input tax · base', s['input_tax_base']),
                  amount('Withholding tax · base', s['withholding_tax_base']),
                  amount('Zero-rated taxable · base', s['zero_taxable_base']),
                  amount('Exempt taxable · base', s['exempt_taxable_base']),
                  amount('Unverified tax · base', s['unverified_tax_base']),
                ],
              ),
              const SizedBox(height: 20),
              if (s['version'] == 2) ...[
                Text(
                  'Tax-control reconciliation',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Text(
                  'Signed base amounts use debit positive and credit negative. Opening and current-period sources are compared with all posted tax-control journal activity through the cutoff.',
                ),
                Text(
                  '${s['control_difference_count']} differences · ${s['control_unassigned_source_count']} unassigned sources · ${s['unattributed_journal_count']} unattributed GL lines · ${s['control_review_count']} sources needing review',
                ),
                if (s['control_status'] == 'blocked')
                  Text(
                    'Tax controls need review before period close.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    amount(
                      'Assigned source balance · base',
                      s['control_source_base'],
                    ),
                    amount(
                      'Tax-control GL balance · base',
                      s['control_gl_base'],
                    ),
                    amount(
                      'Control difference · base',
                      s['control_difference'],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 440,
                  child: DropdownButtonFormField<String>(
                    initialValue: c.controlSection,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Tax-control evidence',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'controls',
                        child: Text('Account totals'),
                      ),
                      DropdownMenuItem(
                        value: 'control_differences',
                        child: Text('Differences'),
                      ),
                      DropdownMenuItem(
                        value: 'control_sources',
                        child: Text('Source tax amounts'),
                      ),
                      DropdownMenuItem(
                        value: 'control_journals',
                        child: Text('Posted GL lines'),
                      ),
                    ],
                    onChanged: c.busy || !c.online
                        ? null
                        : (value) {
                            if (value != null) c.controlDrill(value);
                          },
                  ),
                ),
                if (c.controlAccountId != null || c.controlEvidenceKey != null)
                  TextButton(
                    onPressed: c.busy
                        ? null
                        : () => c.controlDrill(c.controlSection),
                    child: const Text('Clear evidence filter'),
                  ),
                for (final row in c.controlRows)
                  Card(
                    child: ExpansionTile(
                      title: Text(
                        c.controlSection == 'controls'
                            ? '${row['code']} · ${row['name']}'
                            : '${row['tax_control_movement'] == null ? row['source_type'] ?? 'Control difference' : 'Tax-control ${row['tax_control_movement']}'} · ${row['posting_date'] ?? row['evidence_key']}',
                      ),
                      subtitle: Text(
                        c.controlSection == 'controls'
                            ? 'Source ${row['source_closing_base']} · GL ${row['gl_closing_base']} · difference ${row['difference']}'
                            : 'Expected ${row['expected_base'] ?? '—'} · posted ${row['posted_base']}${row['difference'] == null ? '' : ' · difference ${row['difference']}'}${row['review_code'] == null ? '' : ' · ${row['review_code']}'}',
                      ),
                      children: [
                        if (c.controlSection == 'controls')
                          ListTile(
                            title: const Text('Opening and period basis'),
                            subtitle: Text(
                              'Opening: source ${row['source_opening_base']} · GL ${row['gl_opening_base']}\nPeriod: source ${row['source_period_base']} · GL ${row['gl_period_base']}',
                            ),
                          ),
                        if (c.controlSection != 'controls')
                          ListTile(
                            title: const Text('Frozen lineage'),
                            subtitle: SelectableText(
                              'Account ${row['account_id'] ?? 'unassigned'}\nSource ${row['source_id'] ?? row['evidence_key']}\nJournal ${row['journal_entry_id'] ?? '—'}\nBranch ${row['branch_id'] ?? 'see source or GL drill'}',
                            ),
                          ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TextButton(
                              onPressed: c.busy
                                  ? null
                                  : () => c.controlDrill(
                                      'control_sources',
                                      accountId: row['account_id'] as String?,
                                      evidenceKey:
                                          row['evidence_key'] as String?,
                                    ),
                              child: const Text('Source tax'),
                            ),
                            TextButton(
                              onPressed: c.busy
                                  ? null
                                  : () => c.controlDrill(
                                      'control_journals',
                                      accountId: row['account_id'] as String?,
                                      evidenceKey:
                                          row['evidence_key'] as String?,
                                    ),
                              child: const Text('GL lines'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                if (c.controlRows.isEmpty)
                  const Text('No rows for this evidence selection.'),
                if (c.controlNextOffset != null)
                  TextButton(
                    onPressed: c.busy ? null : c.moreControls,
                    child: const Text('More control evidence'),
                  ),
                const SizedBox(height: 20),
              ] else
                const Text(
                  'This earlier review has no tax-control snapshot. Generate a new review for control reconciliation.',
                ),
              Text(
                'Posted source and journal drill',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (c.rows.isEmpty)
                const Text('No tax-defined posted lines in this page.'),
              for (final row in c.rows)
                Card(
                  child: ExpansionTile(
                    title: Text(
                      '${sourceLabels[row['source_type']] ?? 'Posted source'} · ${row['tax_code'] ?? 'Unclassified'} · ${row['tax_kind'] ?? 'Unknown'}',
                    ),
                    subtitle: Text(
                      '${row['posting_date']} · ${row['currency_code']} ${row['tax_amount']} tax · ${row['taxable_amount']} taxable${row['review_code'] == null ? '' : ' · ${row['review_code']}'}',
                    ),
                    children: [
                      ListTile(
                        title: const Text('Frozen source lineage'),
                        subtitle: SelectableText(
                          'Document ${row['source_id']}\nLine ${row['source_line_id']}\nDefinition ${row['definition_id']} · version ${row['definition_version'] ?? 'missing'}\nJournal ${row['journal_entry_id'] ?? 'none'}',
                        ),
                      ),
                      ListTile(
                        title: const Text('Base-currency tax'),
                        subtitle: SelectableText(
                          'Posted ${row['tax_base']} · expected ${row['expected_tax_base']} · taxable ${row['taxable_base']}',
                        ),
                      ),
                      for (final journal
                          in (row['journal_lines'] as List? ?? []))
                        ListTile(
                          title: Text('Journal line ${(journal as Map)['id']}'),
                          subtitle: SelectableText(
                            'Account ${journal['account_id']} · debit ${journal['base_debit']} · credit ${journal['base_credit']}',
                          ),
                        ),
                    ],
                  ),
                ),
              if (c.nextOffset != null)
                TextButton(
                  onPressed: c.busy ? null : c.moreLines,
                  child: const Text('More source lines'),
                ),
            ],
          ],
        ),
      );
    },
  );
}

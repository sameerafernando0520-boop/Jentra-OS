import '../shared/report_wait.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import 'control_reconciliation_controller.dart';
import '../report_export/report_export_screen.dart';
import '../journal_evidence/posted_journal_screen.dart';

class ControlReconciliationScreen extends ConsumerWidget {
  const ControlReconciliationScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(businessCapabilitiesProvider);
    if (caps.isLoading) return const Center(child: CircularProgressIndicator());
    if (caps.hasError) {
      return Center(
        child: TextButton(
          onPressed: () => ref.invalidate(businessCapabilitiesProvider),
          child: const Text('Retry access check'),
        ),
      );
    }
    final c = ref.watch(controlReconciliationControllerProvider);
    return c == null
        ? const Center(
            child: Text(
              'Choose a branch with finance and control reconciliation access.',
            ),
          )
        : ControlReconciliationWorkspace(
            key: ValueKey(c),
            controller: c,
            allowJournal: caps.value?.contains('finance.view') ?? false,
            allowExport:
                caps.value?.contains('finance.reports.export') ?? false,
          );
  }
}

class ControlReconciliationWorkspace extends StatelessWidget {
  const ControlReconciliationWorkspace({
    super.key,
    required this.controller,
    this.allowExport = false,
    this.allowJournal = false,
  });
  final ControlReconciliationController controller;
  final bool allowExport;
  final bool allowJournal;
  Future<void> confirm(BuildContext context) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reverse this allocation?'),
        content: const SingleChildScrollView(
          child: Text(
            'The original allocation remains in history. This posts a linked correction, reopens both items and reverses any exchange, discount or write-off journal effects.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reverse allocation'),
          ),
        ],
      ),
    );
    if (approved == true) await controller.reverse();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller, s = c.summary;
      final grni = (s['kind'] ?? c.form['kind']) == 'GRNI';
      Widget action(
        String title,
        VoidCallback callback, {
        bool enabled = true,
      }) => TextButton(
        onPressed: c.busy || !c.online || !enabled ? null : callback,
        child: Text(title),
      );
      if (c.accessDenied) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Access changed. Reconciliation data has been cleared.',
              ),
              if (c.error != null) Text(c.error!),
              action('Recheck access', c.initialize),
            ],
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            grni
                ? 'GRNI control reconciliation'
                : 'AR / AP control reconciliation',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            grni
                ? 'Compare goods received but not invoiced with their original accrual accounts. Saved reports retain dated receipts, matched bills, unbilled returns and reversals.'
                : 'Compare this branch’s posted open items with their original control accounts. Saved reports preserve the selected posting cutoff and every source difference.',
          ),
          if (c.reportWait.active)
            ReportWaitIndicator(
              state: c.reportWait,
              onCancel: c.cancelReportWait,
            )
          else if (c.busy)
            const LinearProgressIndicator(),
          if (!c.online)
            const Text(
              'Offline — inputs and sealed requests are retained. Reconnect and refresh access to read evidence or post corrections.',
            ),
          if (c.online && !c.verified)
            const Text('Refresh access to read evidence or generate a report.'),
          if (c.error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                c.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (c.message != null)
            Semantics(liveRegion: true, child: Text(c.message!)),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: c.busy || c.pending ? null : c.newReport,
                child: const Text('New report'),
              ),
              OutlinedButton(
                onPressed: c.busy ? null : c.save,
                child: const Text('Save inputs locally'),
              ),
              action('Refresh access', c.initialize),
              action('Refresh saved reports', c.refreshReports),
            ],
          ),
          if (c.correction.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Allocation correction',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${c.correction['kind']} · ${c.correction['source_document_number']} → ${c.correction['target_document_number']}',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: ValueKey('date:${c.correction['allocation_id']}'),
                      initialValue: c.correction['posting_date'] as String?,
                      enabled: !c.busy && c.correctionLocal?.pending == null,
                      decoration: const InputDecoration(
                        labelText: 'Reversal posting date (YYYY-MM-DD)',
                      ),
                      onChanged: (v) => c.correctionField('posting_date', v),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: ValueKey('reason:${c.correction['allocation_id']}'),
                      initialValue: c.correction['reason'] as String?,
                      enabled: !c.busy && c.correctionLocal?.pending == null,
                      decoration: const InputDecoration(
                        labelText: 'Reason for correction',
                      ),
                      maxLength: 1000,
                      minLines: 2,
                      maxLines: 4,
                      onChanged: (v) => c.correctionField('reason', v),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed:
                              c.busy ||
                                  !c.online ||
                                  !c.canReverse(c.correction['kind'] as String)
                              ? null
                              : () => confirm(context),
                          child: Text(
                            c.correctionLocal?.pending == null
                                ? 'Review reversal'
                                : 'Retry saved reversal',
                          ),
                        ),
                        action(
                          'Close correction',
                          c.clearCorrection,
                          enabled: !c.pending,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (c.form['status'] != 'generated') ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final kind in const ['AR', 'AP', 'GRNI'])
                  ChoiceChip(
                    label: Text(switch (kind) {
                      'AR' => 'Receivables (AR)',
                      'AP' => 'Payables (AP)',
                      _ => 'Received, not invoiced (GRNI)',
                    }),
                    selected: c.form['kind'] == kind,
                    onSelected: c.locked ? null : (_) => c.field('kind', kind),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: ValueKey(c.form['id']),
              initialValue: c.form['as_of'] as String? ?? '',
              enabled: !c.locked,
              decoration: const InputDecoration(
                labelText: 'As-of posting date (YYYY-MM-DD)',
              ),
              onChanged: (v) => c.field('as_of', v),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed:
                    c.busy ||
                        !c.online ||
                        !c.verified ||
                        c.correctionLocal?.pending != null
                    ? null
                    : c.generate,
                child: Text(
                  c.local?.pending == null
                      ? 'Generate saved report'
                      : 'Retry saved generation',
                ),
              ),
            ),
          ],
          if (s.isNotEmpty) ...[
            if (allowExport)
              ReportExportLink(
                sourceType: 'control',
                sourceId: s['id'] as String,
                section: c.section,
                filters: {'evidence_key': c.accountId},
                enabled: c.online && c.verified && !c.busy,
              ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${s['kind']} · ${s['entity_name']} · ${s['branch_name']}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      'As of ${s['as_of']} · Generated ${s['generated_at']}',
                    ),
                    Text(
                      '${s['currency_code']} · ${s['kind'] == 'AR' ? 'Debit' : 'Credit'} balances are positive',
                    ),
                    Text(
                      '${grni ? 'Unbilled accrual' : 'Open items'} ${s['subledger_value']} · General ledger ${s['gl_value']}',
                    ),
                    Text(
                      'Difference ${s['difference']} · ${s['difference_count']} source differences',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SelectableText('Report ${s['id']}'),
                  ],
                ),
              ),
            ),
            if (c.accountId != null)
              Wrap(
                children: [
                  SelectableText('Control account ${c.accountId}'),
                  action('Clear account filter', () => c.sources(null)),
                ],
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final pair in {
                  'accounts': 'Controls',
                  'items': grni ? 'Receipts' : 'Open items',
                  if (!grni) 'allocations': 'Allocations',
                  'entries': 'Subledger sources',
                  'journals': 'Journal lines',
                  'differences': 'Differences',
                }.entries)
                  ChoiceChip(
                    label: Text(pair.value),
                    selected: c.section == pair.key,
                    onSelected: c.busy || !c.online
                        ? null
                        : (_) => c.selectSection(pair.key),
                  ),
              ],
            ),
            action('Refresh saved evidence', c.refreshPage),
            if (c.rows.isEmpty && !c.busy)
              const Text('No rows in this saved section.'),
            for (final r in c.rows)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (c.section == 'accounts' ||
                          c.section == 'differences') ...[
                        Text(
                          c.section == 'accounts'
                              ? '${r['code']} · ${r['name']}'
                              : grni
                              ? '${r['source_type']} · ${r['source_id']}'
                              : 'Command ${r['command_id']}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${grni ? 'Expected accrual' : 'Open items'} ${r['subledger_value']} · GL ${r['gl_value']} · Difference ${r['difference']}',
                        ),
                        action(
                          'View account sources',
                          () => c.sources(r['evidence_key'] as String),
                        ),
                      ] else if (c.section == 'items') ...[
                        Text(
                          '${r['document_number']} · ${r['party_name']}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${r['currency_code']} · Original ${r['original_amount']} · ${grni ? 'Matched / returned / reversed' : 'Settled'} ${r['settled_amount']} · Open ${r['open_amount']}',
                        ),
                        Text(
                          'Base original ${r['original_base_amount']} · Base open ${r['open_base_amount']}',
                        ),
                        Text(
                          grni
                              ? 'Received ${r['posting_date']}'
                              : 'Posted ${r['posting_date']} · Due ${r['due_date']}',
                        ),
                        SelectableText(
                          '${r['source_type']} · ${r['source_id']}\nJournal ${r['journal_entry_id']}',
                        ),
                      ] else if (c.section == 'allocations') ...[
                        Text(
                          '${r['source_document_number']} → ${r['target_document_number']}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'Posted ${r['posting_date']} · Source ${r['source_amount']} · Target ${r['transaction_amount']}',
                        ),
                        Text(
                          'FX ${r['exchange_difference']} · Write-off ${r['write_off']} · Discount ${r['discount_amount']}',
                        ),
                        SelectableText(
                          'Allocation ${r['id']}\nJournal ${r['journal_entry_id'] ?? 'No adjustment journal required'}',
                        ),
                        if (r['reversal'] is Map)
                          Text(
                            'Reversed ${(r['reversal'] as Map)['posting_date']} · ${(r['reversal'] as Map)['reason']}',
                          )
                        else if (c.canReverse(s['kind'] as String))
                          action(
                            'Prepare reversal',
                            () => c.chooseAllocation(r),
                            enabled: !c.pending,
                          ),
                      ] else ...[
                        Text(
                          '${r['document_number'] ?? r['source_type']} · ${r['posting_date']}',
                        ),
                        Text('Base value ${r['value']}'),
                        SelectableText(
                          '${r['source_type']} · ${r['source_id']}\nCommand ${r['command_id']}',
                        ),
                        if (grni && c.section == 'entries')
                          SelectableText(
                            'Receipt ${r['receipt_id']}\nJournal ${r['journal_entry_id']}',
                          ),
                        if (c.section == 'journals')
                          SelectableText(
                            'Journal ${r['journal_id']} · Account ${r['account_code']}\nLine ${r['source_line_id'] ?? r['id']}',
                          ),
                      ],
                      if (allowJournal &&
                          (r['journal_id'] ?? r['journal_entry_id']) is String)
                        PostedJournalLink(
                          scope: c.scope,
                          journalId:
                              (r['journal_id'] ?? r['journal_entry_id'])
                                  as String,
                          enabled: c.online && !c.busy && c.verified,
                        ),
                    ],
                  ),
                ),
              ),
            if (c.cursor != null)
              action('More rows', () => c.refreshPage(more: true)),
          ],
          const SizedBox(height: 24),
          Text('Saved reports', style: Theme.of(context).textTheme.titleLarge),
          if (c.reports.isEmpty && !c.busy)
            const Text('No saved reports loaded.'),
          for (final r in c.reports)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${r['kind']} · ${r['as_of']} · ${r['branch_name']}'),
                    Text(
                      'Difference ${r['difference']} · Generated ${r['generated_at']}',
                    ),
                    action('Open report', () => c.open(r), enabled: !c.pending),
                  ],
                ),
              ),
            ),
          if (c.reportCursor != null)
            action('More saved reports', () => c.refreshReports(more: true)),
        ],
      );
    },
  );
}

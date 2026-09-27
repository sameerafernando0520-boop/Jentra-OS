import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_providers.dart';
import 'close_review_controller.dart';
import '../report_export/report_export_screen.dart';
import '../journal_evidence/posted_journal_screen.dart';

class CloseReviewScreen extends ConsumerWidget {
  const CloseReviewScreen({super.key});
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
    final c = ref.watch(closeReviewControllerProvider);
    return c == null
        ? const Center(
            child: Text(
              'Choose an entity and branch with finance, control, stock and cost access.',
            ),
          )
        : CloseReviewWorkspace(
            key: ValueKey(c),
            controller: c,
            allowJournal: caps.value?.contains('finance.view') ?? false,
            allowExport:
                caps.value?.contains('finance.reports.export') ?? false,
          );
  }
}

class CloseReviewWorkspace extends StatelessWidget {
  const CloseReviewWorkspace({
    super.key,
    required this.controller,
    this.allowExport = false,
    this.allowJournal = false,
  });
  final CloseReviewController controller;
  final bool allowExport;
  final bool allowJournal;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller, s = c.summary;
      Widget action(String title, VoidCallback fn, {bool enabled = true}) =>
          TextButton(
            onPressed: c.busy || !c.online || !enabled ? null : fn,
            child: Text(title),
          );
      if (c.accessDenied) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Access changed. Entity review evidence has been cleared.',
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
            'Control and close review',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Review every entity branch at one posting cutoff. AR, AP, GRNI, inventory and bank evidence retain their original sources and account basis.',
          ),
          if (c.busy) const LinearProgressIndicator(),
          if (!c.online)
            const Text(
              'Offline — encrypted inputs and sealed requests are retained. Reconnect and refresh access to read evidence.',
            ),
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
                onPressed: c.busy || c.pending ? null : c.newReview,
                child: const Text('New review'),
              ),
              OutlinedButton(
                onPressed: c.busy || c.pending ? null : c.save,
                child: const Text('Save inputs locally'),
              ),
              action('Refresh access', c.initialize),
              action('Saved reviews', c.refreshReports, enabled: c.verified),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('period-${c.form['period_id']}-${c.periods.length}'),
            initialValue: c.periods.any((p) => p['id'] == c.form['period_id'])
                ? c.form['period_id'] as String?
                : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Fiscal period'),
            items: [
              for (final p in c.periods)
                DropdownMenuItem(
                  value: p['id'] as String,
                  child: Text(
                    '${p['name']} · ${p['start_date']} → ${p['end_date']}',
                  ),
                ),
            ],
            onChanged: c.locked || !c.verified
                ? null
                : (v) {
                    if (v != null) c.field('period_id', v);
                  },
          ),
          if (c.periodCursor != null)
            action('More periods', c.morePeriods, enabled: c.verified),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey('cutoff-${c.form['id']}'),
            initialValue: c.form['as_of'] as String?,
            enabled: !c.locked,
            decoration: const InputDecoration(
              labelText: 'Posting cutoff · YYYY-MM-DD',
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
                      c.form['status'] == 'confirmed'
                  ? null
                  : c.generate,
              child: Text(
                c.pending
                    ? 'Retry saved review request'
                    : 'Generate entity review',
              ),
            ),
          ),
          if (c.pending)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'The outcome is uncertain. Retry uses the same encrypted request and cutoff.',
              ),
            ),
          if (c.reports.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Saved reviews',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final r in c.reports)
              ListTile(
                title: Text('${r['entity_name']} · ${r['as_of']}'),
                subtitle: Text(
                  '${r['status']} · ${r['blocker_count']} close blockers · ${r['generated_at']}',
                ),
                onTap: c.busy || !c.verified || c.pending
                    ? null
                    : () => c.open(r),
              ),
          ],
          if (c.reportCursor != null)
            action(
              'More saved reviews',
              () => c.refreshReports(more: true),
              enabled: c.verified,
            ),
          if (s.isNotEmpty) ...[
            if (allowExport)
              ReportExportLink(
                sourceType: 'close',
                sourceId: s['id'] as String,
                section: c.section,
                filters: {'component_key': c.componentKey},
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
                      '${s['entity_name']} · ${s['status']}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${s['period_name']} · cutoff ${s['as_of']} · ${s['branch_count']} entity branches',
                    ),
                    Text(
                      '${s['control_count']} controls · ${s['difference_count']} source differences · ${s['blocker_count']} close blockers',
                    ),
                    SelectableText(
                      'Report ${s['id']} · generated ${s['generated_at']}',
                    ),
                    const Text(
                      'A saved review is evidence. Hard close rechecks current ledgers and permissions.',
                    ),
                  ],
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final section in const [
                  'controls',
                  'differences',
                  'sources',
                  'stock',
                  'transit',
                  'blockers',
                ])
                  ChoiceChip(
                    label: Text(
                      section[0].toUpperCase() + section.substring(1),
                    ),
                    selected: c.section == section,
                    onSelected: c.busy ? null : (_) => c.select(section),
                  ),
                if (c.componentKey != null)
                  action('Show all components', () => c.select(c.section)),
                action('Refresh page', c.refreshPage),
              ],
            ),
            if (c.componentKey != null)
              SelectableText('Component ${c.componentKey}'),
            if (c.rows.isEmpty && !c.busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No evidence in this section at the selected cutoff.',
                ),
              ),
            for (final row in c.rows)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (c.section == 'controls') ...[
                        Text(
                          '${row['name']} · ${row['status']}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (row['status'] == 'unavailable')
                          Text('Check required: ${row['reason']}')
                        else ...[
                          Text(
                            '${row['currency_code']} · source ${row['subledger_value']} · GL ${row['gl_value']} · difference ${row['difference']}',
                          ),
                          Text(
                            '${row['difference_count']} unexplained source differences',
                          ),
                          if (row['kind'] == 'CASH')
                            Text(
                              row['status'] == 'ledger_only'
                                  ? 'Cash ledger balance; no physical count is asserted.'
                                  : 'Statement ${row['statement_closing']} · unmatched bank ${row['unmatched_bank']} · unmatched book ${row['unmatched_book']}',
                            ),
                          for (final a in row['accounts'] as List)
                            SelectableText(
                              '${(a as Map)['code']} · ${a['name']} · ${a['id']}',
                            ),
                        ],
                        Wrap(
                          spacing: 8,
                          children: [
                            action(
                              'Source evidence',
                              () => c.select(
                                'sources',
                                key: row['component_key'] as String,
                              ),
                            ),
                            action(
                              'Differences',
                              () => c.select(
                                'differences',
                                key: row['component_key'] as String,
                              ),
                            ),
                          ],
                        ),
                      ] else if (c.section == 'blockers') ...[
                        Text(
                          '${row['code']}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        for (final k in [
                          'branch_id',
                          'component_key',
                          'reason',
                          'count',
                          'difference',
                          'sqlstate',
                        ])
                          if (row[k] != null)
                            SelectableText('${_evidenceLabel(k)}: ${row[k]}'),
                      ] else if (c.section == 'sources') ...[
                        Text(
                          '${row['origin']} · ${row['source_type']} · ${row['posting_date']}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text('Exact value ${row['value']}'),
                        for (final k in [
                          'component_key',
                          'source_id',
                          'journal_id',
                          'journal_entry_id',
                          'command_id',
                          'receipt_id',
                          'reference',
                        ])
                          if (row[k] != null)
                            SelectableText('${_evidenceLabel(k)}: ${row[k]}'),
                        if (allowJournal &&
                            (row['journal_id'] ?? row['journal_entry_id'])
                                is String)
                          PostedJournalLink(
                            scope: c.scope,
                            journalId:
                                (row['journal_id'] ?? row['journal_entry_id'])
                                    as String,
                            enabled: c.online && !c.busy && c.verified,
                          ),
                      ] else if (c.section == 'differences') ...[
                        SelectableText(
                          '${row['component_key']} · difference ${row['difference']}',
                        ),
                        for (final k in [
                          'evidence_key',
                          'command_id',
                          'source_type',
                          'source_id',
                          'subledger_value',
                          'gl_value',
                        ])
                          if (row[k] != null)
                            SelectableText('${_evidenceLabel(k)}: ${row[k]}'),
                      ] else ...[
                        Text(
                          '${row['product_name']} · ${row['warehouse_name'] ?? row['source_warehouse_name']}',
                        ),
                        Text(
                          'Quantity ${row['quantity']} · carrying value ${row['value']}',
                        ),
                        if (row['destination_warehouse_name'] != null)
                          Text(
                            'In transit to ${row['destination_warehouse_name']}',
                          ),
                        if (row['exception'] != null)
                          Text('Exception ${row['exception']}'),
                        SelectableText('Source ${row['id']}'),
                      ],
                    ],
                  ),
                ),
              ),
            if (c.cursor != null)
              action('More evidence', () => c.refreshPage(more: true)),
          ],
        ],
      );
    },
  );
}

String _evidenceLabel(String key) => switch (key) {
  'branch_id' => 'Branch',
  'component_key' => 'Component',
  'source_id' => 'Source document',
  'source_type' => 'Source type',
  'journal_id' || 'journal_entry_id' => 'Journal',
  'command_id' => 'Command',
  'receipt_id' => 'Receipt',
  'evidence_key' => 'Evidence',
  'subledger_value' => 'Source value',
  'gl_value' => 'GL value',
  'reference' => 'Reference',
  'difference' => 'Difference',
  'reason' => 'Reason',
  'count' => 'Count',
  'sqlstate' => 'Error code',
  _ => key,
};

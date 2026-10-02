import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_platform/jentra_platform.dart';

import '../../app_providers.dart';
import 'bank_reconciliation_controller.dart';
import '../operations/operational_report_export.dart';

class BankReconciliationScreen extends ConsumerWidget {
  const BankReconciliationScreen({super.key});
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
    final c = ref.watch(bankReconciliationControllerProvider);
    return c == null
        ? const Center(child: Text('Choose a branch with finance access.'))
        : BankReconciliationWorkspace(
            key: ValueKey(c),
            controller: c,
            showOperationalReports: true,
          );
  }
}

class BankReconciliationWorkspace extends StatefulWidget {
  const BankReconciliationWorkspace({
    super.key,
    required this.controller,
    this.showOperationalReports = false,
  });
  final BankReconciliationController controller;
  final bool showOperationalReports;
  @override
  State<BankReconciliationWorkspace> createState() => _BankWorkspaceState();
}

class _BankWorkspaceState extends State<BankReconciliationWorkspace> {
  BankReconciliationController get c => widget.controller;
  int previewOffset = 0;
  final reportAsOf = TextEditingController(
    text: DateTime.now().toUtc().toIso8601String().substring(0, 10),
  );
  @override
  void dispose() {
    reportAsOf.dispose();
    super.dispose();
  }

  Future<void> pickFile() async {
    try {
      final file = await const SetupFileService().openImportFile();
      if (file != null && mounted) {
        previewOffset = 0;
        await c.preview(file.bytes, file.extension, file.name);
      }
    } catch (e) {
      if (mounted) {
        c.handle(e);
        c.emit();
      }
    }
  }

  Future<void> confirm(String action, {String? matchId}) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(switch (action) {
          'import' => 'Import this statement?',
          'reverse' => 'Reverse this match?',
          'rules' => 'Save this bank tolerance?',
          _ => 'Confirm bank match?',
        }),
        content: SingleChildScrollView(
          child: Text(switch (action) {
            'import' => 'The complete validated statement is stored without accounting entries.',
            'reverse' => 'The original match remains in history. Its lines become available again and any original adjustment is reversed in the selected open period.',
            'rules' => 'The new exact tolerance applies to later matches. Existing matching evidence does not change.',
            _ => 'Selected statement and posted transaction lines will be claimed together. Any permitted difference posts an exact balanced adjustment.',
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (approved == true && mounted) await c.execute(action, matchId: matchId);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      if (!c.verified || c.denied) {
        return Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  c.error ?? 'Connect to verify current bank access and restore your encrypted draft.',
                ),
                if (c.busy) const CircularProgressIndicator(),
                TextButton(
                  onPressed: c.online && !c.busy ? c.initialize : null,
                  child: const Text('Verify access'),
                ),
              ],
            ),
          ),
        );
      }
      Widget action(
        String title,
        VoidCallback callback, {
        bool enabled = true,
      }) => TextButton(
        onPressed: !c.locked && c.online && enabled ? callback : null,
        child: Text(title),
      );
      final fieldScale = MediaQuery.textScalerOf(context)
          .scale(1)
          .clamp(1.0, 1.7);
      Widget field(String key, String label, {double width = 260}) => SizedBox(
        width: width * fieldScale,
        child: TextFormField(
          key: ValueKey(
            '${c.bankId}-${c.formEpoch}-$key-${c.form['file_name']}',
          ),
          initialValue: c.form[key] as String? ?? '',
          enabled: !c.locked,
          decoration: InputDecoration(labelText: label),
          onChanged: (v) => c.field(key, v),
        ),
      );
      Widget option(String key, String title, String resource) => SizedBox(
        width: 340 * fieldScale,
        child: DropdownButtonFormField<String>(
          key: ValueKey('${c.bankId}-$key-${c.form[key]}'),
          initialValue: c.form[key] as String?,
          isExpanded: true,
          decoration: InputDecoration(labelText: title),
          items: [
            for (final row in c.rows(resource))
              DropdownMenuItem(
                value: row['id'] as String,
                child: Text(
                  resource == 'rates'
                      ? '${row['source_currency_code']} → ${row['target_currency_code']} · ${row['rate']} · ${row['effective_date']}'
                      : '${row['code']} · ${row['name']}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: c.locked ? null : (v) => c.field(key, v ?? ''),
        ),
      );
      Widget source(String resource, String title) {
        final key = resource == 'statement_lines'
            ? 'statement_line_ids'
            : 'journal_line_ids';
        final selected = c.form[key] as List? ?? [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (c.rows(resource).isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('No source lines available.'),
              ),
            for (final row in c.rows(resource))
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: selected.contains(row['id']),
                onChanged:
                    c.locked || row['match_id'] != null || !c.can('match')
                    ? null
                    : (v) =>
                          c.toggle(resource, row['id'] as String, v ?? false),
                title: Text(
                  '${row['reference'] ?? row['document_number']} · ${row['amount']}',
                ),
                subtitle: Text(
                  '${row['posting_date']} · ${row['description'] ?? row['source_type']}${row['match_id'] != null ? ' · Matched' : ''}',
                ),
              ),
            if (c.cursors[resource] != null)
              action('More $title', () => c.page(resource)),
          ],
        );
      }

      final preview = c.form['lines'] as List? ?? [];
      final rules = c
          .rows('accounts')
          .where((r) => r['id'] == c.bankId)
          .firstOrNull?['reconciliation_rules'];
      final tolerance = rules is Map ? rules['tolerance'] : null;
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Bank reconciliation',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Text(
            'Statement imports, posted transactions and reversible matching',
          ),
          SizedBox(height: widget.showOperationalReports ? 12 : 20),
          if (widget.showOperationalReports)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 210,
                  child: TextField(
                    controller: reportAsOf,
                    enabled: c.online && !c.busy,
                    decoration: const InputDecoration(
                      labelText: 'Report as of · YYYY-MM-DD',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                OperationalReportExport(
                  kind: 'bank_reconciliation',
                  label: 'Save branch bank report for export',
                  inputs: {'as_of': reportAsOf.text.trim()},
                ),
              ],
            ),
          if (widget.showOperationalReports) const SizedBox(height: 20),
          if (!c.online)
            const Text(
              'Offline — commands are disabled. Save draft is available.',
            ),
          if (c.busy) const LinearProgressIndicator(),
          if (c.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(c.error!, semanticsLabel: 'Error: ${c.error}'),
            ),
          if (c.message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(c.message!),
            ),
          if (c.pending)
            Wrap(
              spacing: 12,
              children: [
                const Text('A saved command has an uncertain outcome.'),
                TextButton(
                  onPressed: c.online && !c.busy ? c.retry : null,
                  child: const Text('Retry identical request'),
                ),
              ],
            ),
          if (c.local?.errorCode == 'VERSION_CONFLICT')
            TextButton(
              onPressed: !c.busy ? c.resolveConflict : null,
              child: const Text('Refresh sources and resolve conflict'),
            ),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 400 * fieldScale,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('bank-${c.bankId}'),
                  initialValue:
                      c.rows('accounts').any((r) => r['id'] == c.bankId)
                      ? c.bankId
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Bank account'),
                  items: [
                    for (final row in c.rows('accounts'))
                      DropdownMenuItem(
                        value: row['id'] as String,
                        child: Text(
                          '${row['code']} · ${row['name']} · ${row['currency_code']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: c.locked
                      ? null
                      : (v) {
                          if (v != null) c.selectBank(v);
                        },
                ),
              ),
              if (c.cursors['accounts'] != null)
                action('More accounts', () => c.page('accounts')),
              action('Refresh', c.refresh, enabled: c.bankId != null),
              TextButton(
                onPressed: !c.locked ? c.save : null,
                child: const Text('Save encrypted draft'),
              ),
            ],
          ),
          if (c.bankId != null) ...[
            if (c.can('rules')) ...[
              const SizedBox(height: 24),
              Text(
                'Reconciliation rules',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text('Current exact tolerance: ${tolerance ?? '0'}'),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  field('tolerance', 'New exact tolerance'),
                  action('Save tolerance', () => confirm('rules')),
                ],
              ),
            ],
            const SizedBox(height: 24),
            if (c.can('import')) ...[
              Text(
                'Import statement',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'CSV/XLSX columns: date, reference, description, amount. ISO dates; positive inflows, negative outflows; maximum 2,000 rows.',
              ),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  field('identity', 'Statement identity'),
                  field('start_date', 'Start date · YYYY-MM-DD'),
                  field('end_date', 'End date · YYYY-MM-DD'),
                  field('opening', 'Opening balance'),
                  field('closing', 'Closing balance'),
                ],
              ),
              Wrap(
                spacing: 16,
                children: [
                  action('Choose statement file', pickFile),
                  action(
                    'Import statement',
                    () => confirm('import'),
                    enabled: preview.isNotEmpty,
                  ),
                ],
              ),
              if (preview.isNotEmpty) ...[
                Text(
                  '${c.form['file_name']} · ${preview.length} rows · Net ${c.form['total']}',
                ),
                for (final row in preview.skip(previewOffset).take(50))
                  ListTile(
                    dense: true,
                    title: Text(
                      '${row['date']} · ${row['reference']} · ${row['amount']}',
                    ),
                    subtitle: Text('${row['description']}'),
                  ),
                Wrap(
                  children: [
                    if (previewOffset > 0)
                      TextButton(
                        onPressed: () => setState(
                          () => previewOffset = (previewOffset - 50).clamp(
                            0,
                            2000,
                          ),
                        ),
                        child: const Text('Previous preview'),
                      ),
                    if (previewOffset + 50 < preview.length)
                      TextButton(
                        onPressed: () => setState(() => previewOffset += 50),
                        child: const Text('Next preview'),
                      ),
                  ],
                ),
              ],
            ],
            ExpansionTile(
              title: const Text('Imported statements'),
              children: [
                for (final row in c.rows('statements'))
                  ListTile(
                    title: Text(
                      '${row['identity']} · ${row['row_count']} rows',
                    ),
                    subtitle: Text(
                      '${row['start_date']} — ${row['end_date']} · ${row['opening']} + ${row['total']} = ${row['closing']}',
                    ),
                  ),
                if (c.cursors['statements'] != null)
                  action('More statements', () => c.page('statements')),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Match posted transactions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth >= 1100
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: source('statement_lines', 'Statement lines'),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: source('journal_lines', 'Posted transactions'),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        source('statement_lines', 'Statement lines'),
                        source('journal_lines', 'Posted transactions'),
                      ],
                    ),
            ),
            Text(
              'Selected statement ${c.selectedTotal('statement_lines')} · Posted ${c.selectedTotal('journal_lines')} · Difference ${c.selectedTotal('statement_lines') - c.selectedTotal('journal_lines')}',
            ),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                field('posting_date', 'Matching / reversal date'),
                field('reason', 'Reason', width: 400),
              ],
            ),
            if (c.capabilities.contains('finance.bank.adjust')) ...[
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  option(
                    'adjustment_account_id',
                    'Adjustment offset account',
                    'offset_accounts',
                  ),
                  option(
                    'exchange_rate_id',
                    'FX rate for foreign adjustment',
                    'rates',
                  ),
                ],
              ),
              Wrap(
                children: [
                  if (c.cursors['offset_accounts'] != null)
                    action(
                      'More offset accounts',
                      () => c.page('offset_accounts'),
                    ),
                  if (c.cursors['rates'] != null)
                    action('More FX rates', () => c.page('rates')),
                ],
              ),
            ],
            action(
              'Match selected lines',
              () => confirm('match'),
              enabled: c.can('match'),
            ),
            const SizedBox(height: 24),
            Text(
              'Match history',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (c.rows('matches').isEmpty)
              const Text('No matches recorded for this bank.'),
            for (final row in c.rows('matches'))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${row['posting_date']} · ${row['statement_total']} ${row['currency_code']} · Difference ${row['difference']}',
                      ),
                      Text(
                        '${row['reason']} · ${row['reversal'] == null ? 'Matched' : 'Reversed'}',
                      ),
                      ExpansionTile(
                        title: const Text('Source evidence'),
                        children: [
                          SelectableText(
                            'Match ${row['id']}\nStatement lines: ${(row['statement_line_ids'] as List).join(', ')}\nJournal lines: ${(row['journal_line_ids'] as List).join(', ')}\nAdjustment journal: ${row['adjustment_journal_id'] ?? 'None'}\nRecorded by ${row['created_by']} at ${row['created_at']}',
                          ),
                        ],
                      ),
                      if (row['reversal'] == null)
                        action(
                          'Reverse match',
                          () =>
                              confirm('reverse', matchId: row['id'] as String),
                          enabled:
                              c.can('reverse') &&
                              (row['adjustment_journal_id'] == null ||
                                  c.capabilities.contains(
                                    'finance.bank.adjust',
                                  )),
                        ),
                    ],
                  ),
                ),
              ),
            if (c.cursors['matches'] != null)
              action('More matches', () => c.page('matches')),
          ],
        ],
      );
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';

import '../../app_providers.dart';
import 'manual_journal_controller.dart';
import '../operations/operational_read_access.dart';
import '../financial_dimensions/financial_dimension_controller.dart';
import '../financial_dimensions/financial_dimension_screen.dart';

class ManualJournalScreen extends ConsumerWidget {
  const ManualJournalScreen({super.key});
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
    final c = ref.watch(manualJournalControllerProvider);
    return c == null
        ? const Center(
            child: Text(
              'Choose an entity and branch with finance-view permission.',
            ),
          )
        : ManualJournalWorkspace(
            key: ValueKey(c),
            controller: c,
            financialDimensions: ref.watch(financialDimensionGatewayProvider),
          );
  }
}

class ManualJournalWorkspace extends StatelessWidget {
  const ManualJournalWorkspace({
    required this.controller,
    super.key,
    this.financialDimensions,
  });
  final ManualJournalController controller;
  final FinancialDimensionGateway? financialDimensions;
  Future<void> pick(
    BuildContext context,
    String resource,
    void Function(Map<String, Object?>) selected,
  ) async {
    final epoch = controller.readAccessEpoch;
    final r = await showOperationalReadDialog<Map<String, Object?>>(
      context,
      controller,
      (_) => _JournalPicker(controller: controller, resource: resource),
    );
    if (r != null &&
        context.mounted &&
        controller.currentRead(epoch) &&
        !controller.locked) {
      selected(r);
    }
  }

  Future<void> act(BuildContext context, String verb) async {
    if (!['post', 'recall', 'cancel', 'reject'].contains(verb)) {
      await controller.act(verb);
      return;
    }
    final epoch = controller.readAccessEpoch;
    var note = '';
    final result = await showOperationalReadDialog<String>(
      context,
      controller,
      (dialog) => AlertDialog(
        title: Text(
          verb == 'post'
              ? 'Post approved journal?'
              : '${verb[0].toUpperCase()}${verb.substring(1)} journal',
        ),
        content: verb == 'post'
            ? Text(
                'Post ${controller.form?['grand_total']} ${controller.form?['currency_code']} on ${controller.form?['document_date']}? Posted history is immutable; corrections require a linked reversal.',
              )
            : TextField(
                maxLength: 1000,
                onChanged: (v) => note = v,
                decoration: const InputDecoration(labelText: 'Reason'),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, note),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (result != null && context.mounted && controller.currentRead(epoch)) {
      await controller.act(verb, note: result);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller, f = c.form;
      if (c.accessDenied) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Access changed. Encrypted work is retained.'),
              TextButton(
                onPressed: c.busy || !c.online ? null : () => c.refresh(),
                child: const Text('Recheck access'),
              ),
            ],
          ),
        );
      }
      Widget field(String key, String label, {int max = 1000}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          key: ValueKey('${f?['id']}-${f?['version']}-$key'),
          initialValue: f?[key]?.toString() ?? '',
          readOnly: !c.editable,
          maxLength: max,
          decoration: InputDecoration(
            labelText: label,
            counterText: c.editable ? null : '',
          ),
          onChanged: (v) => c.update(key, v),
        ),
      );
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Manual journals',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Balanced journals require independent approval and posting. AR/AP control corrections use their source documents.',
            ),
            if (!c.online)
              const Text('Offline · encrypted local work remains available.'),
            if (c.error != null)
              SelectableText(
                c.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (c.message != null) Text(c.message!),
            if (c.busy) const LinearProgressIndicator(),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (f == null && c.canManage)
                  FilledButton(
                    onPressed: c.locked ? null : () => c.create(),
                    child: const Text('New journal'),
                  ),
                TextButton(
                  onPressed: c.busy || !c.online ? null : () => c.refresh(),
                  child: const Text('Refresh register'),
                ),
                if (f != null) ...[
                  OutlinedButton(
                    onPressed: c.locked ? null : () => c.saveLocal(),
                    child: const Text('Save locally'),
                  ),
                  OutlinedButton(
                    onPressed: c.locked ? null : () => c.close(),
                    child: const Text('Close local copy'),
                  ),
                ],
              ],
            ),
            if (f != null) ...[
              const SizedBox(height: 24),
              SelectableText(
                '${f['document_number'] ?? 'Unnumbered journal'} · ${f['status']} · version ${f['version'] ?? 0}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (f['reversal_of_id'] != null)
                SelectableText(
                  'Reverses ${f['reversal_of_id']} · original amounts are restored by the server.',
                ),
              if (c.local?.pending != null) ...[
                const Text(
                  'Uncertain command sealed. Retry sends the identical request.',
                ),
                FilledButton(
                  onPressed: c.busy || !c.online ? null : () => c.act('retry'),
                  child: const Text('Retry saved command'),
                ),
              ],
              const SizedBox(height: 16),
              field('document_date', 'Posting date · YYYY-MM-DD', max: 10),
              field('description', 'Description'),
              field('reason', 'Reason'),
              Text(
                'Currency ${f['currency_code'] ?? c.baseCurrency} · rate ${f['exchange_rate'] ?? 'Calculated when saved'}',
              ),
              if (c.editable && f['reversal_of_id'] == null)
                Wrap(
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: () {
                        c.update('currency_code', c.baseCurrency);
                        c.update('exchange_rate_id', null);
                      },
                      child: Text('Use ${c.baseCurrency}'),
                    ),
                    TextButton(
                      onPressed: !c.online
                          ? null
                          : () => pick(context, 'rates', (r) {
                              c.update(
                                'currency_code',
                                r['source_currency_code'],
                              );
                              c.update('exchange_rate_id', r['id']);
                            }),
                      child: const Text('Choose exchange rate'),
                    ),
                  ],
                ),
              if (c.editable && f['reversal_of_id'] == null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonal(
                    onPressed: !c.online
                        ? null
                        : () => pick(context, 'accounts', c.addAccount),
                    child: const Text('Add account line'),
                  ),
                ),
              if (c.editable && f['reversal_of_id'] == null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: !c.online
                        ? null
                        : () => pick(context, 'tax_controls', c.addAccount),
                    child: const Text('Add tax-control line'),
                  ),
                ),
              for (var i = 0; i < (f['lines'] as List).length; i++)
                _LineEditor(
                  controller: c,
                  index: i,
                  financialDimensions: financialDimensions,
                ),
              if (f['grand_total'] != null)
                SelectableText(
                  'Saved balanced total ${f['grand_total']} ${f['currency_code']} · base ${f['base_total']} ${f['base_currency_code']}',
                ),
              const SizedBox(height: 16),
              Text(
                'Attachments',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'Select completed entity or branch files from the shared attachment library.',
              ),
              if (c.editable && c.permissions.contains('core.files.view'))
                TextButton(
                  onPressed: !c.online
                      ? null
                      : () => pick(context, 'attachments', c.attachment),
                  child: const Text('Attach existing file'),
                ),
              for (final raw in f['attachments'] as List? ?? [])
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SelectableText('${(raw as Map)['file_name']}'),
                    if (c.editable)
                      TextButton(
                        onPressed: () =>
                            c.removeAttachment(raw['id'] as String),
                        child: const Text('Remove attachment'),
                      ),
                  ],
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (c.editable)
                    FilledButton(
                      onPressed: !c.online ? null : () => c.act('save'),
                      child: const Text('Save journal'),
                    ),
                  if (!c.locked &&
                      c.online &&
                      c.canManage &&
                      f['status'] == 'draft' &&
                      f['version'] != null)
                    FilledButton(
                      onPressed: () => act(context, 'submit'),
                      child: const Text('Submit for approval'),
                    ),
                  if (!c.locked &&
                      c.online &&
                      f['status'] == 'pending_approval' &&
                      c.permissions.contains('workflow.approvals.decide')) ...[
                    FilledButton(
                      onPressed: () => act(context, 'approve'),
                      child: const Text('Approve'),
                    ),
                    OutlinedButton(
                      onPressed: () => act(context, 'reject'),
                      child: const Text('Reject'),
                    ),
                  ],
                  if (!c.locked &&
                      c.online &&
                      c.canManage &&
                      f['status'] == 'approved')
                    FilledButton(
                      onPressed: () => act(context, 'post'),
                      child: const Text('Post journal'),
                    ),
                  if (!c.locked &&
                      c.online &&
                      c.canManage &&
                      [
                        'pending_approval',
                        'approved',
                        'rejected',
                      ].contains(f['status']))
                    OutlinedButton(
                      onPressed: () => act(context, 'recall'),
                      child: const Text('Recall for editing'),
                    ),
                  if (!c.locked &&
                      c.online &&
                      c.canManage &&
                      [
                        'draft',
                        'pending_approval',
                        'approved',
                        'rejected',
                      ].contains(f['status']) &&
                      f['version'] != null)
                    OutlinedButton(
                      onPressed: () => act(context, 'cancel'),
                      child: const Text('Cancel journal'),
                    ),
                  if (!c.locked &&
                      c.canManage &&
                      f['status'] == 'posted' &&
                      f['reversal_of_id'] == null &&
                      f['reversed_by_id'] == null &&
                      c.permissions.contains('finance.reversals.post'))
                    OutlinedButton(
                      onPressed: () => c.reverse(),
                      child: const Text('Prepare linked reversal'),
                    ),
                ],
              ),
              if (f['journal_entry_id'] != null) ...[
                TextButton(
                  onPressed: c.locked || !c.online
                      ? null
                      : () => c.openLinked(f['id'] as String),
                  child: const Text('Refresh source evidence'),
                ),
                if (f['reversal_of_id'] is String)
                  TextButton(
                    onPressed: c.locked || !c.online
                        ? null
                        : () => c.openLinked(f['reversal_of_id'] as String),
                    child: const Text('Open original journal'),
                  ),
                if (f['reversed_by_id'] is String)
                  TextButton(
                    onPressed: c.locked || !c.online
                        ? null
                        : () => c.openLinked(f['reversed_by_id'] as String),
                    child: const Text('Open posted reversal'),
                  ),
                const SizedBox(height: 24),
                Text(
                  'Posted source evidence',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                SelectableText(
                  'Journal ${f['journal_entry_id']} · source ${f['id']}',
                ),
                if (f['reversed_by_id'] != null)
                  SelectableText('Posted reversal ${f['reversed_by_id']}'),
                for (final raw in f['ledger_lines'] as List? ?? [])
                  SelectableText(
                    'Line ${(raw as Map)['line_number']} · source ${raw['source_line_id']} · debit ${raw['base_debit']} · credit ${raw['base_credit']}',
                  ),
              ],
            ],
            const SizedBox(height: 32),
            Text(
              'Journal register',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (c.items.isEmpty) const Text('No journals loaded.'),
            for (final r in c.items)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${r['document_number'] ?? 'Draft'} · ${r['description']}',
                      ),
                      Text(
                        '${r['document_date']} · ${r['status']} · ${r['grand_total']} ${r['currency_code']}',
                      ),
                      TextButton(
                        onPressed: f != null || c.locked || !c.online
                            ? null
                            : () => c.open(r['id'] as String),
                        child: const Text('Open journal'),
                      ),
                    ],
                  ),
                ),
              ),
            if (c.cursor != null)
              TextButton(
                onPressed: c.busy ? null : () => c.refresh(more: true),
                child: const Text('More journals'),
              ),
          ],
        ),
      );
    },
  );
}

class _LineEditor extends StatelessWidget {
  const _LineEditor({
    required this.controller,
    required this.index,
    this.financialDimensions,
  });
  final ManualJournalController controller;
  final FinancialDimensionGateway? financialDimensions;
  final int index;
  @override
  Widget build(BuildContext context) {
    final c = controller, l = (c.form!['lines'] as List)[index] as Map;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${index + 1}. ${l['account_code']} · ${l['account_name']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (c.editable && c.form!['reversal_of_id'] == null)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final k in [
                    'debit',
                    'credit',
                    'description',
                    if (financialDimensions == null) ...[
                      'cost_center',
                      'project',
                    ],
                  ])
                    SizedBox(
                      width: 250,
                      child: TextFormField(
                        key: ValueKey(
                          '${c.form!['id']}-${c.form!['version']}-${l['line_id']}-$k',
                        ),
                        initialValue: l[k]?.toString() ?? '',
                        decoration: InputDecoration(
                          labelText: switch (k) {
                            'cost_center' => 'Cost center',
                            _ => k[0].toUpperCase() + k.substring(1),
                          },
                        ),
                        onChanged: (v) => c.line(index, k, v),
                      ),
                    ),
                  TextButton(
                    onPressed: () => c.removeLine(index),
                    child: const Text('Remove line'),
                  ),
                  if (financialDimensions != null)
                    for (final kind in ['cost_centre', 'project'])
                      FinancialDimensionButton(
                        scope: c.scope,
                        gateway: financialDimensions!,
                        kind: kind,
                        label: kind == 'cost_centre'
                            ? 'Choose cost centre'
                            : 'Choose project tag',
                        enabled: c.online && !c.locked,
                        onSelected: (row) =>
                            c.financialDimension(index, kind, row),
                      ),
                ],
              )
            else
              SelectableText(
                'Debit ${l['debit']} · credit ${l['credit']} · base ${l['base_amount'] ?? 'Calculated when saved'}\n${l['description'] ?? ''} · ${l['cost_center'] ?? ''} · ${l['project'] ?? ''}',
              ),
            if (financialDimensions != null)
              Text(
                'Cost centre: ${l['cost_center'] ?? 'Unassigned'} · Project: ${l['project'] ?? 'Unassigned'}',
              ),
            if (l['tax_definition_id'] != null) ...[
              const SizedBox(height: 12),
              SelectableText(
                '${l['tax_code']} · ${l['tax_kind']} · ${l['tax_rate']}% · definition version ${l['tax_definition_version']}\nTaxable basis ${l['taxable_amount']} ${c.form!['currency_code']} · tax date ${l['tax_basis_date'] ?? c.form!['document_date']}',
              ),
              if (c.editable && c.form!['reversal_of_id'] == null)
                SizedBox(
                  width: 350,
                  child: TextFormField(
                    key: ValueKey(
                      '${l['line_id']}-${l['tax_definition_id']}-taxable',
                    ),
                    initialValue: l['taxable_amount']?.toString() ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Taxable basis · excludes tax',
                    ),
                    onChanged: (value) =>
                        c.line(index, 'taxable_amount', value),
                  ),
                ),
            ],
            if (l['tax_control_movement'] != null && !c.editable)
              SelectableText(
                'Tax-control ${l['tax_control_movement']} · excluded from period tax-accrual totals',
              ),
            if (c.editable &&
                c.form!['reversal_of_id'] == null &&
                l['is_tax_control'] == true)
              SizedBox(
                width: 440,
                child: DropdownButtonFormField<String>(
                  key: ValueKey(
                    '${l['line_id']}-${l['tax_control_movement']}-movement',
                  ),
                  initialValue: l['tax_control_movement'] as String?,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Tax-control movement',
                  ),
                  items: const [
                    DropdownMenuItem<String>(
                      value: null,
                      child: Text('No control movement'),
                    ),
                    DropdownMenuItem(
                      value: 'settlement',
                      child: Text('Recorded settlement'),
                    ),
                    DropdownMenuItem(
                      value: 'adjustment',
                      child: Text('Reviewed adjustment'),
                    ),
                    DropdownMenuItem(
                      value: 'transfer',
                      child: Text('Control transfer'),
                    ),
                  ],
                  onChanged: (value) => c.taxControlMovement(index, value),
                ),
              ),
            if (c.editable && c.form!['reversal_of_id'] == null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: !c.online
                        ? null
                        : () => ManualJournalWorkspace(controller: c).pick(
                            context,
                            'taxes',
                            (definition) => c.taxDefinition(index, definition),
                          ),
                    child: Text(
                      l['tax_definition_id'] == null
                          ? 'Declare tax treatment'
                          : 'Change tax treatment',
                    ),
                  ),
                  if (l['tax_definition_id'] != null)
                    TextButton(
                      onPressed: () => c.taxDefinition(index, null),
                      child: const Text('Remove tax declaration'),
                    ),
                ],
              ),
              const Text(
                'A tax declaration uses the configured rate and taxable basis. It follows journal approval and posting; statutory review remains required.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _JournalPicker extends StatefulWidget {
  const _JournalPicker({required this.controller, required this.resource});
  final ManualJournalController controller;
  final String resource;
  @override
  State<_JournalPicker> createState() => _JournalPickerState();
}

class _JournalPickerState extends State<_JournalPicker> {
  List<Map<String, Object?>> rows = [];
  String? cursor, error;
  String search = '';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool more = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await widget.controller.options(
        widget.resource,
        after: more ? cursor : null,
        search: search,
      );
      if (!mounted) return;
      setState(() {
        rows = [
          if (more) ...rows,
          for (final x in r['items'] as List)
            (x as Map).cast<String, Object?>(),
        ];
        cursor = r['next_cursor'] as String?;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not load choices. Retry after checking access.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(switch (widget.resource) {
      'tax_controls' => 'Choose a tax-control account',
      'taxes' => 'Choose tax treatment',
      _ => 'Choose ${widget.resource}',
    }),
    content: SizedBox(
      width: 600,
      height: 430,
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(labelText: 'Search'),
            maxLength: 100,
            onChanged: (v) => search = v,
            onSubmitted: (_) => load(),
          ),
          TextButton(
            onPressed: busy ? null : () => load(),
            child: const Text('Search / refresh'),
          ),
          if (error != null) Text(error!),
          if (busy) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              children: [
                for (final r in rows)
                  ListTile(
                    title: Text(
                      widget.resource == 'rates'
                          ? '${r['source_currency_code']} → ${r['target_currency_code']} · ${r['rate']} · ${r['effective_date']}'
                          : widget.resource == 'taxes'
                          ? '${r['code']} · ${r['name']} · ${r['kind']} · ${r['rate']}%'
                          : r['file_name']?.toString() ??
                                '${r['code']} · ${r['name']}',
                    ),
                    onTap: () => Navigator.pop(context, r),
                  ),
                if (cursor != null)
                  TextButton(
                    onPressed: busy ? null : () => load(more: true),
                    child: const Text('More choices'),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Back'),
      ),
    ],
  );
}

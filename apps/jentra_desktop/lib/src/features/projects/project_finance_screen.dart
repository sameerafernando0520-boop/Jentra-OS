import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_domain/jentra_projects.dart';
import 'package:jentra_domain/jentra_project_finance.dart';

import 'project_finance_controller.dart';

final class ProjectFinanceScreen extends ConsumerStatefulWidget {
  const ProjectFinanceScreen({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.currency,
    required this.precision,
    this.controller,
  });
  final String projectId, projectName, currency;
  final int precision;
  final ProjectFinanceController? controller;
  @override
  ConsumerState<ProjectFinanceScreen> createState() =>
      _ProjectFinanceScreenState();
}

final class _ProjectFinanceScreenState
    extends ConsumerState<ProjectFinanceScreen> {
  Future<ProjectFinanceChoice?> _choice(
    ProjectFinanceController c,
    String kind,
    String title,
  ) async {
    return showDialog<ProjectFinanceChoice>(
      context: context,
      builder: (context) =>
          _FinanceChoiceDialog(c: c, kind: kind, title: title),
    );
  }

  Future<void> _select(
    ProjectFinanceController c,
    String field,
    String kind,
    String title,
  ) async {
    final value = await _choice(c, kind, title);
    if (value != null && mounted && c.current) {
      c.choose(field, value);
    }
  }

  Future<void> _task(ProjectFinanceController c) async {
    final task = await _choice(c, 'tasks', 'Allocate to an approved task');
    if (task == null || !mounted || !c.current) {
      return;
    }
    final weight = await _text(
      'Allocation weight',
      'Positive whole-number weight',
      '1',
    );
    if (weight != null && mounted && c.current) {
      c.allocate(task.id, int.parse(weight), task.name);
    }
  }

  Future<String?> _text(String title, String label, String initial) async {
    final edit = TextEditingController(text: initial);
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: edit,
            autofocus: true,
            decoration: InputDecoration(labelText: label),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, edit.text),
              child: const Text('Use value'),
            ),
          ],
        ),
      );
    } finally {
      edit.dispose();
    }
  }

  Future<void> _unit(ProjectFinanceController c) async {
    try {
      final unit = await showDialog<ProjectFinanceRow>(
        context: context,
        builder: (context) => _FinanceUnitDialog(c: c),
      );
      if (unit == null || !mounted || !c.current) {
        return;
      }
      final product = await _choice(
        c,
        'products',
        'Select the sales service product',
      );
      if (product == null || !mounted || !c.current) {
        return;
      }
      final taxable = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Output tax basis'),
          content: const Text(
            'Use an active published output tax definition, or explicitly omit tax for this synthetic line.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No tax'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Choose tax'),
            ),
          ],
        ),
      );
      if (taxable == null || !mounted || !c.current) {
        return;
      }
      final tax = taxable
          ? await _choice(c, 'output_tax', 'Select output tax')
          : null;
      if (taxable && tax == null) {
        return;
      }
      final description = await _text(
        'Invoice line description',
        'Description',
        unit.title,
      );
      if (description != null && mounted && c.current) {
        c.bill(unit, product, tax, description);
      }
    } on DomainError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This approved billing source could not be selected.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _margin(ProjectFinanceController c) async {
    final asOf = TextEditingController(
      text: DateTime.now().toUtc().toIso8601String(),
    );
    final date = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10),
    );
    try {
      final selected = await showDialog<(DateTime, CivilDate)>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Margin reporting dates'),
              content: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: asOf,
                      decoration: const InputDecoration(
                        labelText: 'Recorded as of (UTC ISO date and time)',
                      ),
                    ),
                    TextField(
                      controller: date,
                      decoration: const InputDecoration(
                        labelText: 'Effective through (YYYY-MM-DD)',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    try {
                      final instant = DateTime.parse(asOf.text);
                      if (!instant.isUtc ||
                          instant.isAfter(DateTime.now().toUtc())) {
                        throw const FormatException(
                          'Use a past UTC timestamp ending in Z.',
                        );
                      }
                      Navigator.pop(context, (
                        instant,
                        CivilDate.parse(date.text),
                      ));
                    } catch (_) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Use a past UTC timestamp ending in Z and a valid effective date.',
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text('Load margin'),
                ),
              ],
            );
          },
        ),
      );
      if (selected != null && mounted && c.current) {
        await c.loadMargin(selected.$1, selected.$2);
      }
    } finally {
      asOf.dispose();
      date.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c =
        widget.controller ??
        ref.watch(
          projectFinanceControllerProvider((
            widget.projectId,
            widget.currency,
            widget.precision,
          )),
        );
    if (c == null) {
      return const Center(
        child: Text('Select an authorized project finance scope.'),
      );
    }
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => FocusTraversalGroup(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Project finance · ${widget.projectName}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'Synthetic development. Recorded reimbursement settlement does not execute a bank payment. Supplier AP and protected expense attachments are unavailable.',
            ),
            if (c.busy) const LinearProgressIndicator(),
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  c.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (c.message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(c.message!),
              ),
            if (c.denied)
              const Text('Finance data cleared because access changed.')
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final section in ProjectFinanceSection.values)
                    if (c.has(c.cap(section)))
                      ChoiceChip(
                        label: Text(_label(section)),
                        selected: c.section == section,
                        onSelected: c.busy ? null : (_) => c.load(section),
                      ),
                  OutlinedButton(
                    onPressed: c.busy ? null : () => c.load(c.section),
                    child: const Text('Refresh'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (c.has('projects.expenses.manage'))
                    FilledButton(
                      onPressed: c.locked
                          ? null
                          : () => c.begin('expense_create'),
                      child: const Text('New expense'),
                    ),
                  if (c.has('projects.billing.manage'))
                    FilledButton(
                      onPressed: c.locked
                          ? null
                          : () => c.begin('billing_prepare'),
                      child: const Text('Prepare invoice'),
                    ),
                  if (c.has('projects.billing.manage') &&
                      c.has('service.billing'))
                    OutlinedButton(
                      onPressed: c.locked
                          ? null
                          : () => c.begin('service_source'),
                      child: const Text('Import approved service labor'),
                    ),
                  if (c.has('projects.margin.view'))
                    OutlinedButton(
                      onPressed: c.busy
                          ? null
                          : () => c.loadMargin(
                              DateTime.now().toUtc(),
                              CivilDate.parse(
                                DateTime.now().toIso8601String().substring(
                                  0,
                                  10,
                                ),
                              ),
                            ),
                      child: const Text('Current margin'),
                    ),
                  if (c.has('projects.margin.view'))
                    OutlinedButton(
                      onPressed: c.busy ? null : () => _margin(c),
                      child: const Text('Margin as of…'),
                    ),
                ],
              ),
              if (c.report != null) ...[
                const SizedBox(height: 16),
                Text(
                  'As of ${c.report!.asOf.toIso8601String()} · effective ${c.report!.effectiveDate.value}',
                ),
                Wrap(
                  spacing: 20,
                  runSpacing: 12,
                  children: [
                    for (final e in c.report!.values.entries)
                      SizedBox(
                        width: 245,
                        child: Text(
                          '${e.key.replaceAll('_', ' ')}\n${e.value.toDecimalString()} ${c.report!.currency}',
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              if (c.rows.isEmpty && !c.busy)
                const Text('No records in this finance view.'),
              for (final row in c.rows) _row(c, row),
              if (c.next != null)
                TextButton(
                  onPressed: c.busy ? null : c.more,
                  child: const Text('Load more records'),
                ),
              if (c.form != null) _form(c),
              if (c.recovery.isNotEmpty) ...[
                const Divider(height: 32),
                Text(
                  'Encrypted recovery',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                for (final saved in c.recovery)
                  ListTile(
                    title: Text(saved.action.replaceAll('_', ' ')),
                    subtitle: Text(
                      saved.draft.pending != null
                          ? 'Original sealed request awaiting reconciliation'
                          : 'Saved form · version ${saved.draft.version}',
                    ),
                    trailing: OutlinedButton(
                      onPressed: c.busy ? null : () => c.resume(saved),
                      child: const Text('Resume'),
                    ),
                  ),
              ],
              for (final entry in c.recoveryCursors.entries)
                if (entry.value != null)
                  TextButton(
                    onPressed: c.busy ? null : () => c.moreRecovery(entry.key),
                    child: Text('More saved ${entry.key.replaceAll('_', ' ')}'),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  String _label(ProjectFinanceSection s) => switch (s) {
    ProjectFinanceSection.obligations => 'Reimbursements',
    ProjectFinanceSection.billing => 'Invoices',
    ProjectFinanceSection.units => 'Billing sources',
    _ => s.name[0].toUpperCase() + s.name.substring(1),
  };
  Widget _row(ProjectFinanceController c, ProjectFinanceRow row) {
    final actions = <String>[];
    if (row.section == ProjectFinanceSection.expenses) {
      if ({'draft', 'rejected'}.contains(row.status)) {
        actions.addAll(['expense_correct', 'expense_submit', 'expense_cancel']);
      }
      if (row.status == 'submitted') {
        actions.addAll(['expense_approve', 'expense_reject']);
      }
      if (row.status == 'approved') {
        actions.add('expense_post');
      }
      if (row.status == 'posted') {
        actions.add('expense_reverse');
      }
    }
    if (row.section == ProjectFinanceSection.obligations &&
        row.status == 'outstanding') {
      actions.add('settle');
    }
    if (row.section == ProjectFinanceSection.settlements &&
        row.status == 'recorded') {
      actions.add('settlement_reverse');
    }
    if (row.section == ProjectFinanceSection.billing &&
        row.status == 'prepared') {
      final status = row.values['invoice_status'];
      if (status == 'draft') {
        actions.add('billing_submit');
      }
      if (status == 'submitted') {
        actions.add('billing_decide');
      }
      if (status == 'approved') {
        actions.add('billing_post');
      }
      actions.add('billing_cancel');
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(row.title, style: Theme.of(context).textTheme.titleMedium),
            Text(
              '${row.status} · version ${row.version}${row.amount == null ? '' : ' · ${row.amount!.toDecimalString()} ${row.amount!.currencyCode}'}',
            ),
            if (row.section == ProjectFinanceSection.expenses)
              Text(
                '${row.values['employee_name']} · ${row.values['service_date']} · ${row.values['external_reference']}',
              ),
            if (row.section == ProjectFinanceSection.history)
              Text('${row.values['action']} · ${row.values['recorded_at']}'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in actions)
                  if (c.has(projectFinanceCapability(a)))
                    OutlinedButton(
                      onPressed: c.locked ? null : () => c.begin(a, row: row),
                      child: Text(a.replaceAll('_', ' ')),
                    ),
              ],
            ),
            if (row.section == ProjectFinanceSection.expenses)
              ExpansionTile(
                title: const Text('Original tax, FX and allocation evidence'),
                children: [
                  for (final k in [
                    'evidence_reference',
                    'original_currency',
                    'net',
                    'tax',
                    'gross',
                    'base_net',
                    'base_tax',
                    'base_gross',
                    'tax_rounding_residue',
                    'no_tax_reason',
                    'tax_basis',
                    'fx_basis',
                    'fx_numerator',
                    'fx_denominator',
                  ])
                    if (row.values[k] != null)
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: SelectableText(
                          '${k.replaceAll('_', ' ')}: ${row.values[k]}',
                        ),
                      ),
                  for (final a in (row.values['allocations'] as List).map(
                    projectMap,
                  ))
                    Text(
                      '${a['task_name']} · weight ${a['weight']} · ${a['amount']} ${c.currency}',
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    ProjectFinanceController c,
    String key,
    String title, {
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      key: ValueKey('${c.action}:${c.form!['id']}:$key'),
      initialValue: c.form![key]?.toString() ?? '',
      enabled: !c.locked,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: title,
        border: const OutlineInputBorder(),
      ),
      onChanged: (v) => c.change(key, v),
    ),
  );
  Widget _pick(
    ProjectFinanceController c,
    String field,
    String kind,
    String title,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: OutlinedButton(
      onPressed: c.locked ? null : () => _select(c, field, kind, title),
      child: Text(
        '$title${c.form![field] == null ? '' : ' · ${c.labels[c.form![field]] ?? 'Original frozen selection'}'}',
      ),
    ),
  );
  Widget _form(ProjectFinanceController c) {
    final a = c.action!, p = c.form!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              a.replaceAll('_', ' '),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text('Expected version ${c.expectedVersion} · ${c.currency}'),
            const SizedBox(height: 16),
            if (c.review != null) ...[
              Text(
                'Original source: ${c.review!.title} · ${c.review!.status} · version ${c.review!.version}',
              ),
              if (c.review!.amount != null)
                Text(
                  '${c.review!.amount!.toDecimalString()} ${c.review!.amount!.currencyCode}',
                ),
              if (c.review!.section == ProjectFinanceSection.expenses)
                Text(
                  'Original ${c.review!.values['net']} + tax ${c.review!.values['tax']} = ${c.review!.values['gross']} ${c.review!.values['original_currency']} · evidence ${c.review!.values['evidence_reference']}',
                ),
              const SizedBox(height: 12),
            ],
            if (a == 'service_source')
              _pick(
                c,
                'service_source_id',
                'service_sources',
                'Approved service labor',
              ),
            if (c.review?.section == ProjectFinanceSection.expenses) ...[
              for (final k in [
                'base_net',
                'base_tax',
                'base_gross',
                'tax_rounding_residue',
                'no_tax_reason',
                'tax_basis',
                'fx_basis',
                'fx_numerator',
                'fx_denominator',
                'bill_amount',
              ])
                if (c.review!.values[k] != null)
                  Text('${k.replaceAll('_', ' ')}: ${c.review!.values[k]}'),
              for (final allocation
                  in (c.review!.values['allocations'] as List).map(projectMap))
                Text(
                  '${allocation['task_name']} · weight ${allocation['weight']} · ${allocation['amount']} ${c.currency}',
                ),
            ],
            if (a == 'expense_create' || a == 'expense_correct') ...[
              _pick(c, 'employee_id', 'employees', 'Employee'),
              _field(c, 'external_reference', 'Original external reference'),
              _field(c, 'service_date', 'Service date YYYY-MM-DD'),
              _field(c, 'purpose', 'Purpose', lines: 2),
              _field(c, 'evidence_reference', 'Synthetic evidence reference'),
              _field(c, 'original_currency', 'Original currency'),
              _field(c, 'net', 'Original net'),
              _field(c, 'tax', 'Original tax'),
              _field(c, 'gross', 'Original gross'),
              _pick(
                c,
                'tax_definition_id',
                'input_tax',
                'Input tax definition',
              ),
              if (p['tax_definition_id'] == null)
                _field(c, 'no_tax_reason', 'Explicit no-tax reason'),
              _pick(c, 'exchange_rate_id', 'rates', 'Dated exchange rate'),
              _pick(
                c,
                'expense_account_id',
                'expense_accounts',
                'Expense posting account',
              ),
              _pick(c, 'tax_account_id', 'tax_accounts', 'Tax posting account'),
              _pick(
                c,
                'liability_account_id',
                'liability_accounts',
                'Reimbursement liability account',
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: p['billable'] == true,
                onChanged: c.locked ? null : (v) => c.change('billable', v),
                title: const Text('Approved expense may be billed'),
              ),
              _field(c, 'bill_amount', 'Project billing amount'),
              for (final v in (p['allocations'] as List).map(projectMap))
                ListTile(
                  title: Text(
                    c.labels[v['task_id']] ?? 'Original approved task',
                  ),
                  subtitle: Text('Weight ${v['weight']}'),
                  trailing: IconButton(
                    tooltip: 'Remove allocation',
                    onPressed: c.locked
                        ? null
                        : () => c.removeAllocation(v['task_id'] as String),
                    icon: const Icon(Icons.close),
                  ),
                ),
              OutlinedButton(
                onPressed: c.locked ? null : () => _task(c),
                child: const Text('Add named task allocation'),
              ),
            ],
            if (p.containsKey('posting_date'))
              _field(c, 'posting_date', 'Posting date YYYY-MM-DD'),
            if (a == 'settle') ...[
              _field(c, 'amount', 'Recorded settlement amount'),
              _pick(c, 'bank_id', 'banks', 'Named bank/cash account'),
              _field(c, 'evidence_reference', 'Recorded settlement evidence'),
            ],
            if (a == 'billing_prepare') ...[
              _field(c, 'document_date', 'Invoice date YYYY-MM-DD'),
              _field(c, 'due_date', 'Due date YYYY-MM-DD'),
              _pick(c, 'exchange_rate_id', 'rates', 'Invoice exchange rate'),
              for (final v in (p['units'] as List).map(projectMap))
                ListTile(
                  title: Text(v['description'] as String),
                  subtitle: Text(
                    'Whole source version ${v['source_version']} · ${c.labels[v['product_id']] ?? 'Original sales product'}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove billing source',
                    onPressed: c.locked
                        ? null
                        : () => c.removeUnit(v['unit_id'] as String),
                    icon: const Icon(Icons.close),
                  ),
                ),
              OutlinedButton(
                onPressed: c.locked ? null : () => _unit(c),
                child: const Text('Add whole approved billing source'),
              ),
            ],
            if (a == 'billing_decide')
              Wrap(
                spacing: 8,
                children: [
                  for (final decision in ['approved', 'rejected'])
                    ChoiceChip(
                      label: Text(decision),
                      selected: p['decision'] == decision,
                      onSelected: c.locked
                          ? null
                          : (_) => c.change('decision', decision),
                    ),
                ],
              ),
            _field(c, 'reason', 'Attributable reason', lines: 2),
            if (c.pending != null)
              const Text(
                'This original request is sealed. Editing remains locked until its result is reconciled.',
              ),
            if (c.conflict)
              const Text(
                'The source changed. Compare its current state before replacing the saved version.',
              ),
            if (c.comparison != null)
              Text(
                'Current source: ${c.comparison!.status} · version ${c.comparison!.version} · ${c.comparison!.amount?.toDecimalString() ?? ''}',
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (c.confirmed == null) ...[
                  OutlinedButton(
                    onPressed: c.locked ? null : c.save,
                    child: const Text('Save encrypted draft'),
                  ),
                  FilledButton(
                    onPressed: c.busy || c.conflict || !c.online
                        ? null
                        : c.send,
                    child: Text(
                      c.pending == null
                          ? 'Send finance command'
                          : 'Retry exact request',
                    ),
                  ),
                  if (c.pending != null)
                    OutlinedButton(
                      onPressed: c.busy || !c.online ? null : c.reconcile,
                      child: const Text('Reconcile original receipt'),
                    ),
                  if (c.conflict)
                    OutlinedButton(
                      onPressed: c.busy ? null : c.compare,
                      child: const Text('Compare current source'),
                    ),
                  if (c.comparison != null)
                    OutlinedButton(
                      onPressed: c.busy ? null : c.replace,
                      child: const Text('Replace saved version'),
                    ),
                ],
                TextButton(
                  onPressed: c.pending != null || c.conflict
                      ? null
                      : c.closeForm,
                  child: Text(
                    c.confirmed == null
                        ? 'Close form'
                        : 'Close confirmed result',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class _FinanceUnitDialog extends StatefulWidget {
  const _FinanceUnitDialog({required this.c});
  final ProjectFinanceController c;
  @override
  State<_FinanceUnitDialog> createState() => _FinanceUnitDialogState();
}

final class _FinanceUnitDialogState extends State<_FinanceUnitDialog> {
  List<ProjectFinanceRow> rows = [];
  String? next, error;
  String search = '';
  bool busy = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    setState(() => busy = true);
    try {
      final page = await widget.c.unitChoices(after: more ? next : null);
      if (mounted && widget.c.current) {
        setState(() {
          rows = [if (more) ...rows, ...page.rows];
          next = page.nextAfter;
          error = null;
        });
      }
    } on DomainError catch (e) {
      if (mounted) {
        setState(() {
          rows = [];
          error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Approved billing sources are unavailable.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Select a whole approved source'),
    content: SizedBox(
      width: 600,
      height: 400,
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(
              labelText: 'Filter loaded source names',
            ),
            onChanged: (value) => setState(() => search = value.toLowerCase()),
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          Expanded(
            child: ListView(
              children: [
                for (final row in rows.where(
                  (r) =>
                      r.status == 'available' &&
                      r.title.toLowerCase().contains(search),
                ))
                  ListTile(
                    title: Text(row.title),
                    subtitle: Text(
                      '${row.amount!.toDecimalString()} ${widget.c.currency} · revision ${row.version}${row.values['payable_seconds'] == null ? '' : ' · ${row.values['payable_seconds']} seconds'}',
                    ),
                    onTap: widget.c.current
                        ? () => Navigator.pop(context, row)
                        : null,
                  ),
                if (!busy && rows.where((r) => r.status == 'available').isEmpty)
                  const Text(
                    'No available approved sources on the loaded pages.',
                  ),
                if (next != null)
                  TextButton(
                    onPressed: busy ? null : () => _load(more: true),
                    child: const Text('Load more approved sources'),
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
        child: const Text('Cancel'),
      ),
    ],
  );
}

final class _FinanceChoiceDialog extends StatefulWidget {
  const _FinanceChoiceDialog({
    required this.c,
    required this.kind,
    required this.title,
  });
  final ProjectFinanceController c;
  final String kind, title;
  @override
  State<_FinanceChoiceDialog> createState() => _FinanceChoiceDialogState();
}

final class _FinanceChoiceDialogState extends State<_FinanceChoiceDialog> {
  List<ProjectFinanceChoice> rows = [];
  String? next, error;
  String search = '';
  bool busy = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    setState(() => busy = true);
    try {
      final page = await widget.c.choices(
        widget.kind,
        after: more ? next : null,
      );
      if (mounted) {
        setState(() {
          rows = [if (more) ...rows, ...page.rows];
          next = page.nextAfter;
          error = null;
        });
      }
    } on DomainError catch (e) {
      if (mounted) {
        setState(() => error = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'The named finance choices are unavailable.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 600,
      height: 400,
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(
              labelText: 'Filter loaded names or codes',
            ),
            onChanged: (v) => setState(() => search = v.toLowerCase()),
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          Expanded(
            child: ListView(
              children: [
                for (final row in rows.where(
                  (r) => '${r.name} ${r.code}'.toLowerCase().contains(search),
                ))
                  ListTile(
                    title: Text(row.name),
                    subtitle: Text('${row.code} · version ${row.version}'),
                    onTap: widget.c.current
                        ? () => Navigator.pop(context, row)
                        : null,
                  ),
                if (rows.isEmpty && !busy)
                  const Text('No active named choices in this scope.'),
                if (next != null)
                  TextButton(
                    onPressed: busy ? null : () => _load(more: true),
                    child: const Text('Load more choices'),
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
        child: const Text('Cancel'),
      ),
    ],
  );
}

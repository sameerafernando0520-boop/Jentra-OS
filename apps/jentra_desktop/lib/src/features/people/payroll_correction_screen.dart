import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_domain/jentra_payroll.dart';

import 'payroll_correction_controller.dart';

class PayrollCorrectionScreen extends ConsumerWidget {
  const PayrollCorrectionScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(payrollCorrectionControllerProvider);
    if (c == null) {
      return const Center(
        child: Text(
          'Choose an entity and branch with payroll correction access.',
        ),
      );
    }
    return PayrollCorrectionWorkspace(controller: c);
  }
}

class PayrollCorrectionWorkspace extends StatelessWidget {
  const PayrollCorrectionWorkspace({required this.controller, super.key});
  final PayrollCorrectionController controller;
  Future<void> _edit(BuildContext context, Future<void> action) async {
    await action;
    if (!context.mounted || controller.form == null) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PayrollCorrectionEditor(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final c = controller;
      if (c.denied) {
        return const Center(
          child: Text(
            'Payroll correction access changed. Re-select the current scope.',
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Synthetic payroll corrections',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const Text(
            'Linked source changes reproduce original rules and record signed off-cycle differences. Recorded settlements do not execute bank payments.',
          ),
          if (c.error != null)
            Text(
              c.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (c.message != null) Text(c.message!),
          if (c.busy) const LinearProgressIndicator(),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: c.busy ? null : () => c.refresh(),
                child: const Text('Refresh corrections'),
              ),
              if (c.has('people.payroll.correction.prepare'))
                FilledButton(
                  onPressed: c.busy || !c.online
                      ? null
                      : () => _edit(context, c.beginPrepare()),
                  child: const Text('Prepare linked correction'),
                ),
            ],
          ),
          for (final saved in c.recovery)
            ListTile(
              title: Text(
                saved.expired
                    ? 'Expired correction receipt'
                    : 'Saved correction request',
              ),
              subtitle: Text(saved.capability),
              trailing: TextButton(
                onPressed: c.busy
                    ? null
                    : () => _edit(context, c.resume(saved)),
                child: const Text('Resolve'),
              ),
            ),
          if (c.rows.isEmpty && !c.busy)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No corrections in this scope.'),
            ),
          for (final row in c.rows)
            Card(
              child: ListTile(
                title: Text('${row['posting_date']} · ${row['status']}'),
                subtitle: Text(
                  '${row['currency_code']} · original calculation ${row['original_calculation_id']}',
                ),
                selected: c.selected?['id'] == row['id'],
                onTap: c.busy ? null : () => c.open(row, 'calculation'),
              ),
            ),
          if (c.cursor != null)
            TextButton(
              onPressed: c.busy ? null : () => c.refresh(more: true),
              child: const Text('More corrections'),
            ),
          if (c.selected != null) ...[
            const Divider(),
            Text(
              'Correction review · ${c.selected!['status']}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final action in [
                  'approve',
                  'reject',
                  'post',
                  'reverse',
                  'record',
                ])
                  if (c.canAction(action))
                    OutlinedButton(
                      onPressed: c.busy || !c.online
                          ? null
                          : () => _edit(context, c.beginAction(action)),
                      child: Text(switch (action) {
                        'approve' => 'Approve independently',
                        'reject' => 'Reject proposal',
                        'post' => 'Post off-cycle difference',
                        'reverse' => 'Reverse original difference',
                        _ => 'Record settlement or recovery',
                      }),
                    ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final section in [
                  'calculation',
                  'sources',
                  'history',
                  if (c.has('people.payroll.settle')) 'balances',
                  if (c.has('people.payroll.settle')) 'settlements',
                  if (c.has('people.payroll.payslip.view')) 'payslip',
                ])
                  TextButton(
                    onPressed: c.busy
                        ? null
                        : () => c.open(c.selected!, section),
                    child: Text(section),
                  ),
              ],
            ),
            if (c.detail != null) ...[
              for (final value in c.detail!['items'] as List)
                _review(
                  context,
                  workforceMap(value),
                  c.detail!['section'] as String,
                ),
              if (c.detail!['next_cursor'] != null)
                TextButton(
                  onPressed: c.busy
                      ? null
                      : () => c.open(
                          c.selected!,
                          c.detail!['section'] as String,
                          more: true,
                        ),
                  child: const Text('More review evidence'),
                ),
            ],
          ],
        ],
      );
    },
  );
  Widget _review(
    BuildContext context,
    Map<String, Object?> row,
    String section,
  ) {
    if (section == 'calculation') {
      return _amounts(context, row);
    }
    if (section == 'settlements') {
      return Card(
        child: ListTile(
          title: Text(
            '${row['direction']} · ${row['posting_date']} · ${row['status']}',
          ),
          subtitle: Text('${row['evidence_reference']}'),
          trailing: controller.canAction('settlement_reverse', settlement: row)
              ? TextButton(
                  onPressed: () => _edit(
                    context,
                    controller.beginAction(
                      'settlement_reverse',
                      settlement: row,
                    ),
                  ),
                  child: const Text('Reverse settlement'),
                )
              : null,
        ),
      );
    }
    if (section == 'balances') {
      return Card(
        child: ListTile(
          title: Text(
            '${row['kind']} · ${row['outstanding']} ${row['currency_code']}',
          ),
          subtitle: Text('Original signed difference ${row['amount']}'),
        ),
      );
    }
    if (section == 'sources') {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${row['source_kind']} · ${row['before_seconds']} → ${row['after_seconds']} paid seconds',
              ),
              if (row['impact'] != null) ...[
                const Text('Operational source impact'),
                Text('${workforceMap(row['impact'])['mode']}'),
                const Text('Before'),
                _facts(workforceMap(row['impact'])['before']),
                const Text('After'),
                _facts(workforceMap(row['impact'])['after']),
                for (final value
                    in workforceMap(
                              workforceMap(row['impact'])['after'],
                            )['allocation_impacts']
                            as List? ??
                        const [])
                  Builder(
                    builder: (context) {
                      final allocation = workforceMap(value),
                          impact = workforceMap(allocation['impact']);
                      final before = workforceMap(impact['before']);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Linked ${allocation['source_kind']} · ${impact['project_name'] ?? before['project_name'] ?? impact['order_name'] ?? 'approved work'}',
                          ),
                          const Text('Original linked basis'),
                          _facts(impact['before']),
                          const Text('Revised linked basis'),
                          _facts(impact['after']),
                        ],
                      );
                    },
                  ),
              ],
            ],
          ),
        ),
      );
    }
    if (section == 'payslip') {
      final p = workforceMap(row['payload']);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${p['employee_name']} · ${p['employee_code']} · ${p['start_date']} → ${p['end_date_exclusive']}',
          ),
          _amounts(context, p),
        ],
      );
    }
    return Card(
      child: ListTile(
        title: Text('${row['action']} · version ${row['version']}'),
        subtitle: Text('${row['recorded_at']} · ${row['reason']}'),
      ),
    );
  }

  static Widget _facts(Object? value) {
    if (value is! Map) {
      return const SizedBox.shrink();
    }
    final data = {
      if (value['revision'] is Map) ...workforceMap(value['revision']),
      ...workforceMap(value),
    };
    const labels = {
      'start_local': 'Start local',
      'end_local': 'End local',
      'status': 'Status',
      'charge_seconds': 'Leave charged seconds',
      'payable_seconds': 'Worked paid seconds',
      'seconds': 'Worked paid seconds',
      'unpaid_seconds': 'Unpaid leave seconds',
      'balance_version': 'Leave balance version',
      'cost_rate': 'Original cost per hour',
      'hourly_cost': 'Original cost per hour',
      'hourly_billing': 'Original bill per hour',
      'amount': 'Internal cost',
      'cost_amount': 'Internal cost',
      'billable_amount': 'Customer bill amount',
      'bill_amount': 'Customer bill amount',
    };
    final effects = (data['effects'] ?? data['original_effects']) as List?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in labels.entries)
          if (data.containsKey(entry.key))
            Text('${entry.value}: ${data[entry.key]}'),
        if (data['breaks'] is List)
          Text('Unpaid breaks: ${(data['breaks'] as List).length}'),
        if (effects != null)
          Text(
            'Original grant debit effects: ${effects.length} · ${effects.map(workforceMap).fold<int>(0, (total, row) => total + (row['seconds'] as num).toInt()).abs()} seconds',
          ),
      ],
    );
  }

  static Widget _amounts(
    BuildContext context,
    Map<String, Object?> row,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final key in ['gross', 'deductions', 'employer_cost', 'net'])
            Text(
              '$key: ${workforceMap(row['before'])[key]} → ${workforceMap(row['after'])[key]} · difference ${workforceMap(row['difference'])[key]}',
            ),
          for (final line
              in (workforceMap(row['difference'])['lines'] as List? ??
                  const []))
            Text(
              '${workforceMap(line)['code']} · ${workforceMap(line)['difference']}',
            ),
        ],
      ),
    ),
  );
}

class PayrollCorrectionEditor extends StatelessWidget {
  const PayrollCorrectionEditor({required this.controller, super.key});
  final PayrollCorrectionController controller;
  Widget _field(String key, String label, {TextInputType? keyboard}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextFormField(
      key: ValueKey('${controller.form?['id']}:$key'),
      initialValue: controller.form?[key]?.toString() ?? '',
      enabled: !controller.locked,
      keyboardType: keyboard,
      decoration: InputDecoration(labelText: label),
      onChanged: (v) => controller.update(key, v),
    ),
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final c = controller, p = c.form;
      if (p == null) {
        return const SizedBox.shrink();
      }
      return Dialog(
        child: SizedBox(
          width: 820,
          height: 650,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Synthetic correction · ${c.action}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (c.error != null)
                        Text(
                          c.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      if (c.message != null) Text(c.message!),
                      if (c.action == 'prepare') ...[
                        const Text('Original employee calculation'),
                        for (final row in c.originals)
                          ListTile(
                            selected: row['id'] == p['original_calculation_id'],
                            leading: Icon(
                              row['id'] == p['original_calculation_id']
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                            ),
                            onTap: c.locked
                                ? null
                                : () => c.selectOriginal(row),
                            title: Text(
                              '${row['employee_name']} · ${row['employee_code']}',
                            ),
                            subtitle: Text(
                              '${row['start_date']} → ${row['end_date_exclusive']} · ${row['original_net']} ${row['currency_code']}',
                            ),
                          ),
                        if (c.originalCursor != null)
                          TextButton(
                            onPressed: c.locked
                                ? null
                                : () => c.beginPrepare(more: true),
                            child: const Text('More original calculations'),
                          ),
                        for (final source in c.sources)
                          PayrollCorrectionSourceEditor(
                            key: ValueKey(source['seal_id']),
                            controller: c,
                            source: source,
                          ),
                        if (c.sourceCursor != null && c.original != null)
                          TextButton(
                            onPressed: c.locked
                                ? null
                                : () =>
                                      c.selectOriginal(c.original!, more: true),
                            child: const Text('More sealed sources'),
                          ),
                      ],
                      if (p.containsKey('posting_date'))
                        _field(
                          'posting_date',
                          'Explicit posting date (YYYY-MM-DD)',
                        ),
                      if (c.kind == PayrollCorrectionCommandKind.correction &&
                          c.action == 'reverse') ...[
                        const Text('Current replacement billing evidence'),
                        for (final source in c.sources)
                          PayrollCorrectionReverseCredits(
                            controller: c,
                            source: source,
                          ),
                        if (c.sourceCursor != null)
                          TextButton(
                            onPressed: c.locked ? null : c.reverseSourcesMore,
                            child: const Text('More current sources'),
                          ),
                      ],
                      if (c.kind == PayrollCorrectionCommandKind.settlement &&
                          c.action == 'record') ...[
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          itemHeight: null,
                          initialValue: p['direction'] as String?,
                          decoration: const InputDecoration(
                            labelText: 'Recorded direction',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'pay',
                              child: Text('Pay a positive difference'),
                            ),
                            DropdownMenuItem(
                              value: 'recover',
                              child: Text('Recover a negative difference'),
                            ),
                          ],
                          onChanged: c.locked
                              ? null
                              : (v) => c.update('direction', v),
                        ),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          itemHeight: null,
                          initialValue: p['bank_id'] as String?,
                          decoration: const InputDecoration(
                            labelText: 'Scoped bank account',
                          ),
                          items: [
                            for (final bank in c.banks)
                              DropdownMenuItem(
                                value: bank['id'] as String,
                                child: Text(
                                  '${bank['name']} · ${bank['currency_code']}',
                                ),
                              ),
                          ],
                          onChanged: c.locked
                              ? null
                              : (v) {
                                  final bank = c.banks.firstWhere(
                                    (r) => r['id'] == v,
                                  );
                                  c.update('bank_id', v);
                                  c.update('bank_version', bank['version']);
                                },
                        ),
                        _field(
                          'evidence_reference',
                          'Recorded evidence reference',
                        ),
                        for (final value
                            in c.detail?['items'] as List? ?? const [])
                          Builder(
                            builder: (context) {
                              final balance = workforceMap(value);
                              return TextFormField(
                                key: ValueKey(balance['id']),
                                initialValue:
                                    (p['allocations'] as List? ?? const [])
                                            .map(workforceMap)
                                            .where(
                                              (row) =>
                                                  row['balance_id'] ==
                                                  balance['id'],
                                            )
                                            .firstOrNull?['amount']
                                        as String?,
                                enabled: !c.locked,
                                decoration: InputDecoration(
                                  labelText:
                                      '${balance['kind']} · signed outstanding ${balance['outstanding']}',
                                ),
                                onChanged: (v) =>
                                    c.allocate(balance['id'] as String, v),
                              );
                            },
                          ),
                      ],
                      _field('reason', 'Reason'),
                      if (c.local?.pending != null)
                        const Text(
                          'The request is sealed. Retry uses its exact original identity and body.',
                        ),
                      if (c.conflict) ...[
                        TextButton(
                          onPressed: c.busy ? null : c.compare,
                          child: const Text(
                            'Compare current source and proposal',
                          ),
                        ),
                        if (c.comparison != null) ...[
                          const Text(
                            'Current evidence loaded. Review the updated sources before creating a replacement proposal.',
                          ),
                          TextButton(
                            onPressed: c.busy ? null : c.acceptComparison,
                            child: const Text('Use compared current basis'),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: c.busy
                        ? null
                        : () async {
                            await c.closeForm();
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          },
                    child: const Text('Close'),
                  ),
                  if (c.confirmed == null && c.local?.pending == null)
                    TextButton(
                      onPressed: c.busy ? null : c.save,
                      child: const Text('Save encrypted draft'),
                    ),
                  if (c.confirmed == null && c.local?.pending == null)
                    TextButton(
                      onPressed: c.busy ? null : c.discard,
                      child: const Text('Discard draft'),
                    ),
                  if (c.confirmed == null)
                    FilledButton(
                      onPressed: c.busy || !c.online ? null : c.submit,
                      child: Text(
                        c.local?.pending == null
                            ? 'Submit exact proposal'
                            : 'Retry saved request',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );
    },
  );
}

class PayrollCorrectionSourceEditor extends StatefulWidget {
  const PayrollCorrectionSourceEditor({
    required this.controller,
    required this.source,
    super.key,
  });
  final PayrollCorrectionController controller;
  final Map<String, Object?> source;
  @override
  State<PayrollCorrectionSourceEditor> createState() =>
      _PayrollCorrectionSourceEditorState();
}

class _PayrollCorrectionSourceEditorState
    extends State<PayrollCorrectionSourceEditor> {
  String mode = 'eligibility',
      seconds = '',
      start = '',
      end = '',
      startOffset = '',
      endOffset = '';
  final allocationChanges = <String, Map<String, Object?>>{};
  final billingCredits = <String>{};
  List<Map<String, Object?>> breaks = [];
  @override
  void initState() {
    super.initState();
    final s = widget.source,
        op = workforceMap(s['operational']),
        before = workforceMap(op['before']);
    final saved = (widget.controller.form?['replacements'] as List? ?? const [])
        .map(workforceMap)
        .where((row) => row['seal_id'] == s['seal_id'])
        .firstOrNull;
    final impact = saved?['impact'] == null
        ? null
        : workforceMap(saved!['impact']);
    mode = impact?['mode'] as String? ?? 'eligibility';
    seconds = '${saved?['paid_seconds'] ?? s['paid_seconds']}';
    final geometry = before['revision'] is Map
        ? workforceMap(before['revision'])
        : before;
    start = '${impact?['start_local'] ?? geometry['start_local'] ?? ''}'
        .replaceFirst(' ', 'T');
    end = '${impact?['end_local'] ?? geometry['end_local'] ?? ''}'.replaceFirst(
      ' ',
      'T',
    );
    startOffset =
        '${impact?['start_offset_seconds'] ?? geometry['start_offset_seconds'] ?? ''}';
    endOffset =
        '${impact?['end_offset_seconds'] ?? geometry['end_offset_seconds'] ?? ''}';
    billingCredits.addAll(
      (impact?['billing_credit_line_ids'] as List? ?? const []).cast<String>(),
    );
    breaks =
        (impact?['breaks'] as List? ?? geometry['breaks'] as List? ?? const [])
            .map(workforceMap)
            .toList();
    for (final value in impact?['allocation_changes'] as List? ?? const []) {
      final change = workforceMap(value);
      allocationChanges[change['entry_id'] as String] = change;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller,
        s = widget.source,
        op = workforceMap(s['operational']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${s['source_kind']} · ${s['start_utc']} → ${s['end_utc']} · ${s['paid_seconds']} paid seconds',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              isExpanded: true,
              itemHeight: null,
              initialValue: mode,
              decoration: const InputDecoration(labelText: 'Linked change'),
              items: [
                const DropdownMenuItem(
                  value: 'eligibility',
                  child: Text('Payroll eligibility only'),
                ),
                if (s['source_kind'] != 'leave')
                  const DropdownMenuItem(
                    value: 'geometry',
                    child: Text('Correct approved worked interval'),
                  ),
                if (s['source_kind'] == 'leave')
                  const DropdownMenuItem(
                    value: 'cancel_leave',
                    child: Text(
                      'Cancel leave and restore original balance effects',
                    ),
                  ),
              ],
              onChanged: c.locked ? null : (v) => setState(() => mode = v!),
            ),
            if (mode == 'geometry') ...[
              TextFormField(
                initialValue: start,
                enabled: !c.locked,
                decoration: const InputDecoration(
                  labelText: 'Start local (YYYY-MM-DDTHH:MM:SS)',
                ),
                onChanged: (v) => start = v,
              ),
              TextFormField(
                initialValue: end,
                enabled: !c.locked,
                decoration: const InputDecoration(
                  labelText: 'End local (YYYY-MM-DDTHH:MM:SS)',
                ),
                onChanged: (v) => end = v,
              ),
              TextFormField(
                initialValue: startOffset,
                enabled: !c.locked,
                decoration: const InputDecoration(
                  labelText: 'Start selected UTC offset seconds',
                ),
                onChanged: (v) => startOffset = v,
              ),
              TextFormField(
                initialValue: endOffset,
                enabled: !c.locked,
                decoration: const InputDecoration(
                  labelText: 'End selected UTC offset seconds',
                ),
                onChanged: (v) => endOffset = v,
              ),
              PayrollCorrectionBreakEditor(
                breaks: breaks,
                locked: c.locked,
                onChanged: (values) => setState(() => breaks = values),
              ),
              if ({'project', 'service'}.contains(s['source_kind']))
                PayrollCorrectionCreditPicker(
                  controller: c,
                  sourceRevision: op['source_id'] as String,
                  selected: billingCredits,
                  onChanged: (ids) => setState(() {
                    billingCredits
                      ..clear()
                      ..addAll(ids);
                  }),
                ),
              for (final value
                  in (op['allocations'] as List? ?? const []).where(
                    (value) => workforceMap(value)['active'] != false,
                  ))
                PayrollCorrectionAllocationEditor(
                  controller: c,
                  allocation: workforceMap(value),
                  saved: allocationChanges,
                  locked: c.locked,
                  onChanged: (entry, change) =>
                      allocationChanges[entry] = change,
                ),
            ],
            if (mode != 'cancel_leave') ...[
              const SizedBox(height: 16),
              TextFormField(
                initialValue: seconds,
                enabled: !c.locked,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Revised approved paid seconds',
                ),
                onChanged: (v) => seconds = v,
              ),
            ],
            TextButton(
              onPressed: c.locked
                  ? null
                  : () {
                      final paid = mode == 'cancel_leave'
                          ? 0
                          : int.tryParse(seconds);
                      if (paid == null) {
                        return;
                      }
                      c.replaceSource(
                        s,
                        paid,
                        impact: mode == 'eligibility'
                            ? null
                            : {
                                'mode': mode,
                                'expected_source_version': op['source_version'],
                                if (mode == 'geometry') ...{
                                  'start_local': start,
                                  'end_local': end,
                                  'start_offset_seconds': int.tryParse(
                                    startOffset,
                                  ),
                                  'end_offset_seconds': int.tryParse(endOffset),
                                  'breaks': breaks,
                                  if (billingCredits.isNotEmpty)
                                    'billing_credit_line_ids': billingCredits
                                        .toList(),
                                  'allocation_changes': allocationChanges.values
                                      .toList(),
                                },
                              },
                      );
                    },
              child: const Text('Include source replacement'),
            ),
            if ((c.form?['replacements'] as List? ?? const [])
                .map(workforceMap)
                .any((r) => r['seal_id'] == s['seal_id']))
              const Text('Replacement included in this proposal.'),
          ],
        ),
      ),
    );
  }
}

class PayrollCorrectionAllocationEditor extends StatefulWidget {
  const PayrollCorrectionAllocationEditor({
    required this.controller,
    required this.allocation,
    required this.locked,
    required this.onChanged,
    required this.saved,
    super.key,
  });
  final PayrollCorrectionController controller;
  final Map<String, Map<String, Object?>> saved;
  final Map<String, Object?> allocation;
  final bool locked;
  final void Function(String, Map<String, Object?>) onChanged;
  @override
  State<PayrollCorrectionAllocationEditor> createState() =>
      _PayrollCorrectionAllocationEditorState();
}

class _PayrollCorrectionAllocationEditorState
    extends State<PayrollCorrectionAllocationEditor> {
  String mode = 'retain',
      start = '',
      end = '',
      startOffset = '',
      endOffset = '';
  late Map<String, Object?> operational, before, geometry;
  late String entry;
  final billingCredits = <String>{};
  List<Map<String, Object?>> breaks = [];
  @override
  void initState() {
    super.initState();
    operational = workforceMap(widget.allocation['operational']);
    before = workforceMap(operational['before']);
    geometry = before['revision'] is Map
        ? workforceMap(before['revision'])
        : before;
    entry =
        (operational['entry_id'] ?? before['entry_id'] ?? before['id'])
            as String;
    final saved = widget.saved[entry];
    mode = saved?['mode'] as String? ?? 'retain';
    start = '${saved?['start_local'] ?? geometry['start_local'] ?? ''}'
        .replaceFirst(' ', 'T');
    end = '${saved?['end_local'] ?? geometry['end_local'] ?? ''}'.replaceFirst(
      ' ',
      'T',
    );
    startOffset =
        '${saved?['start_offset_seconds'] ?? geometry['start_offset_seconds'] ?? ''}';
    endOffset =
        '${saved?['end_offset_seconds'] ?? geometry['end_offset_seconds'] ?? ''}';
    billingCredits.addAll(
      (saved?['billing_credit_line_ids'] as List? ?? const []).cast<String>(),
    );
    breaks =
        (saved?['breaks'] as List? ?? geometry['breaks'] as List? ?? const [])
            .map(workforceMap)
            .toList();
  }

  void save() => widget.onChanged(entry, {
    'entry_id': entry,
    'mode': mode,
    if (billingCredits.isNotEmpty)
      'billing_credit_line_ids': billingCredits.toList(),
    if (mode == 'geometry') ...{
      'start_local': start,
      'end_local': end,
      'start_offset_seconds': int.tryParse(startOffset),
      'end_offset_seconds': int.tryParse(endOffset),
      'breaks': breaks,
    },
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Linked ${widget.allocation['source_kind']} allocation · ${operational['project_name'] ?? before['project_name'] ?? before['work_order_id'] ?? entry}',
        ),
        DropdownButtonFormField<String>(
          isExpanded: true,
          itemHeight: null,
          initialValue: mode,
          decoration: const InputDecoration(labelText: 'Allocation impact'),
          items: const [
            DropdownMenuItem(
              value: 'retain',
              child: Text('Retain exact original geometry'),
            ),
            DropdownMenuItem(
              value: 'geometry',
              child: Text('Append revised allocated geometry'),
            ),
            DropdownMenuItem(
              value: 'remove',
              child: Text('Remove allocation with linked original effects'),
            ),
          ],
          onChanged: widget.locked
              ? null
              : (v) {
                  setState(() => mode = v!);
                  save();
                },
        ),
        PayrollCorrectionCreditPicker(
          controller: widget.controller,
          sourceRevision: operational['source_id'] as String,
          selected: billingCredits,
          onChanged: (ids) {
            setState(() {
              billingCredits
                ..clear()
                ..addAll(ids);
            });
            save();
          },
        ),
        if (mode == 'geometry') ...[
          PayrollCorrectionBreakEditor(
            breaks: breaks,
            locked: widget.locked,
            onChanged: (values) {
              setState(() => breaks = values);
              save();
            },
          ),
          TextFormField(
            initialValue: start,
            enabled: !widget.locked,
            decoration: const InputDecoration(
              labelText: 'Allocation start local',
            ),
            onChanged: (v) {
              start = v;
              save();
            },
          ),
          TextFormField(
            initialValue: end,
            enabled: !widget.locked,
            decoration: const InputDecoration(
              labelText: 'Allocation end local',
            ),
            onChanged: (v) {
              end = v;
              save();
            },
          ),
          TextFormField(
            initialValue: startOffset,
            enabled: !widget.locked,
            decoration: const InputDecoration(
              labelText: 'Allocation start UTC offset seconds',
            ),
            onChanged: (v) {
              startOffset = v;
              save();
            },
          ),
          TextFormField(
            initialValue: endOffset,
            enabled: !widget.locked,
            decoration: const InputDecoration(
              labelText: 'Allocation end UTC offset seconds',
            ),
            onChanged: (v) {
              endOffset = v;
              save();
            },
          ),
        ],
      ],
    ),
  );
}

class PayrollCorrectionBreakEditor extends StatelessWidget {
  const PayrollCorrectionBreakEditor({
    required this.breaks,
    required this.locked,
    required this.onChanged,
    super.key,
  });
  final List<Map<String, Object?>> breaks;
  final bool locked;
  final ValueChanged<List<Map<String, Object?>>> onChanged;
  void update(int index, String key, String value) => onChanged([
    for (var i = 0; i < breaks.length; i++)
      if (i == index) {...breaks[i], key: value} else {...breaks[i]},
  ]);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Exact unpaid breaks. Enter UTC timestamps as YYYY-MM-DDTHH:MM:SSZ; breaks must fit the revised interval.',
      ),
      for (var i = 0; i < breaks.length; i++)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                TextFormField(
                  key: ValueKey('$i:start:${breaks.length}'),
                  initialValue: breaks[i]['start_utc'] as String?,
                  enabled: !locked,
                  decoration: InputDecoration(
                    labelText: 'Break ${i + 1} start UTC',
                  ),
                  onChanged: (value) => update(i, 'start_utc', value),
                ),
                TextFormField(
                  key: ValueKey('$i:end:${breaks.length}'),
                  initialValue: breaks[i]['end_utc'] as String?,
                  enabled: !locked,
                  decoration: InputDecoration(
                    labelText: 'Break ${i + 1} end UTC',
                  ),
                  onChanged: (value) => update(i, 'end_utc', value),
                ),
                TextButton(
                  onPressed: locked
                      ? null
                      : () => onChanged([
                          for (var j = 0; j < breaks.length; j++)
                            if (j != i) {...breaks[j]},
                        ]),
                  child: Text('Remove break ${i + 1}'),
                ),
              ],
            ),
          ),
        ),
      TextButton(
        onPressed: locked || breaks.length >= 100
            ? null
            : () => onChanged([
                ...breaks,
                {'start_utc': '', 'end_utc': ''},
              ]),
        child: const Text('Add exact unpaid break'),
      ),
    ],
  );
}

class PayrollCorrectionCreditPicker extends StatelessWidget {
  const PayrollCorrectionCreditPicker({
    required this.controller,
    required this.sourceRevision,
    required this.selected,
    required this.onChanged,
    super.key,
  });
  final PayrollCorrectionController controller;
  final String sourceRevision;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final choices = controller.creditChoices[sourceRevision];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Billed work requires a posted credit against the original invoice before this correction can post.',
          ),
          TextButton(
            onPressed: controller.locked
                ? null
                : () => controller.credits(sourceRevision),
            child: const Text('Load named posted original credits'),
          ),
          if (choices != null && choices.isEmpty)
            const Text(
              'No posted original credits are available in this scope.',
            ),
          for (final credit in choices ?? const <Map<String, Object?>>[])
            CheckboxListTile(
              title: Text(credit['name'] as String),
              value: selected.contains(credit['id']),
              onChanged: controller.locked
                  ? null
                  : (value) {
                      final ids = {...selected};
                      if (value == true) {
                        ids.add(credit['id'] as String);
                      } else {
                        ids.remove(credit['id']);
                      }
                      onChanged(ids);
                    },
            ),
          if (controller.creditCursors[sourceRevision] != null)
            TextButton(
              onPressed: controller.locked
                  ? null
                  : () => controller.credits(sourceRevision, more: true),
              child: const Text('Load more posted credits'),
            ),
        ],
      );
    },
  );
}

class PayrollCorrectionReverseCredits extends StatelessWidget {
  const PayrollCorrectionReverseCredits({
    required this.controller,
    required this.source,
    super.key,
  });
  final PayrollCorrectionController controller;
  final Map<String, Object?> source;
  @override
  Widget build(BuildContext context) {
    final op = workforceMap(source['operational']);
    final row =
        (controller.form?['current_billing_impacts'] as List? ?? const [])
            .map(workforceMap)
            .where((r) => r['seal_id'] == source['seal_id'])
            .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if ({'project', 'service'}.contains(source['source_kind'])) ...[
          Text(
            'Current ${source['source_kind']} · ${op['project_name'] ?? op['entry_name'] ?? source['start_utc']}',
          ),
          PayrollCorrectionCreditPicker(
            controller: controller,
            sourceRevision: op['source_id'] as String,
            selected: (row?['billing_credit_line_ids'] as List? ?? const [])
                .cast<String>()
                .toSet(),
            onChanged: (ids) => controller.currentBillingCredits(source, ids),
          ),
        ],
        for (final value in op['allocations'] as List? ?? const [])
          Builder(
            builder: (context) {
              final allocation = workforceMap(
                workforceMap(value)['operational'],
              );
              final before = workforceMap(allocation['before']);
              final entry =
                  allocation['entry_id'] ?? before['entry_id'] ?? before['id'];
              final choice = (row?['allocation_credits'] as List? ?? const [])
                  .map(workforceMap)
                  .where((r) => r['entry_id'] == entry)
                  .firstOrNull;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Current linked work${workforceMap(value)['active'] == false ? ' · removed allocation' : ''} · ${allocation['project_name'] ?? before['work_order_id'] ?? entry}',
                  ),
                  PayrollCorrectionCreditPicker(
                    controller: controller,
                    sourceRevision: allocation['source_id'] as String,
                    selected:
                        (choice?['billing_credit_line_ids'] as List? ??
                                const [])
                            .cast<String>()
                            .toSet(),
                    onChanged: (ids) => controller.currentBillingCredits(
                      source,
                      ids,
                      allocation: allocation,
                    ),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}

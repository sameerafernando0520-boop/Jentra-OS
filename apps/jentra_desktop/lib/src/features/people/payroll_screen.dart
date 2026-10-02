import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_payroll.dart';
import 'package:jentra_domain/jentra_people.dart';

import '../../app_providers.dart';
import 'organization_screen.dart';
import 'payroll_controller.dart';
import 'payroll_correction_screen.dart';

class PayrollScreen extends ConsumerWidget {
  const PayrollScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(businessCapabilitiesProvider);
    if (caps.isLoading) return const Center(child: CircularProgressIndicator());
    if (caps.hasError) {
      return Center(
        child: TextButton(
          onPressed: () => ref.invalidate(businessCapabilitiesProvider),
          child: const Text('Retry payroll access'),
        ),
      );
    }
    final c = ref.watch(payrollControllerProvider);
    if (c == null) {
      return const Center(
        child: Text(
          'Choose an entity and branch with payroll or payslip access.',
        ),
      );
    }
    return PayrollWorkspace(key: ValueKey(c), controller: c);
  }
}

String payrollViewLabel(PayrollView v) => switch (v) {
  PayrollView.runs => 'Payroll runs',
  PayrollView.rules => 'Rules & assignments',
  PayrollView.payslips => 'Employee payslips',
  PayrollView.self => 'My payslips',
};
String payrollActionLabel(PayrollCommandKind kind, String action) => switch ((
  kind,
  action,
)) {
  (PayrollCommandKind.configuration, 'settings') => 'Set net payable account',
  (PayrollCommandKind.configuration, 'publish') => 'Publish dated rule',
  (PayrollCommandKind.configuration, 'assign') => 'Assign employee component',
  (PayrollCommandKind.settlement, 'record') => 'Record synthetic settlement',
  (PayrollCommandKind.settlement, 'reverse') => 'Reverse settlement',
  (PayrollCommandKind.export, _) => 'Prepare payslip export',
  (_, 'create') => 'Create payroll run',
  (_, 'prepare') => 'Prepare frozen revision',
  (_, 'submit') => 'Submit for approval',
  (_, 'approve') => 'Approve revision',
  (_, 'post') => 'Post payroll',
  (_, 'reverse') => 'Reverse payroll',
  (_, 'cancel') => 'Cancel run',
  _ => action,
};
String _dateRange(Object? from, Object? until) =>
    '$from → $until (end excluded)';

class PayrollWorkspace extends StatelessWidget {
  const PayrollWorkspace({required this.controller, super.key});
  final PayrollController controller;
  Future<void> _editor(BuildContext context, Future<void> operation) async {
    await operation;
    if (!context.mounted || controller.form == null) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PayrollEditor(controller: controller),
    );
  }

  Widget _card(BuildContext context, String title, List<Widget> children) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );
  Widget _button(
    BuildContext context,
    PayrollCommandKind kind,
    String action, {
    Map<String, Object?>? source,
    bool enabled = true,
  }) => OutlinedButton(
    onPressed: controller.busy || !controller.online || !enabled
        ? null
        : () =>
              _editor(context, controller.begin(kind, action, source: source)),
    child: Text(payrollActionLabel(kind, action)),
  );
  Future<void> _employee(BuildContext context) async {
    final c = controller;
    final choice = await organizationPicker(context, 'Employee', (
      query,
      after,
    ) async {
      final rows = await c.employeeChoices(query, after: after);
      return (
        [
          for (final r in rows)
            OrganizationChoice(
              r['id'] as String,
              '${r['display_name']} · ${r['code']}',
            ),
        ],
        rows.length == 50 ? rows.last['id'] as String : null,
      );
    }, () => c.current);
    if (choice != null) await c.selectEmployee(choice.id, choice.label);
  }

  List<Widget> _runDetail(BuildContext context) {
    final c = controller, r = c.selectedRun!;
    return [
      _card(context, '${r.name} · ${r.status}', [
        Text(
          '${_dateRange(r.start.value, r.endExclusive.value)} · ${r.currency} · version ${r.version}',
        ),
        Text('Posting date ${r.postingDate.value}'),
        if (r.digest != null) SelectableText('Frozen digest: ${r.digest}'),
        if (r.preparedBy != null) Text('Prepared by ${r.preparedBy}'),
        if (r.approvedBy != null) Text('Approved by ${r.approvedBy}'),
        if (r.journalId != null)
          SelectableText('Posted journal: ${r.journalId}'),
        if (r.reversalId != null)
          SelectableText('Original reversal: ${r.reversalId}'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final action in [
              'prepare',
              'submit',
              'approve',
              'post',
              'reverse',
              'cancel',
            ])
              if (c.has(
                PayrollCommands.capability(PayrollCommandKind.run, action),
              ))
                _button(
                  context,
                  PayrollCommandKind.run,
                  action,
                  enabled: c.canTransition(action),
                ),
          ],
        ),
        if (r.status == 'submitted' &&
            (r.preparedBy == c.scope.actorId ||
                r.submittedBy == c.scope.actorId))
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'A different authorized person must approve this revision.',
            ),
          ),
      ]),
      _card(context, 'Frozen employee calculations', [
        if (c.calculations.isEmpty)
          const Text(
            'Prepare a revision to freeze eligible employees and approved sources.',
          ),
        for (final calc in c.calculations)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(calc.employeeName),
            subtitle: Text(
              'Gross ${calc.amounts.gross.toDecimalString()} · deductions ${calc.amounts.deductions.toDecimalString()}\nNet ${calc.amounts.net.toDecimalString()} · employer cost ${calc.amounts.employerCost.toDecimalString()} ${r.currency}',
            ),
            onTap: c.busy ? null : () => c.openCalculation(calc),
          ),
        if (c.calculationCursor != null)
          TextButton(
            onPressed: c.busy ? null : () => c.openRun(r.id, more: true),
            child: const Text('More employee calculations'),
          ),
      ]),
      if (c.calculation != null) _calculation(context),
      if (c.has('people.payroll.settle'))
        _card(context, 'Payroll obligations & settlement evidence', [
          const Text(
            'Recording settlement is synthetic accounting evidence. Posting payroll does not mean it has been paid.',
          ),
          const SizedBox(height: 8),
          for (final row in c.obligations)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${row['kind']} · issued ${row['amount']} ${row['currency_code']}',
              ),
              subtitle: Text(
                'Outstanding ${row['outstanding']} · employee ${row['employee_id']}',
              ),
            ),
          if (c.obligationCursor != null)
            TextButton(
              onPressed: c.busy ? null : () => c.moreRelated('obligations'),
              child: const Text('More obligations'),
            ),
          if (r.status == 'posted')
            _button(context, PayrollCommandKind.settlement, 'record'),
          for (final row in c.settlements)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${row['evidence_reference']} · ${row['status']} · ${row['posting_date']}',
                  ),
                  SelectableText('Journal: ${row['journal_id']}'),
                  if (row['status'] == 'recorded')
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _button(
                        context,
                        PayrollCommandKind.settlement,
                        'reverse',
                        source: row,
                      ),
                    ),
                ],
              ),
            ),
          if (c.settlementCursor != null)
            TextButton(
              onPressed: c.busy ? null : () => c.moreRelated('settlements'),
              child: const Text('More settlements'),
            ),
        ]),
      _card(context, 'Immutable payroll history', [
        for (final row in c.history)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${row['action']} · version ${row['version']}'),
            subtitle: Text(
              '${row['reason']}\n${row['recorded_at']} · ${row['actor_id']}',
            ),
          ),
        if (c.historyCursor != null)
          TextButton(
            onPressed: c.busy ? null : () => c.moreRelated('history'),
            child: const Text('More history'),
          ),
      ]),
    ];
  }

  Widget _calculation(BuildContext context) {
    final c = controller,
        data = c.calculation!,
        input = workforceMap(data['input']);
    final summary = c.calculations.where((r) => r.id == data['id']).first;
    return _card(context, 'Calculation explanation · ${input['employee_name']}', [
      Text(
        'Eligible ${input['eligible_days']} / ${input['period_days']} days · paid ${input['paid_seconds']} / planned ${input['planned_seconds']} seconds',
      ),
      Text(
        '${_dateRange(input['eligible_start'], input['eligible_end_exclusive'])} · ${input['timezone']}',
      ),
      SelectableText('Input digest: ${data['input_digest']}'),
      const SizedBox(height: 12),
      for (final value in data['lines'] as List) ...[
        Builder(
          builder: (context) {
            final row = workforceMap(value);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${row['code']} · ${row['classification']} · ${row['amount']} ${c.selectedRun!.currency}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${row['basis']} · ${row['proration']} · ${row['rounding']} (${row['precision']} places)',
                  ),
                  SelectableText(
                    'Exact basis ${row['raw_numerator_units']} / ${row['raw_denominator']} micro-units',
                  ),
                  Text(
                    'Rounded ${row['rounded_amount']} · cap ${row['cap'] ?? 'none'}${row['capped'] == true ? ' (applied)' : ''}',
                  ),
                ],
              ),
            );
          },
        ),
      ],
      if (data['next_code'] != null)
        TextButton(
          onPressed: c.busy
              ? null
              : () => c.openCalculation(summary, moreLines: true),
          child: const Text('More component explanations'),
        ),
      Text(
        'Approved work and leave sources',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      for (final value in data['sources'] as List)
        Builder(
          builder: (_) {
            final row = workforceMap(value);
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${row['source_kind']} · ${row['paid_seconds']} paid seconds',
              ),
              subtitle: Text(
                '${row['start_utc']} → ${row['end_utc']}\n${row['source_id']} · version ${row['source_version']}',
              ),
            );
          },
        ),
      if (data['next_source'] != null)
        TextButton(
          onPressed: c.busy
              ? null
              : () => c.openCalculation(summary, moreSources: true),
          child: const Text('More frozen work sources'),
        ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton(
            onPressed: c.busy ? null : () => c.openSnapshot('rules'),
            child: const Text('Inspect frozen rule versions'),
          ),
          TextButton(
            onPressed: c.busy ? null : () => c.openSnapshot('planned_slots'),
            child: const Text('Inspect planned calendar slots'),
          ),
        ],
      ),
      if (c.frozenSnapshot != null) ...[
        Text(
          c.frozenSnapshot!['section'] == 'rules'
              ? 'Original published rules'
              : 'Original calendar slots',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final item in c.frozenSnapshot!['items'] as List)
          Builder(
            builder: (_) {
              final wire = workforceMap(workforceMap(item)['value']);
              if (c.frozenSnapshot!['section'] == 'rules') {
                final rule = PayrollRuleVersion.fromJson(
                  {...wire}..remove('assignment_id'),
                );
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${rule.rule.code} · ${rule.name} · v${rule.version}',
                  ),
                  subtitle: Text(
                    '${_dateRange(rule.rule.start.value, rule.rule.endExclusive.value)}\nAmount ${rule.rule.amount.toDecimalString()} · rate ${rule.rule.ratioNumerator}/${rule.rule.ratioDenominator}\n${rule.reason} · published ${rule.publishedAt} by ${rule.publishedBy}',
                  ),
                );
              }
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${wire['date']} · ${wire['seconds']} planned seconds',
                ),
                subtitle: Text(
                  'Local ${wire['start_local']} → ${wire['end_local']}\nUTC ${wire['start_utc']} → ${wire['end_utc']}',
                ),
              );
            },
          ),
        if (c.frozenSnapshot!['next_position'] != null)
          TextButton(
            onPressed: c.busy
                ? null
                : () => c.openSnapshot(
                    c.frozenSnapshot!['section'] as String,
                    more: true,
                  ),
            child: const Text('More frozen evidence'),
          ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      if (!c.current) {
        return Center(
          child: Text(c.error ?? 'Payroll access changed. Reload access.'),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Payroll',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const Chip(label: Text('Synthetic development')),
              if (c.has('people.payroll.view'))
                OutlinedButton(
                  onPressed: c.busy
                      ? null
                      : () => showDialog<void>(
                          context: context,
                          builder: (_) => const Dialog(
                            child: SizedBox(
                              width: 1000,
                              height: 720,
                              child: PayrollCorrectionScreen(),
                            ),
                          ),
                        ),
                  child: const Text('Linked corrections'),
                ),
              OutlinedButton(
                onPressed: c.busy || !c.online ? null : () => c.refresh(),
                child: const Text('Reload'),
              ),
              if (!c.online)
                const Chip(
                  label: Text('Offline · reconnect for private recovery'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final view in c.views)
                ChoiceChip(
                  label: Text(payrollViewLabel(view)),
                  selected: c.view == view,
                  onSelected: c.busy ? null : (_) => c.changeView(view),
                ),
            ],
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
          const SizedBox(height: 12),
          if (c.view == PayrollView.runs) ...[
            if (c.has('people.payroll.prepare'))
              Align(
                alignment: Alignment.centerLeft,
                child: _button(context, PayrollCommandKind.run, 'create'),
              ),
            if (c.runs.isEmpty && !c.busy)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No payroll runs in this branch. Configure dated components and eligible employees, then prepare a synthetic run.',
                ),
              ),
            for (final r in c.runs)
              Card(
                child: ListTile(
                  title: Text(r.name),
                  subtitle: Text(
                    '${_dateRange(r.start.value, r.endExclusive.value)}\n${r.status} · ${r.currency} · version ${r.version}',
                  ),
                  selected: c.selectedRun?.id == r.id,
                  onTap: c.busy || !c.online ? null : () => c.openRun(r.id),
                ),
              ),
            if (c.selectedRun != null) ..._runDetail(context),
          ],
          if (c.view == PayrollView.rules) ...[
            _card(context, 'Entity payroll settings', [
              Text(
                c.settings == null
                    ? 'Choose a separate net payable liability account before preparing payroll.'
                    : 'Net payable account configured · version ${c.settings!['version']}',
              ),
              if (c.has('people.payroll.configure'))
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _button(
                      context,
                      PayrollCommandKind.configuration,
                      'settings',
                    ),
                    OutlinedButton(
                      onPressed: c.busy || !c.online
                          ? null
                          : () {
                              c.selectRule(null);
                              _editor(
                                context,
                                c.begin(
                                  PayrollCommandKind.configuration,
                                  'publish',
                                ),
                              );
                            },
                      child: const Text('New component'),
                    ),
                  ],
                ),
            ]),
            _card(context, 'Dated employee components', [
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed:
                      c.busy || !c.online || !c.has('people.employees.view')
                      ? null
                      : () => _employee(context),
                  icon: const Icon(Icons.person_outline),
                  label: Text(c.employeeName ?? 'Choose employee'),
                ),
              ),
              for (final row in c.assignments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${row['component_code']} · ${row['component_name']}',
                  ),
                  subtitle: Text(
                    '${_dateRange(row['start_date'], row['end_date_exclusive'])}\n${row['reason']} · ${row['recorded_at']}',
                  ),
                ),
              if (c.assignmentCursor != null)
                TextButton(
                  onPressed: c.busy ? null : c.moreAssignments,
                  child: const Text('More dated assignments'),
                ),
            ]),
            for (final rule in c.rules)
              _card(context, '${rule.rule.code} · ${rule.name} · v${rule.version}', [
                Text(
                  '${_dateRange(rule.rule.start.value, rule.rule.endExclusive.value)} · ${rule.rule.amount.currencyCode}',
                ),
                Text(
                  '${rule.rule.classification.name} · ${rule.rule.basis.name} · amount ${rule.rule.amount.toDecimalString()}',
                ),
                Text(
                  '${rule.rule.proration.name} · ${rule.rule.rounding.name} (${rule.rule.precision} places) · cap ${rule.rule.cap?.toDecimalString() ?? 'none'}',
                ),
                Text(rule.reason),
                if (c.has('people.payroll.configure'))
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: c.busy || !c.online
                            ? null
                            : () {
                                c.selectRule(rule);
                                _editor(
                                  context,
                                  c.begin(
                                    PayrollCommandKind.configuration,
                                    'publish',
                                  ),
                                );
                              },
                        child: const Text('Publish next dated version'),
                      ),
                      OutlinedButton(
                        onPressed:
                            c.busy ||
                                !c.online ||
                                !c.has('people.employees.view')
                            ? null
                            : () {
                                c.selectRule(rule);
                                _editor(
                                  context,
                                  c.begin(
                                    PayrollCommandKind.configuration,
                                    'assign',
                                  ),
                                );
                              },
                        child: const Text('Assign employee'),
                      ),
                    ],
                  ),
              ]),
          ],
          if (c.view == PayrollView.payslips || c.view == PayrollView.self) ...[
            if (c.view == PayrollView.payslips)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed:
                      c.busy || !c.online || !c.has('people.employees.view')
                      ? null
                      : () => _employee(context),
                  icon: const Icon(Icons.person_outline),
                  label: Text(c.employeeName ?? 'Choose employee'),
                ),
              ),
            for (final row in c.payslips)
              _card(context, '${row['employee_name']} · immutable payslip', [
                Text(_dateRange(row['start_date'], row['end_date_exclusive'])),
                Text(
                  'Gross ${row['gross']} · deductions ${row['deductions']} · net ${row['net']} ${row['currency_code']}',
                ),
                Text(
                  'Employer cost ${row['employer_cost']} · ${row['issued_at']}',
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (c.has('people.payroll.payslip.view'))
                      TextButton(
                        onPressed: c.busy
                            ? null
                            : () => c.openPayslip(row['id'] as String),
                        child: const Text('Open component breakdown'),
                      ),
                    if (c.has('people.payroll.export') &&
                        c.has('people.payroll.payslip.view'))
                      _button(
                        context,
                        PayrollCommandKind.export,
                        'prepare',
                        source: row,
                      ),
                  ],
                ),
              ]),
            if (c.selectedPayslip != null)
              _card(context, 'Immutable payslip components', [
                for (final value in c.selectedPayslip!['lines'] as List)
                  Builder(
                    builder: (_) {
                      final row = workforceMap(value);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${row['code']} · ${row['amount']}'),
                        subtitle: Text(
                          '${row['classification']} · ${row['rounding']} (${row['precision']} places)',
                        ),
                      );
                    },
                  ),
                if (c.selectedPayslip!['next_code'] != null)
                  TextButton(
                    onPressed: c.busy
                        ? null
                        : () => c.openPayslip(
                            workforceMap(c.selectedPayslip!['payslip'])['id']
                                as String,
                            more: true,
                          ),
                    child: const Text('More payslip components'),
                  ),
              ]),
          ],
          if (c.cursor != null)
            TextButton(
              onPressed: c.busy ? null : () => c.refresh(more: true),
              child: const Text('Load more'),
            ),
          if (c.preparedExportId != null)
            _card(context, 'Prepared payslip export', [
              const Text(
                'Save this frozen payslip to a file you choose. The exported private copy is under your control.',
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: c.busy || !c.online ? null : c.writeExport,
                  child: const Text('Save frozen payslip'),
                ),
              ),
            ]),
          if (c.recovery.isNotEmpty)
            _card(context, 'Encrypted payroll recovery', [
              for (final row in c.recovery)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${row.kind.name} · ${row.expired ? 'private fields expired' : 'private draft available'}',
                  ),
                  subtitle: Text(
                    row.expired
                        ? 'Reconcile the original command receipt.'
                        : 'Private expiry ${row.expiresAt}',
                  ),
                  onTap: c.busy || !c.online
                      ? null
                      : () => _editor(context, c.resume(row)),
                ),
            ]),
        ],
      );
    },
  );
}

class PayrollEditor extends StatefulWidget {
  const PayrollEditor({required this.controller, super.key});
  final PayrollController controller;
  @override
  State<PayrollEditor> createState() => _PayrollEditorState();
}

class _PayrollEditorState extends State<PayrollEditor> {
  PayrollController get c => widget.controller;
  final chosenAccounts = <String, Map<String, Object?>>{};
  Future<void> employee({bool add = false}) async {
    final choice = await organizationPicker(context, 'Employee', (
      query,
      after,
    ) async {
      final rows = await c.employeeChoices(query, after: after);
      return (
        [
          for (final r in rows)
            OrganizationChoice(
              r['id'] as String,
              '${r['display_name']} · ${r['code']}',
            ),
        ],
        rows.length == 50 ? rows.last['id'] as String : null,
      );
    }, () => c.current && !c.locked);
    if (choice != null) {
      if (add) {
        c.addEmployee(choice.id, choice.label);
      } else {
        c.update('employee_id', choice.id, label: choice.label);
      }
    }
  }

  Future<void> account(String key, String type) async {
    final choice = await organizationPicker(
      context,
      type == 'bank' ? 'Cash or bank account' : '$type account',
      (query, after) async {
        final page = await c.accountChoices(type, after: after);
        for (final row in page.items) {
          chosenAccounts[row['id'] as String] = row;
        }
        return (
          [
            for (final row in page.items)
              if ('${row['code']} ${row['name']}'.toLowerCase().contains(
                query.toLowerCase(),
              ))
                OrganizationChoice(
                  row['id'] as String,
                  '${row['code']} · ${row['name']} · ${row['currency_code'] ?? 'base currency'}',
                ),
          ],
          page.nextCursor,
        );
      },
      () => c.current && !c.locked,
    );
    if (choice != null) {
      c.update(key, choice.id, label: choice.label);
      if (type == 'bank') {
        c.update('bank_version', chosenAccounts[choice.id]!['version']);
      }
    }
  }

  Widget field(
    String key,
    String label, {
    bool integer = false,
    bool nullable = false,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey(
        '${c.form?['id']}:$key:${c.expectedVersion}:${c.local?.errorCode}:${c.form?['basis']}:${c.form?['classification']}',
      ),
      initialValue: c.form?[key]?.toString() ?? '',
      enabled: !c.locked,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        hintText: key.contains('date') ? 'YYYY-MM-DD' : null,
      ),
      onChanged: (text) => c.update(
        key,
        nullable && text.isEmpty
            ? null
            : integer
            ? int.tryParse(text) ?? text
            : text,
      ),
    ),
  );
  Widget choice(String key, String label, Map<String, String> options) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: DropdownButtonFormField<String>(
          key: ValueKey(
            '${c.form?['id']}:$key:${c.expectedVersion}:${c.form?[key]}',
          ),
          initialValue: c.form?[key] as String?,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final entry in options.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: c.locked ? null : (value) => c.update(key, value),
        ),
      );
  Widget picker(String key, String label, String type) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: OutlinedButton.icon(
      onPressed: c.locked || !c.online ? null : () => account(key, type),
      icon: const Icon(Icons.account_balance_outlined),
      label: Text(
        c.labels[key] ??
            (c.form?[key] == null
                ? 'Choose $label'
                : '$label selected · choose to inspect'),
      ),
    ),
  );
  List<Widget> ruleFields() => [
    field('code', 'Stable component code'),
    field('name', 'Component name'),
    choice('classification', 'Classification', {
      'earning': 'Earning',
      'deduction': 'Deduction',
      'employer_cost': 'Employer cost',
    }),
    field('start_date', 'Effective start date'),
    field('end_date_exclusive', 'Effective end date (excluded)'),
    choice('basis', 'Calculation basis', {
      'fixed': 'Fixed amount',
      'hourly': 'Hourly amount',
      'earnings_ratio': 'Ratio of total earnings',
    }),
    field('amount', 'Exact amount (up to six decimal places)'),
    if (c.form?['basis'] == 'earnings_ratio') ...[
      field('ratio_numerator', 'Rate numerator', integer: true),
      field('ratio_denominator', 'Rate denominator', integer: true),
    ],
    choice('proration', 'Proration', {
      'none': 'None',
      'eligible_days': 'Eligible / period days',
      'paid_seconds': 'Paid / planned seconds',
    }),
    choice('rounding', 'Rounding', {
      'half_away': 'Half away from zero',
      'half_even': 'Half to even',
      'truncate': 'Truncate',
      'floor': 'Floor',
    }),
    field('precision', 'Currency precision (0–6)', integer: true),
    field('cap', 'Optional exact amount cap', nullable: true),
    if (c.form?['classification'] != 'deduction')
      picker('expense_account_id', 'expense account', 'expense'),
    if (c.form?['classification'] != 'earning')
      picker('liability_account_id', 'separate liability account', 'liability'),
  ];
  List<Widget> settlementFields() => [
    field('posting_date', 'Settlement posting date'),
    if (c.action == 'record') ...[
      picker('bank_id', 'cash or bank account', 'bank'),
      field('evidence_reference', 'Unique synthetic evidence reference'),
      const Text(
        'Allocate exact amounts to the original obligations. A blank allocation is excluded.',
      ),
      const SizedBox(height: 12),
      for (final row in c.obligations)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TextFormField(
            key: ValueKey(
              '${c.form?['id']}:${row['id']}:${c.local?.errorCode}',
            ),
            initialValue:
                (c.form?['allocations'] as List?)
                        ?.map(workforceMap)
                        .where((r) => r['obligation_id'] == row['id'])
                        .firstOrNull?['amount']
                    as String? ??
                '',
            enabled: !c.locked,
            decoration: InputDecoration(
              labelText: '${row['kind']} allocation',
              helperText:
                  'Outstanding ${row['outstanding']} ${row['currency_code']} · employee ${row['employee_id']}',
            ),
            onChanged: (text) => c.allocation(row['id'] as String, text),
          ),
        ),
      if (c.obligationCursor != null)
        TextButton(
          onPressed: c.locked ? null : () => c.moreRelated('obligations'),
          child: const Text('More outstanding obligations'),
        ),
    ],
  ];
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      if (!c.current || c.form == null) {
        return AlertDialog(
          title: const Text('Payroll editor closed'),
          content: Text(
            c.message ?? 'Current private payroll access is required.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      }
      final f = c.form!, kind = c.kind!;
      return AlertDialog(
        title: Text(payrollActionLabel(kind, c.action!)),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Synthetic payroll · private fields expire in 24 hours.',
                ),
                const SizedBox(height: 16),
                if (kind == PayrollCommandKind.run && c.action == 'create') ...[
                  field('name', 'Run name'),
                  field('start_date', 'Earning period start'),
                  field('end_date_exclusive', 'Earning period end (excluded)'),
                  field('posting_date', 'Posting date'),
                  OutlinedButton(
                    onPressed:
                        c.locked || !c.online || !c.has('people.employees.view')
                        ? null
                        : () => employee(add: true),
                    child: const Text('Add eligible employee'),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final id in f['employee_ids'] as List)
                        InputChip(
                          label: Text(
                            c.labels[id] ?? 'Saved employee selection',
                          ),
                          onDeleted: c.locked
                              ? null
                              : () => c.removeEmployee(id as String),
                        ),
                    ],
                  ),
                  Text(
                    '${(f['employee_ids'] as List).length} / 200 employees selected',
                  ),
                  const SizedBox(height: 16),
                ],
                if (kind == PayrollCommandKind.run && c.action != 'create') ...[
                  Text(
                    'Run version ${c.expectedVersion} · ${c.selectedRun?.name ?? 'Saved payroll run'}',
                  ),
                  if (f['digest'] != null)
                    SelectableText('Frozen digest: ${f['digest']}'),
                  const SizedBox(height: 12),
                  Text(switch (c.action) {
                    'prepare' => 'Freeze current eligible employees, published rules and approved work/leave. Preparing again clears prior approval.',
                    'approve' => 'Approve this exact frozen revision as a separate authorized person.',
                    'post' => 'Recheck the frozen sources and open period, then post balanced accounting and immutable payslips atomically.',
                    'reverse' => 'Reverse the original journal and obligations once. Active settlements must be reversed first. Original payslips stay in history.',
                    'submit' => 'Submit this exact frozen revision for independent approval.',
                    _ => 'Cancel this unposted run.',
                  }),
                  const SizedBox(height: 16),
                ],
                if (kind == PayrollCommandKind.configuration &&
                    c.action == 'publish')
                  ...ruleFields(),
                if (kind == PayrollCommandKind.configuration &&
                    c.action == 'settings')
                  picker(
                    'net_account_id',
                    'net payable liability account',
                    'liability',
                  ),
                if (kind == PayrollCommandKind.configuration &&
                    c.action == 'assign') ...[
                  Text(
                    'Component ${c.selectedRule?.rule.code ?? 'saved component'}',
                  ),
                  OutlinedButton(
                    onPressed: c.locked || !c.online ? null : () => employee(),
                    child: Text(
                      c.labels['employee_id'] ??
                          (f['employee_id'] == null
                              ? 'Choose employee'
                              : 'Employee selected · choose to inspect'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  field('start_date', 'Assignment start date'),
                  field('end_date_exclusive', 'Assignment end date (excluded)'),
                ],
                if (kind == PayrollCommandKind.settlement)
                  ...settlementFields(),
                if (kind == PayrollCommandKind.export)
                  const Text(
                    'Freeze this immutable payslip and its digest for an attributable export. Choose a local file after confirmation.',
                  ),
                if (kind != PayrollCommandKind.export)
                  field('reason', 'Reason', lines: 3),
                if (c.conflict) ...[
                  const Text(
                    'Saved inputs or version changed. Compare current evidence before replacing this request.',
                  ),
                  TextButton(
                    onPressed: c.busy ? null : c.compare,
                    child: const Text('Compare current payroll'),
                  ),
                  if (c.comparison != null) ...[
                    Text(
                      'Current version ${c.comparison!['version']} · ${c.comparison!['status'] ?? c.comparison!['kind'] ?? 'settings'}',
                    ),
                    if (c.comparison!['digest'] != null)
                      SelectableText(
                        'Current digest: ${c.comparison!['digest']}',
                      ),
                    TextButton(
                      onPressed: c.busy ? null : c.acceptComparison,
                      child: const Text('Use compared version and inputs'),
                    ),
                  ],
                ],
                if (c.pending != null)
                  const Text(
                    'This exact request is sealed. Resolve its result before editing or discarding it.',
                  ),
                if (c.error != null)
                  Text(
                    c.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (c.confirmed != null)
                  const Text(
                    'Command confirmed. Close to refresh the workspace.',
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: c.busy
                ? null
                : () async {
                    await c.closeEditor();
                    if (context.mounted && c.form == null) {
                      Navigator.pop(context);
                    }
                  },
            child: const Text('Close & retain recovery'),
          ),
          if (c.confirmed == null)
            TextButton(
              onPressed: c.locked ? null : c.discard,
              child: const Text('Discard draft'),
            ),
          if (c.confirmed == null)
            TextButton(
              onPressed: c.locked ? null : c.saveLocal,
              child: const Text('Save encrypted draft'),
            ),
          if (c.confirmed == null)
            FilledButton(
              onPressed: c.busy || !c.online || c.conflict ? null : c.submit,
              child: Text(
                c.pending == null ? 'Confirm action' : 'Retry exact request',
              ),
            ),
        ],
      );
    },
  );
}

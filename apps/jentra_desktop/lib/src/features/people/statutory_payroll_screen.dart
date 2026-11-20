import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_payroll.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import 'employee_controller.dart';
import 'payroll_controller.dart';

/// Null unless the development build opts into the statutory payroll candidate.
final lkStatutoryPayrollRepositoryProvider =
    Provider<LkStatutoryPayrollRepository?>((ref) => null);

const _uuid = Uuid();

class StatutoryPayrollScreen extends ConsumerWidget {
  const StatutoryPayrollScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(businessCapabilitiesProvider);
    if (caps.isLoading) return const Center(child: CircularProgressIndicator());
    final scope = ref.watch(activeTenantContextProvider);
    final repository = ref.watch(lkStatutoryPayrollRepositoryProvider);
    if (caps.hasError ||
        scope == null ||
        !scope.hasOperationalScope ||
        repository == null ||
        !caps.value!.contains('people.payroll.view')) {
      return const Center(
        child: Text('Choose an entity and branch with payroll access.'),
      );
    }
    return StatutoryPayrollWorkspace(
      key: ValueKey(scope),
      scope: scope,
      permissions: caps.value!,
      repository: repository,
      payroll: ref.watch(payrollRepositoryProvider),
      employees: ref.watch(employeeRepositoryProvider),
    );
  }
}

class StatutoryPayrollWorkspace extends StatefulWidget {
  const StatutoryPayrollWorkspace({
    required this.scope,
    required this.permissions,
    required this.repository,
    this.payroll,
    this.employees,
    super.key,
  });

  final TenantContext scope;
  final Set<String> permissions;
  final LkStatutoryPayrollRepository repository;
  final PayrollRepository? payroll;
  final EmployeeRepository? employees;

  @override
  State<StatutoryPayrollWorkspace> createState() =>
      _StatutoryPayrollWorkspaceState();
}

class _StatutoryPayrollWorkspaceState extends State<StatutoryPayrollWorkspace> {
  bool _busy = true;
  String? _error, _notice;
  List<LkStatutoryRuleSetRecord> _sets = const [];
  LkEmployerRegistration? _employer;
  Map<String, LkComponentStatutoryRecord> _classes = const {};
  List<PayrollRuleVersion> _earnings = const [];
  final Map<String, (bool, bool, bool)> _edits = {};
  List<Map<String, Object?>> _found = const [];
  String? _employeeId, _employeeName;
  LkEmployeeStatutoryDetails _details = const LkEmployeeStatutoryDetails();
  final _epfNumber = TextEditingController(),
      _etfNumber = TextEditingController(),
      _employerReason = TextEditingController(),
      _classReason = TextEditingController(),
      _search = TextEditingController(),
      _nic = TextEditingController(),
      _member = TextEditingController(),
      _employeeReason = TextEditingController();

  bool get _configure =>
      widget.permissions.contains('people.payroll.configure');
  bool get _approve => widget.permissions.contains('people.payroll.approve');

  @override
  void initState() {
    super.initState();
    _act(_load);
  }

  @override
  void dispose() {
    for (final c in [
      _epfNumber,
      _etfNumber,
      _employerReason,
      _classReason,
      _search,
      _nic,
      _member,
      _employeeReason,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final repo = widget.repository, scope = widget.scope;
    final sets = await repo.ruleSets(scope);
    final employer = await repo.employer(scope);
    final classes = await repo.classifications(scope);
    final rules = widget.payroll == null
        ? const <PayrollRuleVersion>[]
        : (await widget.payroll!.rules(scope)).items;
    final latest = <String, PayrollRuleVersion>{};
    for (final r in rules.where(
      (r) => r.rule.classification == PayrollClassification.earning,
    )) {
      final seen = latest[r.componentId];
      if (seen == null || r.version > seen.version) latest[r.componentId] = r;
    }
    if (!mounted) return;
    setState(() {
      _sets = sets;
      _employer = employer;
      _classes = {for (final c in classes) c.componentId: c};
      _earnings = latest.values.toList()
        ..sort((a, b) => a.rule.code.compareTo(b.rule.code));
      _edits.clear();
      if (employer != null) {
        _epfNumber.text = employer.epfEmployerNumber;
        _etfNumber.text = employer.etfEmployerNumber;
      }
    });
  }

  Future<void> _act(Future<void> Function() work, {String? done}) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await work();
      if (mounted && done != null) setState(() => _notice = done);
    } on DomainError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _propose() => _act(
    () async {
      await widget.repository.proposeLk(
        widget.scope,
        id: _uuid.v4(),
        effectiveFrom: '2025-04-01',
        effectiveToExclusive: '2027-04-01',
      );
      await _load();
    },
    done: 'Sri Lanka rates proposed. Another approver must check and approve them.',
  );

  Future<void> _decide(LkStatutoryRuleSetRecord set, String action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(approve: action == 'approve'),
    );
    if (confirmed != true) return;
    await _act(() async {
      await widget.repository.decide(widget.scope, set.id, action);
      await _load();
    }, done: action == 'approve' ? 'Rates approved.' : 'Rates retired.');
  }

  Future<void> _saveEmployer() => _act(() async {
    await widget.repository.saveEmployer(
      widget.scope,
      id: _uuid.v4(),
      epfEmployerNumber: _epfNumber.text.trim(),
      etfEmployerNumber: _etfNumber.text.trim(),
      reason: _employerReason.text.trim(),
    );
    _employerReason.clear();
    await _load();
  }, done: 'Employer numbers saved.');

  Future<void> _classify(PayrollRuleVersion rule) => _act(() async {
    final (epf, etf, apit) = _edits[rule.componentId]!;
    await widget.repository.classify(
      widget.scope,
      id: _uuid.v4(),
      componentId: rule.componentId,
      epfLiable: epf,
      etfLiable: etf,
      apitRegularProfit: apit,
      reason: _classReason.text.trim(),
    );
    await _load();
  }, done: '${rule.rule.code} classified.');

  Future<void> _findEmployees() => _act(() async {
    final page = await widget.employees!.directory(
      widget.scope,
      search: _search.text.trim(),
    );
    final items = [
      for (final row in page['items']! as List<Object?>)
        Map<String, Object?>.from(row! as Map),
    ];
    if (mounted) setState(() => _found = items);
  });

  Future<void> _openEmployee(String id, String name) => _act(() async {
    final details = await widget.repository.employee(widget.scope, id);
    if (!mounted) return;
    setState(() {
      _employeeId = id;
      _employeeName = name;
      _details = details ?? const LkEmployeeStatutoryDetails();
      _nic.text = _details.nic ?? '';
      _member.text = _details.epfMemberNumber ?? '';
      _found = const [];
    });
  });

  Future<void> _saveEmployee() async {
    final nic = _nic.text.trim().toUpperCase();
    if (nic.isNotEmpty && !LkEmployeeStatutoryDetails.validNic(nic)) {
      setState(
        () => _error = 'Enter an NIC as 9 digits and V or X, or 12 digits.',
      );
      return;
    }
    await _act(() async {
      final details = LkEmployeeStatutoryDetails(
        nic: nic.isEmpty ? null : nic,
        epfMemberNumber: _member.text.trim().isEmpty
            ? null
            : _member.text.trim(),
        coverage: _details.coverage,
        apitCase: _details.apitCase,
        residentOrCitizen: _details.residentOrCitizen,
        primaryEmploymentDeclared: _details.primaryEmploymentDeclared,
        joinedOrLeftInYear: _details.joinedOrLeftInYear,
      );
      await widget.repository.saveEmployee(
        widget.scope,
        id: _uuid.v4(),
        employeeId: _employeeId!,
        details: details,
        reason: _employeeReason.text.trim(),
      );
      _employeeReason.clear();
      if (mounted) setState(() => _details = details);
    }, done: 'Statutory details saved for $_employeeName.');
  }

  LkEmployeeStatutoryDetails _with({
    String? coverage,
    String? apitCase,
    bool? resident,
    bool? primary,
    bool? joined,
  }) => LkEmployeeStatutoryDetails(
    nic: _details.nic,
    epfMemberNumber: _details.epfMemberNumber,
    coverage: coverage ?? _details.coverage,
    apitCase: apitCase ?? _details.apitCase,
    residentOrCitizen: resident ?? _details.residentOrCitizen,
    primaryEmploymentDeclared: primary ?? _details.primaryEmploymentDeclared,
    joinedOrLeftInYear: joined ?? _details.joinedOrLeftInYear,
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Sri Lanka statutory payroll', style: text.headlineMedium),
            const Chip(label: Text('Candidate · development')),
            OutlinedButton(
              onPressed: _busy ? null : () => _act(_load),
              child: const Text('Reload'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'EPF 8% employee and 12% employer, ETF 3% employer, and APIT Table 01. '
          'Runs use these only after a second approver confirms the rates.',
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_notice!),
          ),
        _section(context, 'Rates', [
          if (_sets.isEmpty) const Text('No statutory rates yet.'),
          for (final set in _sets)
            _RuleSetTile(
              set: set,
              canApprove: _approve && !_busy,
              onDecide: (action) => _decide(set, action),
            ),
          if (_configure)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: _busy ? null : _propose,
                child: const Text(
                  'Propose Sri Lanka rates for 2025/26 and 2026/27',
                ),
              ),
            ),
        ]),
        _section(context, 'Employer EPF and ETF numbers', [
          if (_employer == null) const Text('Not recorded yet.'),
          if (_configure) ...[
            TextField(
              controller: _epfNumber,
              decoration: const InputDecoration(
                labelText: 'EPF employer number',
              ),
            ),
            TextField(
              controller: _etfNumber,
              decoration: const InputDecoration(
                labelText: 'ETF employer number',
              ),
            ),
            TextField(
              controller: _employerReason,
              decoration: const InputDecoration(
                labelText: 'Reason for the change',
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: _busy ? null : _saveEmployer,
                child: const Text('Save employer numbers'),
              ),
            ),
          ] else if (_employer != null)
            Text(
              'EPF ${_employer!.epfEmployerNumber} · ETF ${_employer!.etfEmployerNumber}',
            ),
        ]),
        _section(context, 'Earnings classification', [
          if (_earnings.isEmpty)
            const Text('Publish earning components in Payroll first.'),
          if (_configure && _earnings.isNotEmpty)
            TextField(
              controller: _classReason,
              decoration: const InputDecoration(
                labelText: 'Reason for classification changes',
              ),
            ),
          for (final rule in _earnings) _classificationRow(rule),
        ]),
        if (_configure && widget.employees != null)
          _section(context, 'Employee statutory details', _employeeSection()),
      ],
    );
  }

  Widget _classificationRow(PayrollRuleVersion rule) {
    final saved = _classes[rule.componentId];
    final value =
        _edits[rule.componentId] ??
        (saved == null
            ? (false, false, false)
            : (saved.epfLiable, saved.etfLiable, saved.apitRegularProfit));
    void set((bool, bool, bool) next) =>
        setState(() => _edits[rule.componentId] = next);
    final (epf, etf, apit) = value;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        SizedBox(width: 220, child: Text('${rule.rule.code} · ${rule.name}')),
        if (saved == null) const Chip(label: Text('Not classified')),
        FilterChip(
          label: const Text('EPF'),
          selected: epf,
          onSelected: _configure ? (v) => set((v, etf, apit)) : null,
        ),
        FilterChip(
          label: const Text('ETF'),
          selected: etf,
          onSelected: _configure ? (v) => set((epf, v, apit)) : null,
        ),
        FilterChip(
          label: const Text('APIT'),
          selected: apit,
          onSelected: _configure ? (v) => set((epf, etf, v)) : null,
        ),
        if (_configure && _edits.containsKey(rule.componentId))
          OutlinedButton(
            onPressed: _busy ? null : () => _classify(rule),
            child: const Text('Save'),
          ),
      ],
    );
  }

  List<Widget> _employeeSection() => [
    Row(
      children: [
        Expanded(
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(labelText: 'Find an employee'),
            onSubmitted: (_) => _findEmployees(),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: _busy ? null : _findEmployees,
          child: const Text('Search'),
        ),
      ],
    ),
    for (final row in _found)
      ListTile(
        title: Text('${row['display_name']}'),
        subtitle: Text('${row['code']}'),
        onTap: _busy
            ? null
            : () => _openEmployee('${row['id']}', '${row['display_name']}'),
      ),
    if (_employeeId != null) ...[
      Text(
        'Editing $_employeeName',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      TextField(
        controller: _nic,
        decoration: const InputDecoration(labelText: 'NIC'),
      ),
      TextField(
        controller: _member,
        decoration: const InputDecoration(labelText: 'EPF member number'),
      ),
      DropdownButtonFormField<String>(
        initialValue: _details.coverage,
        decoration: const InputDecoration(labelText: 'EPF and ETF coverage'),
        items: [
          for (final c in LkEmployeeStatutoryDetails.coverages)
            DropdownMenuItem(
              value: c,
              child: Text(
                c == 'standard' ? 'Standard' : 'Exempt (needs review)',
              ),
            ),
        ],
        onChanged: (v) => setState(() => _details = _with(coverage: v)),
      ),
      DropdownButtonFormField<String>(
        initialValue: _details.apitCase,
        decoration: const InputDecoration(labelText: 'APIT case'),
        items: [
          for (final c in LkEmployeeStatutoryDetails.apitCases)
            DropdownMenuItem(value: c, child: Text(_apitCaseLabel(c))),
        ],
        onChanged: (v) => setState(() => _details = _with(apitCase: v)),
      ),
      CheckboxListTile(
        title: const Text('Resident or citizen'),
        value: _details.residentOrCitizen,
        onChanged: (v) => setState(() => _details = _with(resident: v)),
      ),
      CheckboxListTile(
        title: const Text('Primary employment declaration received'),
        value: _details.primaryEmploymentDeclared,
        onChanged: (v) => setState(() => _details = _with(primary: v)),
      ),
      CheckboxListTile(
        title: const Text('Joined or left during this year of assessment'),
        value: _details.joinedOrLeftInYear,
        onChanged: (v) => setState(() => _details = _with(joined: v)),
      ),
      TextField(
        controller: _employeeReason,
        decoration: const InputDecoration(labelText: 'Reason for the change'),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          onPressed: _busy ? null : _saveEmployee,
          child: const Text('Save statutory details'),
        ),
      ),
    ],
  ];

  Widget _section(BuildContext context, String title, List<Widget> children) =>
      Card(
        margin: const EdgeInsets.only(top: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              ...children,
            ],
          ),
        ),
      );
}

String _apitCaseLabel(String value) => switch (value) {
  'regular_primary' => 'Regular pay from primary employment (Table 01)',
  'lump_sum_or_arrears' => 'Lump sum or arrears',
  'terminal_benefit' => 'Terminal benefit',
  'secondary_employment' => 'Secondary employment',
  'employer_paid_tax' => 'Tax paid by the employer',
  _ => 'Foreign employer',
};

class _RuleSetTile extends StatelessWidget {
  const _RuleSetTile({
    required this.set,
    required this.canApprove,
    required this.onDecide,
  });

  final LkStatutoryRuleSetRecord set;
  final bool canApprove;
  final void Function(String action) onDecide;

  @override
  Widget build(BuildContext context) {
    final r = set.ruleSet;
    return ExpansionTile(
      key: ValueKey(set.id),
      title: Text(
        '${r.effectiveFrom} to ${r.effectiveToExclusive} (exclusive)',
      ),
      subtitle: Text(
        '${switch (set.status) {
          'pending' => 'Pending approval',
          'approved' => 'Approved',
          _ => 'Retired',
        }} · EPF ${r.epfEmployeePercent}% + ${r.epfEmployerPercent}% · ETF ${r.etfEmployerPercent}%',
      ),
      childrenPadding: const EdgeInsets.all(12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('APIT Table 01 (monthly regular profits)'),
        for (final b in r.apitBands)
          Text(
            '${b.upto == null ? 'Above the last bound' : 'Up to Rs ${b.upto!.toDecimalString()}'}: '
            '${b.rate}% less Rs ${b.reduction.toDecimalString()}',
          ),
        const SizedBox(height: 8),
        const Text('Sources'),
        for (final MapEntry(:key, :value) in set.sources.entries)
          SelectableText('$key: $value'),
        if (canApprove && set.status != 'retired')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: set.status == 'pending'
                ? FilledButton(
                    onPressed: () => onDecide('approve'),
                    child: const Text('Approve rates'),
                  )
                : OutlinedButton(
                    onPressed: () => onDecide('retire'),
                    child: const Text('Retire rates'),
                  ),
          ),
      ],
    );
  }
}

class _ConfirmDialog extends StatefulWidget {
  const _ConfirmDialog({required this.approve});
  final bool approve;

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.approve ? 'Approve statutory rates?' : 'Retire statutory rates?',
    ),
    content: widget.approve
        ? CheckboxListTile(
            value: _checked,
            onChanged: (v) => setState(() => _checked = v ?? false),
            title: const Text(
              'I checked every rate and APIT band against the official sources.',
            ),
          )
        : const Text(
            'Payroll runs stop using these rates. Approve a replacement first.',
          ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: widget.approve && !_checked
            ? null
            : () => Navigator.pop(context, true),
        child: Text(widget.approve ? 'Approve' : 'Retire'),
      ),
    ],
  );
}

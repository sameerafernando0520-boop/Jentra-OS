import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_tax_lk.dart';
import 'package:jentra_platform/jentra_finance_platform.dart'
    show ReportExportFiles;
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import '../report_export/report_export_controller.dart';

/// Null unless the development build opts into the Sri Lanka tax candidate.
final lkTaxRepositoryProvider = Provider<LkTaxRepository?>((ref) => null);

const _uuid = Uuid();

class LkTaxSchedulesScreen extends ConsumerWidget {
  const LkTaxSchedulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(businessCapabilitiesProvider);
    if (caps.isLoading) return const Center(child: CircularProgressIndicator());
    final scope = ref.watch(activeTenantContextProvider);
    final repository = ref.watch(lkTaxRepositoryProvider);
    if (caps.hasError ||
        scope == null ||
        !scope.hasOperationalScope ||
        repository == null ||
        !caps.value!.contains('finance.view')) {
      return const Center(
        child: Text('Choose an entity and branch with tax review access.'),
      );
    }
    return LkTaxWorkspace(
      key: ValueKey(scope),
      scope: scope,
      permissions: caps.value!,
      repository: repository,
      files: ref.watch(reportExportFilesProvider),
    );
  }
}

String _previousMonth() {
  final now = DateTime.now();
  final month = DateTime(now.year, now.month - 1);
  return '${month.year}-${month.month.toString().padLeft(2, '0')}';
}

class LkTaxWorkspace extends StatefulWidget {
  const LkTaxWorkspace({
    required this.scope,
    required this.permissions,
    required this.repository,
    this.files,
    super.key,
  });

  final TenantContext scope;
  final Set<String> permissions;
  final LkTaxRepository repository;
  final ReportExportFiles? files;

  @override
  State<LkTaxWorkspace> createState() => _LkTaxWorkspaceState();
}

class _LkTaxWorkspaceState extends State<LkTaxWorkspace> {
  bool _busy = true, _quarter = false;
  String? _error, _notice;
  List<LkVatMappingRow> _rows = const [];
  final Map<String, LkVatLine> _choices = {};
  LkVatReturn? _return;
  List<LkSsclSettings> _ssclSettings = const [];
  LkSsclReturn? _sscl;
  bool _ssclZero = false, _ssclExempt = false;
  final _reason = TextEditingController(),
      _month = TextEditingController(text: _previousMonth()),
      _ssclFrom = TextEditingController(text: '2026-04'),
      _ssclTo = TextEditingController(text: '2027-04'),
      _ssclRate = TextEditingController(text: '2.5'),
      _ssclPortion = TextEditingController(text: '100'),
      _ssclActivity = TextEditingController(),
      _ssclReason = TextEditingController(),
      _ssclQuarter = TextEditingController(text: '2026-04');

  bool get _approve =>
      widget.permissions.contains('finance.classifications.approve');
  bool get _export => widget.permissions.contains('finance.reports.export');

  @override
  void initState() {
    super.initState();
    _act(_load);
  }

  @override
  void dispose() {
    for (final c in [
      _reason,
      _month,
      _ssclFrom,
      _ssclTo,
      _ssclRate,
      _ssclPortion,
      _ssclActivity,
      _ssclReason,
      _ssclQuarter,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await widget.repository.vatMappings(widget.scope);
    final settings = await widget.repository.ssclSettings(widget.scope);
    if (mounted) {
      setState(() {
        _rows = rows;
        _ssclSettings = settings;
      });
    }
  }

  static final _monthPattern = RegExp(r'^[0-9]{4}-(0[1-9]|1[0-2])$');
  static final _percentPattern = RegExp(
    r'^(0|[1-9][0-9]?|100)(\.[0-9]{1,6})?$',
  );

  Future<void> _proposeSscl() async {
    final from = _ssclFrom.text.trim(), to = _ssclTo.text.trim();
    if (!_monthPattern.hasMatch(from) ||
        !_monthPattern.hasMatch(to) ||
        !_percentPattern.hasMatch(_ssclRate.text.trim()) ||
        !_percentPattern.hasMatch(_ssclPortion.text.trim()) ||
        _ssclActivity.text.trim().isEmpty ||
        _ssclReason.text.trim().isEmpty) {
      setState(
        () => _error = 'Enter months as YYYY-MM, percentages from 0 to 100, the activity and a reason.',
      );
      return;
    }
    await _act(() async {
      await widget.repository.proposeSsclSettings(
        widget.scope,
        id: _uuid.v4(),
        effectiveFrom: '$from-01',
        effectiveToExclusive: '$to-01',
        ratePercent: _ssclRate.text.trim(),
        liablePortionPercent: _ssclPortion.text.trim(),
        includeZeroRated: _ssclZero,
        includeExempt: _ssclExempt,
        activity: _ssclActivity.text.trim(),
        reason: _ssclReason.text.trim(),
      );
      await _load();
    }, done: 'SSCL settings proposed. Another approver must check them.');
  }

  Future<void> _decideSscl(LkSsclSettings s, String action) async {
    if (action == 'approve') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => _ConfirmDialog(
          title:
              'Approve SSCL at ${s.ratePercent.toDecimalString()}% on a ${s.liablePortionPercent.toDecimalString()}% portion?',
          statement: 'I checked the rate, liable portion and treatment of exports and exempt sales against the SSCL Act and IRD guidance.',
        ),
      );
      if (confirmed != true) return;
    }
    await _act(
      () async {
        await widget.repository.decideSsclSettings(widget.scope, s.id, action);
        await _load();
      },
      done: switch (action) {
        'approve' => 'SSCL settings approved.',
        _ => 'SSCL settings retired.',
      },
    );
  }

  Future<void> _prepareSscl() async {
    final quarter = _ssclQuarter.text.trim();
    if (!RegExp(r'^[0-9]{4}-(01|04|07|10)$').hasMatch(quarter)) {
      setState(
        () => _error =
            'Enter the quarter start as YYYY-01, YYYY-04, YYYY-07 or YYYY-10.',
      );
      return;
    }
    await _act(() async {
      final prepared = await widget.repository.ssclReturn(
        widget.scope,
        quarterStart: '$quarter-01',
      );
      if (mounted) setState(() => _sscl = prepared);
    });
  }

  Future<void> _saveSscl() => _act(() async {
    final prepared = _sscl!;
    final path = await widget.files!.choose(
      'sscl-workpaper-${prepared.quarterStart.substring(0, 7)}.csv',
    );
    if (path == null) return;
    await widget.files!.write(
      path,
      Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(prepared.toCsv())]),
      'text/csv',
    );
    if (mounted) setState(() => _notice = 'SSCL workpaper saved to $path.');
  });

  List<Widget> _ssclSection() {
    final prepared = _sscl;
    return [
      const Text(
        'SSCL is due on turnover, including sales without a tax code. Settings count only after a second approver confirms them.',
      ),
      for (final s in _ssclSettings)
        Wrap(
          key: ValueKey(s.id),
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${s.effectiveFrom} to ${s.effectiveToExclusive}: ${s.ratePercent.toDecimalString()}% on '
              '${s.liablePortionPercent.toDecimalString()}% of turnover (${s.activity}) · ${s.status}',
            ),
            if (_approve && s.status == 'pending')
              FilledButton(
                onPressed: _busy ? null : () => _decideSscl(s, 'approve'),
                child: const Text('Approve SSCL'),
              ),
            if (s.status != 'retired')
              OutlinedButton(
                onPressed: _busy ? null : () => _decideSscl(s, 'retire'),
                child: Text(s.status == 'pending' ? 'Withdraw' : 'Retire'),
              ),
          ],
        ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (label, controller) in [
            ('From (YYYY-MM)', _ssclFrom),
            ('To, exclusive (YYYY-MM)', _ssclTo),
            ('Rate %', _ssclRate),
            ('Liable portion %', _ssclPortion),
          ])
            SizedBox(
              width: 170,
              child: TextField(
                controller: controller,
                decoration: InputDecoration(labelText: label),
              ),
            ),
          SizedBox(
            width: 260,
            child: TextField(
              controller: _ssclActivity,
              decoration: const InputDecoration(labelText: 'Business activity'),
            ),
          ),
          FilterChip(
            label: const Text('Count exports'),
            selected: _ssclZero,
            onSelected: (v) => setState(() => _ssclZero = v),
          ),
          FilterChip(
            label: const Text('Count exempt sales'),
            selected: _ssclExempt,
            onSelected: (v) => setState(() => _ssclExempt = v),
          ),
        ],
      ),
      TextField(
        controller: _ssclReason,
        decoration: const InputDecoration(
          labelText: 'Reason for the SSCL settings',
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          onPressed: _busy ? null : _proposeSscl,
          child: const Text('Propose SSCL settings'),
        ),
      ),
      if (_export) ...[
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 170,
              child: TextField(
                controller: _ssclQuarter,
                decoration: const InputDecoration(
                  labelText: 'Quarter start (YYYY-MM)',
                ),
              ),
            ),
            OutlinedButton(
              onPressed: _busy ? null : _prepareSscl,
              child: const Text('Prepare SSCL workpaper'),
            ),
          ],
        ),
        if (prepared != null) ...[
          Text(
            '${prepared.quarterStart} to ${prepared.quarterEndExclusive} (exclusive)',
          ),
          for (final MapEntry(:key, :value) in prepared.turnover.entries)
            Text('$key: Rs ${lkTaxTwo(value)}'),
          Text('Turnover counted Rs ${lkTaxTwo(prepared.includedTurnover)}'),
          if (prepared.ssclDue != null)
            Text(
              'Liable turnover Rs ${lkTaxTwo(prepared.liableTurnover!)} · SSCL due Rs ${lkTaxTwo(prepared.ssclDue!)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          for (final b in prepared.blockers)
            Text(
              '• ${b.documentNumber ?? ''} ${b.message}'.trim(),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (widget.files != null)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: _busy ? null : _saveSscl,
                child: const Text('Save SSCL CSV'),
              ),
            ),
        ],
      ],
    ];
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

  Future<void> _propose(LkVatMappingRow row) async {
    final line = _choices[row.taxDefinitionId];
    if (line == null || _reason.text.trim().isEmpty) {
      setState(() => _error = 'Choose a VAT return line and give a reason.');
      return;
    }
    await _act(() async {
      await widget.repository.proposeVatMapping(
        widget.scope,
        id: _uuid.v4(),
        taxDefinitionId: row.taxDefinitionId,
        line: line,
        reason: _reason.text.trim(),
      );
      await _load();
    }, done: '${row.code} mapping proposed. Another approver must check it.');
  }

  Future<void> _decide(
    LkVatMappingRow row,
    LkVatMapping mapping,
    String action,
  ) async {
    if (action == 'approve') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => _ConfirmDialog(
          title: 'Approve ${row.code} → ${mapping.line.label}?',
          statement:
              'I checked this treatment against the IRD VAT return guidance.',
        ),
      );
      if (confirmed != true) return;
    }
    await _act(
      () async {
        await widget.repository.decideVatMapping(
          widget.scope,
          mapping.id,
          action,
        );
        await _load();
      },
      done: action == 'approve'
          ? '${row.code} mapping approved.'
          : '${row.code} mapping withdrawn.',
    );
  }

  Future<void> _prepare() async {
    final month = _month.text.trim();
    if (!RegExp(r'^[0-9]{4}-(0[1-9]|1[0-2])$').hasMatch(month)) {
      setState(
        () => _error = 'Enter the first month as YYYY-MM, for example 2026-04.',
      );
      return;
    }
    final start = DateTime.utc(
      int.parse(month.substring(0, 4)),
      int.parse(month.substring(5)),
    );
    final end = DateTime.utc(start.year, start.month + (_quarter ? 3 : 1));
    String iso(DateTime d) => d.toIso8601String().substring(0, 10);
    await _act(() async {
      final prepared = await widget.repository.vatReturn(
        widget.scope,
        from: iso(start),
        toExclusive: iso(end),
      );
      if (mounted) setState(() => _return = prepared);
    });
  }

  Future<void> _save() => _act(() async {
    final prepared = _return!;
    final path = await widget.files!.choose(
      'vat-workpaper-${prepared.from.substring(0, 7)}.csv',
    );
    if (path == null) return;
    // A byte order mark lets spreadsheet apps read Sinhala and Tamil names.
    await widget.files!.write(
      path,
      Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(prepared.toCsv())]),
      'text/csv',
    );
    if (mounted) setState(() => _notice = 'Workpaper saved to $path.');
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final prepared = _return;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Sri Lanka tax schedules', style: text.headlineMedium),
            const Chip(label: Text('Candidate · development')),
            OutlinedButton(
              onPressed: _busy ? null : () => _act(_load),
              child: const Text('Reload'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Workpapers for review by your accountant before filing. They are not certified returns.',
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
        _section(context, 'VAT return mappings', [
          const Text(
            'Map each tax code to its IRD VAT return line. Mappings count only after a second approver confirms them.',
          ),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(
              labelText: 'Reason for new mappings',
            ),
          ),
          if (_rows.isEmpty)
            const Text('No tax codes yet. Add them in business setup.'),
          for (final row in _rows) _mappingRow(row),
        ]),
        if (_export)
          _section(context, 'VAT workpaper', [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 170,
                  child: TextField(
                    controller: _month,
                    decoration: const InputDecoration(
                      labelText: 'First month (YYYY-MM)',
                    ),
                  ),
                ),
                ChoiceChip(
                  label: const Text('Month'),
                  selected: !_quarter,
                  onSelected: (_) => setState(() => _quarter = false),
                ),
                ChoiceChip(
                  label: const Text('Quarter'),
                  selected: _quarter,
                  onSelected: (_) => setState(() => _quarter = true),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _prepare,
                  child: const Text('Prepare workpaper'),
                ),
              ],
            ),
            if (prepared != null) ..._workpaper(prepared),
          ]),
        _section(context, 'SSCL quarterly workpaper', _ssclSection()),
      ],
    );
  }

  Widget _mappingRow(LkVatMappingRow row) {
    final suitable = LkVatLine.values
        .where((l) => l.suits(row.kind, row.rate))
        .toList();
    final current = _choices[row.taxDefinitionId];
    return Card(
      key: ValueKey(row.taxDefinitionId),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 6,
          children: [
            Text(
              '${row.code} · ${row.name} · ${row.kind} ${row.rate.toDecimalString()}%',
            ),
            Text(
              row.approved == null
                  ? 'Not mapped'
                  : 'Approved: ${row.approved!.line.label}',
              style: row.approved == null
                  ? TextStyle(color: Theme.of(context).colorScheme.error)
                  : null,
            ),
            for (final p in row.pending)
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Pending: ${p.line.label} (${p.reason})'),
                  if (_approve)
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _decide(row, p, 'approve'),
                      child: const Text('Approve'),
                    ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _decide(row, p, 'retire'),
                    child: const Text('Withdraw'),
                  ),
                ],
              ),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final l in suitable)
                  ChoiceChip(
                    label: Text(l.label),
                    selected: current == l,
                    onSelected: (_) =>
                        setState(() => _choices[row.taxDefinitionId] = l),
                  ),
                OutlinedButton(
                  onPressed: _busy || current == null
                      ? null
                      : () => _propose(row),
                  child: const Text('Propose'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _workpaper(LkVatReturn r) => [
    Text(
      '${r.from} to ${r.toExclusive} (exclusive) · entity TIN ${r.entityTin ?? 'not recorded'}',
    ),
    for (final l in r.lines)
      Text(
        '${l.line.label}: value Rs ${lkTaxTwo(l.value)} · VAT Rs ${lkTaxTwo(l.tax)}',
      ),
    Text(
      'Output tax Rs ${lkTaxTwo(r.outputTax)} · input tax claimable Rs ${lkTaxTwo(r.inputTaxClaimable)}',
    ),
    Text(
      '${r.refundable ? 'Net refundable' : 'Net payable'} Rs ${lkTaxTwo(r.netPayable)}',
      style: Theme.of(context).textTheme.titleMedium,
    ),
    Text(
      '${r.outputSchedule.length} supplies and ${r.inputSchedule.length} purchases in the schedules.',
    ),
    if (r.blockers.isNotEmpty) ...[
      Text(
        '${r.blockers.length} lines need attention before filing:',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      for (final b in r.blockers.take(20))
        Text('• ${b.documentNumber ?? ''} ${b.message}'),
      if (r.blockers.length > 20)
        Text('… and ${r.blockers.length - 20} more in the saved CSV.'),
    ],
    if (widget.files != null)
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Save CSV'),
        ),
      ),
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

class _ConfirmDialog extends StatefulWidget {
  const _ConfirmDialog({required this.title, required this.statement});
  final String title, statement;

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: CheckboxListTile(
      value: _checked,
      onChanged: (v) => setState(() => _checked = v ?? false),
      title: Text(widget.statement),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _checked ? () => Navigator.pop(context, true) : null,
        child: const Text('Approve'),
      ),
    ],
  );
}

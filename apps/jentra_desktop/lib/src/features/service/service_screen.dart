import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_service.dart';

import '../../app_providers.dart';
import 'service_controller.dart';

String serviceLabel(String value) => switch (value) {
  'order' => 'Work orders',
  'policy' => 'SLA policies',
  'coverage' => 'Contracts and warranties',
  'plan' => 'Maintenance plans',
  'reading' => 'Meter readings',
  'occurrence' => 'Maintenance occurrences',
  'labor' => 'Labor',
  'equipment' => 'Equipment',
  'ticket' => 'Tickets',
  'approve_labor' => 'Approve labor',
  'cancel_labor' => 'Cancel original labor',
  'cancel_order' => 'Cancel work order',
  'cancel_ticket' => 'Cancel ticket',
  'generate' => 'Generate due maintenance',
  'defer' => 'Defer maintenance',
  'reprioritize' => 'Change priority and SLA',
  'evaluate' => 'Evaluate SLA',
  _ =>
    value
        .replaceAll('_', ' ')
        .split(' ')
        .map((x) => x.isEmpty ? x : '${x[0].toUpperCase()}${x.substring(1)}')
        .join(' '),
};

class ServiceScreen extends ConsumerWidget {
  const ServiceScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(businessCapabilitiesProvider);
    if (caps.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (caps.hasError) {
      return Center(
        child: TextButton(
          onPressed: () => ref.invalidate(businessCapabilitiesProvider),
          child: const Text('Retry service access'),
        ),
      );
    }
    final c = ref.watch(serviceControllerProvider);
    return c == null
        ? const Center(
            child: Text('Choose an entity and branch with service access.'),
          )
        : ServiceWorkspace(key: ValueKey(c), controller: c);
  }
}

class ServiceWorkspace extends StatefulWidget {
  const ServiceWorkspace({super.key, required this.controller});
  final ServiceController controller;
  @override
  State<ServiceWorkspace> createState() => _ServiceWorkspaceState();
}

class _ServiceWorkspaceState extends State<ServiceWorkspace> {
  ServiceController get c => widget.controller;
  String search = '';
  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _run(Future<void> Function() work) async {
    try {
      await work();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is FormatException
                  ? e.message
                  : 'The service action could not be completed.',
            ),
          ),
        );
      }
    }
  }

  void _begin(String action, {bool existing = false}) => unawaited(
    _run(() async {
      await c.begin(action, target: existing ? c.selected?.record : null);
    }),
  );
  List<String> get actions {
    final r = c.selected?.record;
    if (r == null) {
      return [];
    }
    final row = r.toJson();
    return switch (r.kind) {
      ServiceKind.equipment => ['coverage', 'plan', 'reading'],
      ServiceKind.ticket =>
        r.status == 'open'
            ? ['order', 'pause', 'reprioritize', 'evaluate', 'cancel_ticket']
            : r.status == 'paused'
            ? ['resume', 'reprioritize', 'cancel_ticket']
            : [],
      ServiceKind.order => switch (r.status) {
        'planned' => ['dispatch', 'cancel_order'],
        'dispatched' => ['accept', 'cancel_order'],
        'accepted' => ['start', 'labor', 'complete', 'cancel_order'],
        'working' => ['labor', 'complete', 'cancel_order'],
        'completed' => ['close'],
        _ => [],
      },
      ServiceKind.labor =>
        r.status == 'submitted'
            ? ['approve_labor', 'cancel_labor']
            : r.status == 'approved' && row['billing_consumption_id'] == null
            ? ['cancel_labor']
            : [],
      ServiceKind.plan => ['generate'],
      ServiceKind.occurrence => ['defer'],
      _ => [],
    };
  }

  @override
  Widget build(BuildContext context) {
    if (c.denied) {
      return const Center(
        child: Text(
          'Current service access is required. Select an authorized scope.',
        ),
      );
    }
    final visible = c.records
        .where((r) => r.label.toLowerCase().contains(search.toLowerCase()))
        .toList();
    return PopScope(
      canPop: c.pending == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_run(c.save));
        }
      },
      child: FocusTraversalGroup(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Service', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            const Text(
              'Customer equipment, service delivery and preventive maintenance. Billing eligibility, invoicing and payment have separate evidence.',
            ),
            if (!c.online)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Offline. Encrypted drafts remain available; reconnect to authorize and send.',
                ),
              ),
            if (c.busy) const LinearProgressIndicator(),
            if (c.error != null) _notice(c.error!, error: true),
            if (c.message != null) _notice(c.message!),
            if (c.authority != null &&
                (!c.authority!.parts || !c.authority!.assets))
              _notice(
                'Service stock reservation, issue, return and internal asset identity require their reviewed installed providers.',
              ),
            if (c.authority != null && !c.authority!.billing)
              _notice(
                'Approved billable labor is preserved for the billing workspace. The direct service invoice adapter is unavailable.',
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in ServiceKind.values)
                  ChoiceChip(
                    label: Text(serviceLabel(k.name)),
                    selected: c.kind == k,
                    onSelected: c.busy
                        ? null
                        : (_) => unawaited(
                            _run(() async {
                              await c.selectKind(k);
                            }),
                          ),
                  ),
                OutlinedButton.icon(
                  onPressed: c.busy ? null : () => unawaited(_run(c.refresh)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Filter this loaded page',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (x) => setState(() => search = x),
            ),
            const SizedBox(height: 12),
            if ({
                  'equipment',
                  'policy',
                  'ticket',
                  'plan',
                }.contains(c.kind.name) &&
                c.has(ServiceCommands.capability(c.kind.name)))
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: c.locked ? null : () => _begin(c.kind.name),
                  icon: const Icon(Icons.add),
                  label: Text(
                    'Create ${serviceLabel(c.kind.name).toLowerCase()}',
                  ),
                ),
              ),
            if (visible.isEmpty && !c.busy)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No service records on this page.'),
              ),
            for (final r in visible)
              Card(
                child: ListTile(
                  isThreeLine: true,
                  title: Text(r.label),
                  subtitle: Text(
                    '${serviceLabel(r.kind.name)} · ${r.status ?? 'recorded'} · version ${r.version}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: c.busy ? null : () => unawaited(_run(() => c.open(r))),
                ),
              ),
            if (c.cursor != null)
              TextButton(
                onPressed: c.busy
                    ? null
                    : () => unawaited(_run(() => c.refresh(more: true))),
                child: const Text('Load more records'),
              ),
            if (c.selected != null) ...[
              const SizedBox(height: 20),
              _section(c.selected!.record.label, [
                _facts(c.selected!.record.toJson()),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in actions.where(
                      (a) => c.has(ServiceCommands.capability(a)),
                    ))
                      OutlinedButton(
                        onPressed: c.locked
                            ? null
                            : () => _begin(
                                a,
                                existing: !{
                                  'coverage',
                                  'plan',
                                  'reading',
                                  'order',
                                  'labor',
                                }.contains(a),
                              ),
                        child: Text(serviceLabel(a)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Attributable history',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final event in c.selected!.events)
                  ExpansionTile(
                    title: Text(
                      '${serviceLabel(event.toJson()['action'] as String)} · version ${event.version}',
                    ),
                    subtitle: Text(event.toJson()['reason'] as String),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: _facts(event.toJson()),
                      ),
                    ],
                  ),
                if (c.selected!.nextCursor != null)
                  TextButton(
                    onPressed: c.busy
                        ? null
                        : () => unawaited(
                            _run(() => c.open(c.selected!.record, more: true)),
                          ),
                    child: const Text('Load more history'),
                  ),
              ]),
            ],
            if (c.form != null)
              _section(serviceLabel(c.action!), [
                ServiceEditor(
                  key: ValueKey(
                    '${c.form!['id']}.${c.action}.${c.expectedVersion}',
                  ),
                  controller: c,
                ),
                if (c.pending != null)
                  _notice(
                    'The original encrypted request is pending. Its exact content is frozen. Reconcile or retry it.',
                  ),
                if (c.conflicted)
                  _notice(
                    'The server version changed. Compare it before explicitly replacing the draft basis.',
                    error: true,
                  ),
                if (c.comparison != null)
                  _section('Current server record', [
                    _facts(c.comparison!.record.toJson()),
                    TextButton(
                      onPressed: () => unawaited(_run(c.adoptComparison)),
                      child: const Text('Use this version for the saved draft'),
                    ),
                  ]),
                if (c.confirmed != null)
                  _notice(
                    'The command is confirmed. Local cleanup or a subsequent read cannot undo this result.',
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (c.pending != null)
                      OutlinedButton(
                        onPressed: c.busy
                            ? null
                            : () => unawaited(_run(c.reconcile)),
                        child: const Text('Reconcile original request'),
                      ),
                    if (c.conflicted)
                      OutlinedButton(
                        onPressed: c.busy
                            ? null
                            : () => unawaited(_run(c.compare)),
                        child: const Text('Compare current version'),
                      ),
                    if (c.pending == null &&
                        !c.conflicted &&
                        c.confirmed == null)
                      OutlinedButton(
                        onPressed: c.busy
                            ? null
                            : () => unawaited(_run(c.save)),
                        child: const Text('Save encrypted draft'),
                      ),
                    if (c.confirmed == null && !c.conflicted)
                      FilledButton(
                        onPressed: c.busy || !c.online
                            ? null
                            : () => unawaited(_run(c.send)),
                        child: Text(
                          c.pending != null
                              ? 'Retry original request'
                              : 'Submit ${serviceLabel(c.action!).toLowerCase()}',
                        ),
                      ),
                    if (c.pending == null)
                      TextButton(
                        onPressed: c.busy
                            ? null
                            : () => unawaited(_run(c.discard)),
                        child: Text(
                          c.confirmed != null
                              ? 'Close confirmed result'
                              : 'Discard draft',
                        ),
                      ),
                  ],
                ),
              ]),
            _section('Encrypted recovery', [
              if (c.recovery.isEmpty) const Text('No authorized saved drafts.'),
              for (final saved in c.recovery)
                ListTile(
                  title: Text(serviceLabel(saved.action)),
                  subtitle: Text(
                    saved.draft.pending != null
                        ? 'Original request pending'
                        : 'Saved draft · version ${saved.draft.version}',
                  ),
                  onTap: c.busy
                      ? null
                      : () => unawaited(_run(() => c.resume(saved))),
                ),
              TextButton(
                onPressed: c.busy
                    ? null
                    : () => unawaited(_run(c.loadRecovery)),
                child: const Text('Refresh recovery'),
              ),
              for (final entry in c.recoveryCursors.entries.where(
                (x) => x.value != null,
              ))
                TextButton(
                  onPressed: c.busy
                      ? null
                      : () => unawaited(
                          _run(() => c.loadRecovery(moreAction: entry.key)),
                        ),
                  child: Text(
                    'More ${serviceLabel(entry.key).toLowerCase()} drafts',
                  ),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Card(
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
  Widget _notice(String text, {bool error = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      style: TextStyle(
        color: error ? Theme.of(context).colorScheme.error : null,
      ),
    ),
  );
  Widget _facts(Map<String, Object?> row) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final entry in row.entries.where((x) => x.value != null))
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: SelectableText(
            '${serviceLabel(entry.key)}: ${entry.value is Map ? 'recorded source evidence' : entry.value}',
          ),
        ),
    ],
  );
}

class ServiceEditor extends StatefulWidget {
  const ServiceEditor({super.key, required this.controller});
  final ServiceController controller;
  @override
  State<ServiceEditor> createState() => _ServiceEditorState();
}

class _ServiceEditorState extends State<ServiceEditor> {
  ServiceController get c => widget.controller;
  final inputs = <String, TextEditingController>{};
  @override
  void dispose() {
    for (final value in inputs.values) {
      value.dispose();
    }
    super.dispose();
  }

  static const choices = {
    'customer_id': 'customer',
    'contact_id': 'contact',
    'employee_id': 'employee',
    'owner_id': 'employee',
    'calendar_version_id': 'calendar',
    'equipment_id': 'equipment',
    'coverage_id': 'coverage',
    'policy_id': 'policy',
    'ticket_id': 'ticket',
    'order_id': 'order',
    'claim_id': 'claim',
  };
  static const options = {
    'priority': ['low', 'normal', 'high', 'urgent'],
    'billing_kind': ['nonbillable', 'billable'],
    'basis': ['calendar', 'meter'],
  };
  Future<void> _choose(String field) async {
    final formId = c.form?['id'], formAction = c.action;
    final choice = await showDialog<ServiceChoice>(
      context: context,
      builder: (context) => _ServicePicker(
        controller: c,
        kind: choices[field]!,
        title: serviceLabel(field.replaceAll('_id', '')),
      ),
    );
    if (choice != null &&
        mounted &&
        c.current &&
        c.form?['id'] == formId &&
        c.action == formAction) {
      await c.choose(field, choice);
    }
  }

  Widget _input(
    String field, {
    String? label,
    Map<String, Object?>? entry,
    String? entryKey,
    void Function(String)? update,
  }) {
    final data = entry ?? c.form!,
        key = entry == null ? field : '$entryKey.$field';
    final controller = inputs.putIfAbsent(
      key,
      () => TextEditingController(text: data[field]?.toString() ?? ''),
    );
    final text = data[field]?.toString() ?? '';
    if (controller.text != text) {
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        enabled: !c.locked,
        minLines: 1,
        maxLines: {'reason', 'resolution', 'exception_reason'}.contains(field)
            ? 3
            : 1,
        decoration: InputDecoration(
          labelText: label ?? serviceLabel(field),
          helperText: field.endsWith('_utc')
              ? 'UTC instant: YYYY-MM-DDTHH:MM:SSZ'
              : field.endsWith('_date') ||
                    field == 'end_date_exclusive' ||
                    field == 'deferred_until'
              ? 'Civil date: YYYY-MM-DD'
              : null,
        ),
        onChanged:
            update ??
            (value) {
              final original = c.form![field];
              c.edit(
                field,
                original is int ||
                        {
                          'next_meter',
                          'rollover_max',
                          'interval_units',
                          'response_seconds',
                          'resolution_seconds',
                          'raw_value',
                        }.contains(field)
                    ? int.tryParse(value) ?? value
                    : value.isEmpty &&
                          {
                            'exception_reason',
                            'claim_id',
                            'rollover_max',
                          }.contains(field)
                    ? null
                    : value,
              );
            },
        textInputAction: field == 'reason'
            ? TextInputAction.done
            : TextInputAction.next,
        onSubmitted: field == 'reason' ? (_) => unawaited(c.send()) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = c.action!, row = c.form!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Expected version ${c.expectedVersion}. Approval, invoice and payment are separate decisions.',
        ),
        const SizedBox(height: 14),
        for (final field in ServiceCommands.fields(a).where(
          (x) =>
              !{
                'action',
                'id',
                'booking_id',
                'occurrence_id',
                'currency_code',
                'precision',
                'breaks',
                'offsets',
                'provider_id',
              }.contains(x) &&
              !(a == 'generate' && {'ticket_id', 'order_id'}.contains(x)),
        ))
          if (choices.containsKey(field))
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: OutlinedButton(
                onPressed: c.locked ? null : () => unawaited(_choose(field)),
                child: Text(
                  '${serviceLabel(field.replaceAll('_id', ''))}: ${c.labels[field] ?? (row[field] != null ? 'Recorded choice ${row[field].toString().substring(0, 8)}' : 'Choose')}',
                ),
              ),
            )
          else if (field == 'kind')
            _select(
              field,
              a == 'equipment'
                  ? ['customer']
                  : a == 'coverage'
                  ? ['contract', 'warranty']
                  : ['initial', 'reading', 'reset', 'rollover'],
            )
          else if (options.containsKey(field))
            _select(field, options[field]!)
          else if (row[field] is bool)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(serviceLabel(field)),
              value: row[field] as bool,
              onChanged: c.locked ? null : (value) => c.edit(field, value),
            )
          else if (field == 'next_date' && row['basis'] == 'meter' ||
              field == 'next_meter' && row['basis'] == 'calendar')
            const SizedBox.shrink()
          else
            _input(field),
        if (a == 'labor') ...[
          Text(
            'Rates use ${row['currency_code']} and half-even rounding to ${row['precision']} decimals. A billing reference explicitly records contract terms or the nonbillable decision.',
          ),
          _nested('breaks', ['start_utc', 'end_utc'], 'Unpaid breaks'),
        ],
        if (a == 'policy')
          _nested('offsets', [
            'date',
            'start_minute',
            'start_offset_seconds',
            'end_offset_seconds',
          ], 'Ambiguous calendar boundary choices'),
        if (a == 'generate')
          const Text(
            'This request saves the original occurrence, ticket and work order identifiers before it is sent. Retry reuses that occurrence.',
          ),
      ],
    );
  }

  Widget _select(String field, List<String> values) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: DropdownButtonFormField<String>(
      initialValue: rowValue(field),
      isExpanded: true,
      decoration: InputDecoration(labelText: serviceLabel(field)),
      items: values
          .map((v) => DropdownMenuItem(value: v, child: Text(serviceLabel(v))))
          .toList(),
      onChanged: c.locked ? null : (v) => c.edit(field, v),
    ),
  );
  String? rowValue(String field) => c.form![field] as String?;
  Widget _nested(String field, List<String> fields, String title) {
    final values = (c.form![field] as List).map(serviceMap).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title),
        for (var i = 0; i < values.length; i++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  for (final f in fields)
                    _input(
                      f,
                      entry: values[i],
                      entryKey: '$field.$i',
                      update: (v) {
                        final copy = values
                            .map((x) => Map<String, Object?>.from(x))
                            .toList();
                        copy[i][f] =
                            f.endsWith('_seconds') || f == 'start_minute'
                            ? int.tryParse(v) ?? v
                            : v;
                        c.edit(field, copy);
                      },
                    ),
                  TextButton(
                    onPressed: c.locked
                        ? null
                        : () {
                            values.removeAt(i);
                            c.edit(field, values);
                          },
                    child: const Text('Remove boundary'),
                  ),
                ],
              ),
            ),
          ),
        TextButton(
          onPressed:
              c.locked || values.length >= (field == 'breaks' ? 16 : 2000)
              ? null
              : () => c.edit(field, [
                  ...values,
                  {
                    for (final f in fields)
                      f: f.endsWith('_seconds') || f == 'start_minute' ? 0 : '',
                  },
                ]),
          child: Text('Add ${field == 'breaks' ? 'break' : 'offset choice'}'),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}

class _ServicePicker extends StatefulWidget {
  const _ServicePicker({
    required this.controller,
    required this.kind,
    required this.title,
  });
  final ServiceController controller;
  final String kind, title;
  @override
  State<_ServicePicker> createState() => _ServicePickerState();
}

class _ServicePickerState extends State<_ServicePicker> {
  List<ServiceChoice> rows = [];
  String? cursor, error;
  bool busy = false;
  String search = '';
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load({bool more = false}) async {
    setState(() => busy = true);
    try {
      final page = await widget.controller.choices(
        widget.kind,
        after: more ? cursor : null,
      );
      if (!mounted || !widget.controller.current) {
        return;
      }
      setState(() {
        rows = more ? [...rows, ...page.items] : page.items;
        cursor = page.nextCursor;
        error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'These scoped choices are unavailable. Retry after checking current access.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Choose ${widget.title.toLowerCase()}'),
    content: SizedBox(
      width: 560,
      height: 450,
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(
              labelText: 'Filter loaded choices',
            ),
            onChanged: (v) => setState(() => search = v),
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          Expanded(
            child: ListView(
              children: [
                for (final row in rows.where(
                  (r) => r.name.toLowerCase().contains(search.toLowerCase()),
                ))
                  ListTile(
                    title: Text(row.name),
                    subtitle: Text('Version ${row.version}'),
                    onTap: widget.controller.current
                        ? () => Navigator.of(context).pop(row)
                        : null,
                  ),
                if (rows.isEmpty && !busy)
                  const Text('No authorized choices on this page.'),
                if (cursor != null)
                  TextButton(
                    onPressed: busy ? null : () => unawaited(load(more: true)),
                    child: const Text('Load more choices'),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      if (error != null)
        TextButton(
          onPressed: busy ? null : () => unawaited(load()),
          child: const Text('Retry'),
        ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
    ],
  );
}

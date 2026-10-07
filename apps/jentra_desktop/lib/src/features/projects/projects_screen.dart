import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_domain/jentra_projects.dart';

import '../../app_providers.dart';
import 'projects_controller.dart';

String projectActionLabel(String a) => switch (a) {
  'create' => 'Create project',
  'plan' => 'Prepare plan',
  'approve_plan' => 'Approve exact plan',
  'reject_plan' => 'Reject exact plan',
  'progress' => 'Record progress',
  'waive' => 'Mark non-billable',
  'time_create' => 'Record project time',
  'time_correct' => 'Revise unconsumed time',
  'time_submit' => 'Submit time',
  'time_approve' => 'Approve time',
  'time_reject' => 'Reject time',
  'time_cancel' => 'Cancel original time',
  'close' => 'Close project',
  _ => a,
};

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});
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
          child: const Text('Retry project access'),
        ),
      );
    }
    final c = ref.watch(projectsControllerProvider);
    if (c == null) {
      return const Center(
        child: Text('Choose an entity and branch with project access.'),
      );
    }
    return ProjectsWorkspace(key: ValueKey(c), controller: c);
  }
}

class ProjectsWorkspace extends StatefulWidget {
  const ProjectsWorkspace({super.key, required this.controller});
  final ProjectsController controller;
  @override
  State<ProjectsWorkspace> createState() => _ProjectsWorkspaceState();
}

class _ProjectsWorkspaceState extends State<ProjectsWorkspace> {
  ProjectsController get c => widget.controller;
  Widget _card(String title, List<Widget> children) => Card(
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
  Widget _buttons(List<Widget> children) =>
      Wrap(spacing: 8, runSpacing: 8, children: children);
  Widget _button(String label, VoidCallback work, {bool enabled = true}) =>
      OutlinedButton(
        onPressed: enabled && !c.busy && c.current ? work : null,
        child: Text(label),
      );
  Future<void> _safe(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This named source or calendar could not be verified. Refresh and try again.',
            ),
          ),
        );
      }
    }
  }

  Future<ProjectChoice?> _choice(String kind, {bool optional = false}) =>
      showDialog<ProjectChoice>(
        context: context,
        builder: (context) =>
            _ProjectChoiceDialog(controller: c, kind: kind, optional: optional),
      );
  Widget _field(String key, String label, {int lines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      key: ValueKey('${c.form?['id']}-${c.expectedVersion}-$key'),
      initialValue: c.form?[key]?.toString() ?? '',
      enabled: !c.locked,
      decoration: InputDecoration(labelText: label),
      maxLines: lines,
      onChanged: (v) => c.edit(key, key == 'progress' ? int.tryParse(v) : v),
    ),
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Projects, time and expenses',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Synthetic project planning, exact common time, expenses and billing. Open a project to review its financial sources.',
        ),
        if (!c.online)
          const Text(
            'Offline. Saved requests remain encrypted; reconnect before reading or sending.',
          ),
        if (c.busy) const LinearProgressIndicator(),
        if (c.error != null)
          Text(
            c.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (c.message != null) Text(c.message!),
        const SizedBox(height: 12),
        _buttons([
          _button('Refresh', () => unawaited(c.refresh())),
          if (c.has('projects.manage'))
            _button(
              'Create project',
              () => unawaited(c.begin('create')),
              enabled: !c.locked,
            ),
        ]),
        _card('Project register', [
          if (c.records.isEmpty)
            const Text('No projects are available in this branch.'),
          for (final r in c.records)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${r.code} · ${r.name}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${r.status} · ${r.currency} · ${r.start.value} to ${r.end.value} (exclusive) · version ${r.version}',
                  ),
                  Text(
                    'Manager: ${r.managerName} · Customer: ${r.customerName ?? 'Internal project'}',
                  ),
                  _button('Open ${r.code}', () => unawaited(c.select(r.id))),
                ],
              ),
            ),
          if (c.cursor != null)
            _button('More projects', () => unawaited(c.more())),
        ]),
        if (c.selected != null) _detail(),
        if (c.form != null) _form(),
        if (c.recovery.isNotEmpty ||
            c.recoveryCursors.values.any((v) => v != null))
          _card('Encrypted recovery', [
            for (final d in c.recovery)
              ListTile(
                title: Text(projectActionLabel(d.action)),
                subtitle: Text(
                  d.draft.pending != null
                      ? 'Original request awaiting confirmation'
                      : d.draft.errorCode == 'VERSION_CONFLICT'
                      ? 'Current-version comparison required'
                      : 'Saved editable form',
                ),
                trailing: TextButton(
                  onPressed: c.busy ? null : () => unawaited(c.resume(d)),
                  child: const Text('Resume'),
                ),
              ),
            for (final a in c.recoveryCursors.keys.where(
              (a) => c.recoveryCursors[a] != null,
            ))
              _button(
                'More ${projectActionLabel(a)} drafts',
                () => unawaited(c.moreRecovery(a)),
              ),
          ]),
        const SizedBox(height: 24),
      ],
    ),
  );
  Widget _detail() {
    final r = c.selected!;
    return _card(r.name, [
      _buttons([
        _button(
          'Milestones',
          () => unawaited(
            _safe(() async {
              if (!await c.canLeave() || !mounted) return;
              context.go('/projects/${r.id}/milestones', extra: r);
            }),
          ),
          enabled: !c.locked,
        ),
        if (c.has('projects.cost.view') || c.has('projects.billing.manage'))
          _button(
            'Expenses and billing',
            () => unawaited(
              _safe(() async {
                if (!await c.canLeave() || !mounted) return;
                context.go('/projects/${r.id}/finance', extra: r);
              }),
            ),
            enabled: !c.locked,
          ),
        if (c.has('projects.manage') && c.has('projects.cost.manage'))
          _button(
            'Prepare plan',
            () => unawaited(c.begin('plan')),
            enabled: !c.locked && r.status == 'open',
          ),
        if (c.has('projects.manage'))
          _button(
            'Close project',
            () => unawaited(c.begin('close')),
            enabled: !c.locked && r.status == 'open',
          ),
      ]),
      const SizedBox(height: 8),
      _buttons([
        for (final s in ProjectSection.values.where(
          (s) =>
              s != ProjectSection.timeEvents &&
              (!s.privateCost || c.has('projects.cost.view')),
        ))
          FilterChip(
            label: Text(switch (s) {
              ProjectSection.resourceCost => 'Resource cost rates',
              ProjectSection.timeCost => 'Time cost',
              _ => s.name,
            }),
            selected: c.section == s,
            onSelected: c.busy ? null : (_) => unawaited(c.show(s)),
          ),
      ]),
      const SizedBox(height: 12),
      if (c.rows.isEmpty) const Text('No rows in this scoped view.'),
      for (final row in c.rows) _row(row),
      if (c.next != null)
        _button('More ${c.section.name}', () => unawaited(c.moreDetail())),
    ]);
  }

  Widget _row(ProjectRow row) {
    final actions = <Widget>[];
    String title;
    final facts = <String>[];
    switch (row) {
      case ProjectPlan():
        title = 'Plan revision ${row.version} · ${row.status}';
        facts.addAll([
          row.terms,
          'Reason: ${row.reason}',
          'Prepared by ${row.actorId}',
          if (row.decision != null)
            '${row.decision!.decision} by ${row.decision!.actorId}: ${row.decision!.reason}',
        ]);
        if (row.status == 'pending' &&
            c.has('projects.approve') &&
            c.has('projects.cost.view')) {
          for (final a in ['approve_plan', 'reject_plan']) {
            actions.add(
              _button(
                projectActionLabel(a),
                () => unawaited(c.begin(a, plan: row)),
                enabled: !c.locked,
              ),
            );
          }
        }
        actions.add(
          _button(
            'View plan tasks',
            () => unawaited(c.show(ProjectSection.tasks, parent: row.id)),
          ),
        );
        actions.add(
          _button(
            'View plan resources',
            () => unawaited(c.show(ProjectSection.resources, parent: row.id)),
          ),
        );
      case ProjectTask():
        title = row.name;
        facts.addAll([
          'Task owner: ${row.ownerName}',
          '${row.basis.start.value} to ${row.basis.endExclusive.value} (exclusive)',
          'Planned ${row.basis.plannedSeconds} seconds · progress ${(row.basis.progressBasisPoints / 100).toStringAsFixed(2)}%',
          'Dependencies: ${row.basis.dependencies.length} immutable task references',
        ]);
        if (c.has('projects.manage') && row.planId == c.selected?.planId) {
          actions.add(
            _button(
              'Record progress',
              () => unawaited(c.begin('progress', task: row)),
              enabled: !c.locked,
            ),
          );
        }
      case ProjectResource():
        title =
            '${row.employeeName} · ${row.active ? 'Approved capacity' : 'Historical/proposed capacity'}';
        facts.addAll([
          '${row.startLocal} to ${row.endLocal}',
          '${row.plannedSeconds} seconds · hourly bill rate ${row.billRate.toDecimalString()} ${row.billRate.currencyCode}',
          'UTC ${row.span.startUtc.toIso8601String()} to ${row.span.endUtc.toIso8601String()}',
        ]);
        if (row.active && c.has('projects.time.manage')) {
          actions.add(
            _button(
              'Record project time',
              () => unawaited(c.begin('time_create', resource: row)),
              enabled: !c.locked,
            ),
          );
        }
      case ProjectTime():
        title = '${row.employeeName} · ${row.status} · version ${row.version}';
        facts.addAll([
          '${row.startLocal} to ${row.endLocal} · ${row.work.payableSeconds} payable seconds',
          '${row.work.breakSeconds} break seconds · ${row.attendanceClaimId == null ? 'Direct project claim' : 'Approved attendance allocation'}',
          'Whole billing unit: ${row.billAmount.toDecimalString()} ${row.billAmount.currencyCode}',
          row.reason,
        ]);
        if ({'draft', 'rejected'}.contains(row.status) &&
            c.has('projects.time.manage')) {
          for (final a in ['time_correct', 'time_submit']) {
            actions.add(
              _button(
                projectActionLabel(a),
                () => unawaited(c.begin(a, time: row)),
                enabled: !c.locked,
              ),
            );
          }
        }
        if (row.status == 'submitted' && c.has('projects.time.approve')) {
          for (final a in ['time_approve', 'time_reject']) {
            actions.add(
              _button(
                projectActionLabel(a),
                () => unawaited(c.begin(a, time: row)),
                enabled: !c.locked,
              ),
            );
          }
        }
        if (row.status == 'approved' && c.has('projects.time.approve')) {
          actions.add(
            _button(
              'Cancel original time',
              () => unawaited(c.begin('time_cancel', time: row)),
              enabled: !c.locked,
            ),
          );
        }
        actions.add(
          _button(
            'Original time history',
            () => unawaited(c.show(ProjectSection.timeEvents, parent: row.id)),
          ),
        );
      case ProjectBudget():
        title = 'Frozen synthetic cost budget';
        facts.add('${row.budget.toDecimalString()} ${row.budget.currencyCode}');
      case ProjectResourceCost():
        title = 'Frozen synthetic resource cost rate';
        facts.add(
          '${row.hourlyRate.toDecimalString()} ${row.hourlyRate.currencyCode} per hour',
        );
      case ProjectTimeCost():
        title =
            'Original time cost · ${row.active ? 'Active' : 'Retained history'}';
        facts.addAll([
          'Rate ${row.hourlyRate.toDecimalString()} ${row.hourlyRate.currencyCode} per hour',
          'Exact cost ${row.amount.toDecimalString()} ${row.amount.currencyCode}',
        ]);
      case ProjectUnit():
        title = '${row.basis.source.name} · ${row.status}';
        facts.addAll([
          'Whole unit quantity ${row.basis.salesQuantity} · ${row.basis.amount.toDecimalString()} ${row.basis.amount.currencyCode}',
          if (row.basis.payableSeconds != null)
            'Original duration ${row.basis.payableSeconds} seconds',
          'Source revision ${row.basis.sourceVersion}',
        ]);
        if (row.status == 'available' && c.has('projects.billing.manage')) {
          actions.add(
            _button(
              'Mark non-billable',
              () => unawaited(c.begin('waive', unit: row)),
              enabled: !c.locked,
            ),
          );
        }
      case ProjectTimeEvent():
        title = '${projectActionLabel(row.action)} · version ${row.version}';
        facts.addAll([
          row.reason,
          'Actor ${row.actorId} · ${row.recordedAt.toIso8601String()}',
        ]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          for (final fact in facts) Text(fact),
          _buttons(actions),
          const Divider(),
        ],
      ),
    );
  }

  Widget _form() {
    final p = c.form!,
        a = c.action!,
        children = <Widget>[
          Text('Original expected version ${c.expectedVersion}'),
          const SizedBox(height: 12),
        ];
    switch (a) {
      case 'create':
        children.addAll([
          _field('code', 'Project code'),
          _field('name', 'Project name'),
          Text('Currency: ${p['currency_code']}'),
          _button(
            'Manager: ${c.labels[p['manager_id']] ?? 'Choose named employee'}',
            () => unawaited(
              _safe(() async {
                final v = await _choice('employees');
                if (v != null) {
                  c.choose('manager_id', v);
                }
              }),
            ),
            enabled: !c.locked,
          ),
          _button(
            'Customer: ${c.labels[p['customer_id']] ?? 'Internal project / choose customer'}',
            () => unawaited(
              _safe(() async {
                final v = await _choice('customers');
                if (v != null) {
                  c.choose('customer_id', v);
                }
              }),
            ),
            enabled: !c.locked,
          ),
          if (p['customer_id'] != null)
            _button(
              'Use internal project',
              () => c.choose('customer_id', null),
              enabled: !c.locked,
            ),
          _field('start_date', 'Start date (YYYY-MM-DD)'),
          _field('end_date_exclusive', 'End date, exclusive (YYYY-MM-DD)'),
        ]);
      case 'plan':
        children.addAll([
          _field('terms', 'Explicit commercial terms', lines: 3),
          _field(
            'budget',
            'Synthetic internal cost budget (${c.selected?.currency})',
          ),
          const Text(
            'Tasks and named resource reservations determine exact planned seconds. Internal cost rates are separate from payroll.',
          ),
          _buttons([
            _button(
              'Add task',
              () => unawaited(_taskDialog()),
              enabled: !c.locked,
            ),
            _button(
              'Add named resource',
              () => unawaited(_resourceDialog()),
              enabled: !c.locked && (p['tasks'] as List).isNotEmpty,
            ),
          ]),
          for (final raw in p['tasks'] as List) _taskDraft(projectMap(raw)),
          for (final raw in p['resources'] as List)
            _resourceDraft(projectMap(raw)),
        ]);
      case 'approve_plan':
      case 'reject_plan':
        children.addAll(_planReview());
      case 'progress':
        children.add(_field('progress', 'Progress basis points (0–10000)'));
      case 'time_create':
      case 'time_correct':
        children.addAll([
          Text(
            'Employee: ${c.labels[p['employee_id']] ?? 'Original scoped employee'}',
          ),
          Text(
            'Reservation: ${c.labels[p['resource_slot_id']] ?? 'Original approved reservation'}',
          ),
          _button(
            'Choose current named reservation',
            () => unawaited(_timeResourceDialog()),
            enabled: !c.locked,
          ),
          _field('start_local', 'Local start (YYYY-MM-DDTHH:MM:SS)'),
          _field('end_local', 'Local end (YYYY-MM-DDTHH:MM:SS)'),
          Text(
            'Selected UTC offsets: ${p['start_offset_seconds']} / ${p['end_offset_seconds']} seconds',
          ),
          _button(
            'Resolve local times in published calendar',
            () => unawaited(_timeOffsetsDialog()),
            enabled: !c.locked,
          ),
          Text(
            'Work source: ${p['attendance_claim_id'] == null ? 'Direct project claim' : c.labels[p['attendance_claim_id']] ?? 'Original approved attendance claim'}',
          ),
          _buttons([
            _button(
              'Choose approved attendance',
              () => unawaited(_claimDialog()),
              enabled: !c.locked,
            ),
            _button(
              'Use direct project claim',
              () => c.chooseClaim(null),
              enabled: !c.locked,
            ),
          ]),
          const Text(
            'Direct claims fail if attendance or another payable claim already owns the time. Attendance allocations exclude already allocated segments.',
          ),
          for (var i = 0; i < (p['breaks'] as List).length; i++)
            _buttons([
              Text(
                'Break ${(p['breaks'] as List)[i]['start_utc']} to ${(p['breaks'] as List)[i]['end_utc']}',
              ),
              _button(
                'Remove break ${i + 1}',
                () => c.removeBreak(i),
                enabled: !c.locked,
              ),
            ]),
          _button(
            'Add ordered UTC break',
            () => unawaited(_breakDialog()),
            enabled: !c.locked,
          ),
        ]);
      default:
        children.add(
          const Text(
            'This decision keeps its original source, version and immutable history.',
          ),
        );
    }
    children.addAll([
      _field('reason', 'Reason', lines: 2),
      if (c.pending != null)
        const Text(
          'The exact request is sealed. Reconcile its receipt or retry the original request.',
        ),
      if (c.conflict)
        const Text(
          'The server version changed. Compare the current source before adopting its version.',
        ),
      if (c.comparison != null) _currentComparison(),
      _buttons([
        if (c.confirmed == null)
          _button(
            c.pending == null
                ? 'Send ${projectActionLabel(a)}'
                : 'Retry exact original request',
            () => unawaited(c.send()),
            enabled:
                !c.conflict &&
                (c.pending != null ||
                    !{'approve_plan', 'reject_plan'}.contains(a) ||
                    c.planReview != null),
          ),
        if (c.pending != null && c.confirmed == null)
          _button('Reconcile original receipt', () => unawaited(c.reconcile())),
        if (c.pending == null && !c.conflict && c.confirmed == null)
          _button('Save encrypted form', () => unawaited(c.save())),
        if (c.conflict)
          _button('Compare current source', () => unawaited(c.compare())),
        if (c.comparison != null)
          _button(
            'Adopt reviewed server version',
            () => unawaited(c.adoptComparison()),
          ),
        if (c.pending == null && c.confirmed == null)
          _button('Discard editable form', () => unawaited(c.discard())),
        if (c.confirmed != null && c.pending != null)
          _button(
            'Retry confirmed encrypted cleanup',
            () => unawaited(c.retryConfirmedCleanup()),
          ),
        if (c.confirmed != null && c.pending == null)
          _button(
            'Close confirmed form',
            () => unawaited(c.dismissConfirmed()),
          ),
      ]),
    ]);
    return _card(projectActionLabel(a), children);
  }

  Widget _currentComparison() {
    final value = c.comparison!, project = value.project;
    return _card('Current server source', [
      Text(
        '${project.code} · ${project.name} · ${project.status} · version ${project.version}',
      ),
      Text(
        'Manager: ${project.managerName} · Customer: ${project.customerName ?? 'Internal project'}',
      ),
      Text(
        '${project.start.value} to ${project.end.value} (exclusive) · ${project.currency}',
      ),
      Text(
        'Saved request expected version ${c.expectedVersion}. Review the current source alongside the saved form.',
      ),
      for (final row in value.rows)
        if (row is ProjectTime && row.id == c.form!['id']) ...[
          Text(
            '${row.employeeName} · ${row.status} · time version ${row.version}',
          ),
          Text(
            '${row.startLocal} to ${row.endLocal} · offsets ${row.startOffset}/${row.endOffset} seconds',
          ),
          Text(
            '${row.work.payableSeconds} payable seconds · bill ${row.billAmount.toDecimalString()} ${project.currency}',
          ),
          Text(
            'Source: ${row.attendanceClaimId == null ? 'Direct project claim' : 'Approved attendance allocation'}',
          ),
          for (final span in row.work.breaks)
            Text(
              'Break ${span.startUtc.toIso8601String()} to ${span.endUtc.toIso8601String()}',
            ),
          Text('Current reason: ${row.reason}'),
        ] else if (row is ProjectPlan) ...[
          Text('Plan revision ${row.version} · ${row.status}'),
          Text(row.terms),
          Text('Original reason: ${row.reason}'),
          SelectableText('Digest: ${row.digest}'),
        ],
    ]);
  }

  Widget _taskDraft(Map<String, Object?> t) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t['name'] as String,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          '${t['start_date']} to ${t['end_date_exclusive']} (exclusive) · ${t['planned_seconds']} planned seconds',
        ),
        Text(
          'Task owner: ${c.labels[t['owner_id']] ?? 'Original selected employee'}',
        ),
        Text(
          'Prerequisites: ${(t['dependencies'] as List).map((id) => (c.form!['tasks'] as List).map(projectMap).firstWhere((v) => v['id'] == id)['name']).join(', ')}',
        ),
        _button(
          'Remove task',
          () => _safe(() async {
            c.removeTask(t['id'] as String);
          }),
          enabled: !c.locked,
        ),
      ],
    ),
  );
  Widget _resourceDraft(Map<String, Object?> s) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          c.labels[s['id']] ?? 'Original named resource reservation',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          '${s['start_local']} to ${s['end_local']} · calendar ${c.labels[s['calendar_version_id']] ?? 'Original immutable calendar'}',
        ),
        Text(
          'Hourly bill ${s['bill_rate']} · internal cost ${s['cost_rate']} ${c.selected?.currency ?? ''}',
        ),
        _button(
          'Remove resource',
          () => c.removeResource(s['id'] as String),
          enabled: !c.locked,
        ),
      ],
    ),
  );
  List<Widget> _planReview() {
    final review = c.planReview;
    if (review == null) {
      return [
        const Text(
          'The immutable full plan review is unavailable. Reopen the original plan before deciding.',
        ),
      ];
    }
    final names = {for (final t in review.tasks) t.id: t.name},
        rates = {for (final r in review.rates) r.id: r.hourlyRate};
    return [
      Text(
        'Plan revision ${review.plan.version} · prepared by ${review.plan.actorId}',
      ),
      Text(review.plan.terms),
      Text(
        'Internal cost budget: ${review.budget.budget.toDecimalString()} ${review.budget.budget.currencyCode}',
      ),
      SelectableText('Exact approval digest: ${review.plan.digest}'),
      for (final t in review.tasks)
        Text(
          '${t.name} · owner ${t.ownerName}: ${t.basis.start.value} to ${t.basis.endExclusive.value} (exclusive), ${t.basis.plannedSeconds} seconds; prerequisites ${t.basis.dependencies.map((id) => names[id]).join(', ')}',
        ),
      for (final s in review.resources)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '${s.employeeName} → ${names[s.taskId]}: ${s.startLocal} to ${s.endLocal}; ${s.plannedSeconds} seconds; bill ${s.billRate.toDecimalString()}, cost ${rates[s.id]!.toDecimalString()} ${s.billRate.currencyCode}/hour; offsets ${s.startOffset}/${s.endOffset} seconds.',
          ),
        ),
    ];
  }

  Future<void> _taskDialog() async {
    final name = TextEditingController(),
        start = TextEditingController(text: c.selected!.start.value),
        end = TextEditingController(text: c.selected!.end.value);
    final dependencies = <String>{};
    ProjectChoice? owner;
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => _ProjectDialog('Add task', [
            OutlinedButton(
              onPressed: () async {
                final selected = await _choice('employees');
                if (context.mounted && selected != null) {
                  update(() => owner = selected);
                }
              },
              child: Text(owner?.name ?? 'Choose task owner'),
            ),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Task name'),
            ),
            TextField(
              controller: start,
              decoration: const InputDecoration(
                labelText: 'Start date (YYYY-MM-DD)',
              ),
            ),
            TextField(
              controller: end,
              decoration: const InputDecoration(
                labelText: 'End date, exclusive (YYYY-MM-DD)',
              ),
            ),
            for (final t in (c.form!['tasks'] as List).map(projectMap))
              CheckboxListTile(
                title: Text('Requires ${t['name']}'),
                value: dependencies.contains(t['id']),
                onChanged: (v) => update(() {
                  if (v == true) {
                    dependencies.add(t['id'] as String);
                  } else {
                    dependencies.remove(t['id']);
                  }
                }),
              ),
            FilledButton(
              onPressed: owner == null
                  ? null
                  : () => _safe(() async {
                      c.addTask(
                        name.text,
                        start.text,
                        end.text,
                        owner: owner!,
                        dependencies: dependencies,
                      );
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    }),
              child: const Text('Add task'),
            ),
          ]),
        ),
      );
    } finally {
      name.dispose();
      start.dispose();
      end.dispose();
    }
  }

  Future<void> _resourceDialog() async {
    final start = TextEditingController(
          text: '${c.selected!.start.value}T09:00:00',
        ),
        end = TextEditingController(
          text: '${c.selected!.start.value}T10:00:00',
        ),
        bill = TextEditingController(),
        cost = TextEditingController();
    ProjectChoice? employee, calendar;
    String? task;
    ProjectLocalResolution? first, last;
    int? firstOffset, lastOffset;
    String? error;
    bool busy = false;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (dialog, update) =>
              _ProjectDialog('Reserve named resource capacity', [
                DropdownButtonFormField<String>(
                  initialValue: task,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Task'),
                  items: (c.form!['tasks'] as List)
                      .map(projectMap)
                      .map(
                        (t) => DropdownMenuItem(
                          value: t['id'] as String,
                          child: Text(t['name'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: busy ? null : (v) => update(() => task = v),
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final v = await _choice('employees');
                          if (dialog.mounted && v != null) {
                            update(() => employee = v);
                          }
                        },
                  child: Text(employee?.name ?? 'Choose employee'),
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final v = await _choice('calendars');
                          if (dialog.mounted && v != null) {
                            update(() {
                              calendar = v;
                              first = null;
                              last = null;
                              firstOffset = null;
                              lastOffset = null;
                            });
                          }
                        },
                  child: Text(
                    calendar?.name ?? 'Choose published calendar version',
                  ),
                ),
                TextField(
                  controller: start,
                  decoration: const InputDecoration(
                    labelText: 'Local start (YYYY-MM-DDTHH:MM:SS)',
                  ),
                  enabled: !busy,
                  onChanged: (_) => update(() {
                    first = null;
                    firstOffset = null;
                  }),
                ),
                TextField(
                  controller: end,
                  decoration: const InputDecoration(
                    labelText: 'Local end (YYYY-MM-DDTHH:MM:SS)',
                  ),
                  enabled: !busy,
                  onChanged: (_) => update(() {
                    last = null;
                    lastOffset = null;
                  }),
                ),
                TextField(
                  controller: bill,
                  decoration: const InputDecoration(
                    labelText: 'Explicit hourly bill rate',
                  ),
                  enabled: !busy,
                ),
                TextField(
                  controller: cost,
                  decoration: const InputDecoration(
                    labelText: 'Explicit synthetic hourly cost rate',
                  ),
                  enabled: !busy,
                ),
                if (error != null) Text(error!),
                if (busy) const LinearProgressIndicator(),
                OutlinedButton(
                  onPressed: busy || calendar == null
                      ? null
                      : () async {
                          update(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            final a = await c.resolve(
                                  calendar!.coverage!,
                                  start.text,
                                ),
                                z = await c.resolve(
                                  calendar!.coverage!,
                                  end.text,
                                );
                            if (dialog.mounted) {
                              update(() {
                                first = a;
                                last = z;
                                firstOffset = a.candidates.length == 1
                                    ? a.candidates.single.offsetSeconds
                                    : null;
                                lastOffset = z.candidates.length == 1
                                    ? z.candidates.single.offsetSeconds
                                    : null;
                              });
                            }
                          } catch (_) {
                            if (dialog.mounted) {
                              update(
                                () => error = 'Check the published calendar and local times. Nonexistent times cannot be selected.',
                              );
                            }
                          } finally {
                            if (dialog.mounted) {
                              update(() => busy = false);
                            }
                          }
                        },
                  child: const Text('Resolve both local times'),
                ),
                if (first != null)
                  _offsets(
                    'Start',
                    first!,
                    firstOffset,
                    (v) => update(() => firstOffset = v),
                  ),
                if (last != null)
                  _offsets(
                    'End',
                    last!,
                    lastOffset,
                    (v) => update(() => lastOffset = v),
                  ),
                FilledButton(
                  onPressed:
                      busy ||
                          employee == null ||
                          calendar == null ||
                          task == null ||
                          firstOffset == null ||
                          lastOffset == null
                      ? null
                      : () => _safe(() async {
                          c.addResource(
                            task!,
                            employee!,
                            calendar!,
                            start.text,
                            end.text,
                            firstOffset!,
                            lastOffset!,
                            bill.text,
                            cost.text,
                          );
                          if (dialog.mounted) {
                            Navigator.pop(dialog);
                          }
                        }),
                  child: const Text('Add reservation'),
                ),
              ]),
        ),
      );
    } finally {
      start.dispose();
      end.dispose();
      bill.dispose();
      cost.dispose();
    }
  }

  Widget _offsets(
    String label,
    ProjectLocalResolution r,
    int? selected,
    void Function(int) choose,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '$label · ${r.timezone} · ${r.isGap
            ? 'Nonexistent local time'
            : r.isAmbiguous
            ? 'Choose an explicit UTC offset'
            : 'Resolved time'}',
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final v in r.candidates)
            ChoiceChip(
              label: Text(
                '${v.offsetSeconds} seconds · ${v.utc.toIso8601String()}',
              ),
              selected: selected == v.offsetSeconds,
              onSelected: (_) => choose(v.offsetSeconds),
            ),
        ],
      ),
    ],
  );
  Future<void> _timeResourceDialog() async {
    await _safe(() async {
      final p = await c.readDetail(c.selected!.id, ProjectSection.resources);
      if (!mounted) {
        return;
      }
      final resource = await showDialog<ProjectResource>(
        context: context,
        builder: (context) => _ProjectResourceDialog(
          controller: c,
          initial: p,
          employeeId: c.form!['employee_id'] as String,
        ),
      );
      if (resource != null) {
        c.chooseResource(resource);
      }
    });
  }

  Future<void> _timeOffsetsDialog() async {
    await _safe(() async {
      final project = c.selected;
      if (project == null) {
        throw const FormatException('Restore current project view.');
      }
      var page = await c.readDetail(project.id, ProjectSection.resources);
      ProjectResource? resource;
      while (resource == null) {
        for (final row in page.rows.whereType<ProjectResource>()) {
          if (row.id == c.form!['resource_slot_id']) {
            resource = row;
          }
        }
        if (resource != null || page.next == null) {
          break;
        }
        page = await c.readDetail(
          project.id,
          ProjectSection.resources,
          after: page.next,
        );
      }
      if (resource == null) {
        throw const FormatException('Choose a current approved resource.');
      }
      final calendar = await _choice('calendars');
      if (calendar == null) {
        return;
      }
      if (calendar.id != resource.calendarId) {
        throw const FormatException(
          'Select the original resource calendar version.',
        );
      }
      final first = await c.resolve(
            calendar.coverage!,
            c.form!['start_local'] as String,
          ),
          last = await c.resolve(
            calendar.coverage!,
            c.form!['end_local'] as String,
          );
      if (!mounted) {
        return;
      }
      int? a = first.candidates.length == 1
              ? first.candidates.single.offsetSeconds
              : null,
          z = last.candidates.length == 1
              ? last.candidates.single.offsetSeconds
              : null;
      await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => _ProjectDialog('Resolve project time', [
            _offsets('Start', first, a, (v) => update(() => a = v)),
            _offsets('End', last, z, (v) => update(() => z = v)),
            FilledButton(
              onPressed: a == null || z == null
                  ? null
                  : () {
                      c.chooseTimeOffsets(a!, z!);
                      Navigator.pop(context);
                    },
              child: const Text('Use selected original calendar offsets'),
            ),
          ]),
        ),
      );
    });
  }

  Future<void> _claimDialog() async {
    await _safe(() async {
      final employee = c.form!['employee_id'] as String,
          page = await c.claims(employee);
      if (!mounted) {
        return;
      }
      final claim = await showDialog<ProjectAttendanceClaim>(
        context: context,
        builder: (context) => _ProjectClaimDialog(
          controller: c,
          employeeId: employee,
          initial: page,
        ),
      );
      if (claim != null) {
        c.chooseClaim(claim);
      }
    });
  }

  Future<void> _breakDialog() async {
    final start = TextEditingController(), end = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => _ProjectDialog('Add ordered UTC break', [
          TextField(
            controller: start,
            decoration: const InputDecoration(
              labelText: 'UTC start (YYYY-MM-DDTHH:MM:SSZ)',
            ),
          ),
          TextField(
            controller: end,
            decoration: const InputDecoration(
              labelText: 'UTC end (YYYY-MM-DDTHH:MM:SSZ)',
            ),
          ),
          FilledButton(
            onPressed: () => _safe(() async {
              c.addBreak(start.text, end.text);
              if (context.mounted) {
                Navigator.pop(context);
              }
            }),
            child: const Text('Add break'),
          ),
        ]),
      );
    } finally {
      start.dispose();
      end.dispose();
    }
  }
}

class _ProjectDialog extends StatelessWidget {
  const _ProjectDialog(this.title, this.children);
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: 720,
      height: MediaQuery.sizeOf(context).height * .85,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Expanded(child: ListView(children: children)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ProjectChoiceDialog extends StatefulWidget {
  const _ProjectChoiceDialog({
    required this.controller,
    required this.kind,
    this.optional = false,
  });
  final ProjectsController controller;
  final String kind;
  final bool optional;
  @override
  State<_ProjectChoiceDialog> createState() => _ProjectChoiceDialogState();
}

class _ProjectChoiceDialogState extends State<_ProjectChoiceDialog> {
  List<ProjectChoice> rows = [];
  String? next, error;
  String filter = '';
  bool busy = true;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    unawaited(_load());
  }

  void _changed() {
    if (!widget.controller.current && mounted) {
      setState(() {
        rows = [];
        next = null;
        error = 'Project access changed.';
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    setState(() => busy = true);
    try {
      final page = await widget.controller.choices(
        widget.kind,
        after: more ? next : null,
      );
      if (mounted) {
        setState(() {
          rows = [if (more) ...rows, ...page.rows];
          next = page.next;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Named choices could not be verified.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => _ProjectDialog('Choose ${widget.kind}', [
    TextField(
      decoration: const InputDecoration(
        labelText: 'Filter loaded named choices',
      ),
      onChanged: (v) => setState(() => filter = v.toLowerCase()),
    ),
    if (busy) const LinearProgressIndicator(),
    if (error != null) Text(error!),
    for (final row in rows.where(
      (r) => '${r.code} ${r.name}'.toLowerCase().contains(filter),
    ))
      ListTile(
        title: Text(row.name),
        subtitle: Text(
          '${row.code}${row.coverage == null ? '' : ' · ${row.coverage!.start.value} to ${row.coverage!.endExclusive.value} · ${row.coverage!.timezone}'}',
        ),
        onTap: widget.controller.current
            ? () => Navigator.pop(context, row)
            : null,
      ),
    if (next != null)
      OutlinedButton(
        onPressed: busy ? null : () => unawaited(_load(more: true)),
        child: const Text('Load next named page'),
      ),
    if (error != null)
      OutlinedButton(
        onPressed: busy ? null : () => unawaited(_load()),
        child: const Text('Retry choices'),
      ),
  ]);
}

class _ProjectResourceDialog extends StatefulWidget {
  const _ProjectResourceDialog({
    required this.controller,
    required this.initial,
    required this.employeeId,
  });
  final ProjectsController controller;
  final ProjectDetail initial;
  final String employeeId;
  @override
  State<_ProjectResourceDialog> createState() => _ProjectResourceDialogState();
}

class _ProjectResourceDialogState extends State<_ProjectResourceDialog> {
  late List<ProjectResource> rows;
  String? next, error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    rows = widget.initial.rows.cast<ProjectResource>();
    next = widget.initial.next;
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (!widget.controller.current && mounted) {
      setState(() {
        rows = [];
        next = null;
        error = 'Project access changed.';
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  Future<void> _more() async {
    setState(() => busy = true);
    try {
      final page = await widget.controller.readDetail(
        widget.initial.project.id,
        ProjectSection.resources,
        after: next,
      );
      if (mounted) {
        setState(() {
          rows = [...rows, ...page.rows.cast<ProjectResource>()];
          next = page.next;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Resource page is unavailable.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => _ProjectDialog('Choose approved employee reservation', [
    if (error != null) Text(error!),
    if (busy) const LinearProgressIndicator(),
    for (final row in rows.where(
      (r) => r.active && r.employeeId == widget.employeeId,
    ))
      ListTile(
        title: Text(row.employeeName),
        subtitle: Text(
          '${row.startLocal} to ${row.endLocal} · ${row.plannedSeconds} seconds',
        ),
        onTap: widget.controller.current
            ? () => Navigator.pop(context, row)
            : null,
      ),
    if (next != null)
      OutlinedButton(
        onPressed: busy ? null : () => unawaited(_more()),
        child: const Text('More approved reservations'),
      ),
  ]);
}

class _ProjectClaimDialog extends StatefulWidget {
  const _ProjectClaimDialog({
    required this.controller,
    required this.employeeId,
    required this.initial,
  });
  final ProjectsController controller;
  final String employeeId;
  final ProjectPage<ProjectAttendanceClaim> initial;
  @override
  State<_ProjectClaimDialog> createState() => _ProjectClaimDialogState();
}

class _ProjectClaimDialogState extends State<_ProjectClaimDialog> {
  late List<ProjectAttendanceClaim> rows;
  String? next, error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    rows = widget.initial.rows;
    next = widget.initial.next;
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (!widget.controller.current && mounted) {
      setState(() {
        rows = [];
        next = null;
        error = 'Project access changed.';
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  Future<void> _more() async {
    setState(() => busy = true);
    try {
      final page = await widget.controller.claims(
        widget.employeeId,
        after: next,
      );
      if (mounted) {
        setState(() {
          rows = [...rows, ...page.rows];
          next = page.next;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Attendance source page is unavailable.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => _ProjectDialog('Choose approved attendance', [
    if (error != null) Text(error!),
    if (busy) const LinearProgressIndicator(),
    if (rows.isEmpty)
      const Text(
        'No approved attendance is available for this employee in this branch.',
      ),
    for (final row in rows)
      ListTile(
        title: Text(
          '${row.span.startUtc.toIso8601String()} to ${row.span.endUtc.toIso8601String()}',
        ),
        subtitle: Text(
          '${row.payableSeconds} payable seconds; allocated segments remain protected',
        ),
        onTap: widget.controller.current
            ? () => Navigator.pop(context, row)
            : null,
      ),
    if (next != null)
      OutlinedButton(
        onPressed: busy ? null : () => unawaited(_more()),
        child: const Text('More approved attendance sources'),
      ),
  ]);
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_projects.dart';
import 'package:jentra_domain/jentra_milestones.dart';

import 'milestones_controller.dart';

String _milestoneAmount(MilestoneRecord r) {
  final decimal = r.amount.toDecimalString(), dot = decimal.indexOf('.');
  return decimal.substring(0, dot + (r.precision == 0 ? 0 : r.precision + 1));
}

final class MilestonesWorkspace extends ConsumerWidget {
  const MilestonesWorkspace({
    super.key,
    required this.projectId,
    this.controller,
  });
  final String projectId;
  final MilestonesController? controller;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = controller ?? ref.watch(milestoneControllerProvider(projectId));
    if (c == null) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Select an authorized project scope to review milestones.',
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => PopScope(
        canPop: c.form == null || c.confirmed,
        onPopInvokedWithResult: (popped, result) async {
          if (!popped && await c.canLeave() && context.mounted) {
            Navigator.of(context).pop();
          }
        },
        child: Scaffold(
          appBar: AppBar(title: const Text('Project milestones')),
          body: FocusTraversalGroup(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  c.project?.name ?? 'Project milestones',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Review a completed deliverable, its dated owner and commercial terms. Approval creates one billing unit; invoice and payment are separate.',
                ),
                if (c.project != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Customer: ${c.project!.customerName ?? 'A billable customer is required'} • ${c.project!.currency} • ${c.project!.precision} decimal places',
                    ),
                  ),
                if (c.error != null)
                  Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        c.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                if (c.message != null)
                  Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(c.message!),
                    ),
                  ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: c.current && c.online && !c.busy
                          ? () => unawaited(c.refresh())
                          : null,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh milestones'),
                    ),
                    FilledButton.icon(
                      onPressed:
                          c.current &&
                              c.online &&
                              !c.busy &&
                              c.has('projects.manage')
                          ? () => unawaited(c.begin('create'))
                          : null,
                      icon: const Icon(Icons.add),
                      label: const Text('New milestone'),
                    ),
                  ],
                ),
                if (c.busy) const LinearProgressIndicator(),
                const SizedBox(height: 16),
                if (c.records.isEmpty && !c.busy && c.current)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No milestones loaded. Create terms against an approved project task.',
                    ),
                  ),
                for (final r in c.records)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${r.taskName} • Owner: ${r.ownerName} • Due: ${r.due.value}',
                          ),
                          Text(
                            '${r.currency} ${_milestoneAmount(r)} • ${r.status} • Billing: ${r.unitStatus ?? 'awaiting approval'}',
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: c.current && c.online && !c.busy
                                    ? () => unawaited(c.select(r))
                                    : null,
                                child: const Text('Review milestone'),
                              ),
                              for (final a in _actions(r))
                                TextButton(
                                  onPressed:
                                      c.current &&
                                          c.online &&
                                          !c.busy &&
                                          c.has(MilestoneCommands.capability(a))
                                      ? () => unawaited(c.begin(a, target: r))
                                      : null,
                                  child: Text(_action(a)),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                if (c.cursor != null)
                  TextButton(
                    onPressed: !c.busy && c.online
                        ? () => unawaited(c.refresh(more: true))
                        : null,
                    child: const Text('Load more milestones'),
                  ),
                if (c.selected != null) _MilestoneReview(c: c),
                if (c.form != null) _MilestoneForm(c: c),
                if (c.recovery.isNotEmpty) ...[
                  const Divider(height: 32),
                  Text(
                    'Encrypted recovery',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  for (final saved in c.recovery)
                    ListTile(
                      title: Text(
                        '${_action(saved.action)} • ${saved.draft.pending == null ? 'saved draft' : 'original request awaiting reconciliation'}',
                      ),
                      subtitle: Text(
                        saved.draft.form['name'] as String? ??
                            'Milestone revision ${saved.draft.version}',
                      ),
                      trailing: TextButton(
                        onPressed: !c.busy && c.current && c.online
                            ? () => unawaited(c.resume(saved))
                            : null,
                        child: const Text('Resume'),
                      ),
                    ),
                ],
                for (final a in c.recoveryCursors.keys.where(
                  (a) => c.recoveryCursors[a] != null,
                ))
                  TextButton(
                    onPressed: !c.busy && c.online
                        ? () => unawaited(c.loadRecovery(a: a))
                        : null,
                    child: Text('Load more ${_action(a).toLowerCase()} drafts'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _action(String a) => switch (a) {
  'create' => 'Create',
  'correct' => 'Correct terms',
  'submit' => 'Submit for review',
  'approve' => 'Approve',
  'reject' => 'Reject',
  'cancel' => 'Cancel',
  _ => a,
};
List<String> _actions(MilestoneRecord r) => switch (r.status) {
  'draft' => ['correct', 'submit', 'cancel'],
  'submitted' => ['approve', 'reject', 'cancel'],
  'rejected' => ['correct', 'cancel'],
  'approved' => ['correct', 'cancel'],
  _ => [],
};

final class _MilestoneReview extends StatelessWidget {
  const _MilestoneReview({required this.c});
  final MilestonesController c;
  @override
  Widget build(BuildContext context) {
    final d = c.selected!, r = d.record;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Review ${r.name}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text('Customer: ${r.customerName}'),
            Text('Task: ${r.taskName} • Owner: ${r.ownerName}'),
            Text('Due: ${r.due.value} • ${r.currency} ${_milestoneAmount(r)}'),
            const SizedBox(height: 12),
            Text('Commercial terms: ${r.commercialTerms}'),
            Text(
              'Payment: ${r.paymentTerms} • ${r.paymentDays} days from invoice date',
            ),
            Text('Completion evidence: ${r.evidence}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final k in ['events', 'revisions'])
                  OutlinedButton(
                    onPressed: c.online && !c.busy
                        ? () => unawaited(c.select(r, kind: k))
                        : null,
                    child: Text(
                      k == 'events'
                          ? 'Decision history'
                          : 'Original commercial revisions',
                    ),
                  ),
              ],
            ),
            for (final row in d.rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Revision ${row.version} • ${row.kind == 'events' ? _action(row.facts['action'] as String) : row.facts['name']} • ${row.recordedAt.toUtc()}',
                    ),
                    if (row.kind == 'revisions') ...[
                      Text(
                        '${row.facts['currency_code']} ${row.facts['amount']} • Due: ${row.facts['due_date']} • Owner: ${row.facts['owner_name']}',
                      ),
                      Text(
                        'Commercial terms: ${row.facts['commercial_terms']}',
                      ),
                      Text(
                        'Payment: ${row.facts['payment_terms']} • ${row.facts['payment_due_days']} days',
                      ),
                      Text('Evidence: ${row.facts['evidence_reference']}'),
                    ],
                    Text('Reason: ${row.facts['reason']}'),
                  ],
                ),
              ),
            if (d.next != null)
              TextButton(
                onPressed: !c.busy && c.online
                    ? () => unawaited(c.select(r, kind: d.kind, more: true))
                    : null,
                child: const Text('Load more history'),
              ),
          ],
        ),
      ),
    );
  }
}

final class _MilestoneForm extends StatelessWidget {
  const _MilestoneForm({required this.c});
  final MilestonesController c;
  Future<void> _choose(BuildContext context, bool task) async {
    final n = c.accessEpoch,
        f = c.formEpoch,
        result = await showDialog<Object>(
          context: context,
          builder: (_) => _MilestonePicker(c: c, task: task),
        );
    if (result is ProjectTask) c.chooseTask(result, n, f);
    if (result is ProjectChoice) c.chooseOwner(result, n, f);
  }

  Future<void> _save(BuildContext context) async {
    try {
      await c.save();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The draft could not be saved. Keep this workspace open and retry.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = c.form!, a = c.action!, terms = {'create', 'correct'}.contains(a);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_action(a)} milestone',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (terms) ...[
              Text(
                'Project: ${c.project?.name ?? 'Current scoped project'} • Customer: ${c.project?.customerName ?? 'Billable customer required'}',
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: !c.locked && c.online
                        ? () => _choose(context, true)
                        : null,
                    child: Text(
                      'Task: ${c.labels['task_id'] ?? 'Choose approved task'}',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: !c.locked && c.online
                        ? () => _choose(context, false)
                        : null,
                    child: Text(
                      'Owner: ${c.labels['owner_id'] ?? 'Choose dated owner'}',
                    ),
                  ),
                ],
              ),
              for (final k in [
                'name',
                'due_date',
                'amount',
                'commercial_terms',
                'payment_terms',
                'payment_due_days',
                'evidence_reference',
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: TextFormField(
                    key: ValueKey('milestone:${c.formEpoch}:$k'),
                    initialValue: p[k]?.toString() ?? '',
                    enabled: !c.locked,
                    decoration: InputDecoration(
                      labelText: switch (k) {
                        'name' => 'Milestone name',
                        'due_date' => 'Due date (YYYY-MM-DD)',
                        'amount' =>
                          'Exact amount (${c.project?.currency ?? 'project currency'})',
                        'commercial_terms' => 'Commercial terms',
                        'payment_terms' => 'Payment terms',
                        'payment_due_days' => 'Days from invoice date (0–365)',
                        _ => 'Completion evidence reference',
                      },
                    ),
                    maxLines: {'commercial_terms', 'payment_terms'}.contains(k)
                        ? 3
                        : 1,
                    onChanged: (v) => c.edit(
                      k,
                      k == 'payment_due_days' ? (int.tryParse(v) ?? v) : v,
                    ),
                  ),
                ),
            ] else
              Text(
                'This decision binds the selected immutable revision and exact commercial terms.',
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: TextFormField(
                key: ValueKey('milestone:${c.formEpoch}:reason'),
                initialValue: p['reason'] as String? ?? '',
                enabled: !c.locked,
                decoration: const InputDecoration(
                  labelText: 'Decision or correction reason',
                ),
                onChanged: (v) => c.edit('reason', v),
              ),
            ),
            if (c.conflicted) ...[
              const Text(
                'Compare the current source before creating a replacement request.',
              ),
              OutlinedButton(
                onPressed: c.online && !c.busy
                    ? () => unawaited(c.compare())
                    : null,
                child: const Text('Compare current revision'),
              ),
              if (c.comparison != null) ...[
                Text(
                  'Current revision ${c.comparison!.record.version}: ${c.comparison!.record.name} • ${c.comparison!.record.amount.toDecimalString()} • ${c.comparison!.record.status}',
                ),
                OutlinedButton(
                  onPressed: !c.busy
                      ? () => unawaited(c.adoptComparison())
                      : null,
                  child: const Text('Bind reviewed current version'),
                ),
              ],
            ],
            if (c.pending != null)
              const Text(
                'The original encrypted request is sealed. Reconcile it before editing.',
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton(
                  onPressed: !c.locked && c.online
                      ? () => _save(context)
                      : null,
                  child: const Text('Save encrypted draft'),
                ),
                FilledButton(
                  onPressed: !c.locked && c.online
                      ? () => unawaited(c.send())
                      : null,
                  child: Text(_action(a)),
                ),
                if (c.pending != null) ...[
                  OutlinedButton(
                    onPressed: c.current && c.online && !c.busy
                        ? () => unawaited(c.reconcile())
                        : null,
                    child: const Text('Reconcile original request'),
                  ),
                  OutlinedButton(
                    onPressed: c.current && c.online && !c.busy && !c.confirmed
                        ? () => unawaited(c.retryOriginal())
                        : null,
                    child: const Text('Retry original request'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class _MilestonePicker extends StatefulWidget {
  const _MilestonePicker({required this.c, required this.task});
  final MilestonesController c;
  final bool task;
  @override
  State<_MilestonePicker> createState() => _MilestonePickerState();
}

final class _MilestonePickerState extends State<_MilestonePicker> {
  late final int n, f;
  List<Object> rows = [];
  String? next, error;
  bool busy = false;
  bool get valid =>
      widget.c.current &&
      widget.c.online &&
      widget.c.accessEpoch == n &&
      widget.c.formEpoch == f;
  @override
  void initState() {
    super.initState();
    n = widget.c.accessEpoch;
    f = widget.c.formEpoch;
    widget.c.addListener(_changed);
    unawaited(_load());
  }

  void _changed() {
    if (mounted && !valid) {
      setState(() {
        rows = [];
        next = null;
        error = 'The milestone scope or form changed. Close this picker.';
      });
    }
  }

  Future<void> _load({bool more = false}) async {
    if (!valid || busy) return;
    setState(() => busy = true);
    try {
      final ProjectPage<Object> page = widget.task
          ? await widget.c.tasks(after: more ? next : null)
          : await widget.c.owners(after: more ? next : null);
      if (mounted && valid) {
        setState(() {
          rows = more ? [...rows, ...page.rows] : page.rows;
          next = page.next;
          error = null;
        });
      }
    } catch (_) {
      if (mounted && valid) {
        setState(
          () => error =
              'Named sources are unavailable. Retry the authorized read.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    widget.c.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.task
          ? 'Choose an approved task'
          : 'Choose a dated accountable owner',
    ),
    content: SizedBox(
      width: 600,
      height: 400,
      child: Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          Expanded(
            child: ListView(
              children: [
                for (final row in rows)
                  ListTile(
                    title: Text(
                      row is ProjectTask
                          ? row.name
                          : (row as ProjectChoice).name,
                    ),
                    subtitle: row is ProjectTask
                        ? Text(
                            '${row.ownerName} • ${row.basis.start.value} to ${row.basis.endExclusive.value} • ${row.basis.progressBasisPoints / 100}%',
                          )
                        : null,
                    enabled: valid && !busy,
                    onTap: valid && !busy
                        ? () => Navigator.pop(context, row)
                        : null,
                  ),
              ],
            ),
          ),
          if (next != null)
            TextButton(
              onPressed: valid && !busy
                  ? () => unawaited(_load(more: true))
                  : null,
              child: const Text('Load more named sources'),
            ),
          if (error != null && valid)
            TextButton(
              onPressed: !busy ? () => unawaited(_load()) : null,
              child: const Text('Retry sources'),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}

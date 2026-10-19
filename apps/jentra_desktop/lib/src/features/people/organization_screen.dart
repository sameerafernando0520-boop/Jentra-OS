import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_people.dart';

import 'organization_controller.dart';
import '../../app_providers.dart';

class OrganizationScreen extends ConsumerWidget {
  const OrganizationScreen({super.key});
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
          child: const Text('Retry organization access'),
        ),
      );
    }
    final c = ref.watch(organizationControllerProvider);
    if (c == null) {
      return const Center(
        child: Text(
          'Choose an entity and branch with organization permission.',
        ),
      );
    }
    return OrganizationWorkspace(key: ValueKey(c), controller: c);
  }
}

class OrganizationWorkspace extends StatefulWidget {
  const OrganizationWorkspace({required this.controller, super.key});
  final OrganizationController controller;
  @override
  State<OrganizationWorkspace> createState() => _OrganizationWorkspaceState();
}

class _OrganizationWorkspaceState extends State<OrganizationWorkspace> {
  late final date = TextEditingController(text: widget.controller.asOfDate);
  final search = TextEditingController();
  @override
  void dispose() {
    date.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> _editor() async {
    final c = widget.controller;
    if (c.form == null || !mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final current = ref.watch(organizationControllerProvider);
          if (current != c) {
            return AlertDialog(
              title: const Text('Organization access changed'),
              content: const Text('Close this editor and reload access.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          }
          return OrganizationEditor(controller: c);
        },
      ),
    );
  }

  Future<void> _employee() async {
    final c = widget.controller;
    final choice = await organizationPicker(context, 'Employee', (
      query,
      after,
    ) async {
      final rows = await c.employeeChoices(query, c.asOfDate, after: after);
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
    if (choice != null) {
      await c.openEmployee(choice.id);
    }
  }

  Widget card(String title, List<Widget> children) => Card(
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
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      if (!c.current) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              c.error ?? 'Organization access changed. Reload access.',
            ),
          ),
        );
      }
      String deptName(String? id) => id == null
          ? 'No parent'
          : c.departments.where((d) => d.id == id).firstOrNull?.name ??
                'Historical department';
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Organization & calendars',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              OutlinedButton(
                onPressed: c.busy ? null : () => c.refresh(),
                child: const Text('Reload'),
              ),
              if (!c.online)
                const Chip(label: Text('Offline · encrypted drafts available')),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 220,
                child: TextField(
                  controller: date,
                  decoration: const InputDecoration(
                    labelText: 'As of date',
                    helperText: 'YYYY-MM-DD',
                  ),
                ),
              ),
              SizedBox(
                width: 300,
                child: TextField(
                  controller: search,
                  decoration: const InputDecoration(
                    labelText: 'Find department',
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: c.busy
                    ? null
                    : () => c.filter(date.text, search.text),
                child: const Text('Apply filters'),
              ),
            ],
          ),
          if (c.busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            ),
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
          if (c.recovery.isNotEmpty || c.recoveryCursor != null)
            card('Encrypted recovery', [
              for (final d in c.recovery)
                ListTile(
                  title: Text(organizationActionLabel(d.action)),
                  subtitle: Text(
                    d.pending != null
                        ? 'Original request awaiting confirmation'
                        : d.errorCode == 'VERSION_CONFLICT'
                        ? 'Compare the changed server version'
                        : 'Saved local draft',
                  ),
                  trailing: IconButton(
                    tooltip: 'Resume draft',
                    onPressed: c.busy || c.form != null
                        ? null
                        : () async {
                            await c.resume(d);
                            await _editor();
                          },
                    icon: const Icon(Icons.restore),
                  ),
                ),
              if (c.recoveryCursor != null)
                TextButton(
                  onPressed: c.busy ? null : c.moreRecovery,
                  child: const Text('More recovery records'),
                ),
            ]),
          card('Departments', [
            if (c.canManage)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: c.locked || c.form != null
                      ? null
                      : () async {
                          c.beginDepartment();
                          await _editor();
                        },
                  child: const Text('Create department'),
                ),
              ),
            if (c.departments.isEmpty && !c.busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No departments cover this date.'),
              ),
            for (final d in c.departments)
              ListTile(
                title: Text('${d.name} · ${d.code}'),
                subtitle: Text(
                  '${d.dates.start} → ${d.dates.endExclusive ?? 'Open'} · ${deptName(d.parentId)}',
                ),
                selected: c.selectedDepartment?.id == d.id,
                onTap: c.busy ? null : () => c.openDepartment(d),
                trailing: const Icon(Icons.chevron_right),
              ),
            if (c.departmentCursor != null)
              TextButton(
                onPressed: c.busy ? null : () => c.refresh(more: true),
                child: const Text('More departments'),
              ),
          ]),
          if (c.selectedDepartment != null)
            card('${c.selectedDepartment!.name} history', [
              if (c.canManage)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: c.locked || c.form != null
                        ? null
                        : () async {
                            c.beginDepartment(revise: true);
                            await _editor();
                          },
                    child: const Text('Revise department'),
                  ),
                ),
              for (final r in c.history)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '${r.name} · ${r.dates.start} → ${r.dates.endExclusive ?? 'Open'}\n${deptName(r.parentId)} · ${r.supersededAt == null ? 'Current revision' : 'Superseded revision'}\n${r.reason}\nRecorded ${r.recordedAt.toIso8601String()}',
                  ),
                ),
              if (c.historyCursor != null)
                TextButton(
                  onPressed: c.busy
                      ? null
                      : () =>
                            c.openDepartment(c.selectedDepartment!, more: true),
                  child: const Text('More department history'),
                ),
            ]),
          card('Employee organization', [
            if (c.permissions.contains('people.employees.view'))
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: c.busy || !c.online ? null : _employee,
                  child: const Text('Choose employee'),
                ),
              ),
            if (c.selectedEmployee == null)
              const Text(
                'Choose an employee to inspect dated department, manager and calendar assignments.',
              ),
            if (c.selectedEmployee != null) ...[
              Text(
                '${c.selectedEmployee!.displayName} · ${c.selectedEmployee!.code}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (!c.assignments.any(
                (a) =>
                    a.active && a.dates.contains(CivilDate.parse(c.asOfDate)),
              ))
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Organization and calendar are unconfigured on this date.',
                  ),
                ),
              if (c.canAssign)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: c.locked || c.form != null
                        ? null
                        : () async {
                            c.beginAssignment();
                            await _editor();
                          },
                    child: const Text('Assign organization'),
                  ),
                ),
              for (final a in c.assignments)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${a.roleTitle} · ${a.departmentName}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${a.dates.start} → ${a.dates.endExclusive} · ${a.active ? 'Current revision' : 'Superseded revision'}\n${a.reason}',
                      ),
                      Text(
                        a.managerId == null
                            ? 'No manager assigned'
                            : 'Manager · ${a.managerName}',
                      ),
                      Text(
                        '${a.calendarName} · ${a.calendarTimezone} · version ${a.calendarVersionId.substring(0, 8)}',
                      ),
                      if (a.withdrawal != null)
                        Text(
                          'Withdrawn: ${a.withdrawal!.reason}\nRecorded ${a.withdrawal!.recordedAt.toIso8601String()}',
                        ),
                      if (a.active && c.canAssign)
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: c.locked || c.form != null
                                  ? null
                                  : () async {
                                      c.beginAssignment(replace: a);
                                      await _editor();
                                    },
                              child: const Text('Replace revision'),
                            ),
                            OutlinedButton(
                              onPressed: c.locked || c.form != null
                                  ? null
                                  : () async {
                                      c.beginAssignment(replace: a, end: true);
                                      await _editor();
                                    },
                              child: const Text('End assignment'),
                            ),
                            if (a.dates.start.compareTo(
                                  CivilDate.parse(c.asOfDate),
                                ) >
                                0)
                              OutlinedButton(
                                onPressed: c.locked || c.form != null
                                    ? null
                                    : () async {
                                        c.beginAssignment(
                                          replace: a,
                                          withdraw: true,
                                        );
                                        await _editor();
                                      },
                                child: const Text('Withdraw future assignment'),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              if (c.assignmentCursor != null)
                TextButton(
                  onPressed: c.busy
                      ? null
                      : () =>
                            c.openEmployee(c.selectedEmployee!.id, more: true),
                  child: const Text('More assignment history'),
                ),
            ],
          ]),
        ],
      );
    },
  );
}

String organizationActionLabel(String action) => switch (action) {
  'department_create' => 'Create department',
  'department_revise' => 'Revise department',
  'assign' => 'Assign organization',
  'replace' => 'Replace organization revision',
  'end_assignment' => 'End organization assignment',
  'withdraw_assignment' => 'Withdraw future organization assignment',
  _ => 'Organization request',
};

final class OrganizationChoice {
  const OrganizationChoice(this.id, this.label);
  final String id, label;
}

typedef OrganizationChoices =
    Future<(List<OrganizationChoice>, String?)> Function(
      String query,
      String? after,
    );
Future<OrganizationChoice?> organizationPicker(
  BuildContext context,
  String label,
  OrganizationChoices load,
  bool Function() current,
) => showDialog<OrganizationChoice>(
  context: context,
  builder: (_) => Consumer(
    builder: (context, ref, _) {
      ref.watch(organizationControllerProvider);
      return _OrganizationPicker(label: label, load: load, current: current);
    },
  ),
);

class _OrganizationPicker extends StatefulWidget {
  const _OrganizationPicker({
    required this.label,
    required this.load,
    required this.current,
  });
  final String label;
  final OrganizationChoices load;
  final bool Function() current;
  @override
  State<_OrganizationPicker> createState() => _OrganizationPickerState();
}

class _OrganizationPickerState extends State<_OrganizationPicker> {
  final query = TextEditingController();
  List<OrganizationChoice> rows = [];
  String? after, error;
  bool busy = false;
  int epoch = 0;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    epoch++;
    query.dispose();
    super.dispose();
  }

  Future<void> refresh({bool more = false}) async {
    final run = ++epoch;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.load(query.text, more ? after : null);
      if (!mounted || run != epoch || !widget.current()) {
        return;
      }
      setState(() {
        rows = [if (more) ...rows, ...result.$1];
        after = result.$2;
      });
    } catch (_) {
      if (mounted && run == epoch) {
        setState(() {
          rows = [];
          error = 'Unable to load permitted choices. Retry when connected.';
        });
      }
    } finally {
      if (mounted && run == epoch) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Choose ${widget.label.toLowerCase()}'),
    content: SizedBox(
      width: 560,
      height: 400,
      child: Column(
        children: [
          TextField(
            controller: query,
            onSubmitted: (_) => refresh(),
            decoration: InputDecoration(
              labelText: 'Find ${widget.label.toLowerCase()}',
              suffixIcon: IconButton(
                tooltip: 'Search',
                onPressed: busy ? null : () => refresh(),
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          if (busy) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              children: widget.current()
                  ? [
                      if (error != null) Text(error!),
                      if (rows.isEmpty && !busy && error == null)
                        const ListTile(
                          title: Text('No permitted choices match this date.'),
                        ),
                      for (final row in rows)
                        ListTile(
                          title: Text(row.label),
                          onTap: busy
                              ? null
                              : () {
                                  if (widget.current()) {
                                    Navigator.pop(context, row);
                                  }
                                },
                        ),
                      if (after != null)
                        TextButton(
                          onPressed: busy ? null : () => refresh(more: true),
                          child: const Text('More choices'),
                        ),
                    ]
                  : [const Text('Access changed. Close this picker.')],
            ),
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

class OrganizationEditor extends StatefulWidget {
  const OrganizationEditor({required this.controller, super.key});
  final OrganizationController controller;
  @override
  State<OrganizationEditor> createState() => _OrganizationEditorState();
}

class _OrganizationEditorState extends State<OrganizationEditor> {
  final labels = <String, String>{};
  Future<void> choose(String key) async {
    final c = widget.controller;
    final form = c.form!;
    final date = form['start_date'] as String;
    final choice = await organizationPicker(
      context,
      key == 'parent_id'
          ? 'Parent department'
          : key == 'department_id'
          ? 'Department'
          : key == 'manager_id'
          ? 'Manager'
          : 'Calendar version',
      (query, after) async {
        if (key == 'parent_id' || key == 'department_id') {
          final page = await c.repository.departments(
            c.scope,
            CivilDate.parse(date),
            search: query,
            after: after,
          );
          return (
            [
              for (final d in page.items)
                if (key != 'parent_id' || d.id != form['id'])
                  OrganizationChoice(d.id, '${d.name} · ${d.code}'),
            ],
            page.nextCursor,
          );
        }
        if (key == 'manager_id') {
          final rows = await c.employeeChoices(query, date, after: after);
          return (
            [
              for (final row in rows)
                if (row['id'] != form['employee_id'])
                  OrganizationChoice(
                    row['id'] as String,
                    '${row['display_name']} · ${row['code']}',
                  ),
            ],
            rows.length == 50 ? rows.last['id'] as String : null,
          );
        }
        final page = await c.calendars!.directory(
          c.scope,
          asOfDate: date,
          search: query,
          after: after,
        );
        return (
          [
            for (final row in page.page.items)
              if (row.coverage != null)
                OrganizationChoice(
                  row.coverage!.id,
                  '${row.calendar.name} · ${row.coverage!.start} → ${row.coverage!.endExclusive} · ${row.coverage!.timezone}',
                ),
          ],
          page.page.nextCursor,
        );
      },
      () => c.current,
    );
    if (choice != null && mounted && c.current && !c.locked) {
      labels[key] = choice.label;
      c.edit(key, choice.id);
      setState(() {});
    }
  }

  Widget field(
    String key,
    String label, {
    bool nullable = false,
    bool enabled = true,
    int lines = 1,
  }) {
    final c = widget.controller;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        key: ValueKey('${c.form!['id']}:$key'),
        initialValue: c.form![key]?.toString() ?? '',
        enabled: enabled && !c.locked,
        maxLines: lines,
        onChanged: (value) =>
            c.edit(key, nullable && value.isEmpty ? null : value),
        decoration: InputDecoration(
          labelText: label,
          helperText: key.contains('date')
              ? 'YYYY-MM-DD${nullable ? ' · blank means open' : ''}'
              : null,
        ),
      ),
    );
  }

  Widget picker(String key, String label, {bool nullable = false}) {
    final c = widget.controller;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton(
            onPressed: c.locked || !c.online ? null : () => choose(key),
            child: Text(
              labels[key] ??
                  (c.form![key] == null
                      ? 'Choose $label'
                      : '$label selected · choose to inspect'),
            ),
          ),
          if (nullable && c.form![key] != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: c.locked
                    ? null
                    : () {
                        labels.remove(key);
                        c.edit(key, null);
                      },
                child: Text('Clear $label'),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      if (!c.current || c.form == null) {
        return AlertDialog(
          title: Text(
            c.current
                ? 'Organization request finished'
                : 'Organization access changed',
          ),
          content: Text(
            c.current
                ? c.message ?? 'The request is complete.'
                : 'Close the editor and reload access.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      }
      final department = c.action!.startsWith('department_');
      final end = {'end_assignment', 'withdraw_assignment'}.contains(c.action);
      return AlertDialog(
        title: Text(organizationActionLabel(c.action!)),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Expected ${department ? 'department' : 'employee'} version ${c.expectedVersion}',
                ),
                const SizedBox(height: 16),
                if (department) ...[
                  if (c.action == 'department_create')
                    field('code', 'Reserved department code'),
                  field('name', 'Department name'),
                  picker('parent_id', 'parent department', nullable: true),
                ],
                if (!department) ...[
                  Text(
                    c.selectedEmployee?.displayName ??
                        'Saved employee assignment',
                  ),
                  const SizedBox(height: 16),
                  if (!end) ...[
                    field('role_title', 'Role title'),
                    picker('department_id', 'department'),
                    picker('manager_id', 'manager', nullable: true),
                    picker('calendar_version_id', 'calendar version'),
                  ],
                ],
                field(
                  'start_date',
                  'Start date',
                  enabled: c.action != 'replace' && !end,
                ),
                field(
                  'end_date_exclusive',
                  'End date (exclusive)',
                  nullable: department,
                  enabled:
                      c.action != 'replace' &&
                      c.action != 'withdraw_assignment',
                ),
                field('reason', 'Reason', lines: 3),
                if (c.local?.pending != null)
                  const Text(
                    'The original request is sealed. Retry it to resolve the result before editing or discarding.',
                  ),
                if (c.conflict) ...[
                  const Text(
                    'The server version changed. Inspect current history before retaining this draft.',
                  ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: c.busy || !c.online ? null : c.compare,
                        child: const Text('Compare current history'),
                      ),
                      TextButton(
                        onPressed: c.busy || c.comparedVersion == null
                            ? null
                            : c.replaceConflict,
                        child: const Text('Retain compared draft'),
                      ),
                    ],
                  ),
                ],
                if (c.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      c.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (c.message != null) Text(c.message!),
                if (c.busy) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: c.locked ? null : c.discard,
            child: const Text('Discard'),
          ),
          OutlinedButton(
            onPressed: c.locked ? null : c.save,
            child: const Text('Save draft'),
          ),
          FilledButton(
            onPressed: c.busy || !c.online || c.conflict ? null : c.submit,
            child: Text(
              c.local?.pending != null
                  ? 'Retry original request'
                  : 'Confirm change',
            ),
          ),
          TextButton(
            onPressed: c.busy
                ? null
                : () async {
                    if (await c.canLeave() && context.mounted) {
                      Navigator.pop(context);
                    }
                  },
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

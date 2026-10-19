import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import '../../app_providers.dart';
import 'employee_controller.dart';

class EmployeeScreen extends ConsumerWidget {
  const EmployeeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(businessCapabilitiesProvider);
    if (capabilities.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (capabilities.hasError) {
      return Center(
        child: TextButton(
          onPressed: () => ref.invalidate(businessCapabilitiesProvider),
          child: const Text('Retry employee access check'),
        ),
      );
    }
    final controller = ref.watch(employeeControllerProvider);
    if (controller == null) {
      return const Center(
        child: Text(
          'Choose an entity and branch with employee directory permission.',
        ),
      );
    }
    return EmployeeWorkspace(key: ValueKey(controller), controller: controller);
  }
}

class EmployeeWorkspace extends StatefulWidget {
  const EmployeeWorkspace({required this.controller, super.key});
  final EmployeeController controller;
  @override
  State<EmployeeWorkspace> createState() => _EmployeeWorkspaceState();
}

class _EmployeeWorkspaceState extends State<EmployeeWorkspace> {
  bool _initialDateSynced = false;
  late final TextEditingController search = TextEditingController(
    text: widget.controller.search,
  );
  late final TextEditingController asOf = TextEditingController(
    text: widget.controller.asOfDate,
  );
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncInitialDate);
    _syncInitialDate();
  }

  void _syncInitialDate() {
    if (_initialDateSynced) return;
    if (asOf.text.isNotEmpty) {
      _initialDateSynced = true;
    } else if (widget.controller.asOfDate.isNotEmpty) {
      asOf.text = widget.controller.asOfDate;
      _initialDateSynced = true;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncInitialDate);
    search.dispose();
    asOf.dispose();
    super.dispose();
  }

  Future<void> _edit(String action, {String? eventId}) async {
    final controller = widget.controller;
    if (action == 'create') {
      controller.beginCreate();
    } else {
      controller.beginAction(action, eventId: eventId);
    }
    if (controller.form == null || !mounted) return;
    if (action == 'assignment') await controller.loadBranches();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EmployeeEditor(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      if (c.accessDenied) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                c.error ?? 'Employee access changed. Switch to an authorized branch to continue.',
              ),
              if (c.online)
                TextButton(
                  onPressed: c.busy ? null : () => c.refresh(),
                  child: const Text('Retry employee access'),
                ),
            ],
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(JentraSpacing.x6),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  JentraSectionHeader(
                    title: 'Employees',
                    description: 'Scoped operational identity and dated employment history.',
                    trailing: c.online
                        ? const JentraStatusBadge(
                            label: 'Connected',
                            tone: JentraStatusTone.success,
                          )
                        : const JentraStatusBadge(
                            label: 'Offline drafts',
                            tone: JentraStatusTone.info,
                          ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 320,
                        child: TextField(
                          controller: search,
                          decoration: const InputDecoration(
                            labelText: 'Search',
                            helperText: 'Code or name',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onSubmitted: (value) => c.filter(nextSearch: value),
                        ),
                      ),
                      SizedBox(
                        width: 260,
                        child: TextField(
                          controller: asOf,
                          decoration: const InputDecoration(
                            labelText: 'As of date',
                            helperText: 'YYYY-MM-DD',
                          ),
                          onSubmitted: (value) => c.filter(nextDate: value),
                        ),
                      ),
                      DropdownButton<String>(
                        value: c.status,
                        items: const [
                          DropdownMenuItem(
                            value: 'employed',
                            child: Text('Employed'),
                          ),
                          DropdownMenuItem(
                            value: 'future',
                            child: Text('Future'),
                          ),
                          DropdownMenuItem(
                            value: 'ended',
                            child: Text('Ended'),
                          ),
                        ],
                        onChanged: c.busy
                            ? null
                            : (value) {
                                if (value != null) c.filter(nextStatus: value);
                              },
                      ),
                      OutlinedButton.icon(
                        onPressed: c.busy
                            ? null
                            : () => c.filter(
                                nextSearch: search.text,
                                nextDate: asOf.text,
                              ),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Apply filters'),
                      ),
                      if (c.canCreate)
                        FilledButton.icon(
                          onPressed: c.busy || c.local?.pending != null
                              ? null
                              : () => _edit('create'),
                          icon: const Icon(Icons.person_add_alt_1_outlined),
                          label: const Text('New employee'),
                        ),
                    ],
                  ),
                  if (c.busy) const LinearProgressIndicator(),
                  if (c.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        c.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (c.message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(c.message!),
                    ),
                  if (c.local?.pending != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Wrap(
                            spacing: 12,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text(
                                'Employee request awaiting confirmation. Retry its saved version.',
                              ),
                              FilledButton(
                                onPressed: c.online && !c.busy
                                    ? c.submit
                                    : null,
                                child: const Text('Retry original request'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (c.form != null && c.local?.pending == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: OutlinedButton.icon(
                        onPressed: c.busy
                            ? null
                            : () async {
                                await showDialog<void>(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (_) =>
                                      _EmployeeEditor(controller: c),
                                );
                              },
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Resume employee draft'),
                      ),
                    ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
            if (c.items.isEmpty && !c.busy)
              const SliverToBoxAdapter(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No employees in this branch for the selected date and status.',
                    ),
                  ),
                ),
              )
            else
              SliverList.builder(
                itemCount: c.items.length,
                itemBuilder: (context, index) {
                  final row = c.items[index];
                  return Card(
                    child: ListTile(
                      title: Text('${row['code']} · ${row['display_name']}'),
                      subtitle: Text('Version ${row['version']} · ${c.status}'),
                      trailing: const Icon(Icons.chevron_right),
                      selected: c.selected?['id'] == row['id'],
                      onTap: c.busy ? null : () => c.open(row['id'] as String),
                    ),
                  );
                },
              ),
            if (c.cursor != null)
              SliverToBoxAdapter(
                child: Center(
                  child: TextButton(
                    onPressed: c.busy ? null : () => c.refresh(more: true),
                    child: const Text('Load more employees'),
                  ),
                ),
              ),
            if (c.selected != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: _EmployeeDetail(controller: c, onAction: _edit),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _EmployeeDetail extends StatelessWidget {
  const _EmployeeDetail({required this.controller, required this.onAction});
  final EmployeeController controller;
  final Future<void> Function(String action, {String? eventId}) onAction;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final record = c.selected!;
    final assignments = (record['assignments'] as List).cast<Map>();
    final active = assignments
        .where((a) => a['end_date_exclusive'] == null)
        .firstOrNull;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              record['display_name'] as String,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              '${record['code']} · ${record['work_email'] ?? 'No work email'}',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (c.canCreate)
                  OutlinedButton(
                    onPressed: c.locked ? null : () => onAction('identity'),
                    child: const Text('Edit identity'),
                  ),
                if (c.canManageEmployment &&
                    c.status == 'employed' &&
                    active != null)
                  OutlinedButton(
                    onPressed: c.locked ? null : () => onAction('assignment'),
                    child: const Text('Change assignment'),
                  ),
                if (c.canManageEmployment &&
                    c.status == 'employed' &&
                    active != null)
                  OutlinedButton(
                    onPressed: c.locked ? null : () => onAction('end'),
                    child: const Text('End employment'),
                  ),
                if (c.canManageEmployment && c.status == 'ended')
                  OutlinedButton(
                    onPressed: c.locked ? null : () => onAction('rehire'),
                    child: const Text('Record rehire'),
                  ),
              ],
            ),
            const Divider(height: 28),
            Text(
              'Employment in this branch',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final assignment in assignments)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${assignment['job_title']} · ${assignment['employment_type']}',
                ),
                subtitle: Text(
                  '${assignment['start_date']} – '
                  '${assignment['end_date_exclusive'] ?? 'Open'}',
                ),
              ),
            if (c.canReadHistory) ...[
              const Divider(height: 28),
              Text(
                'Scoped history',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final event in c.events)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${event['action']} · ${event['effective_date']}',
                  ),
                  subtitle: Text(
                    event['reason'] as String? ?? 'Initial record',
                  ),
                  trailing:
                      c.canManageEmployment &&
                          event['action'] == 'assignment' &&
                          (event['effective_date'] as String).compareTo(
                                c.asOfDate,
                              ) >
                              0
                      ? TextButton(
                          onPressed: c.locked
                              ? null
                              : () => onAction(
                                  'correct',
                                  eventId: event['id'] as String,
                                ),
                          child: const Text('Cancel scheduled change'),
                        )
                      : null,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmployeeEditor extends StatefulWidget {
  const _EmployeeEditor({required this.controller});
  final EmployeeController controller;
  @override
  State<_EmployeeEditor> createState() => _EmployeeEditorState();
}

class _EmployeeEditorState extends State<_EmployeeEditor> {
  final fields = <String, TextEditingController>{};
  late final String action;
  @override
  void initState() {
    super.initState();
    action = widget.controller.form!['action'] as String;
    for (final name in [
      'code',
      'display_name',
      'work_email',
      'start_date',
      'effective_date',
      'end_date_exclusive',
      'job_title',
      'reason',
    ]) {
      if (widget.controller.form!.containsKey(name)) {
        fields[name] = TextEditingController(
          text: widget.controller.form![name]?.toString() ?? '',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Widget _text(
    String key,
    String label, {
    bool date = false,
    double width = 285,
  }) {
    final field = fields[key];
    if (field == null) return const SizedBox.shrink();
    return SizedBox(
      width: width,
      child: TextField(
        controller: field,
        maxLength: key == 'reason'
            ? 1000
            : key == 'work_email'
            ? 254
            : null,
        readOnly: date,
        onTap: date
            ? () async {
                final initial = DateTime.tryParse(field.text) ?? DateTime.now();
                final selected = await showDatePicker(
                  context: context,
                  initialDate: initial,
                  firstDate: DateTime(1900),
                  lastDate: DateTime(2100),
                );
                if (selected != null) {
                  final value = selected.toIso8601String().substring(0, 10);
                  field.text = value;
                  widget.controller.edit(key, value);
                }
              }
            : null,
        onChanged: date ? null : (value) => widget.controller.edit(key, value),
        decoration: InputDecoration(
          labelText: label,
          helperText: date ? 'Civil date in entity time zone' : null,
          suffixIcon: date ? const Icon(Icons.calendar_today_outlined) : null,
        ),
      ),
    );
  }

  Future<void> _submit() async {
    await widget.controller.submit();
    if (!mounted) return;
    if (widget.controller.form == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final fieldWidth = MediaQuery.textScalerOf(context).scale(1) >= 1.5
        ? 560.0
        : 285.0;
    return AlertDialog(
      title: Text(switch (action) {
        'create' => 'New employee',
        'identity' => 'Edit identity',
        'assignment' => 'Schedule assignment',
        'end' => 'End employment',
        'rehire' => 'Record rehire',
        _ => 'Cancel scheduled change',
      }),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Employment dates use the entity calendar. '
                'Saved actions retain an attributable history.',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _text('code', 'Employee code', width: fieldWidth),
                  _text('display_name', 'Display name', width: fieldWidth),
                  _text(
                    'work_email',
                    'Work email (optional)',
                    width: fieldWidth,
                  ),
                  _text(
                    'start_date',
                    'Start date',
                    date: true,
                    width: fieldWidth,
                  ),
                  _text(
                    'effective_date',
                    'Effective date',
                    date: true,
                    width: fieldWidth,
                  ),
                  _text(
                    'end_date_exclusive',
                    'First day no longer employed',
                    date: true,
                    width: fieldWidth,
                  ),
                  _text('job_title', 'Job title', width: fieldWidth),
                  if (c.form!.containsKey('employment_type'))
                    SizedBox(
                      width: fieldWidth,
                      child: DropdownButtonFormField<String>(
                        initialValue: c.form!['employment_type'] as String?,
                        decoration: const InputDecoration(
                          labelText: 'Employment type',
                        ),
                        items: employeeEmploymentTypes
                            .map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(type.replaceAll('_', ' ')),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            c.edit('employment_type', value);
                          }
                        },
                      ),
                    ),
                  if (action == 'assignment')
                    SizedBox(
                      width: fieldWidth,
                      child: DropdownButtonFormField<String>(
                        initialValue:
                            c.branches.any(
                              (b) =>
                                  b['id'] == c.form!['destination_branch_id'],
                            )
                            ? c.form!['destination_branch_id'] as String
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Destination branch',
                        ),
                        items: [
                          for (final branch in c.branches)
                            DropdownMenuItem(
                              value: branch['id'] as String,
                              child: Text(branch['name'] as String),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            c.edit('destination_branch_id', value);
                          }
                        },
                      ),
                    ),
                  _text('reason', 'Reason', width: fieldWidth),
                ],
              ),
              if (c.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    c.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (action == 'correct')
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'The original event remains in history. Only a future, '
                    'unconsumed assignment can be cancelled.',
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: c.busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        TextButton(
          onPressed: c.busy
              ? null
              : () async {
                  await c.saveLocal();
                  if (!mounted) return;
                  if (c.error == null) {
                    Navigator.of(this.context).pop();
                  } else {
                    setState(() {});
                  }
                },
          child: const Text('Save encrypted draft'),
        ),
        FilledButton(
          onPressed: c.busy || !c.online ? null : _submit,
          child: Text(c.busy ? 'Saving…' : 'Confirm action'),
        ),
      ],
    );
  }
}

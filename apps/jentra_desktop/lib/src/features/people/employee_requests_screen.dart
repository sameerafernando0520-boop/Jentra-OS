import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'employee_requests_controller.dart';

String employeeRequestKind(String kind) =>
    kind == 'attendance' ? 'Attendance evidence' : 'Leave cancellations';

class EmployeeRequestsScreen extends ConsumerWidget {
  const EmployeeRequestsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(employeeRequestsControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Employee requests')),
      body: controller == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Sign in with MFA and choose an entity and branch with workforce access.',
                ),
              ),
            )
          : EmployeeRequestsWorkspace(
              key: ValueKey(controller),
              controller: controller,
            ),
    );
  }
}

class EmployeeRequestsWorkspace extends StatefulWidget {
  const EmployeeRequestsWorkspace({required this.controller, super.key});
  final EmployeeRequestsController controller;
  @override
  State<EmployeeRequestsWorkspace> createState() =>
      _EmployeeRequestsWorkspaceState();
}

class _EmployeeRequestsWorkspaceState extends State<EmployeeRequestsWorkspace> {
  final reason = TextEditingController();
  EmployeeRequestsController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.addListener(_wipeIfUnavailable);
    unawaited(c.refresh());
  }

  void _wipeIfUnavailable() {
    if (!c.current || !c.online) reason.clear();
  }

  @override
  void dispose() {
    c.removeListener(_wipeIfUnavailable);
    reason.clear();
    reason.dispose();
    super.dispose();
  }

  Future<void> _decide(bool approve) async {
    if (reason.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a reason for this decision.')),
      );
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          approve
              ? (c.kind == 'attendance'
                    ? 'Resolve attendance evidence?'
                    : 'Cancel approved leave?')
              : 'Decline this request?',
        ),
        content: Text(
          approve && c.kind == 'leave_cancel'
              ? 'This cancels the linked approved leave and reverses its leave balance through the leave workflow.'
              : approve
              ? 'The matching approved attendance record will be linked to this evidence.'
              : 'The employee will see the decision and your reason.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm decision'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted || c.locked) return;
    await c.decide(approve: approve, reason: reason.text);
    if (c.pending == null) reason.clear();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      if (!c.current) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(c.error ?? 'HR access changed. Reopen this screen.'),
          ),
        );
      }
      final row = c.selected;
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final kind in c.kinds)
                ChoiceChip(
                  label: Text(employeeRequestKind(kind)),
                  selected: kind == c.kind,
                  onSelected: c.locked
                      ? null
                      : (_) {
                          reason.clear();
                          unawaited(c.changeKind(kind));
                        },
                ),
              OutlinedButton.icon(
                onPressed: c.locked
                    ? null
                    : () {
                        reason.clear();
                        unawaited(c.refresh());
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('Reload'),
              ),
            ],
          ),
          if (c.busy) const LinearProgressIndicator(),
          if (!c.online)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Reconnect to review private employee requests.'),
            ),
          if (c.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(c.error!, semanticsLabel: c.error),
            ),
          if (c.message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(c.message!),
            ),
          if (c.pending != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This decision has an unconfirmed result. Verify the original request before making another decision.',
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: c.busy || !c.online ? null : c.retry,
                      child: const Text('Verify original decision'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (c.rows.isEmpty && !c.busy && c.online && c.pending == null)
            const Text(
              'No pending employee requests in this entity and branch.',
            ),
          for (final item in c.rows)
            Card(
              child: ListTile(
                selected: row?['id'] == item['id'],
                title: Text(item['employee_name']! as String),
                subtitle: Text(
                  c.kind == 'attendance'
                      ? '${item['action'] == 'correction' ? 'Correction' : 'Clock evidence'} · ${item['observed_at']}\n${item['reason']}'
                      : '${item['start_local']} to ${item['end_local']}\n${item['reason']}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: c.locked
                    ? null
                    : () {
                        reason.clear();
                        unawaited(c.open(item));
                      },
              ),
            ),
          if (c.cursor != null)
            OutlinedButton(
              onPressed: c.locked ? null : () => c.refresh(more: true),
              child: const Text('More requests'),
            ),
          if (row != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Review · ${row['employee_name']}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(row['reason']! as String),
                    if (c.kind == 'attendance') ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Choose the matching approved attendance. Create or correct and independently approve it in Attendance first.',
                      ),
                      if (c.attendance.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'No matching approved attendance was found on this page.',
                          ),
                        ),
                      for (final entry in c.attendance)
                        ListTile(
                          leading: Icon(
                            c.canonical?.id == entry.id
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                          ),
                          title: Text(
                            '${entry.revision.startLocal} to ${entry.revision.endLocal}',
                          ),
                          subtitle: Text(
                            'Approved · revision ${entry.revision.version} · ${entry.revision.reason}',
                          ),
                          selected: c.canonical?.id == entry.id,
                          onTap: c.locked
                              ? null
                              : () => c.chooseAttendance(entry),
                        ),
                      if (c.attendanceCursor != null)
                        OutlinedButton(
                          onPressed: c.locked ? null : c.moreAttendance,
                          child: const Text('Search more approved attendance'),
                        ),
                    ] else ...[
                      const SizedBox(height: 12),
                      Text('Linked leave: ${row['source_status']}'),
                      Text('${row['start_local']} to ${row['end_local']}'),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: reason,
                      enabled: !c.locked && c.canDecide,
                      maxLength: 1000,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Decision reason',
                      ),
                    ),
                    if (!c.canDecide)
                      const Text(
                        'A colleague with approval permission must record the decision.',
                      ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton(
                          onPressed:
                              c.locked ||
                                  !c.canDecide ||
                                  c.kind == 'attendance' && c.canonical == null
                              ? null
                              : () => _decide(true),
                          child: Text(
                            c.kind == 'attendance'
                                ? 'Resolve with approved attendance'
                                : 'Approve leave cancellation',
                          ),
                        ),
                        OutlinedButton(
                          onPressed: c.locked || !c.canDecide
                              ? null
                              : () => _decide(false),
                          child: const Text('Decline request'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

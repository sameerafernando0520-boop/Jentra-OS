import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_people.dart';

import '../../app_providers.dart';
import 'organization_screen.dart';
import 'workforce_controller.dart';

class WorkforceScreen extends ConsumerWidget {
  const WorkforceScreen({super.key});
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
          child: const Text('Retry workforce access'),
        ),
      );
    }
    final c = ref.watch(workforceControllerProvider);
    if (c == null) {
      return const Center(
        child: Text(
          'Choose an entity and branch with attendance or leave access.',
        ),
      );
    }
    return WorkforceWorkspace(key: ValueKey(c), controller: c);
  }
}

String workforceViewLabel(WorkforceView view) => switch (view) {
  WorkforceView.attendance => 'Attendance',
  WorkforceView.leave => 'Leave requests',
  WorkforceView.policies => 'Leave policies',
  WorkforceView.rawEvents => 'Clock events',
  WorkforceView.workClaims => 'Work ownership',
};
String workforceDuration(int seconds) =>
    '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m ${seconds % 60}s';
String workforceKindLabel(WorkforceCommandKind kind) => switch (kind) {
  WorkforceCommandKind.attendance => 'Attendance',
  WorkforceCommandKind.leavePolicy => 'Leave policy',
  WorkforceCommandKind.leaveGrant => 'Leave balance',
  WorkforceCommandKind.leaveRequest => 'Private leave',
};
String workforceActionLabel(String action) => switch (action) {
  'raw_import' => 'Import clock event',
  'raw_import_batch' => 'Import clock CSV',
  'create' => 'Create',
  'correct' => 'Correct',
  'publish' => 'Publish version',
  'accrue' => 'Accrue',
  'carry' => 'Carry forward',
  'adjust' => 'Adjust',
  'submit' => 'Submit',
  'approve' => 'Approve',
  'reject' => 'Reject',
  'cancel' => 'Cancel',
  _ => action,
};
String workforceRange(WorkSpan span) =>
    '${span.startUtc.toIso8601String()} → ${span.endUtc.toIso8601String()}';

class WorkforceWorkspace extends StatefulWidget {
  const WorkforceWorkspace({required this.controller, super.key});
  final WorkforceController controller;
  @override
  State<WorkforceWorkspace> createState() => _WorkforceWorkspaceState();
}

class _WorkforceWorkspaceState extends State<WorkforceWorkspace> {
  late final date = TextEditingController(text: widget.controller.asOfDate);
  @override
  void dispose() {
    date.dispose();
    super.dispose();
  }

  Future<void> employee() async {
    final c = widget.controller;
    final choice = await organizationPicker(context, 'Employee', (
      query,
      after,
    ) async {
      final rows = await c.employeeChoices(query, after: after);
      return (
        [
          for (final row in rows)
            OrganizationChoice(
              row['id'] as String,
              '${row['display_name']} · ${row['code']}',
            ),
        ],
        rows.length == 50 ? rows.last['id'] as String : null,
      );
    }, () => c.current);
    if (choice != null) {
      await c.selectEmployee(choice.id);
    }
  }

  Future<void> editor(Future<void> action) async {
    await action;
    final c = widget.controller;
    if (!mounted || c.form == null) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WorkforceEditor(controller: c),
    );
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
  Widget action(
    String label,
    WorkforceCommandKind kind,
    String command, {
    bool transition = false,
    bool enabled = true,
  }) {
    final c = widget.controller;
    return OutlinedButton(
      onPressed: c.busy || !c.online || !enabled
          ? null
          : () => editor(
              transition ? c.transition(kind, command) : c.begin(kind, command),
            ),
      child: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      if (!c.current) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(c.error ?? 'Workforce access changed. Reload access.'),
          ),
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
                'Attendance & leave',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              OutlinedButton(
                onPressed: c.busy || !c.online ? null : () => c.refresh(),
                child: const Text('Reload'),
              ),
              if (!c.online)
                const Chip(
                  label: Text('Offline · saved operational drafts available'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed:
                    c.busy || !c.online || !c.has('people.employees.view')
                    ? null
                    : employee,
                icon: const Icon(Icons.person_outline),
                label: Text(c.employeeName ?? 'Choose employee'),
              ),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: date,
                  decoration: const InputDecoration(
                    labelText: 'As of date',
                    hintText: 'YYYY-MM-DD',
                  ),
                ),
              ),
              TextButton(
                onPressed: c.busy ? null : () => c.filterDate(date.text),
                child: const Text('Apply date'),
              ),
              if (c.assignedCalendar != null)
                Chip(
                  label: Text(
                    'Calendar: ${c.assignedCalendar!.calendar.name} · ${c.assignedCalendar!.version.summary.coverage.timezone}',
                  ),
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
                  label: Text(workforceViewLabel(view)),
                  selected: c.view == view,
                  onSelected: c.busy ? null : (_) => c.changeView(view),
                ),
            ],
          ),
          if (c.busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            ),
          if (c.error != null)
            card('Workforce unavailable', [SelectableText(c.error!)]),
          if (c.message != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(c.message!)),
          if (c.view == WorkforceView.leave ||
              c.view == WorkforceView.policies) ...[
            card('Policy and dated balance', [
              if (c.policies.isEmpty)
                const Text(
                  'No visible leave policies. A policy manager can create a synthetic policy.',
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final policy in c.policies)
                    ChoiceChip(
                      label: Text('${policy.code} · ${policy.name}'),
                      selected: c.selectedPolicy?.id == policy.id,
                      onSelected: c.busy || !c.online
                          ? null
                          : (_) => c.selectPolicy(policy),
                    ),
                ],
              ),
              if (c.policyCursor != null)
                TextButton(
                  onPressed: c.busy ? null : c.morePolicies,
                  child: const Text('More policies'),
                ),
              if (c.selectedPolicyVersion != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Effective ${c.selectedPolicyVersion!.start.value} to ${c.selectedPolicyVersion!.endExclusive.value} (exclusive) · ${c.selectedPolicyVersion!.unit}',
                ),
                Text(
                  'Accrual ${workforceDuration(c.selectedPolicyVersion!.accrualSeconds)} ${c.selectedPolicyVersion!.accrualFrequency} · carry cap ${workforceDuration(c.selectedPolicyVersion!.carryCapSeconds)} · expiry ${c.selectedPolicyVersion!.expiryDays} days',
                ),
                Text(
                  'Eligible: ${c.selectedPolicyVersion!.eligibleTypes.join(', ')} · unpaid shortfall ${c.selectedPolicyVersion!.allowUnpaid ? 'allowed' : 'blocked'}',
                ),
              ] else if (c.selectedPolicy != null)
                const Text('No policy version covers this date.'),
              if (c.balance != null)
                Text(
                  'Available ${workforceDuration(c.balance!.availableSeconds)} · balance revision ${c.balance!.accountVersion}',
                ),
              if (c.balance?.policyId == c.selectedPolicy?.id) ...[
                for (final grant in c.balanceGrants)
                  ListTile(
                    title: Text('${grant.sourceKind} · ${grant.sourceKey}'),
                    subtitle: Text(
                      '${grant.effective.value} → ${grant.expiry.value} (expiry exclusive)\nGranted ${workforceDuration(grant.seconds)} · remaining ${workforceDuration(grant.remainingSeconds)}',
                    ),
                  ),
                if (c.balance?.nextCursor != null)
                  TextButton(
                    onPressed: c.busy ? null : c.moreBalance,
                    child: const Text('More grant sources'),
                  ),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (c.has('people.leave.policy.manage'))
                    action(
                      'Create policy',
                      WorkforceCommandKind.leavePolicy,
                      'create',
                    ),
                  if (c.has('people.leave.policy.manage') &&
                      c.selectedPolicy != null)
                    OutlinedButton(
                      onPressed: c.busy || !c.online
                          ? null
                          : () => editor(c.publishPolicy()),
                      child: const Text('Publish next policy version'),
                    ),
                  if (c.has('people.leave.policy.manage'))
                    action(
                      'Accrue entitlement',
                      WorkforceCommandKind.leaveGrant,
                      'accrue',
                      enabled:
                          c.balance != null && c.selectedPolicyVersion != null,
                    ),
                  if (c.has('people.leave.policy.manage'))
                    action(
                      'Carry forward',
                      WorkforceCommandKind.leaveGrant,
                      'carry',
                      enabled:
                          c.balance != null && c.selectedPolicyVersion != null,
                    ),
                  if (c.has('people.leave.adjust'))
                    action(
                      'Adjust balance',
                      WorkforceCommandKind.leaveGrant,
                      'adjust',
                      enabled:
                          c.balance != null && c.selectedPolicyVersion != null,
                    ),
                ],
              ),
              if (c.view == WorkforceView.policies) ...[
                for (final v in c.policyHistory)
                  ListTile(
                    title: Text(
                      'Version ${v.version} · ${v.start.value} → ${v.endExclusive.value}',
                    ),
                    subtitle: Text(
                      '${v.reason}\nPublished ${v.publishedAt.toIso8601String()}',
                    ),
                  ),
              ],
            ]),
          ],
          if (c.view != WorkforceView.policies)
            card(workforceViewLabel(c.view), [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (c.view == WorkforceView.attendance &&
                      c.has('people.attendance.manage'))
                    action(
                      'Record attendance',
                      WorkforceCommandKind.attendance,
                      'create',
                      enabled: c.canCreate,
                    ),
                  if (c.view == WorkforceView.leave &&
                      c.has('people.leave.manage'))
                    action(
                      'Request leave',
                      WorkforceCommandKind.leaveRequest,
                      'create',
                      enabled: c.canCreate && c.selectedPolicyVersion != null,
                    ),
                  if (c.view == WorkforceView.rawEvents &&
                      c.has('people.attendance.import'))
                    action(
                      'Import clock event',
                      WorkforceCommandKind.attendance,
                      'raw_import',
                      enabled: c.employeeId != null,
                    ),
                  if (c.view == WorkforceView.rawEvents &&
                      c.has('people.attendance.import'))
                    action(
                      'Import clock CSV',
                      WorkforceCommandKind.attendance,
                      'raw_import_batch',
                      enabled: c.employeeId != null,
                    ),
                ],
              ),
              if (c.employeeId == null)
                const Text('Choose an employee to load scoped records.'),
              if (c.employeeId != null &&
                  !c.canCreate &&
                  {
                    WorkforceView.attendance,
                    WorkforceView.leave,
                  }.contains(c.view))
                const Text(
                  'A dated organization assignment and published calendar are required to record an interval.',
                ),
              if (c.employeeId != null &&
                  !c.busy &&
                  switch (c.view) {
                    WorkforceView.attendance => c.attendance.isEmpty,
                    WorkforceView.leave => c.leave.isEmpty,
                    WorkforceView.rawEvents => c.rawEvents.isEmpty,
                    WorkforceView.workClaims => c.workClaims.isEmpty,
                    _ => false,
                  })
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No visible records for this employee.'),
                ),
              if (c.view == WorkforceView.attendance) ...[
                for (final row in c.attendance)
                  ListTile(
                    title: Text(
                      '${row.status} · ${workforceDuration(row.revision.payableSeconds)}',
                    ),
                    subtitle: Text(workforceRange(row.revision.span)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: c.busy ? null : () => c.openAttendance(row.id),
                  ),
              ],
              if (c.view == WorkforceView.leave) ...[
                for (final row in c.leave)
                  ListTile(
                    title: Text(
                      '${row.status} · ${workforceDuration(row.chargeSeconds)}',
                    ),
                    subtitle: Text(workforceRange(row.span)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: c.busy ? null : () => c.openLeave(row.id),
                  ),
              ],
              if (c.view == WorkforceView.rawEvents) ...[
                const Text('Immutable clock batch history'),
                for (final batch in c.clockBatches)
                  ListTile(
                    title: Text(
                      '${batch.sourceSystem} · ${batch.rowCount} events',
                    ),
                    subtitle: Text(
                      '${batch.importedCount} imported · ${batch.rowCount - batch.importedCount} reused\n${batch.importedAt.toIso8601String()}',
                    ),
                    onTap: c.busy ? null : () => c.openClockBatch(batch.id),
                  ),
                if (c.clockBatchCursor != null)
                  TextButton(
                    onPressed: c.busy ? null : c.moreClockBatches,
                    child: const Text('More clock batches'),
                  ),
                if (c.selectedClockBatch != null) ...[
                  Text('Batch digest: ${c.selectedClockBatch!.digest}'),
                  for (final row in c.clockLineage)
                    ListTile(
                      title: Text(
                        '${row.position}. ${row.sourceKey} · ${row.reused ? 'reused' : 'imported'}',
                      ),
                      subtitle: Text(
                        '${row.observedUtc.toIso8601String()}\nOriginal event ${row.eventId}',
                      ),
                    ),
                  if (c.clockLineageCursor != null)
                    TextButton(
                      onPressed: c.busy
                          ? null
                          : () => c.openClockBatch(
                              c.selectedClockBatch!.id,
                              more: true,
                            ),
                      child: const Text('More batch lineage'),
                    ),
                ],
                for (final row in c.rawEvents)
                  ListTile(
                    title: Text('${row.sourceSystem} · ${row.sourceKey}'),
                    subtitle: Text(
                      '${row.observedUtc.toIso8601String()}\nImported ${row.importedAt.toIso8601String()}',
                    ),
                  ),
              ],
              if (c.view == WorkforceView.workClaims) ...[
                for (final row in c.workClaims)
                  ListTile(
                    title: Text(
                      '${row.sourceKind} · ${row.active ? 'active' : 'revoked'} · ${workforceDuration(row.payableSeconds)}',
                    ),
                    subtitle: Text(workforceRange(row.span)),
                  ),
              ],
              if (c.cursor != null)
                TextButton(
                  onPressed: c.busy ? null : () => c.refresh(more: true),
                  child: const Text('More records'),
                ),
            ]),
          if (c.view == WorkforceView.attendance &&
              c.selectedAttendance != null)
            card('Attendance detail', [
              Text(
                '${c.selectedAttendance!.status} · revision ${c.selectedAttendance!.version}',
              ),
              Text(
                '${c.selectedAttendance!.revision.startLocal} → ${c.selectedAttendance!.revision.endLocal}',
              ),
              Text(
                'Gross ${workforceDuration(c.selectedAttendance!.revision.grossSeconds)} · breaks ${workforceDuration(c.selectedAttendance!.revision.breakSeconds)} · payable ${workforceDuration(c.selectedAttendance!.revision.payableSeconds)}',
              ),
              SelectableText(c.selectedAttendance!.revision.reason),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (c.has('people.attendance.manage')) ...[
                    action(
                      'Correct interval',
                      WorkforceCommandKind.attendance,
                      'correct',
                      transition: true,
                    ),
                    if (c.selectedAttendance!.status == 'draft')
                      action(
                        'Submit attendance',
                        WorkforceCommandKind.attendance,
                        'submit',
                        transition: true,
                      ),
                  ],
                  if (c.has('people.attendance.approve') &&
                      c.selectedAttendance!.status == 'submitted') ...[
                    action(
                      'Approve',
                      WorkforceCommandKind.attendance,
                      'approve',
                      transition: true,
                    ),
                    action(
                      'Reject',
                      WorkforceCommandKind.attendance,
                      'reject',
                      transition: true,
                    ),
                  ],
                  if (c.has('people.attendance.approve') &&
                      c.selectedAttendance!.status == 'approved')
                    action(
                      'Cancel approval',
                      WorkforceCommandKind.attendance,
                      'cancel',
                      transition: true,
                    ),
                ],
              ),
              for (final event in c.attendanceHistory)
                ListTile(
                  title: Text(
                    'Revision ${event.version} · ${workforceDuration(event.payableSeconds)}',
                  ),
                  subtitle: Text(
                    '${event.reason}\n${event.recordedAt.toIso8601String()}',
                  ),
                ),
              if (c.historyCursor != null)
                TextButton(
                  onPressed: c.busy
                      ? null
                      : () => c.openAttendance(
                          c.selectedAttendance!.id,
                          more: true,
                        ),
                  child: const Text('More history'),
                ),
            ]),
          if (c.view == WorkforceView.leave && c.selectedLeave != null)
            card('Private leave detail', [
              Text(
                '${c.selectedLeave!.status} · revision ${c.selectedLeave!.version}',
              ),
              Text(
                'Charged ${workforceDuration(c.selectedLeave!.chargeSeconds)} · unpaid ${workforceDuration(c.selectedLeave!.unpaidSeconds)}',
              ),
              SelectableText(c.selectedLeave!.reason),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (c.has('people.leave.manage') &&
                      c.selectedLeave!.status == 'draft')
                    action(
                      'Submit request',
                      WorkforceCommandKind.leaveRequest,
                      'submit',
                      transition: true,
                    ),
                  if (c.has('people.leave.approve') &&
                      c.selectedLeave!.status == 'submitted') ...[
                    action(
                      'Approve leave',
                      WorkforceCommandKind.leaveRequest,
                      'approve',
                      transition: true,
                    ),
                    action(
                      'Reject leave',
                      WorkforceCommandKind.leaveRequest,
                      'reject',
                      transition: true,
                    ),
                  ],
                  if (c.has('people.leave.approve') &&
                      c.selectedLeave!.status == 'approved')
                    action(
                      'Cancel leave',
                      WorkforceCommandKind.leaveRequest,
                      'cancel',
                      transition: true,
                    ),
                ],
              ),
              for (final event in c.leaveHistory)
                ListTile(
                  title: Text('${event.action} · ${event.afterStatus}'),
                  subtitle: Text(
                    '${event.reason}\n${event.recordedAt.toIso8601String()}',
                  ),
                ),
              if (c.historyCursor != null)
                TextButton(
                  onPressed: c.busy
                      ? null
                      : () => c.openLeave(c.selectedLeave!.id, more: true),
                  child: const Text('More private history'),
                ),
            ]),
          card('Encrypted recovery', [
            const Text(
              'Private leave text expires after 24 hours. Uncertain requests retain a minimal receipt for reconciliation.',
            ),
            for (final saved in c.recovery)
              ListTile(
                title: Text(
                  '${workforceKindLabel(saved.kind)} · ${workforceActionLabel(saved.draft.action)}',
                ),
                subtitle: Text(
                  saved.draft.pending != null
                      ? 'Exact request retained · reconcile before editing'
                      : saved.draft.errorCode ?? 'Saved draft',
                ),
                trailing: TextButton(
                  onPressed: c.busy ? null : () => editor(c.resume(saved)),
                  child: const Text('Resume'),
                ),
              ),
            for (final saved in c.leaveRecovery)
              ListTile(
                title: Text(
                  saved.expired
                      ? 'Expired private leave draft'
                      : 'Private leave draft',
                ),
                subtitle: Text(
                  saved.expiresAt == null
                      ? 'Minimal receipt retained'
                      : 'Text expires ${saved.expiresAt!.toIso8601String()}',
                ),
                trailing: TextButton(
                  onPressed: c.busy || !c.online
                      ? null
                      : () => editor(c.resumeLeave(saved)),
                  child: Text(saved.expired ? 'Reconcile' : 'Resume'),
                ),
              ),
            for (final entry in c.recoveryCursors.entries.where(
              (entry) => entry.value != null,
            ))
              TextButton(
                onPressed: c.busy ? null : () => c.moreRecovery(entry.key),
                child: Text('More ${workforceKindLabel(entry.key)} recovery'),
              ),
          ]),
        ],
      );
    },
  );
}

class WorkforceEditor extends StatelessWidget {
  const WorkforceEditor({required this.controller, super.key});
  final WorkforceController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller, form = controller.form;
      if (!c.current || form == null) {
        return AlertDialog(
          title: Text(
            c.confirmed != null
                ? 'Command confirmed'
                : 'Workforce editor closed',
          ),
          content: Text(
            c.message ?? c.error ?? 'Reload the workspace to continue.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      }
      final action = form['action'] as String;
      Widget text(
        String key,
        String label, {
        bool integer = false,
        int lines = 1,
      }) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          key: ValueKey('${form['id']}-$key-${c.comparedVersion}'),
          initialValue: form[key]?.toString() ?? '',
          enabled: !c.locked,
          maxLines: lines,
          decoration: InputDecoration(labelText: label),
          onChanged: (value) =>
              c.setField(key, integer ? int.tryParse(value) : value),
        ),
      );
      Widget select(String key, String label, List<String> values) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: form[key] as String?,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final value in values)
              DropdownMenuItem(value: value, child: Text(value)),
          ],
          onChanged: c.locked ? null : (value) => c.setField(key, value),
        ),
      );
      Widget offsets(
        String label,
        String key,
        CalendarLocalResolution? resolution,
      ) {
        if (resolution == null) {
          return Text(
            '$label: resolve the published time zone before submitting.',
          );
        }
        if (resolution.isGap) {
          return Text(
            '$label is in a clock-change gap. Choose an existing local time.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$label · ${resolution.timezone}${resolution.isAmbiguous ? ' · choose one occurrence' : ''}',
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in resolution.candidates)
                  ChoiceChip(
                    label: Text(value.utc.toIso8601String()),
                    selected: form[key] == value.offsetSeconds,
                    onSelected: c.locked
                        ? null
                        : (_) => c.setField(key, value.offsetSeconds),
                  ),
              ],
            ),
          ],
        );
      }

      return PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(
            '${workforceKindLabel(c.kind!)} · ${workforceActionLabel(action)}',
          ),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (c.employeeName != null &&
                      c.kind != WorkforceCommandKind.leavePolicy)
                    Text(c.employeeName!),
                  Text('Expected revision ${c.expectedVersion}'),
                  if (c.kind == WorkforceCommandKind.leaveRequest)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Use a brief private reason. Local text expires after 24 hours.',
                      ),
                    ),
                  if (c.kind == WorkforceCommandKind.leavePolicy) ...[
                    if (action == 'create') ...[
                      text('code', 'Policy code'),
                      text('name', 'Policy name'),
                    ],
                    text('start_date', 'Effective from · YYYY-MM-DD'),
                    text(
                      'end_date_exclusive',
                      'Effective until (exclusive) · YYYY-MM-DD',
                    ),
                    select('unit', 'Entitlement unit', ['hours', 'days']),
                    text(
                      'day_seconds',
                      'Nominal working day · whole seconds',
                      integer: true,
                    ),
                    select('accrual_frequency', 'Accrual frequency', [
                      'once',
                      'monthly',
                    ]),
                    text(
                      'accrual_seconds',
                      'Accrual · whole seconds',
                      integer: true,
                    ),
                    text(
                      'carry_cap_seconds',
                      'Carry cap · whole seconds',
                      integer: true,
                    ),
                    text('expiry_days', 'Grant expiry · days', integer: true),
                    const Text('Eligible employment types'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final type in [
                          'permanent',
                          'fixed_term',
                          'casual',
                          'contractor',
                        ])
                          FilterChip(
                            label: Text(type),
                            selected: (form['eligible_types'] as List).contains(
                              type,
                            ),
                            onSelected: c.locked
                                ? null
                                : (enabled) {
                                    final selected = List<String>.from(
                                      form['eligible_types'] as List,
                                    );
                                    enabled
                                        ? selected.add(type)
                                        : selected.remove(type);
                                    c.setField('eligible_types', selected);
                                  },
                          ),
                      ],
                    ),
                    SwitchListTile(
                      title: const Text('Allow explicit unpaid shortfall'),
                      value: form['allow_unpaid'] as bool,
                      onChanged: c.locked
                          ? null
                          : (value) => c.setField('allow_unpaid', value),
                    ),
                  ],
                  if (c.kind == WorkforceCommandKind.leaveGrant) ...[
                    if (action == 'accrue')
                      text(
                        'period_start',
                        'Accrual period starts · YYYY-MM-DD',
                      ),
                    if (action == 'adjust') ...[
                      text('effective_date', 'Effective date · YYYY-MM-DD'),
                      text('source_key', 'Unique adjustment reference'),
                      text(
                        'seconds',
                        'Signed adjustment · whole seconds',
                        integer: true,
                      ),
                    ],
                    if (action == 'carry') ...[
                      text('boundary_date', 'Carry boundary · YYYY-MM-DD'),
                      DropdownButtonFormField<String>(
                        initialValue: form['prior_version_id'] as String?,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Prior immutable policy version',
                        ),
                        items: [
                          for (final version in c.policyHistory.where(
                            (v) => v.id != form['policy_version_id'],
                          ))
                            DropdownMenuItem(
                              value: version.id,
                              child: Text(
                                'Version ${version.version} · ${version.start.value} → ${version.endExclusive.value}',
                              ),
                            ),
                        ],
                        onChanged: c.locked
                            ? null
                            : (id) => c.setField('prior_version_id', id),
                      ),
                    ],
                  ],
                  if (action == 'raw_import') ...[
                    text('source_system', 'Source system'),
                    text('source_key', 'Unique source event reference'),
                    text('observed_utc', 'Observed UTC · YYYY-MM-DDTHH:MM:SSZ'),
                    OutlinedButton(
                      onPressed: c.locked ? null : c.checksumRawEvent,
                      child: const Text('Validate and checksum source event'),
                    ),
                    Text(
                      (form['checksum'] as String).isEmpty
                          ? 'Source event checksum required.'
                          : 'Source event checksum recorded.',
                    ),
                  ],
                  if (action == 'raw_import_batch') ...[
                    text('source_system', 'Source system'),
                    const Text(
                      'Select a UTF-8 CSV with source_key,observed_utc. Maximum 200 events and 64 KiB. Review before submitting; this imports raw evidence only.',
                    ),
                    OutlinedButton(
                      onPressed: c.locked ? null : c.chooseClockFile,
                      child: const Text('Choose and preview clock CSV'),
                    ),
                    Text(
                      '${(form['records'] as List).length} raw events · ${c.employeeName ?? 'Selected employee'}',
                    ),
                    for (final (index, raw)
                        in (form['records'] as List).indexed)
                      ListTile(
                        dense: true,
                        title: Text(
                          '${index + 1}. ${(raw as Map)['source_key']}',
                        ),
                        subtitle: Text(raw['observed_utc'] as String),
                      ),
                    if ((form['records'] as List).isNotEmpty)
                      const Text(
                        'Exact duplicates may be reused. Changed duplicates reject the whole batch.',
                      ),
                  ],
                  if (form.containsKey('start_local')) ...[
                    text('start_local', 'Start local · YYYY-MM-DDTHH:MM:SS'),
                    text('end_local', 'End local · YYYY-MM-DDTHH:MM:SS'),
                    OutlinedButton(
                      onPressed: c.locked || !c.online ? null : c.resolveTimes,
                      child: const Text('Resolve published time zone'),
                    ),
                    offsets('Start', 'start_offset_seconds', c.startResolution),
                    const SizedBox(height: 12),
                    offsets('End', 'end_offset_seconds', c.endResolution),
                  ],
                  if (form.containsKey('breaks')) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Unpaid breaks · exact UTC intervals inside attendance',
                      ),
                    ),
                    for (final (index, raw) in (form['breaks'] as List).indexed)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              key: ValueKey('break-start-$index-${form['id']}'),
                              initialValue:
                                  (raw as Map)['start_utc'] as String?,
                              enabled: !c.locked,
                              decoration: const InputDecoration(
                                labelText: 'Break start UTC',
                              ),
                              onChanged: (value) {
                                final breaks = [
                                  for (final row in form['breaks'] as List)
                                    Map<String, Object?>.from(row as Map),
                                ];
                                breaks[index]['start_utc'] = value;
                                c.setField('breaks', breaks);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              key: ValueKey('break-end-$index-${form['id']}'),
                              initialValue: raw['end_utc'] as String?,
                              enabled: !c.locked,
                              decoration: const InputDecoration(
                                labelText: 'Break end UTC',
                              ),
                              onChanged: (value) {
                                final breaks = [
                                  for (final row in form['breaks'] as List)
                                    Map<String, Object?>.from(row as Map),
                                ];
                                breaks[index]['end_utc'] = value;
                                c.setField('breaks', breaks);
                              },
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove break',
                            onPressed: c.locked
                                ? null
                                : () => c.setField(
                                    'breaks',
                                    [...form['breaks'] as List]
                                      ..removeAt(index),
                                  ),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    TextButton(
                      onPressed:
                          c.locked || (form['breaks'] as List).length >= 16
                          ? null
                          : () => c.setField('breaks', [
                              ...form['breaks'] as List,
                              {'start_utc': '', 'end_utc': ''},
                            ]),
                      child: const Text('Add unpaid break'),
                    ),
                    if (c.rawEvents.length >= 2) ...[
                      DropdownButtonFormField<String>(
                        initialValue: form['raw_start_id'] as String?,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Optional raw start event',
                        ),
                        items: [
                          for (final row in c.rawEvents)
                            DropdownMenuItem(
                              value: row.id,
                              child: Text(
                                '${row.sourceKey} · ${row.observedUtc.toIso8601String()}',
                              ),
                            ),
                        ],
                        onChanged: c.locked
                            ? null
                            : (id) => c.setField('raw_start_id', id),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: form['raw_end_id'] as String?,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Optional raw end event',
                        ),
                        items: [
                          for (final row in c.rawEvents)
                            DropdownMenuItem(
                              value: row.id,
                              child: Text(
                                '${row.sourceKey} · ${row.observedUtc.toIso8601String()}',
                              ),
                            ),
                        ],
                        onChanged: c.locked
                            ? null
                            : (id) => c.setField('raw_end_id', id),
                      ),
                    ],
                  ],
                  if (!{'raw_import', 'raw_import_batch'}.contains(action))
                    text(
                      'reason',
                      c.kind == WorkforceCommandKind.leaveRequest
                          ? 'Private reason'
                          : 'Operational reason',
                      lines: 3,
                    ),
                  if (c.pending != null)
                    const Text(
                      'The exact submitted request is retained. Retry it to reconcile the outcome before editing.',
                    ),
                  if (c.conflict) ...[
                    const Text(
                      'The record changed. Compare the current server record before replacing the draft revision.',
                    ),
                    TextButton(
                      onPressed: c.busy ? null : c.compareConflict,
                      child: const Text('Compare current record'),
                    ),
                    if (c.comparedVersion != null) ...[
                      Text('Server revision ${c.comparedVersion}'),
                      if (c.kind == WorkforceCommandKind.attendance &&
                          c.selectedAttendance != null)
                        Text(
                          '${c.selectedAttendance!.status}\n${workforceRange(c.selectedAttendance!.revision.span)}\n${c.selectedAttendance!.revision.reason}',
                        ),
                      if (c.kind == WorkforceCommandKind.leaveRequest &&
                          c.selectedLeave != null)
                        Text(
                          '${c.selectedLeave!.status}\n${workforceRange(c.selectedLeave!.span)}\n${c.selectedLeave!.reason}',
                        ),
                      if (c.kind == WorkforceCommandKind.leavePolicy &&
                          c.selectedPolicy != null)
                        Text(
                          '${c.selectedPolicy!.name}\nLatest coverage ${c.selectedPolicy!.latest.start.value} → ${c.selectedPolicy!.latest.endExclusive.value}\n${c.selectedPolicy!.latest.reason}',
                        ),
                      if (c.kind == WorkforceCommandKind.leaveGrant &&
                          c.balance != null)
                        Text(
                          'Current available ${workforceDuration(c.balance!.availableSeconds)}',
                        ),
                      TextButton(
                        onPressed: c.busy ? null : c.replaceConflict,
                        child: const Text('Use reviewed revision'),
                      ),
                    ],
                  ],
                  if (c.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: SelectableText(c.error!),
                    ),
                  if (c.message != null) Text(c.message!),
                  if (c.busy) const LinearProgressIndicator(),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: c.busy
                  ? null
                  : () async {
                      if (await c.canLeave() && context.mounted) {
                        Navigator.pop(context);
                      }
                    },
              child: const Text('Save & close'),
            ),
            TextButton(
              onPressed: c.busy || c.pending != null
                  ? null
                  : () async {
                      await c.discard();
                      if (c.form == null && context.mounted) {
                        Navigator.pop(context);
                      }
                    },
              child: const Text('Discard draft'),
            ),
            FilledButton(
              onPressed:
                  c.busy || !c.online || c.conflict || c.confirmed != null
                  ? null
                  : c.submit,
              child: Text(
                c.pending != null ? 'Retry exact request' : 'Confirm command',
              ),
            ),
          ],
        ),
      );
    },
  );
}

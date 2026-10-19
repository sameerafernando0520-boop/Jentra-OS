import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_assurance.dart';

import '../../app_providers.dart';
import 'assurance_workspace_controller.dart';

class AssuranceWorkspaceScreen extends ConsumerWidget {
  const AssuranceWorkspaceScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(businessCapabilitiesProvider);
    if (caps.isLoading) return const Center(child: CircularProgressIndicator());
    if (caps.hasError) {
      return Center(
        child: TextButton(
          onPressed: () => ref.invalidate(businessCapabilitiesProvider),
          child: const Text('Retry access check'),
        ),
      );
    }
    final c = ref.watch(assuranceWorkspaceControllerProvider);
    return c == null
        ? const Center(
            child: Text(
              'Choose an entity and branch where you can view audit evidence.',
            ),
          )
        : AssuranceWorkspace(key: ValueKey(c), controller: c);
  }
}

String _levelLabel(ReminderLevel l) => switch (l) {
  ReminderLevel.onTrack => 'On track',
  ReminderLevel.dueSoon => 'Due soon',
  ReminderLevel.overdue => 'Overdue',
  ReminderLevel.escalated => 'Escalated',
};

String _date(DateTime? d) =>
    d == null ? 'no due date' : d.toIso8601String().substring(0, 10);

class AssuranceWorkspace extends StatelessWidget {
  const AssuranceWorkspace({super.key, required this.controller});
  final AssuranceWorkspaceController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller, theme = Theme.of(context);
      Widget action(String title, VoidCallback fn, {bool enabled = true}) =>
          TextButton(
            onPressed: c.busy || !c.online || !enabled ? null : fn,
            child: Text(title),
          );
      if (c.accessDenied) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Access changed. Audit work has been cleared.'),
              if (c.error != null) Text(c.error!),
              action('Recheck access', c.refresh),
            ],
          ),
        );
      }
      Widget levelChip(ReminderLevel l) => Chip(
        label: Text(_levelLabel(l)),
        backgroundColor: l == ReminderLevel.escalated
            ? theme.colorScheme.errorContainer
            : l == ReminderLevel.overdue
            ? theme.colorScheme.tertiaryContainer
            : null,
      );
      Widget workItem(AssuranceWorkItem i, {required bool mine}) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(i.title, style: theme.textTheme.titleMedium),
              Text(
                '${i.kind == 'finding' ? 'Finding' : 'Evidence request'} · ${i.engagementName} · ${i.status} · due ${_date(i.dueDate)}',
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  levelChip(i.level),
                  action(
                    'Open engagement',
                    () => c.open(i.engagementId),
                    enabled: c.verified,
                  ),
                  if (mine && c.canRespond && i.canRespond(c.scope.actorId))
                    action(
                      'Respond',
                      () => c.startResponse(i),
                      enabled: c.verified && !c.pending,
                    ),
                  if (mine &&
                      c.evidenceFiles != null &&
                      c.capabilities.contains(
                        AssuranceWorkspaceController.submitCapability,
                      ) &&
                      i.canSubmitEvidence(c.scope.actorId))
                    action(
                      'Upload evidence',
                      () => c.submitEvidence(i),
                      enabled: c.verified && c.online,
                    ),
                ],
              ),
            ],
          ),
        ),
      );
      final o = c.overview;
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Governance & Audit', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text(
            'Your audit requests and findings, overdue team work and the engagement register. Reminder levels come from due dates; engagement leads can send reminders to the people responsible.',
          ),
          if (c.busy) const LinearProgressIndicator(),
          if (!c.online)
            const Text(
              'Offline — a saved response draft and any sealed request are retained. Reconnect and refresh access to read audit work.',
            ),
          if (c.error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                c.error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (c.message != null)
            Semantics(liveRegion: true, child: Text(c.message!)),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              action('Refresh access', c.refresh),
              for (final (key, label) in const [
                ('work', 'My work'),
                ('engagements', 'Engagements'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: c.section == key,
                  onSelected: c.busy ? null : (_) => c.select(key),
                ),
            ],
          ),
          if (o != null) ...[
            const SizedBox(height: 16),
            _OverdueSummary(controller: c, overview: o),
          ],
          if (c.responding) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Management response',
                      style: theme.textTheme.titleLarge,
                    ),
                    Text(
                      '${c.form['finding_title']} · ${c.form['engagement_name']}',
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: ValueKey('response-${c.form['finding_id']}'),
                      initialValue: c.form['response'] as String?,
                      enabled: !c.pending && !c.busy,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Response and remediation plan',
                      ),
                      onChanged: (v) => c.field('response', v),
                    ),
                    TextFormField(
                      key: ValueKey('due-${c.form['finding_id']}'),
                      initialValue: c.form['due_date'] as String?,
                      enabled: !c.pending && !c.busy,
                      decoration: const InputDecoration(
                        labelText: 'Remediation due · YYYY-MM-DD',
                      ),
                      onChanged: (v) => c.field('due_date', v.trim()),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: c.form['accept_risk'] == true,
                      title: const Text(
                        'Request risk acceptance instead of remediation',
                      ),
                      subtitle: const Text(
                        'An independent approver decides; you cannot approve your own request.',
                      ),
                      onChanged: c.pending || c.busy
                          ? null
                          : (v) => c.field('accept_risk', v ?? false),
                    ),
                    if (c.pending)
                      const Text(
                        'The outcome is uncertain. Retry uses the same encrypted request.',
                      ),
                    if (c.conflicted)
                      const Text(
                        'The engagement changed. Refresh, then start the response again.',
                      ),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(
                          onPressed:
                              c.busy || !c.online || !c.verified || c.conflicted
                              ? null
                              : c.submitResponse,
                          child: Text(
                            c.pending
                                ? 'Retry saved response'
                                : 'Send response',
                          ),
                        ),
                        OutlinedButton(
                          onPressed: c.busy || c.pending
                              ? null
                              : c.saveResponse,
                          child: const Text('Save draft locally'),
                        ),
                        OutlinedButton(
                          onPressed: c.busy || c.pending
                              ? null
                              : c.discardResponse,
                          child: const Text('Discard draft'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (c.commanding) _CommandCard(controller: c),
          if (c.pack != null) _PackCard(controller: c),
          const SizedBox(height: 16),
          if (c.section == 'work') ...[
            if (o == null && !c.busy)
              const Text('Refresh access to load your audit work.')
            else if (o != null) ...[
              const SizedBox(height: 16),
              Text('Assigned to me', style: theme.textTheme.titleLarge),
              if (o.mine.isEmpty)
                const Text('Nothing is assigned to you in this branch.'),
              for (final i in o.mine) workItem(i, mine: true),
              const SizedBox(height: 16),
              Text('Overdue team work', style: theme.textTheme.titleLarge),
              if (o.team.isEmpty)
                const Text(
                  'No overdue or escalated items on engagements you lead or audit.',
                ),
              for (final i in o.team) workItem(i, mine: false),
            ],
          ] else if (c.section == 'engagements') ...[
            if (c.engagements.isEmpty && !c.busy)
              const Text('No engagements in this branch.'),
            for (final e in c.engagements)
              Card(
                child: ListTile(
                  title: Text('${e.name} · ${e.status.name}'),
                  subtitle: Text(
                    '${_date(e.periodStart)} → ${_date(e.periodEnd)} · ${e.openRequests} open requests (${e.overdueRequests} overdue) · ${e.openFindings} open findings (${e.overdueFindings} overdue) · ${e.candidateExceptions} candidate exceptions${e.evidenceFrozen ? ' · evidence frozen' : ''}',
                  ),
                  onTap: c.busy || !c.verified ? null : () => c.open(e.id),
                ),
              ),
            if (c.cursor != null)
              action(
                'More engagements',
                c.moreEngagements,
                enabled: c.verified,
              ),
          ] else if (c.detail != null)
            _EngagementDetailView(controller: c),
        ],
      );
    },
  );
}

const _snapshotLabels = {
  'it_control.access_review': 'Access review',
  'procurement.three_way_match': 'Three-way match overrides',
  'workforce.attendance_approvals': 'Attendance approvals',
};

class _EngagementDetailView extends StatelessWidget {
  const _EngagementDetailView({required this.controller});
  final AssuranceWorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller, theme = Theme.of(context), detail = c.detail!;
    final v = c.view, caps = c.capabilities, me = c.scope.actorId;
    final e = (detail['engagement'] as Map).cast<String, Object?>();
    List<Map<String, Object?>> rows(String k) => [
      for (final x in detail[k] as List) (x as Map).cast<String, Object?>(),
    ];
    final ready = !c.busy && c.online && c.verified && !c.commandPending;
    Widget act(String label, String action, Map<String, Object?> prefill) =>
        TextButton(
          onPressed: ready ? () => c.startCommand(action, prefill) : null,
          child: Text(label),
        );
    Widget heading(String t) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(t, style: theme.textTheme.titleMedium),
    );
    Widget row(String text, List<Widget> actions) => Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [Text(text), ...actions],
    );
    String code(String controlId) => v?.control(controlId)?.code ?? 'control';
    final report = v?.currentReport;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${e['name']} · ${e['status']}',
              style: theme.textTheme.titleLarge,
            ),
            TextButton(
              onPressed: c.closeDetail,
              child: const Text('Back to register'),
            ),
            TextButton(
              onPressed: ready ? () => c.open(e['id']! as String) : null,
              child: const Text('Refresh engagement'),
            ),
          ],
        ),
        Text(
          '${e['period_start']} → ${e['period_end']} · version ${e['version']}',
        ),
        Text('${e['scope_summary']}'),
        if (e['evidence_cutoff_digest'] != null)
          SelectableText('Evidence cutoff ${e['evidence_cutoff_digest']}'),
        if (v != null)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final to in v.transitionTargets(caps))
                act('Move to ${to.name}', 'transition', {
                  'to_status': to.name,
                  'reason': '',
                  'label': '${e['status']} → ${to.name}',
                }),
              if (v.canFreeze(caps, me))
                act('Freeze evidence', 'freeze_evidence', {
                  'reason': '',
                  'label':
                      'Lock accepted evidence and record its cutoff digest',
                }),
              if (v.canIssueReport(caps, me))
                act('Issue report', 'issue_report', {
                  'summary': '',
                  'label':
                      'Report version ${(v.currentReport?.version ?? 0) + 1}',
                }),
              if (v.canReopenReport(caps))
                act('Reopen report', 'reopen_report', {
                  'reason': '',
                  'label': 'Reissue as a new report version',
                }),
            ],
          ),
        heading('Controls'),
        if (v != null)
          for (final x in v.controls)
            row('${x.code} · ${x.title} · ${x.risk.name}', [
              if (v.canRequestEvidence(caps))
                act('Request evidence', 'request_evidence', {
                  'control_id': x.id,
                  'owner_id': x.ownerId,
                  'due_date': _plusDays(c.today, 14),
                  'description': '',
                  'label': '${x.code} · ${x.title}',
                }),
              if (v.canDesignTest(caps))
                act('Design test', 'design_test', {
                  'control_id': x.id,
                  'code': '',
                  'objective': '',
                  'population_size': '',
                  'sample_start': '1',
                  'label': '${x.code} · ${x.title} · ${x.risk.name} risk',
                }),
              if (v.canRecordException(caps))
                act('Record exception', 'record_exception', {
                  'control_id': x.id,
                  'description': '',
                  'severity': x.risk.name,
                  'label': '${x.code} · ${x.title}',
                }),
            ]),
        heading('Evidence requests'),
        if (v != null && v.requests.isEmpty)
          const Text('No evidence requested.'),
        if (v != null)
          for (final r in v.requests)
            row(
              '${code(r.controlId)} · ${r.status.name} · due ${r.dueDate}${r.evidenceSha256 == null ? '' : ' · ${r.evidenceSha256}'}',
              [
                if (v.canCollect(caps, r))
                  act('Collect system snapshot', 'collect_system_evidence', {
                    'request_id': r.id,
                    'source_kind': 'it_control.access_review',
                    'source_id': null,
                    'label': '${code(r.controlId)} · due ${r.dueDate}',
                  }),
                if (v.canReview(caps, r, me))
                  act('Review evidence', 'review_evidence', {
                    'request_id': r.id,
                    'decision': 'accept',
                    'reason': '',
                    'label': '${code(r.controlId)} · ${r.evidenceSha256}',
                  }),
              ],
            ),
        heading('Tests'),
        if (v != null && v.tests.isEmpty) const Text('No tests designed.'),
        if (v != null)
          for (final t in v.tests)
            row(
              '${t.code} · ${code(t.controlId)} · ${t.status.name} · sample ${t.sampleSize} of ${t.populationSize}',
              [
                if (v.canExecuteTest(caps, t))
                  act('Record test run', 'execute_test', {
                    'procedure_id': t.id,
                    'items_tested': '${t.sampleSize}',
                    'exceptions_found': '0',
                    'conclusion': 'effective',
                    'workpaper_sha256': '',
                    'label': '${t.code} · sample of ${t.sampleSize}',
                  }),
                if (v.canReviewTest(caps, t, me))
                  act('Review test', 'review_test', {
                    'procedure_id': t.id,
                    'decision': 'accept',
                    'reason': '',
                    'label': t.code,
                  }),
              ],
            ),
        heading('Exceptions'),
        if (v != null && v.exceptions.isEmpty)
          const Text('No exceptions recorded.'),
        if (v != null)
          for (final x in v.exceptions)
            row(
              '${code(x.controlId)} · ${x.severity.name} · ${x.status.name} · ${x.source.replaceAll('_', ' ')}',
              [
                if (v.canIssueFinding(caps, x))
                  act('Issue finding', 'issue_finding', {
                    'exception_id': x.id,
                    'owner_id': v.control(x.controlId)?.ownerId ?? '',
                    'title': '',
                    'severity': x.severity.name,
                    'label':
                        '${code(x.controlId)} · ${x.severity.name} exception',
                  }),
                if (v.canDismiss(caps, x))
                  act('Dismiss', 'dismiss_exception', {
                    'exception_id': x.id,
                    'reason': '',
                    'label':
                        '${code(x.controlId)} · ${x.severity.name} exception',
                  }),
              ],
            ),
        heading('Findings'),
        if (rows('findings').isEmpty) const Text('No findings issued.'),
        if (v == null)
          for (final x in rows('findings'))
            Text('${x['title']} · ${x['severity']} · ${x['status']}'),
        if (v != null)
          for (final f in v.findings)
            row(
              '${f.title} · ${f.severity.name} · ${f.status.wire.replaceAll('_', ' ')}',
              [
                if (v.canDecideRisk(caps, f, me))
                  act('Decide risk', 'decide_risk', {
                    'finding_id': f.id,
                    'decision': 'approve',
                    'reason': '',
                    'label': f.title,
                  }),
                if (v.canRetest(caps, f, me))
                  act('Retest', 'retest', {
                    'finding_id': f.id,
                    'result': 'pass',
                    'evidence_sha256': '',
                    'note': '',
                    'label': f.title,
                  }),
                if (v.canReopenFinding(caps, f, me))
                  act('Reopen', 'reopen_finding', {
                    'finding_id': f.id,
                    'reason': '',
                    'label': f.title,
                  }),
              ],
            ),
        heading('Reports'),
        if (rows('reports').isEmpty) const Text('No report issued.'),
        for (final x in rows('reports'))
          SelectableText('Version ${x['report_version']} · ${x['digest']}'),
        if (v != null && report != null && v.canExport(caps))
          act('Export audit pack', 'export_pack', {
            'report_id': report.id,
            'label': 'Report version ${report.version}',
          }),
        heading('History'),
        for (final x in rows('events'))
          Text(
            '${x['version']} · ${x['action']}${x['to_status'] == null ? '' : ' → ${x['to_status']}'} · ${x['occurred_at']}',
          ),
      ],
    );
  }
}

String _plusDays(String civil, int days) =>
    DateTime.parse('${civil}T00:00:00Z')
        .add(Duration(days: days))
        .toIso8601String()
        .substring(0, 10);

class _CommandCard extends StatelessWidget {
  const _CommandCard({required this.controller});
  final AssuranceWorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller, theme = Theme.of(context), a = c.commandAction!;
    final f = c.commandForm, locked = c.commandPending || c.busy;
    final id = f[a.aggregateKey];
    Widget text(String key, String label, {int lines = 1}) => TextFormField(
      key: ValueKey('$key-$id'),
      initialValue: f[key] as String?,
      enabled: !c.commandPending && !c.busy,
      maxLines: lines,
      decoration: InputDecoration(labelText: label),
      onChanged: (value) => c.commandField(key, value),
    );
    Widget choice(String key, Map<String, String> options) => Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final MapEntry(key: value, value: label) in options.entries)
          ChoiceChip(
            label: Text(label),
            selected: f[key] == value,
            onSelected: c.commandPending || c.busy
                ? null
                : (_) => c.commandField(key, value),
          ),
      ],
    );
    const severities = {
      'low': 'Low',
      'medium': 'Medium',
      'high': 'High',
      'critical': 'Critical',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.label, style: theme.textTheme.titleLarge),
              Text('${f['label'] ?? ''}'),
              const SizedBox(height: 8),
              ...switch (a.action) {
                'request_evidence' => [
                  text('due_date', 'Due · YYYY-MM-DD'),
                  text('description', 'What evidence is needed', lines: 3),
                  const Text('The request goes to the control owner.'),
                ],
                'collect_system_evidence' => [
                  choice('source_kind', _snapshotLabels),
                  const Text(
                    'The server builds an immutable snapshot over the audit period and records its digest; you cannot review evidence you collect.',
                  ),
                ],
                'review_evidence' => [
                  choice('decision', const {
                    'accept': 'Accept',
                    'reject': 'Return for rework',
                  }),
                  text('reason', 'Reason', lines: 2),
                ],
                'record_exception' => [
                  text('description', 'What was observed', lines: 3),
                  choice('severity', severities),
                  const Text(
                    'An exception is not a finding; another team member decides it.',
                  ),
                ],
                'dismiss_exception' => [
                  text('reason', 'Why it is not a finding', lines: 2),
                ],
                'issue_finding' => [
                  text('title', 'Finding title'),
                  choice('severity', severities),
                  const Text(
                    'The finding goes to the control owner for a management response.',
                  ),
                ],
                'transition' => [
                  text('reason', 'Reason for the stage change', lines: 2),
                ],
                'freeze_evidence' => [
                  text('reason', 'Reason', lines: 2),
                  const Text(
                    'After the freeze no evidence can be added or reviewed; tests then run against the frozen set.',
                  ),
                ],
                'issue_report' => [
                  text('summary', 'Report summary', lines: 4),
                  const Text(
                    'The report snapshots the current findings and cannot be changed; the lead auditor cannot issue it.',
                  ),
                ],
                'reopen_report' => [
                  text('reason', 'Reason', lines: 2),
                  const Text(
                    'The issued version is kept; reissuing creates a new version.',
                  ),
                ],
                'decide_risk' => [
                  choice('decision', const {
                    'approve': 'Accept the risk',
                    'reject': 'Require remediation',
                  }),
                  text('reason', 'Reason', lines: 2),
                ],
                'retest' => [
                  choice('result', const {
                    'pass': 'Pass — close the finding',
                    'fail': 'Fail — back to remediation',
                  }),
                  text('evidence_sha256', 'Retest evidence SHA-256'),
                  text('note', 'Note', lines: 2),
                ],
                'reopen_finding' => [text('reason', 'Reason', lines: 2)],
                'design_test' => [
                  text('code', 'Test code, e.g. TRS-SAMPLE'),
                  text('objective', 'Objective', lines: 2),
                  text('population_size', 'Population size'),
                  text('sample_start', 'Sample start position'),
                  const Text(
                    'The server sets the sample size from the control risk and records the sampled positions.',
                  ),
                ],
                'execute_test' => [
                  text('items_tested', 'Items tested'),
                  text('exceptions_found', 'Exceptions found'),
                  choice('conclusion', const {
                    'effective': 'Effective',
                    'ineffective': 'Ineffective',
                  }),
                  text('workpaper_sha256', 'Workpaper SHA-256'),
                  const Text(
                    'Every sampled item must be tested; exceptions require an ineffective conclusion.',
                  ),
                ],
                'review_test' => [
                  choice('decision', const {
                    'accept': 'Accept',
                    'return': 'Return for rework',
                  }),
                  text('reason', 'Reason', lines: 2),
                ],
                _ => [
                  const Text(
                    'The pack lists the issued report and evidence digests, not stored files. It is hashed again on this device before it can be saved.',
                  ),
                ],
              },
              if (a.requiresRecentMfa)
                const Text(
                  'Requires multi-factor authentication completed in the last 15 minutes.',
                ),
              if (c.commandPending)
                const Text(
                  'The outcome is uncertain or awaits MFA. Retry uses the same encrypted request.',
                ),
              if (c.commandConflicted)
                const Text(
                  'The engagement changed. Refresh it, then start again.',
                ),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed:
                        c.busy ||
                            !c.online ||
                            !c.verified ||
                            c.commandConflicted
                        ? null
                        : c.submitCommand,
                    child: Text(
                      c.commandPending ? 'Retry saved request' : 'Send',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: locked ? null : c.saveCommand,
                    child: const Text('Save draft locally'),
                  ),
                  OutlinedButton(
                    onPressed: c.busy || c.commandPending
                        ? null
                        : c.discardCommand,
                    child: const Text('Discard draft'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PackCard extends StatelessWidget {
  const _PackCard({required this.controller});
  final AssuranceWorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller, p = c.pack!, theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Audit pack', style: theme.textTheme.titleLarge),
              Text(
                p.verified
                    ? 'Verified: the downloaded text hashes to the recorded digest.'
                    : 'Not verified: the downloaded text does not match the recorded digest.',
                style: p.verified
                    ? null
                    : TextStyle(color: theme.colorScheme.error),
              ),
              SelectableText('Recorded ${p.pack.recordedSha256}'),
              SelectableText('Computed ${p.computedSha256}'),
              Text(
                'Report version ${p.pack.reportVersion} · ${p.pack.evidence.length} evidence items',
              ),
              FilledButton(
                onPressed: p.verified && c.files != null && !c.busy
                    ? c.savePack
                    : null,
                child: const Text('Save verified pack'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Counts by reminder level for the work in view, and the lead's reminder
/// action.
class _OverdueSummary extends StatelessWidget {
  const _OverdueSummary({required this.controller, required this.overview});
  final AssuranceWorkspaceController controller;
  final AssuranceOverview overview;

  @override
  Widget build(BuildContext context) {
    final c = controller, o = overview;
    Widget card(
      String label,
      ReminderLevel level,
      IconData icon,
      JentraStatusTone tone,
      String helper,
    ) => SizedBox(
      width: 220,
      child: JentraKpiCard(
        label: label,
        value: '${o.count(level)}',
        helper: o.count(level) == 0 ? 'None' : helper,
        icon: icon,
        tone: o.count(level) == 0 ? JentraStatusTone.success : tone,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            card(
              'Due soon',
              ReminderLevel.dueSoon,
              Icons.schedule,
              JentraStatusTone.info,
              '≤ ${o.dueSoonDays} days',
            ),
            card(
              'Overdue',
              ReminderLevel.overdue,
              Icons.timer_off_outlined,
              JentraStatusTone.warning,
              'Past due',
            ),
            card(
              'Escalated',
              ReminderLevel.escalated,
              Icons.priority_high,
              JentraStatusTone.danger,
              '> ${o.escalateAfterDays} days late',
            ),
          ],
        ),
        if (c.canSendReminders) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: c.sendingReminders || c.busy || !c.online
                    ? null
                    : c.sendReminders,
                icon: const Icon(Icons.notifications_active_outlined, size: 18),
                label: Text(
                  c.sendingReminders ? 'Sending reminders…' : 'Send reminders',
                ),
              ),
              Text(
                'Owners of due and late items get an in-app notice; escalations also go to the engagement lead.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
        if (c.reminderMessage != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: JentraStatusBadge(
                label: c.reminderMessage!,
                tone: JentraStatusTone.success,
              ),
            ),
          ),
        if (c.reminderError != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                c.reminderError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
      ],
    );
  }
}

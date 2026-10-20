import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_assurance.dart';

import '../../app_providers.dart';
import 'assurance_format.dart';
import 'assurance_widgets.dart';
import 'assurance_workspace_controller.dart';

class AssuranceWorkspaceScreen extends ConsumerWidget {
  const AssuranceWorkspaceScreen({super.key, this.engagementId});

  /// An engagement to open, from a reminder notice link.
  final String? engagementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(businessCapabilitiesProvider);
    if (caps.isLoading) return const Center(child: CircularProgressIndicator());
    if (caps.hasError) {
      return JentraEmptyState(
        title: 'Access could not be checked',
        description: 'Check your connection, then try again.',
        icon: Icons.cloud_off_outlined,
        action: OutlinedButton(
          onPressed: () => ref.invalidate(businessCapabilitiesProvider),
          child: const Text('Retry access check'),
        ),
      );
    }
    final c = ref.watch(assuranceWorkspaceControllerProvider);
    final link = engagementId;
    if (c != null && link != null) c.openWhenReady(link);
    return c == null
        ? const JentraEmptyState(
            title: 'No audit work here',
            description:
                'Choose an entity and branch where you can view audit '
                'evidence, or ask an organisation owner for an assurance role.',
            icon: Icons.fact_check_outlined,
          )
        : AssuranceWorkspace(key: ValueKey(c), controller: c);
  }
}

/// A status code from the server as a badge; an unknown code still reads in
/// words, in a neutral tone.
Widget _badge<T extends Enum>(List<T> values, Object? code) {
  for (final v in values) {
    if ((v is FindingStatus ? v.wire : v.name) == code) return auditBadge(v);
  }
  return auditBadge('$code');
}

String _levelLabel(ReminderLevel l) => switch (l) {
  ReminderLevel.onTrack => 'On track',
  ReminderLevel.dueSoon => 'Due soon',
  ReminderLevel.overdue => 'Overdue',
  ReminderLevel.escalated => 'Escalated',
};

String _date(DateTime? d) => d == null ? 'no due date' : auditDate(d);

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
        return JentraEmptyState(
          title: 'Access changed',
          description: 'Audit work has been cleared. ${c.error ?? ''}'.trim(),
          icon: Icons.lock_outline,
          action: OutlinedButton(
            onPressed: c.busy || !c.online ? null : c.refresh,
            child: const Text('Recheck access'),
          ),
        );
      }
      Widget heading(String t) => Padding(
        padding: const EdgeInsets.only(
          top: JentraSpacing.x5,
          bottom: JentraSpacing.x2,
        ),
        child: Semantics(
          header: true,
          child: Text(t, style: theme.textTheme.titleMedium),
        ),
      );
      // The same tones as the summary cards above the queue.
      Widget levelChip(ReminderLevel l) => JentraStatusBadge(
        label: _levelLabel(l),
        tone: switch (l) {
          ReminderLevel.onTrack => JentraStatusTone.success,
          ReminderLevel.dueSoon => JentraStatusTone.info,
          ReminderLevel.overdue => JentraStatusTone.warning,
          ReminderLevel.escalated => JentraStatusTone.danger,
        },
      );
      Widget workItem(AssuranceWorkItem i, {required bool mine}) =>
          AuditItemPanel(
            title: i.title,
            badges: [
              levelChip(i.level),
              if (i.kind == 'finding')
                _badge(FindingStatus.values, i.status)
              else
                _badge(EvidenceRequestStatus.values, i.status),
            ],
            details: [
              i.kind == 'finding' ? 'Finding' : 'Evidence request',
              i.engagementName,
              'due ${_date(i.dueDate)}',
            ],
            actions: [
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
          );
      final o = c.overview;
      return ListView(
        padding: const EdgeInsets.all(JentraSpacing.x6),
        children: [
          AuditScreenHeader(
            title: 'Governance & Audit',
            description:
                'Your audit requests and findings, overdue team work and the '
                'engagement register. Reminder levels come from due dates; '
                'engagement leads can send reminders to the people responsible.',
            onRefresh: c.busy || !c.online ? null : c.refresh,
            sections: const [
              ('work', 'My work'),
              ('engagements', 'Engagements'),
            ],
            selected: c.section,
            onSelect: c.busy ? null : c.select,
          ),
          const SizedBox(height: JentraSpacing.x3),
          if (c.busy) const LinearProgressIndicator(),
          if (!c.online)
            const AuditNotice(
              'Offline — a saved response draft and any sealed request are '
              'kept on this device. Reconnect, then refresh to read audit work.',
              tone: JentraStatusTone.warning,
            ),
          if (c.error != null)
            AuditNotice(c.error!, tone: JentraStatusTone.danger),
          if (c.message != null)
            AuditNotice(c.message!, tone: JentraStatusTone.success),
          if (o != null) ...[
            const SizedBox(height: JentraSpacing.x4),
            _OverdueSummary(controller: c, overview: o),
          ],
          if (c.responding) ...[
            const SizedBox(height: JentraSpacing.x4),
            JentraPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Management response',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    '${c.form['finding_title']} · ${c.form['engagement_name']}',
                  ),
                  const SizedBox(height: JentraSpacing.x3),
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
                  const SizedBox(height: JentraSpacing.x3),
                  AuditDateField(
                    key: ValueKey('due-${c.form['finding_id']}'),
                    label: 'Remediation due',
                    value: c.form['due_date'] as String?,
                    enabled: !c.pending && !c.busy,
                    onChanged: (v) => c.field('due_date', v),
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
                    const AuditNotice(
                      'The outcome is uncertain. Retry uses the same encrypted request.',
                      tone: JentraStatusTone.warning,
                    ),
                  if (c.conflicted)
                    const AuditNotice(
                      'The engagement changed. Refresh, then start the response again.',
                      tone: JentraStatusTone.warning,
                    ),
                  const SizedBox(height: JentraSpacing.x3),
                  Wrap(
                    spacing: JentraSpacing.x2,
                    runSpacing: JentraSpacing.x2,
                    children: [
                      FilledButton(
                        onPressed:
                            c.busy || !c.online || !c.verified || c.conflicted
                            ? null
                            : c.submitResponse,
                        child: Text(
                          c.pending ? 'Retry saved response' : 'Send response',
                        ),
                      ),
                      OutlinedButton(
                        onPressed: c.busy || c.pending ? null : c.saveResponse,
                        child: const Text('Save draft locally'),
                      ),
                      OutlinedButton(
                        onPressed: c.busy || c.pending
                            ? null
                            : () async {
                                if (await confirmDiscardDraft(context)) {
                                  await c.discardResponse();
                                }
                              },
                        child: const Text('Discard draft'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          if (c.commanding) _CommandCard(controller: c),
          if (c.pack != null) _PackCard(controller: c),
          if (c.section == 'work') ...[
            if (o == null && !c.busy)
              AuditNotLoaded(
                what: 'your audit work',
                online: c.online,
                failed: c.error != null,
                onRefresh: c.busy ? null : c.refresh,
              )
            else if (o != null) ...[
              heading('Assigned to me'),
              if (o.mine.isEmpty)
                const JentraEmptyState(
                  title: 'Nothing assigned to you',
                  description:
                      'Evidence requests and findings you own in this branch '
                      'appear here.',
                  icon: Icons.inbox_outlined,
                ),
              for (final i in o.mine) workItem(i, mine: true),
              heading('Overdue team work'),
              if (o.team.isEmpty)
                const JentraEmptyState(
                  title: 'No overdue team work',
                  description:
                      'Overdue and escalated items on engagements you lead or '
                      'audit appear here.',
                  icon: Icons.task_alt,
                ),
              for (final i in o.team) workItem(i, mine: false),
            ],
          ] else if (c.section == 'engagements') ...[
            heading('Engagement register'),
            if (c.engagements.isEmpty && !c.busy)
              c.online && c.error == null
                  ? const JentraEmptyState(
                      title: 'No engagements in this branch',
                      description:
                          'Engagements are created from approved plans in '
                          'Audit planning. Refresh after one is created.',
                      icon: Icons.event_note_outlined,
                    )
                  : AuditNotLoaded(
                      what: 'the engagement register',
                      online: c.online,
                      failed: c.error != null,
                      onRefresh: c.busy ? null : c.refresh,
                    ),
            for (final e in c.engagements)
              AuditItemPanel(
                title: e.name,
                badges: [
                  auditBadge(e.status),
                  if (e.evidenceFrozen)
                    const JentraStatusBadge(
                      label: 'Evidence frozen',
                      tone: JentraStatusTone.neutral,
                      icon: Icons.lock_outline,
                    ),
                ],
                details: [
                  '${_date(e.periodStart)} → ${_date(e.periodEnd)}',
                  '${e.openRequests} open requests (${e.overdueRequests} overdue)',
                  '${e.openFindings} open findings (${e.overdueFindings} overdue)',
                  '${e.candidateExceptions} candidate exceptions',
                ],
                openLabel: 'Open ${e.name}',
                onOpen: c.busy || !c.verified ? null : () => c.open(e.id),
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
      padding: const EdgeInsets.only(
        top: JentraSpacing.x5,
        bottom: JentraSpacing.x2,
      ),
      child: Semantics(
        header: true,
        child: Text(t, style: theme.textTheme.titleMedium),
      ),
    );
    // A section with nothing in it yet; the section heading says what.
    Widget none(String t) => Text(
      t,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: context.jentraColors.textSecondary,
      ),
    );
    String code(String controlId) => v?.control(controlId)?.code ?? 'control';
    final report = v?.currentReport;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: JentraSpacing.x4),
        Wrap(
          spacing: JentraSpacing.x2,
          children: [
            TextButton.icon(
              onPressed: c.closeDetail,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back to register'),
            ),
            TextButton.icon(
              onPressed: ready ? () => c.open(e['id']! as String) : null,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh engagement'),
            ),
          ],
        ),
        const SizedBox(height: JentraSpacing.x2),
        JentraPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: JentraSpacing.x2,
                runSpacing: JentraSpacing.x1,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      '${e['name']}',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  _badge(EngagementStatus.values, e['status']),
                  if (e['evidence_cutoff_digest'] != null)
                    const JentraStatusBadge(
                      label: 'Evidence frozen',
                      tone: JentraStatusTone.neutral,
                      icon: Icons.lock_outline,
                    ),
                ],
              ),
              const SizedBox(height: JentraSpacing.x1),
              Text(
                '${auditDate(e['period_start'])} → ${auditDate(e['period_end'])} · version ${e['version']}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: context.jentraColors.textSecondary,
                ),
              ),
              const SizedBox(height: JentraSpacing.x2),
              Text('${e['scope_summary']}'),
              if (e['evidence_cutoff_digest'] != null) ...[
                const SizedBox(height: JentraSpacing.x2),
                Wrap(
                  spacing: JentraSpacing.x2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('Evidence cutoff'),
                    DigestText('${e['evidence_cutoff_digest']}'),
                  ],
                ),
              ],
              if (v != null) ...[
                const SizedBox(height: JentraSpacing.x2),
                Wrap(
                  spacing: JentraSpacing.x2,
                  runSpacing: JentraSpacing.x1,
                  children: [
                    for (final to in v.transitionTargets(caps))
                      act('Move to ${auditLabel(to.name)}', 'transition', {
                        'to_status': to.name,
                        'reason': '',
                        'label':
                            '${auditLabel('${e['status']}')} → ${auditLabel(to.name)}',
                      }),
                    if (v.canFreeze(caps, me))
                      act('Freeze evidence', 'freeze_evidence', {
                        'reason': '',
                        'label': 'Lock accepted evidence and record its cutoff digest',
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
              ],
            ],
          ),
        ),
        heading('Controls'),
        if (v != null)
          for (final x in v.controls)
            AuditItemPanel(
              title: '${x.code} · ${x.title}',
              badges: [
                auditBadge(x.risk, label: '${auditLabel(x.risk.name)} risk'),
              ],
              actions: [
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
              ],
            ),
        heading('Evidence requests'),
        if (v != null && v.requests.isEmpty) none('No evidence requested.'),
        if (v != null)
          for (final r in v.requests)
            AuditItemPanel(
              title: code(r.controlId),
              badges: [auditBadge(r.status)],
              details: [
                'due ${auditDate(r.dueDate)}',
                if (r.uploaded && r.evidenceId != null)
                  assuranceEvidenceFileName(r.fileName ?? '', r.evidenceId!),
              ],
              digest: r.evidenceSha256,
              actions: [
                if (v.canVerifyStored(caps, r, me))
                  TextButton(
                    onPressed: ready ? () => c.verifyStoredEvidence(r) : null,
                    child: const Text('Verify file'),
                  ),
                if (v.canDownload(caps, r) && c.downloads != null)
                  TextButton.icon(
                    onPressed: ready && c.files != null
                        ? () => c.downloadEvidence(r)
                        : null,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Download'),
                  ),
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
                    'label':
                        '${code(r.controlId)} · SHA-256 ${shortDigest(r.evidenceSha256 ?? '')}',
                  }),
              ],
            ),
        heading('Tests'),
        if (v != null && v.tests.isEmpty) none('No tests designed.'),
        if (v != null)
          for (final t in v.tests)
            AuditItemPanel(
              title: t.code,
              badges: [auditBadge(t.status)],
              details: [
                code(t.controlId),
                'sample ${t.sampleSize} of ${t.populationSize}',
              ],
              actions: [
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
        if (v != null && v.exceptions.isEmpty) none('No exceptions recorded.'),
        if (v != null)
          for (final x in v.exceptions)
            AuditItemPanel(
              title: code(x.controlId),
              badges: [auditBadge(x.severity), auditBadge(x.status)],
              details: [x.source.replaceAll('_', ' ')],
              actions: [
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
        if (rows('findings').isEmpty) none('No findings issued.'),
        if (v == null)
          for (final x in rows('findings'))
            AuditItemPanel(
              title: '${x['title']}',
              badges: [
                _badge(AssuranceSeverity.values, x['severity']),
                _badge(FindingStatus.values, x['status']),
              ],
            ),
        if (v != null)
          for (final f in v.findings)
            AuditItemPanel(
              title: f.title,
              badges: [auditBadge(f.severity), auditBadge(f.status)],
              actions: [
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
        if (rows('reports').isEmpty) none('No report issued.'),
        for (final x in rows('reports'))
          AuditItemPanel(
            title: 'Version ${x['report_version']}',
            digest: '${x['digest']}',
          ),
        if (v != null && report != null && v.canExport(caps))
          Align(
            alignment: Alignment.centerLeft,
            child: act('Export audit pack', 'export_pack', {
              'report_id': report.id,
              'label': 'Report version ${report.version}',
            }),
          ),
        heading('History'),
        JentraPanel(
          padding: const EdgeInsets.all(JentraSpacing.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final x in rows('events'))
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: JentraSpacing.x1,
                  ),
                  child: Text(
                    '${x['version']} · ${auditLabel('${x['action']}')}${x['to_status'] == null ? '' : ' → ${auditLabel('${x['to_status']}')}'} · ${auditDateTime('${x['occurred_at']}')}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
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
      padding: const EdgeInsets.only(top: JentraSpacing.x4),
      child: JentraPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(a.label, style: theme.textTheme.titleLarge),
            ),
            Text('${f['label'] ?? ''}'),
            const SizedBox(height: 8),
            ...switch (a.action) {
              'request_evidence' => [
                AuditDateField(
                  key: ValueKey('due_date-$id'),
                  label: 'Due',
                  value: f['due_date'] as String?,
                  enabled: !locked,
                  onChanged: (v) => c.commandField('due_date', v),
                ),
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
              const AuditNotice(
                'The outcome is uncertain or awaits MFA. Retry uses the same encrypted request.',
                tone: JentraStatusTone.warning,
              ),
            if (c.commandConflicted)
              const AuditNotice(
                'The engagement changed. Refresh it, then start again.',
                tone: JentraStatusTone.warning,
              ),
            const SizedBox(height: JentraSpacing.x3),
            Wrap(
              spacing: JentraSpacing.x2,
              runSpacing: JentraSpacing.x2,
              children: [
                FilledButton(
                  onPressed:
                      c.busy || !c.online || !c.verified || c.commandConflicted
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
                      : () async {
                          if (await confirmDiscardDraft(context)) {
                            await c.discardCommand();
                          }
                        },
                  child: const Text('Discard draft'),
                ),
              ],
            ),
          ],
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
      padding: const EdgeInsets.only(top: JentraSpacing.x4),
      child: JentraPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text('Audit pack', style: theme.textTheme.titleLarge),
            ),
            AuditNotice(
              p.verified
                  ? 'Verified: the downloaded text hashes to the recorded digest.'
                  : 'Not verified: the downloaded text does not match the recorded digest.',
              tone: p.verified
                  ? JentraStatusTone.success
                  : JentraStatusTone.danger,
            ),
            const SizedBox(height: JentraSpacing.x2),
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

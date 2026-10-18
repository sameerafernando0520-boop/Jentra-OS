import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
            'Your audit requests and findings, overdue team work and the engagement register. Reminder levels are derived from due dates when the page loads; no notifications are sent.',
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
          const SizedBox(height: 16),
          if (c.section == 'work') ...[
            if (o == null && !c.busy)
              const Text('Refresh access to load your audit work.')
            else if (o != null) ...[
              Wrap(
                spacing: 8,
                children: [
                  for (final l in const [
                    ReminderLevel.dueSoon,
                    ReminderLevel.overdue,
                    ReminderLevel.escalated,
                  ])
                    Chip(label: Text('${_levelLabel(l)}: ${o.count(l)}')),
                ],
              ),
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
            _EngagementDetailView(detail: c.detail!, onClose: c.closeDetail),
        ],
      );
    },
  );
}

class _EngagementDetailView extends StatelessWidget {
  const _EngagementDetailView({required this.detail, required this.onClose});
  final Map<String, Object?> detail;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = (detail['engagement'] as Map).cast<String, Object?>();
    List<Map<String, Object?>> rows(String k) => [
      for (final x in detail[k] as List) (x as Map).cast<String, Object?>(),
    ];
    Widget heading(String t) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(t, style: theme.textTheme.titleMedium),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${e['name']} · ${e['status']}',
                style: theme.textTheme.titleLarge,
              ),
            ),
            TextButton(
              onPressed: onClose,
              child: const Text('Back to register'),
            ),
          ],
        ),
        Text(
          '${e['period_start']} → ${e['period_end']} · version ${e['version']}',
        ),
        Text('${e['scope_summary']}'),
        if (e['evidence_cutoff_digest'] != null)
          SelectableText('Evidence cutoff ${e['evidence_cutoff_digest']}'),
        heading('Controls'),
        for (final x in rows('controls'))
          Text('${x['control_code']} · ${x['title']} · ${x['risk']}'),
        heading('Evidence requests'),
        for (final x in rows('requests'))
          Text(
            '${x['status']} · due ${x['due_date']} · rework ${x['rework_count']}${x['evidence'] is Map ? ' · ${(x['evidence'] as Map)['sha256']}' : ''}',
          ),
        heading('Findings'),
        if (rows('findings').isEmpty) const Text('No findings issued.'),
        for (final x in rows('findings'))
          Text('${x['title']} · ${x['severity']} · ${x['status']}'),
        heading('Reports'),
        if (rows('reports').isEmpty) const Text('No report issued.'),
        for (final x in rows('reports'))
          SelectableText('Version ${x['report_version']} · ${x['digest']}'),
        heading('History'),
        for (final x in rows('events'))
          Text(
            '${x['version']} · ${x['action']}${x['to_status'] == null ? '' : ' → ${x['to_status']}'} · ${x['occurred_at']}',
          ),
      ],
    );
  }
}

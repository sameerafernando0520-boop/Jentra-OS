import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_assurance.dart';

import '../../app_providers.dart';
import 'assurance_format.dart';
import 'assurance_planning_controller.dart';
import 'assurance_settings_controller.dart';
import 'assurance_settings_panel.dart';
import 'assurance_widgets.dart';
import 'assurance_template_editor.dart';

class AssurancePlanningScreen extends ConsumerWidget {
  const AssurancePlanningScreen({super.key});
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
    final c = ref.watch(assurancePlanningControllerProvider);
    final settings = ref.watch(assuranceSettingsControllerProvider);
    return c == null
        ? const JentraEmptyState(
            title: 'No audit planning here',
            description:
                'Choose an entity and branch where you can plan audits or '
                'view audit evidence, or ask an organisation owner for an '
                'assurance role.',
            icon: Icons.account_tree_outlined,
          )
        : AssurancePlanning(
            key: ValueKey(c),
            controller: c,
            settings: settings,
          );
  }
}

const _categories = {
  'process': 'Process',
  'entity': 'Entity',
  'system': 'System',
  'compliance': 'Compliance',
  'project': 'Project',
};

class AssurancePlanning extends StatelessWidget {
  const AssurancePlanning({super.key, required this.controller, this.settings});
  final AssurancePlanningController controller;

  /// Tenant settings (A9); when present the page offers a Settings section and
  /// rates risk with the tenant's bands.
  final AssuranceSettingsController? settings;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller, theme = Theme.of(context), caps = c.capabilities;
      final ready = !c.busy && c.online && c.verified && !c.pending;
      Widget act(String label, String action, Map<String, Object?> prefill) =>
          TextButton(
            onPressed: ready ? () => c.startCommand(action, prefill) : null,
            child: Text(label),
          );
      // The main action of a section, e.g. "Create plan".
      Widget primary(
        String label,
        String action,
        Map<String, Object?> prefill,
      ) => JentraPrimaryButton(
        label: label,
        icon: Icons.add,
        onPressed: ready ? () => c.startCommand(action, prefill) : null,
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
      Widget none(String t) => Text(
        t,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: context.jentraColors.textSecondary,
        ),
      );
      if (c.accessDenied) {
        return JentraEmptyState(
          title: 'Access changed',
          description: 'Planning data has been cleared. ${c.error ?? ''}'
              .trim(),
          icon: Icons.lock_outline,
          action: OutlinedButton(
            onPressed: c.busy || !c.online ? null : c.refresh,
            child: const Text('Recheck access'),
          ),
        );
      }
      final u = c.universe, p = c.plan;
      final manage = caps.contains('assurance.plan.manage');
      final notLoaded = AuditNotLoaded(
        what: 'planning data',
        online: c.online,
        failed: c.error != null,
        onRefresh: c.busy ? null : c.refresh,
      );
      const register = {
        'code': '',
        'name': '',
        'category': 'process',
        'owner_id': '',
      };
      final create = {'name': '', 'period_start': c.today, 'period_end': ''};
      return ListView(
        padding: const EdgeInsets.all(JentraSpacing.x6),
        children: [
          AuditScreenHeader(
            title: 'Audit planning',
            description:
                'The audit universe with risk ratings, the plan register, '
                'maker-checker approval and engagements created from '
                'approved plans.',
            onRefresh: c.busy || !c.online ? null : c.refresh,
            sections: [
              ('universe', 'Audit universe'),
              ('plans', 'Plans'),
              if (settings != null) ('settings', 'Settings'),
            ],
            selected: c.section,
            onSelect: c.busy ? null : c.select,
          ),
          const SizedBox(height: JentraSpacing.x3),
          if (c.busy) const LinearProgressIndicator(),
          if (!c.online)
            const AuditNotice(
              'Offline — a saved draft and any sealed request are kept on '
              'this device. Reconnect, then refresh to read planning data.',
              tone: JentraStatusTone.warning,
            ),
          if (c.error != null)
            AuditNotice(c.error!, tone: JentraStatusTone.danger),
          if (c.message != null)
            AuditNotice(c.message!, tone: JentraStatusTone.success),
          if (c.commanding)
            _PlanCommandCard(
              controller: c,
              bands: settings?.page?.effective.bands ?? RatingBands.standard,
            ),
          const SizedBox(height: JentraSpacing.x4),
          if (c.section == 'universe' && u == null && !c.busy)
            notLoaded
          else if (c.section == 'universe' && u != null) ...[
            if (u.items.isEmpty)
              JentraEmptyState(
                title: 'No audit areas yet',
                description: u.canRegister(caps)
                    ? 'Register the processes, entities and systems you '
                          'audit, then assess their risk.'
                    : 'Audit planners register the areas to audit here.',
                icon: Icons.category_outlined,
                action: u.canRegister(caps)
                    ? primary('Register area', 'register_item', register)
                    : null,
              )
            else if (u.canRegister(caps))
              Align(
                alignment: Alignment.centerLeft,
                child: primary('Register area', 'register_item', register),
              ),
            if (u.items.isNotEmpty) heading('Audit areas'),
            for (final i in u.items)
              AuditItemPanel(
                title: '${i.code} · ${i.name}',
                badges: [
                  if (i.rating case final r?)
                    auditBadge(
                      r,
                      label: '${auditLabel(r.name)} risk (${i.score})',
                    )
                  else
                    const JentraStatusBadge(
                      label: 'Not assessed',
                      tone: JentraStatusTone.neutral,
                    ),
                  if (!i.active)
                    const JentraStatusBadge(
                      label: 'Retired',
                      tone: JentraStatusTone.neutral,
                    ),
                ],
                details: ['${_categories[i.category]}'],
                actions: [
                  if (u.canAssess(caps, i, c.actorId))
                    act('Assess risk', 'assess_risk', {
                      'item_id': i.id,
                      'likelihood': '3',
                      'impact': '3',
                      'rationale': '',
                      'label': '${i.code} · ${i.name}',
                    }),
                  if (u.canRetire(caps, i))
                    act('Retire', 'retire_item', {
                      'item_id': i.id,
                      'reason': '',
                      'label': '${i.code} · ${i.name}',
                    }),
                ],
              ),
            heading('Engagement templates'),
            if (manage)
              Align(
                alignment: Alignment.centerLeft,
                child: primary('Create template', 'create_template', {
                  'code': '',
                  'name': '',
                  'controls': [
                    {'control_code': '', 'title': '', 'risk': 'medium'},
                  ],
                  'requests': <Map<String, Object?>>[],
                }),
              ),
            if (u.currentTemplates.isEmpty)
              none('No templates. Plan items can be added without one.'),
            for (final t in u.currentTemplates)
              AuditItemPanel(
                title: '${t.code} · ${t.name}',
                badges: [
                  JentraStatusBadge(
                    label: 'Version ${t.version}',
                    tone: JentraStatusTone.neutral,
                  ),
                ],
                details: [
                  if (u.definitions[t.id] case final definition?)
                    '${definition.controls.length} controls · ${definition.requests.length} evidence requests',
                ],
                actions: [
                  if (manage && u.definitions[t.id] != null)
                    act('Create new version', 'create_template', {
                      'code': t.code,
                      'name': t.name,
                      'controls': [
                        for (final row in u.definitions[t.id]!.controls)
                          {...row},
                      ],
                      'requests': [
                        for (final row in u.definitions[t.id]!.requests)
                          {...row},
                      ],
                    }),
                ],
              ),
          ] else if (c.section == 'settings' && settings != null) ...[
            AssuranceSettingsPanel(controller: settings!),
          ] else if (c.section == 'plans') ...[
            if (c.plans.isEmpty && !c.busy)
              c.online && c.error == null
                  ? JentraEmptyState(
                      title: 'No plans in this branch',
                      description: manage
                          ? 'Create a plan for an audit period, add areas '
                                'from the universe and submit it for approval.'
                          : 'Audit planners create plans here.',
                      icon: Icons.event_note_outlined,
                      action: manage
                          ? primary('Create plan', 'create_plan', create)
                          : null,
                    )
                  : notLoaded
            else if (manage)
              Align(
                alignment: Alignment.centerLeft,
                child: primary('Create plan', 'create_plan', create),
              ),
            if (c.plans.isNotEmpty) heading('Plan register'),
            for (final s in c.plans)
              AuditItemPanel(
                title: s.name,
                badges: [auditBadge(s.status)],
                details: [
                  '${auditDate(s.periodStart)} → ${auditDate(s.periodEnd)}',
                  '${s.activeItems} areas',
                  'version ${s.version}',
                ],
                openLabel: 'Open ${s.name}',
                onOpen: c.busy || !c.verified ? null : () => c.openPlan(s.id),
              ),
            if (c.cursor != null)
              TextButton(
                onPressed: ready ? c.morePlans : null,
                child: const Text('More plans'),
              ),
          ] else if (c.section == 'plan' && p != null && u != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: c.closePlan,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back to plans'),
              ),
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
                        child: Text(p.name, style: theme.textTheme.titleLarge),
                      ),
                      auditBadge(p.status),
                    ],
                  ),
                  const SizedBox(height: JentraSpacing.x1),
                  Text(
                    '${auditDate(p.periodStart)} → ${auditDate(p.periodEnd)} · version ${p.version}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: context.jentraColors.textSecondary,
                    ),
                  ),
                  if (p.approvedDigest != null) ...[
                    const SizedBox(height: JentraSpacing.x2),
                    Wrap(
                      spacing: JentraSpacing.x2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('Approved'),
                        DigestText(p.approvedDigest!),
                      ],
                    ),
                  ],
                  const SizedBox(height: JentraSpacing.x2),
                  Wrap(
                    spacing: JentraSpacing.x2,
                    runSpacing: JentraSpacing.x1,
                    children: [
                      if (p.canEdit(caps) && p.plannable(u).isNotEmpty)
                        act('Add area', 'add_plan_item', {
                          'item_id': p.plannable(u).first.id,
                          'frequency': 'once',
                          'template_id': '',
                          'lead_auditor_id': c.actorId,
                          'scope_summary': '',
                        }),
                      if (p.canSubmit(caps))
                        act('Submit for approval', 'submit_plan', {}),
                      if (p.canDecide(caps, c.actorId))
                        act('Approve or return', 'decide_plan', {
                          'decision': 'approve',
                          'reason': '',
                        }),
                      if (p.canRevise(caps))
                        act('Revise plan', 'supersede_plan', {
                          'supersedes_plan_id': p.id,
                          'name':
                              '${p.name.length > 150 ? p.name.substring(0, 150) : p.name} (revised)',
                        }),
                      if (p.canCancel(caps))
                        act('Cancel plan', 'cancel_plan', {'reason': ''}),
                    ],
                  ),
                ],
              ),
            ),
            if (p.uncovered.isNotEmpty) ...[
              heading('High-risk areas not covered'),
              // Not signalled by colour alone (WCAG 1.4.1).
              for (final x in p.uncovered)
                AuditItemPanel(
                  title: x.code,
                  badges: [
                    const JentraStatusBadge(
                      label: 'Not covered',
                      tone: JentraStatusTone.warning,
                    ),
                    auditBadge(
                      x.rating,
                      label: '${auditLabel(x.rating.name)} risk',
                    ),
                  ],
                ),
            ],
            heading('Planned areas'),
            if (p.activeItems.isEmpty) none('No areas planned yet.'),
            for (final i in p.items)
              AuditItemPanel(
                title: '${i.code} · ${i.name}',
                badges: [
                  auditBadge(
                    i.rating,
                    label: '${auditLabel(i.rating.name)} risk',
                  ),
                  if (!i.active)
                    const JentraStatusBadge(
                      label: 'Removed',
                      tone: JentraStatusTone.neutral,
                    ),
                ],
                details: [
                  auditLabel(i.frequency.name),
                  '${i.occurrences.length} of ${i.frequency.occurrences} created',
                ],
                actions: [
                  if (p.canEdit(caps) && i.active)
                    act('Remove', 'remove_plan_item', {
                      'plan_item_id': i.id,
                      'reason': '',
                      'label': '${i.code} · ${i.name}',
                    }),
                  if (p.canInstantiate(caps, i))
                    act(
                      'Create engagement ${p.nextOccurrence(i)} of ${i.frequency.occurrences}',
                      'instantiate_engagement',
                      {
                        'plan_item_id': i.id,
                        'occurrence': '${p.nextOccurrence(i)}',
                        'label':
                            '${i.code} · occurrence ${p.nextOccurrence(i)}',
                      },
                    ),
                ],
              ),
          ],
        ],
      );
    },
  );
}

class _PlanCommandCard extends StatelessWidget {
  const _PlanCommandCard({required this.controller, required this.bands});
  final AssurancePlanningController controller;
  final RatingBands bands;

  static const _labels = {
    'register_item': 'Register audit area',
    'assess_risk': 'Assess risk',
    'retire_item': 'Retire area',
    'create_plan': 'Create plan',
    'create_template': 'Create engagement template',
    'add_plan_item': 'Add area to plan',
    'remove_plan_item': 'Remove area from plan',
    'submit_plan': 'Submit plan for approval',
    'decide_plan': 'Approve or return plan',
    'cancel_plan': 'Cancel plan',
    'instantiate_engagement': 'Create engagement',
    'supersede_plan': 'Revise approved plan',
  };

  @override
  Widget build(BuildContext context) {
    final c = controller, theme = Theme.of(context), f = c.form;
    final action = f['action']! as String;
    final key =
        '${f['item_id'] ?? f['plan_id'] ?? ''}-${f['plan_item_id'] ?? ''}';
    Widget text(String k, String label, {int lines = 1}) => TextFormField(
      key: ValueKey('$k-$key'),
      initialValue: f[k] as String?,
      enabled: !c.pending && !c.busy,
      maxLines: lines,
      decoration: InputDecoration(labelText: label),
      onChanged: (v) => c.field(k, v),
    );
    Widget date(String k, String label, {String? firstDate}) => AuditDateField(
      key: ValueKey('$k-$key'),
      label: label,
      value: f[k] as String?,
      firstDate: firstDate,
      enabled: !c.pending && !c.busy,
      onChanged: (v) => c.field(k, v),
    );
    Widget choice(String k, Map<String, String> options) => Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final MapEntry(key: value, value: label) in options.entries)
          ChoiceChip(
            label: Text(label),
            selected: f[k] == value,
            onSelected: c.pending || c.busy ? null : (_) => c.field(k, value),
          ),
      ],
    );
    // People are chosen by name; a typed id is the fallback when the list
    // cannot be read.
    Widget person(String k, String label) {
      final known = c.people?.members ?? const <AssurancePerson>[];
      if (known.isEmpty) return text(k, '$label user ID');
      final current = f[k] as String?;
      return DropdownButtonFormField<String>(
        key: ValueKey('person-$k'),
        initialValue: known.any((m) => m.userId == current) ? current : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final m in known)
            DropdownMenuItem(
              value: m.userId,
              child: Text(m.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: c.pending || c.busy
            ? null
            : (v) {
                if (v != null) c.field(k, v);
              },
      );
    }

    final scale = {for (var n = 1; n <= 5; n++) '$n': '$n'};
    final u = c.universe, p = c.plan;
    String? rating() {
      final l = int.tryParse('${f['likelihood']}'),
          i = int.tryParse('${f['impact']}');
      if (l == null || i == null) return null;
      return '${assuranceRiskRating(l, i, bands: bands).name} (score ${l * i})';
    }

    return Padding(
      padding: const EdgeInsets.only(top: JentraSpacing.x4),
      child: JentraPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                _labels[action] ?? action,
                style: theme.textTheme.titleLarge,
              ),
            ),
            if (f['label'] != null) Text('${f['label']}'),
            const SizedBox(height: 8),
            ...switch (action) {
              'create_template' => [
                text('code', 'Template code, e.g. TREASURY'),
                text('name', 'Template name'),
                AssuranceTemplateEditor(controller: c),
              ],
              'register_item' => [
                text('code', 'Code, e.g. P2P'),
                text('name', 'Name'),
                choice('category', _categories),
                person('owner_id', 'Area owner'),
              ],
              'assess_risk' => [
                const Text('Likelihood'),
                choice('likelihood', scale),
                const Text('Impact'),
                choice('impact', scale),
                if (rating() != null) Text('Rating: ${rating()}'),
                text('rationale', 'Rationale', lines: 2),
              ],
              'retire_item' ||
              'remove_plan_item' ||
              'cancel_plan' => [text('reason', 'Reason', lines: 2)],
              'create_plan' => [
                text('name', 'Plan name'),
                const SizedBox(height: JentraSpacing.x3),
                date('period_start', 'Period start'),
                const SizedBox(height: JentraSpacing.x3),
                date(
                  'period_end',
                  'Period end',
                  firstDate: f['period_start'] as String?,
                ),
              ],
              'add_plan_item' => [
                if (u != null && p != null)
                  choice('item_id', {
                    for (final i in p.plannable(u))
                      i.id: '${i.code} · ${i.rating!.name}',
                  }),
                choice('frequency', {
                  for (final q in AuditFrequency.values)
                    q.name: '${q.name} (${q.occurrences})',
                }),
                if (u != null)
                  choice('template_id', {
                    '': 'No template',
                    for (final t in u.currentTemplates)
                      t.id: '${t.code} v${t.version}',
                  }),
                person('lead_auditor_id', 'Lead auditor'),
                text('scope_summary', 'Scope summary', lines: 2),
                const Text('The lead auditor must not own the area.'),
              ],
              'supersede_plan' => [
                text('name', 'Name of the revision'),
                const Text(
                  "Copies this plan's period and areas into a new draft. The approved plan stays in force until the revision is approved, then it is marked superseded.",
                ),
              ],
              'submit_plan' => [
                const Text(
                  'After submission the plan is locked until it is approved or returned.',
                ),
              ],
              'decide_plan' => [
                choice('decision', const {
                  'approve': 'Approve',
                  'return': 'Return to draft',
                }),
                text('reason', 'Reason', lines: 2),
                const Text(
                  'Requires multi-factor authentication completed in the last 15 minutes. The maker and submitter cannot decide.',
                ),
              ],
              _ => [
                const Text(
                  'Creates the engagement for this occurrence with the planned lead, period and template controls and requests.',
                ),
              ],
            },
            if (c.pending)
              const AuditNotice(
                'The outcome is uncertain or awaits MFA. Retry uses the same encrypted request.',
                tone: JentraStatusTone.warning,
              ),
            if (c.conflicted)
              const AuditNotice(
                'This changed. Refresh, then start again.',
                tone: JentraStatusTone.warning,
              ),
            const SizedBox(height: JentraSpacing.x3),
            Wrap(
              spacing: JentraSpacing.x2,
              runSpacing: JentraSpacing.x2,
              children: [
                FilledButton(
                  onPressed: c.busy || !c.online || !c.verified || c.conflicted
                      ? null
                      : c.submit,
                  child: Text(c.pending ? 'Retry saved request' : 'Send'),
                ),
                OutlinedButton(
                  onPressed: c.busy || c.pending ? null : c.saveDraft,
                  child: const Text('Save draft locally'),
                ),
                OutlinedButton(
                  onPressed: c.busy || c.pending
                      ? null
                      : () async {
                          if (await confirmDiscardDraft(context)) {
                            await c.discardDraft();
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_assurance.dart';

import '../../app_providers.dart';
import 'assurance_format.dart';
import 'assurance_planning_controller.dart';
import 'assurance_settings_controller.dart';
import 'assurance_settings_panel.dart';

class AssurancePlanningScreen extends ConsumerWidget {
  const AssurancePlanningScreen({super.key});
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
    final c = ref.watch(assurancePlanningControllerProvider);
    final settings = ref.watch(assuranceSettingsControllerProvider);
    return c == null
        ? const Center(
            child: Text(
              'Choose an entity and branch where you can plan audits or view audit evidence.',
            ),
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
      Widget row(String text, List<Widget> actions) => Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [Text(text), ...actions],
      );
      Widget heading(String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Semantics(
          header: true,
          child: Text(t, style: theme.textTheme.titleMedium),
        ),
      );
      if (c.accessDenied) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Access changed. Planning data has been cleared.'),
              if (c.error != null) Text(c.error!),
              TextButton(
                onPressed: c.busy || !c.online ? null : c.refresh,
                child: const Text('Recheck access'),
              ),
            ],
          ),
        );
      }
      final u = c.universe, p = c.plan;
      final manage = caps.contains('assurance.plan.manage');
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Audit planning', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text(
            'The audit universe with risk ratings, the plan register, maker-checker approval and engagements created from approved plans.',
          ),
          if (c.busy) const LinearProgressIndicator(),
          if (!c.online)
            const Text(
              'Offline — a saved draft and any sealed request are retained. Reconnect and refresh to read planning data.',
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
              TextButton(
                onPressed: c.busy || !c.online ? null : c.refresh,
                child: const Text('Refresh'),
              ),
              for (final (key, label) in [
                ('universe', 'Audit universe'),
                ('plans', 'Plans'),
                if (settings != null) ('settings', 'Settings'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: c.section == key,
                  onSelected: c.busy ? null : (_) => c.select(key),
                ),
            ],
          ),
          if (c.commanding)
            _PlanCommandCard(
              controller: c,
              bands: settings?.page?.effective.bands ?? RatingBands.standard,
            ),
          const SizedBox(height: 16),
          if (c.section == 'universe' && u != null) ...[
            if (u.canRegister(caps))
              act('Register area', 'register_item', {
                'code': '',
                'name': '',
                'category': 'process',
                'owner_id': '',
              }),
            if (u.items.isEmpty) const Text('No audit areas registered.'),
            for (final i in u.items)
              row(
                '${i.code} · ${i.name} · ${_categories[i.category]} · ${i.rating == null ? 'Not assessed' : '${auditLabel(i.rating!.name)} risk (${i.score})'}${i.active ? '' : ' · retired'}',
                [
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
            if (u.currentTemplates.isEmpty)
              const Text('No templates. Plan items can be added without one.'),
            for (final t in u.currentTemplates)
              Text('${t.code} v${t.version} · ${t.name}'),
          ] else if (c.section == 'settings' && settings != null) ...[
            AssuranceSettingsPanel(controller: settings!),
          ] else if (c.section == 'plans') ...[
            if (manage)
              act('Create plan', 'create_plan', {
                'name': '',
                'period_start': c.today,
                'period_end': '',
              }),
            if (c.plans.isEmpty && !c.busy)
              const Text('No plans in this branch.'),
            for (final s in c.plans)
              Card(
                child: ListTile(
                  title: Text('${s.name} · ${auditLabel(s.status.name)}'),
                  subtitle: Text(
                    '${auditDate(s.periodStart)} → ${auditDate(s.periodEnd)} · ${s.activeItems} areas · version ${s.version}',
                  ),
                  onTap: c.busy || !c.verified ? null : () => c.openPlan(s.id),
                ),
              ),
            if (c.cursor != null)
              TextButton(
                onPressed: ready ? c.morePlans : null,
                child: const Text('More plans'),
              ),
          ] else if (c.section == 'plan' && p != null && u != null) ...[
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${p.name} · ${auditLabel(p.status.name)}',
                  style: theme.textTheme.titleLarge,
                ),
                TextButton(
                  onPressed: c.closePlan,
                  child: const Text('Back to plans'),
                ),
              ],
            ),
            Text(
              '${auditDate(p.periodStart)} → ${auditDate(p.periodEnd)} · version ${p.version}',
            ),
            if (p.approvedDigest != null)
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Approved'),
                  DigestText(p.approvedDigest!),
                ],
              ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
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
            if (p.uncovered.isNotEmpty) ...[
              heading('High-risk areas not covered'),
              // Not signalled by colour alone (WCAG 1.4.1).
              for (final x in p.uncovered)
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const JentraStatusBadge(
                      label: 'Not covered',
                      tone: JentraStatusTone.warning,
                    ),
                    Text('${x.code} · ${auditLabel(x.rating.name)} risk'),
                  ],
                ),
            ],
            heading('Planned areas'),
            if (p.activeItems.isEmpty) const Text('No areas planned yet.'),
            for (final i in p.items)
              row(
                '${i.code} · ${i.name} · ${auditLabel(i.rating.name)} risk · ${i.frequency.name} · ${i.occurrences.length} of ${i.frequency.occurrences} created${i.active ? '' : ' · removed'}',
                [
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
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _labels[action] ?? action,
                style: theme.textTheme.titleLarge,
              ),
              if (f['label'] != null) Text('${f['label']}'),
              const SizedBox(height: 8),
              ...switch (action) {
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
                  text('period_start', 'Period start · YYYY-MM-DD'),
                  text('period_end', 'Period end · YYYY-MM-DD'),
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
                const Text(
                  'The outcome is uncertain or awaits MFA. Retry uses the same encrypted request.',
                ),
              if (c.conflicted)
                const Text('This changed. Refresh, then start again.'),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed:
                        c.busy || !c.online || !c.verified || c.conflicted
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
      ),
    );
  }
}

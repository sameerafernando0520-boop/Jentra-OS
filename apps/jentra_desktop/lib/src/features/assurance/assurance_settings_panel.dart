import 'package:flutter/material.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_assurance.dart';

import 'assurance_settings_controller.dart';

String _source(String s) => switch (s) {
  'tenant' => 'Organisation settings',
  'entity' => 'Settings for this entity',
  _ => 'Using defaults',
};

String _ruleName(String code) => switch (code) {
  'ACCESS_PRIVILEGED_NO_MFA' => 'Privileged roles without MFA',
  'P2P_MATCH_OVERRIDE' => 'Three-way-match overrides',
  'P2P_OVERRIDE_BY_CREATOR' => 'Overrides approved by the bill creator',
  'HR_ATTENDANCE_SELF_APPROVAL' => 'Self-approved attendance',
  _ => code,
};

/// Audit settings for the organisation or this entity, with a live preview of
/// the reminder timeline and rating bands while editing.
class AssuranceSettingsPanel extends StatelessWidget {
  const AssuranceSettingsPanel({super.key, required this.controller});
  final AssuranceSettingsController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller, theme = Theme.of(context);
      final colors = context.jentraColors;
      final p = c.page;
      if (c.accessDenied) {
        return JentraEmptyState(
          title: 'Access changed',
          description: 'Settings have been cleared. ${c.error ?? ''}',
          icon: Icons.lock_outline,
          action: OutlinedButton(
            onPressed: c.busy || !c.online ? null : c.refresh,
            child: const Text('Recheck access'),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JentraSectionHeader(
            title: 'Audit settings',
            description:
                'When reminders fall due, how long finding owners have to '
                'respond, how risk scores become ratings, and which '
                'monitoring rules raise candidate exceptions.',
            trailing: p == null
                ? null
                : JentraStatusBadge(
                    label: _source(p.effective.source),
                    tone: p.effective.source == 'default'
                        ? JentraStatusTone.neutral
                        : JentraStatusTone.info,
                  ),
          ),
          const SizedBox(height: JentraSpacing.x3),
          if (c.busy) const LinearProgressIndicator(),
          if (c.error != null)
            Semantics(
              liveRegion: true,
              child: Text(c.error!, style: TextStyle(color: colors.danger)),
            ),
          if (c.message != null)
            Semantics(
              liveRegion: true,
              child: JentraStatusBadge(
                label: c.message!,
                tone: JentraStatusTone.success,
              ),
            ),
          if (p != null && !c.editing) ...[
            _Summary(settings: p.effective, rules: p.rules),
            if (c.canEdit) ...[
              const SizedBox(height: JentraSpacing.x4),
              Wrap(
                spacing: JentraSpacing.x2,
                runSpacing: JentraSpacing.x2,
                children: [
                  OutlinedButton.icon(
                    onPressed: c.ready ? () => c.edit('tenant') : null,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit for the organisation'),
                  ),
                  OutlinedButton.icon(
                    onPressed: c.ready ? () => c.edit('entity') : null,
                    icon: const Icon(Icons.apartment_outlined, size: 18),
                    label: const Text('Override for this entity'),
                  ),
                ],
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: JentraSpacing.x3),
                child: Text(
                  'Only audit planners can change these settings.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
          if (p != null && c.editing) _Editor(controller: c),
        ],
      );
    },
  );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.settings, required this.rules});
  final AssuranceSettings settings;
  final List<({String code, String description})> rules;

  @override
  Widget build(BuildContext context) {
    final s = settings, b = s.bands;
    Widget fact(String label, String value, IconData icon) => SizedBox(
      width: 300,
      child: JentraKpiCard(
        label: label,
        value: value,
        helper: s.source == 'default' ? 'Default' : 'Configured',
        icon: icon,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: JentraSpacing.x3,
          runSpacing: JentraSpacing.x3,
          children: [
            fact('Due soon', '${s.dueSoonDays} days before', Icons.schedule),
            fact(
              'Escalated',
              '${s.escalateAfterDays} days late',
              Icons.priority_high,
            ),
            fact(
              'Finding response',
              '${s.findingResponseDays} days',
              Icons.reply_outlined,
            ),
            fact(
              'Rating bands',
              '${b.critical} / ${b.high} / ${b.medium}',
              Icons.stacked_bar_chart,
            ),
          ],
        ),
        const SizedBox(height: JentraSpacing.x4),
        Text('Monitoring rules', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: JentraSpacing.x2),
        for (final r in rules)
          Padding(
            padding: const EdgeInsets.only(bottom: JentraSpacing.x1),
            child: Wrap(
              spacing: JentraSpacing.x2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                JentraStatusBadge(
                  label: s.monitoring[r.code]!.enabled ? 'On' : 'Off',
                  tone: s.monitoring[r.code]!.enabled
                      ? JentraStatusTone.success
                      : JentraStatusTone.neutral,
                ),
                Text(_ruleName(r.code)),
                Text(
                  'raises from ${s.monitoring[r.code]!.minCount} occurrence(s)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Editor extends StatelessWidget {
  const _Editor({required this.controller});
  final AssuranceSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller, theme = Theme.of(context), f = c.form;
    final errors = c.errors, locked = c.pending || c.busy;
    final level = f['level'];
    Widget number(String key, String label, {String? helper}) => SizedBox(
      width: 300,
      child: TextFormField(
        key: ValueKey('settings-$key'),
        initialValue: '${f[key] ?? ''}',
        enabled: !locked,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          errorText: errors[key],
          errorMaxLines: 2,
          helperMaxLines: 2,
        ),
        onChanged: (v) => c.field(key, v),
      ),
    );
    final preview = c.preview;
    final today = DateTime.now().toUtc();
    String levelAt(int days) {
      final l = preview!.level(today.add(Duration(days: days)), today);
      return switch (l) {
        ReminderLevel.onTrack => 'On track',
        ReminderLevel.dueSoon => 'Due soon',
        ReminderLevel.overdue => 'Overdue',
        ReminderLevel.escalated => 'Escalated',
      };
    }

    return JentraPanel(
      semanticsLabel: 'Edit audit settings',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            level == 'entity'
                ? 'Edit settings for this entity'
                : 'Edit settings for the organisation',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: JentraSpacing.x1),
          Text(
            level == 'entity'
                ? 'These replace the organisation settings for this legal entity only.'
                : 'These apply to every legal entity without its own settings.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: JentraSpacing.x4),
          Text('Reminders', style: theme.textTheme.titleSmall),
          const SizedBox(height: JentraSpacing.x3),
          Wrap(
            spacing: JentraSpacing.x4,
            runSpacing: JentraSpacing.x2,
            children: [
              number(
                'due_soon_days',
                'Due soon',
                helper: 'Days before the due date, 1–30',
              ),
              number(
                'escalate_after_days',
                'Escalate after',
                helper: 'Days late, 1–90',
              ),
              number(
                'finding_response_days',
                'Finding response',
                helper: 'Days after a finding is issued, 1–90',
              ),
            ],
          ),
          const SizedBox(height: JentraSpacing.x4),
          Text(
            'Rating bands (minimum score)',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: JentraSpacing.x3),
          Wrap(
            spacing: JentraSpacing.x4,
            runSpacing: JentraSpacing.x2,
            children: [
              number('band_critical', 'Critical from'),
              number('band_high', 'High from'),
              number('band_medium', 'Medium from'),
            ],
          ),
          const SizedBox(height: JentraSpacing.x4),
          Text('Monitoring rules', style: theme.textTheme.titleSmall),
          for (final code in assuranceMonitoringRuleCodes)
            Wrap(
              spacing: JentraSpacing.x3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 360,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_ruleName(code)),
                    value: f['enabled.$code'] != false,
                    onChanged: locked
                        ? null
                        : (v) => c.field('enabled.$code', v),
                  ),
                ),
                number(
                  'min.$code',
                  'Raise from',
                  helper: 'Occurrences, 1–10000',
                ),
              ],
            ),
          const SizedBox(height: JentraSpacing.x4),
          Semantics(
            liveRegion: true,
            child: preview == null
                ? Text(
                    'Fix the highlighted values to see the preview.',
                    style: TextStyle(color: context.jentraColors.danger),
                  )
                : Text(
                    'Preview — due in ${preview.dueSoonDays + 1} days: ${levelAt(preview.dueSoonDays + 1)}; '
                    'due today: ${levelAt(0)}; 1 day late: ${levelAt(-1)}; '
                    '${preview.escalateAfterDays + 1} days late: ${levelAt(-preview.escalateAfterDays - 1)}. '
                    'A score of ${preview.bands.high} is rated ${preview.bands.rate(preview.bands.high).name}.',
                  ),
          ),
          if (c.pending)
            const Padding(
              padding: EdgeInsets.only(top: JentraSpacing.x2),
              child: JentraStatusBadge(
                label: 'Saved — complete MFA if asked, then retry',
                tone: JentraStatusTone.warning,
              ),
            ),
          const SizedBox(height: JentraSpacing.x2),
          Text(
            'Saving needs multi-factor authentication from the last 15 minutes. '
            'Existing risk assessments keep the rating they were given.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: JentraSpacing.x4),
          Wrap(
            spacing: JentraSpacing.x2,
            runSpacing: JentraSpacing.x2,
            children: [
              JentraPrimaryButton(
                label: c.pending ? 'Retry saved request' : 'Save settings',
                loading: c.busy,
                onPressed: !c.online || !c.verified || c.conflicted
                    ? null
                    : c.submit,
              ),
              OutlinedButton(
                onPressed: locked ? null : c.discardDraft,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

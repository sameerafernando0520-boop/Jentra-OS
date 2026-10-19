import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_assurance.dart';

import '../../app_providers.dart';
import 'assurance_access_controller.dart';

class AssuranceAccessScreen extends ConsumerWidget {
  const AssuranceAccessScreen({super.key});
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
    final c = ref.watch(assuranceAccessControllerProvider);
    return c == null
        ? const JentraEmptyState(
            title: 'Audit access is for role managers',
            description:
                'Ask an organisation owner to give people assurance roles.',
            icon: Icons.admin_panel_settings_outlined,
          )
        : AssuranceAccessView(key: ValueKey(c), controller: c);
  }
}

String scopeLabel(AccessScope s) => switch (s) {
  AccessScope.tenant => 'Organisation-wide',
  AccessScope.entity => 'This entity',
  AccessScope.branch => 'This branch',
};

class AssuranceAccessView extends StatelessWidget {
  const AssuranceAccessView({super.key, required this.controller});
  final AssuranceAccessController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller, theme = Theme.of(context);
      final colors = context.jentraColors;
      if (c.accessDenied) {
        return JentraEmptyState(
          title: 'Access changed',
          description:
              'Member and role details have been cleared. ${c.error ?? ''}',
          icon: Icons.lock_outline,
          action: OutlinedButton(
            onPressed: c.busy || !c.online ? null : c.refresh,
            child: const Text('Recheck access'),
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(JentraSpacing.x6),
        children: [
          JentraSectionHeader(
            title: 'Audit access',
            description:
                'Choose who can plan, run, review and respond to audits. '
                'Each change needs multi-factor authentication from the last '
                '15 minutes and is recorded with who made it.',
            trailing: IconButton(
              tooltip: 'Refresh',
              onPressed: c.busy || !c.online ? null : c.refresh,
              icon: const Icon(Icons.refresh),
            ),
          ),
          const SizedBox(height: JentraSpacing.x3),
          if (c.busy) const LinearProgressIndicator(),
          if (!c.online)
            const JentraStatusBadge(
              label: 'Offline — saved changes are kept until you reconnect',
              tone: JentraStatusTone.warning,
            ),
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
          if (c.commanding) ...[
            const SizedBox(height: JentraSpacing.x4),
            _ChangeCard(controller: c),
          ],
          const SizedBox(height: JentraSpacing.x6),
          Text('Roles', style: theme.textTheme.titleMedium),
          const SizedBox(height: JentraSpacing.x3),
          Wrap(
            spacing: JentraSpacing.x3,
            runSpacing: JentraSpacing.x3,
            children: [
              for (final r in AssuranceRole.values)
                SizedBox(
                  width: 300,
                  child: JentraPanel(
                    semanticsLabel: r.label,
                    padding: const EdgeInsets.all(JentraSpacing.x4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.label, style: theme.textTheme.titleSmall),
                        const SizedBox(height: JentraSpacing.x1),
                        Text(
                          r.summary,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        if (r.requiresMfa) ...[
                          const SizedBox(height: JentraSpacing.x2),
                          const JentraStatusBadge(
                            label: 'Requires MFA',
                            tone: JentraStatusTone.info,
                            icon: Icons.verified_user_outlined,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: JentraSpacing.x6),
          Text(
            c.verified ? 'Members (${c.members.length})' : 'Members',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: JentraSpacing.x3),
          if (c.verified && c.members.isEmpty)
            const JentraEmptyState(
              title: 'No members yet',
              description: 'Invite people to this organisation first, then give them assurance roles here.',
              icon: Icons.group_add_outlined,
            ),
          for (final m in c.members)
            Padding(
              padding: const EdgeInsets.only(bottom: JentraSpacing.x2),
              child: JentraPanel(
                semanticsLabel: m.label,
                padding: const EdgeInsets.all(JentraSpacing.x4),
                child: Wrap(
                  spacing: JentraSpacing.x3,
                  runSpacing: JentraSpacing.x2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Wrap(
                      spacing: JentraSpacing.x2,
                      runSpacing: JentraSpacing.x2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(m.label, style: theme.textTheme.titleSmall),
                        JentraStatusBadge(
                          label: m.linked ? 'Employee record' : 'Not linked',
                          tone: m.linked
                              ? JentraStatusTone.success
                              : JentraStatusTone.neutral,
                        ),
                        if (m.assignments.isEmpty)
                          Text(
                            'No assurance role',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        for (final a in m.assignments)
                          Chip(
                            label: Text(
                              '${a.role.label} · ${scopeLabel(a.scope)}',
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                    OutlinedButton(
                      onPressed: c.ready && c.canManage && !c.commanding
                          ? () => c.startChange(
                              m,
                              AssuranceRole.values.firstWhere(
                                (r) => !m.assignments.any((a) => a.role == r),
                                orElse: () => AssuranceRole.values.first,
                              ),
                              AccessScope.entity,
                              grant: true,
                            )
                          : null,
                      child: const Text('Change access'),
                    ),
                  ],
                ),
              ),
            ),
          if (c.access?.nextCursor != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: c.ready ? c.more : null,
                child: const Text('More members'),
              ),
            ),
        ],
      );
    },
  );
}

class _ChangeCard extends StatelessWidget {
  const _ChangeCard({required this.controller});
  final AssuranceAccessController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller, theme = Theme.of(context);
    final role = c.role!, scope = c.accessScope!, grant = c.granting;
    final label = '${c.form['label']}';
    final locked = c.pending || c.busy;
    Widget chips<T>(
      List<T> values,
      T selected,
      String Function(T) name,
      void Function(T) pick,
    ) => Wrap(
      spacing: JentraSpacing.x2,
      runSpacing: JentraSpacing.x2,
      children: [
        for (final v in values)
          ChoiceChip(
            label: Text(name(v)),
            selected: v == selected,
            onSelected: locked ? null : (_) => pick(v),
          ),
      ],
    );
    return JentraPanel(
      semanticsLabel: 'Change access for $label',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Change access · $label', style: theme.textTheme.titleLarge),
          const SizedBox(height: JentraSpacing.x3),
          chips<bool>(
            const [true, false],
            grant,
            (g) => g ? 'Give role' : 'Remove role',
            (g) => c.choose(grant: g),
          ),
          const SizedBox(height: JentraSpacing.x3),
          Text('Role', style: theme.textTheme.labelLarge),
          const SizedBox(height: JentraSpacing.x1),
          chips<AssuranceRole>(
            AssuranceRole.values,
            role,
            (r) => r.label,
            (r) => c.choose(role: r),
          ),
          const SizedBox(height: JentraSpacing.x3),
          Text('Applies to', style: theme.textTheme.labelLarge),
          const SizedBox(height: JentraSpacing.x1),
          chips<AccessScope>(
            AccessScope.values,
            scope,
            scopeLabel,
            (s) => c.choose(scope: s),
          ),
          const SizedBox(height: JentraSpacing.x3),
          Text(
            grant
                ? 'Gives $label the ${role.label} role (${scopeLabel(scope).toLowerCase()}). ${role.summary}'
                : '$label will no longer hold ${role.label} (${scopeLabel(scope).toLowerCase()}).',
          ),
          if (grant && role.requiresMfa)
            Text(
              'They will need multi-factor authentication to use this role.',
              style: theme.textTheme.bodySmall,
            ),
          if (c.pending)
            const Padding(
              padding: EdgeInsets.only(top: JentraSpacing.x2),
              child: JentraStatusBadge(
                label: 'Saved — complete MFA if asked, then retry',
                tone: JentraStatusTone.warning,
              ),
            ),
          if (c.conflicted)
            const Text(
              'This person\'s access changed. Refresh, then start again.',
            ),
          const SizedBox(height: JentraSpacing.x4),
          Wrap(
            spacing: JentraSpacing.x2,
            runSpacing: JentraSpacing.x2,
            children: [
              JentraPrimaryButton(
                label: c.pending ? 'Retry saved request' : 'Confirm change',
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

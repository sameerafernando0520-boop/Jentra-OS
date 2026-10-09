import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import '../data/employee_gateway.dart';
import '../employee_controller.dart';
import '../l10n/employee_strings.dart';
import 'employee_components.dart';
import 'employee_reviews.dart';
import 'leave_draft_screen.dart';
import 'onboarding_screens.dart';

class EmployeeShell extends StatefulWidget {
  const EmployeeShell({
    required this.controller,
    required this.onSettings,
    super.key,
  });
  final EmployeeController controller;
  final VoidCallback onSettings;
  @override
  State<EmployeeShell> createState() => _EmployeeShellState();
}

class _EmployeeShellState extends State<EmployeeShell> {
  String _destination = 'home';
  EmployeeController get controller => widget.controller;

  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  void _reviews({bool actionsOnly = false}) => _open(
    EmployeeReviewsScreen(controller: controller, actionsOnly: actionsOnly),
  );
  void _help() {
    final s = EmployeeStrings.of(context);
    _open(
      EmployeeInfoScreen(
        title: s('hrHelp'),
        message: s('hrHelpCopy'),
        icon: Icons.support_agent_outlined,
      ),
    );
  }

  Future<void> _draft() async {
    final routeVersion = controller.privateRouteVersion;
    _open(
      EmployeeLeaveDraftScreen(
        controller: controller,
        initialDraft: controller.leaveDraft,
        onSave: (draft) async {
          if (routeVersion != controller.privateRouteVersion) return false;
          await controller.saveLeaveDraft(draft);
          return controller.phase == EmployeePhase.ready &&
              controller.error == null &&
              controller.leaveDraft != null;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = EmployeeStrings.of(context);
    final person = controller.identity;
    if (person == null) return const SizedBox.shrink();
    final compact =
        MediaQuery.textScalerOf(context).scale(14) > 20 || s.language != 'en';
    return Scaffold(
      appBar: AppBar(
        title: JentraBrandLockup(
          size: 28,
          inverse: Theme.of(context).brightness == Brightness.dark,
        ),
        actions: [
          IconButton(
            key: const Key('employee-refresh'),
            tooltip: s('refresh'),
            onPressed: controller.busy ? null : controller.refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            key: const Key('employee-inbox'),
            tooltip: s('inbox'),
            onPressed: () => _reviews(actionsOnly: true),
            icon: const Icon(Icons.inbox_outlined),
          ),
        ],
      ),
      body: switch (_destination) {
        'work' => _work(s),
        'leave' => _leave(s),
        'pay' => _pay(s),
        'more' => _more(s, person),
        _ => _home(s, person),
      },
      bottomNavigationBar: _EmployeeNavigation(
        selected: _destination,
        compact: compact,
        onSelected: (value) => setState(() => _destination = value),
      ),
    );
  }

  Widget _home(EmployeeStrings s, EmployeeIdentity person) {
    final toAcknowledge = controller.reviews
        .where((r) => r.canAcknowledge)
        .length;
    return EmployeePageBody(
      onRefresh: controller.refresh,
      children: [
        Text(
          person.workspace.tenantName,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: context.jentraColors.textSecondary),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EmployeeHeading(s('yourWorkday'), large: true),
            const SizedBox(height: 8),
            Text(
              person.displayName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${person.workspace.entityName} · ${person.workspace.branchName}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.jentraColors.textSecondary),
            ),
          ],
        ),
        if (controller.error != null)
          EmployeeMessage(title: s.failure(controller.error!), error: true),
        if (controller.hasPendingCommand)
          EmployeePendingAction(controller: controller),
        JentraPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Icon(Icons.fact_check_outlined, size: 28),
              ),
              const SizedBox(height: 16),
              EmployeeHeading(s('reviews')),
              const SizedBox(height: 8),
              Text(s('reviewsCopy')),
              const SizedBox(height: 16),
              if (controller.reviewsLoading) const LinearProgressIndicator(),
              if (controller.reviewsError != null)
                Text(controller.reviewsError!.message),
              if (!controller.reviewsLoading && controller.reviewsError == null)
                EmployeeStatus(
                  toAcknowledge > 0
                      ? '${s('reviewActions')}: $toAcknowledge'
                      : s('noActions'),
                  icon: toAcknowledge > 0
                      ? Icons.mark_email_unread_outlined
                      : Icons.check_circle_outline,
                ),
              const SizedBox(height: 18),
              FilledButton(
                key: const Key('employee-open-reviews'),
                onPressed: _reviews,
                child: Text(s('reviews')),
              ),
            ],
          ),
        ),
        EmployeeHeading(s('quickActions')),
        EmployeeActionTile(
          title: s('leave'),
          icon: Icons.event_available_outlined,
          subtitle: s(
            controller.leaveDraft == null ? 'createDraft' : 'localDraft',
          ),
          onTap: () => setState(() => _destination = 'leave'),
        ),
        EmployeeActionTile(
          title: s('profile'),
          icon: Icons.person_outline,
          onTap: () => _open(EmployeeProfileScreen(identity: person)),
        ),
        EmployeeActionTile(
          title: s('hrHelp'),
          icon: Icons.support_agent_outlined,
          onTap: _help,
        ),
      ],
    );
  }

  Widget _work(EmployeeStrings s) => EmployeePageBody(
    children: [
      EmployeeHeading(s('work'), large: true),
      EmployeeMessage(
        title: s('workUnavailable'),
        message: s('workCopy'),
        icon: Icons.calendar_month_outlined,
      ),
      EmployeeActionTile(
        title: s('hrHelp'),
        icon: Icons.support_agent_outlined,
        onTap: _help,
      ),
    ],
  );

  Widget _leave(EmployeeStrings s) {
    final draft = controller.leaveDraft;
    return EmployeePageBody(
      children: [
        EmployeeHeading(s('leave'), large: true),
        EmployeeMessage(
          title: s('leaveUnavailable'),
          message: s('leaveCopy'),
          icon: Icons.event_note_outlined,
        ),
        if (controller.error != null)
          EmployeeMessage(title: s.failure(controller.error!), error: true),
        if (draft != null)
          JentraPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EmployeeStatus(
                  s('localDraft'),
                  warning: true,
                  icon: Icons.save_outlined,
                ),
                const SizedBox(height: 16),
                EmployeeHeading(draft.leaveType),
                const SizedBox(height: 8),
                Text(
                  '${DateFormat.yMMMd(s.language).format(draft.startDate)} – ${DateFormat.yMMMd(s.language).format(draft.endDate)}',
                ),
                const SizedBox(height: 8),
                Text(draft.reason),
                const SizedBox(height: 12),
                Text(
                  s('notSubmitted'),
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: controller.busy ? null : _draft,
                  child: Text(s('editDraft')),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: controller.busy
                      ? null
                      : () async {
                          final remove = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(s('deleteDraftCopy')),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: Text(s('cancel')),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text(s('deleteDraft')),
                                ),
                              ],
                            ),
                          );
                          if (remove == true) {
                            await controller.discardLeaveDraft();
                          }
                        },
                  child: Text(s('deleteDraft')),
                ),
              ],
            ),
          ),
        if (draft == null)
          FilledButton(
            key: const Key('employee-create-draft'),
            onPressed: controller.busy ? null : _draft,
            child: Text(s('createDraft')),
          ),
        Text(
          s('draftExpires'),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: context.jentraColors.textSecondary),
        ),
      ],
    );
  }

  Widget _pay(EmployeeStrings s) => EmployeePageBody(
    children: [
      EmployeeHeading(s('pay'), large: true),
      EmployeeMessage(
        title: s('payUnavailable'),
        message: s('payCopy'),
        icon: Icons.receipt_long_outlined,
      ),
      JentraPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lock_outline, size: 28),
            const SizedBox(height: 16),
            EmployeeHeading(s('payPrivacy')),
            const SizedBox(height: 8),
            Text(s('payPrivacyCopy')),
          ],
        ),
      ),
      EmployeeActionTile(
        title: s('hrHelp'),
        icon: Icons.support_agent_outlined,
        onTap: _help,
      ),
    ],
  );

  Widget _more(EmployeeStrings s, EmployeeIdentity person) => EmployeePageBody(
    children: [
      EmployeeHeading(s('more'), large: true),
      EmployeeActionTile(
        title: s('profile'),
        icon: Icons.person_outline,
        onTap: () => _open(EmployeeProfileScreen(identity: person)),
      ),
      EmployeeActionTile(
        title: s('reviews'),
        icon: Icons.fact_check_outlined,
        onTap: _reviews,
      ),
      EmployeeActionTile(
        key: const Key('employee-more-work'),
        title: s('work'),
        icon: Icons.calendar_month_outlined,
        onTap: () => setState(() => _destination = 'work'),
      ),
      EmployeeActionTile(
        key: const Key('employee-more-pay'),
        title: s('pay'),
        icon: Icons.receipt_long_outlined,
        onTap: () => setState(() => _destination = 'pay'),
      ),
      EmployeeActionTile(
        title: s('documents'),
        icon: Icons.folder_outlined,
        onTap: () => _open(
          EmployeeInfoScreen(
            title: s('documents'),
            message: s('documentsUnavailable'),
            icon: Icons.folder_outlined,
          ),
        ),
      ),
      EmployeeActionTile(
        title: s('hrHelp'),
        icon: Icons.support_agent_outlined,
        onTap: _help,
      ),
      EmployeeHeading(s('account')),
      EmployeeActionTile(
        key: const Key('employee-settings'),
        title: s('settings'),
        icon: Icons.tune,
        onTap: widget.onSettings,
      ),
      EmployeeActionTile(
        title: s('switchWorkspace'),
        icon: Icons.business_outlined,
        onTap: () => _open(EmployeeWorkspacePicker(controller: controller)),
      ),
      EmployeeMessage(
        title: s('security'),
        message: '${s('securityCopy')}\n\n${s('storageCopy')}',
        icon: Icons.shield_outlined,
      ),
      OutlinedButton(onPressed: controller.lock, child: Text(s('lockNow'))),
      TextButton(
        key: const Key('employee-sign-out'),
        onPressed: controller.busy ? null : controller.signOut,
        child: Text(s('signOut')),
      ),
    ],
  );
}

class _EmployeeNavigation extends StatelessWidget {
  const _EmployeeNavigation({
    required this.selected,
    required this.compact,
    required this.onSelected,
  });
  final String selected;
  final bool compact;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) {
    final s = EmployeeStrings.of(context);
    final destinations = compact
        ? ['home', 'leave', 'more']
        : ['home', 'work', 'leave', 'pay', 'more'];
    final effective = compact && {'work', 'pay'}.contains(selected)
        ? 'more'
        : selected;
    const icons = {
      'home': Icons.home_outlined,
      'work': Icons.calendar_month_outlined,
      'leave': Icons.event_available_outlined,
      'pay': Icons.receipt_long_outlined,
      'more': Icons.grid_view_outlined,
    };
    return Material(
      color: context.jentraColors.panel,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final value in destinations)
                  Expanded(
                    child: Semantics(
                      selected: value == effective,
                      button: true,
                      child: InkWell(
                        key: Key('employee-nav-$value'),
                        onTap: () => onSelected(value),
                        borderRadius: BorderRadius.circular(8),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 64),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 8,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: value == effective
                                        ? context.jentraColors.infoSurface
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    icons[value],
                                    size: 24,
                                    color: value == effective
                                        ? context.jentraColors.action
                                        : context.jentraColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  s(value),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: value == effective
                                            ? context.jentraColors.action
                                            : context
                                                  .jentraColors
                                                  .textSecondary,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EmployeeInfoScreen extends StatelessWidget {
  const EmployeeInfoScreen({
    required this.title,
    required this.message,
    required this.icon,
    super.key,
  });
  final String title, message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: EmployeePageBody(
      children: [EmployeeMessage(title: title, message: message, icon: icon)],
    ),
  );
}

class EmployeeProfileScreen extends StatelessWidget {
  const EmployeeProfileScreen({required this.identity, super.key});
  final EmployeeIdentity identity;
  @override
  Widget build(BuildContext context) {
    final s = EmployeeStrings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s('profile'))),
      body: EmployeePageBody(
        children: [
          JentraPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.person_outline, size: 32),
                const SizedBox(height: 16),
                EmployeeHeading(identity.displayName, large: true),
                const SizedBox(height: 16),
                EmployeeStatus(
                  s('connectedProfile'),
                  icon: Icons.verified_user_outlined,
                ),
              ],
            ),
          ),
          Text(s('profileCopy')),
          for (final value in [
            (s('company'), identity.workspace.tenantName),
            (s('entity'), identity.workspace.entityName),
            (s('branch'), identity.workspace.branchName),
            (s('timeZone'), identity.workspace.timeZone),
          ])
            JentraPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value.$1,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: context.jentraColors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  Text(value.$2),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class EmployeeWorkspacePicker extends StatelessWidget {
  const EmployeeWorkspacePicker({required this.controller, super.key});
  final EmployeeController controller;
  @override
  Widget build(BuildContext context) {
    final s = EmployeeStrings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s('switchWorkspace'))),
      body: EmployeePageBody(
        children: [
          Text(s('workspaceCopy')),
          for (final workspace in controller.workspaces)
            EmployeeActionTile(
              title: workspace.tenantName,
              subtitle: '${workspace.entityName}\n${workspace.branchName}',
              icon: Icons.business_outlined,
              onTap: () => controller.selectWorkspace(workspace),
            ),
        ],
      ),
    );
  }
}

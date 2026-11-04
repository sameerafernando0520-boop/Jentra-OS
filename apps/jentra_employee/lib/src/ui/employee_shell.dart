import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import '../data/employee_gateway.dart';
import '../data/employee_self_service.dart';
import '../employee_controller.dart';
import '../l10n/employee_strings.dart';
import 'employee_components.dart';
import 'employee_help_screen.dart';
import 'employee_identity.dart';
import 'employee_profile_screen.dart';
import 'employee_reviews.dart';
import 'employee_surfaces.dart';
import 'leave_draft_screen.dart';
import 'onboarding_screens.dart';
import 'employee_attendance.dart';
import 'employee_leave.dart';
import 'employee_private_services.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && controller.consumePhotoProfileReturn()) {
        _open(EmployeeProfileScreen(controller: controller));
      } else if (mounted && controller.selfService.consumeDocumentReturn()) {
        _open(
          EmployeePrivateServiceScreen(
            controller: controller.selfService,
            service: EmployeeService.documents,
          ),
        );
      }
    });
  }

  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  void _reviews({bool actionsOnly = false}) => _open(
    EmployeeReviewsScreen(controller: controller, actionsOnly: actionsOnly),
  );
  void _help() => _open(EmployeeHelpScreen(onPrepareLeaveDraft: _draft));
  void _inbox() => _open(
    EmployeeInboxScreen(
      controller: controller.selfService,
      onOpenDestination: _noticeDestination,
    ),
  );
  Future<void> _noticeDestination(String destination) async {
    Navigator.of(context).pop();
    if (destination == 'reviews') {
      await controller.refreshReviews();
      if (mounted && controller.phase == EmployeePhase.ready) _reviews();
    } else if (destination == 'documents' || destination == 'cases') {
      _open(
        EmployeePrivateServiceScreen(
          controller: controller.selfService,
          service: destination == 'documents'
              ? EmployeeService.documents
              : EmployeeService.cases,
        ),
      );
    } else {
      setState(
        () => _destination = switch (destination) {
          'attendance' => 'work',
          'leave' => 'leave',
          'pay' => 'pay',
          _ => 'home',
        },
      );
    }
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
            onPressed: _inbox,
            icon: const Icon(Icons.inbox_outlined),
          ),
        ],
      ),
      body: KeyedSubtree(
        key: ValueKey('employee-page-$_destination'),
        child: switch (_destination) {
          'work' => EmployeeAttendanceBody(controller: controller.selfService),
          'leave' => EmployeeLeaveBody(employee: controller, onDraft: _draft),
          'pay' => EmployeePrivateServiceBody(
            controller: controller.selfService,
            service: EmployeeService.payslips,
          ),
          'activity' => _activity(s),
          'more' => _more(s, person),
          _ => _home(s, person),
        },
      ),
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
        EmployeeIdentityHero(
          identity: person,
          photo: controller.profilePhoto,
          onOpen: () => _open(EmployeeProfileScreen(controller: controller)),
        ),
        if (controller.error != null)
          EmployeeMessage(title: s.failure(controller.error!), error: true),
        if (controller.hasPendingCommand)
          EmployeePendingAction(controller: controller),
        EmployeeSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.mark_email_unread_outlined, size: 24),
                  const SizedBox(width: 12),
                  Expanded(child: EmployeeHeading(s('upNext'))),
                ],
              ),
              const SizedBox(height: 10),
              if (controller.reviewsLoading) const LinearProgressIndicator(),
              if (controller.reviewsError != null)
                Text(s.failure(controller.reviewsError!)),
              if (!controller.reviewsLoading && controller.reviewsError == null)
                EmployeeStatus(
                  toAcknowledge > 0
                      ? '${s('reviewActions')}: $toAcknowledge'
                      : s('noActions'),
                  icon: toAcknowledge > 0
                      ? Icons.mark_email_unread_outlined
                      : Icons.check_circle_outline,
                ),
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const Key('employee-open-reviews'),
                onPressed: _reviews,
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                iconAlignment: IconAlignment.end,
                label: Text(s('reviews')),
              ),
            ],
          ),
        ),
        if (controller.leaveDraft != null)
          EmployeeActionTile(
            title: s('draftSummary'),
            subtitle: s('notSubmitted'),
            icon: Icons.edit_note_rounded,
            onTap: _draft,
          ),
        EmployeeSectionHeader(title: s('teamServices')),
        EmployeeServiceGroup(
          children: [
            EmployeeServiceRow(
              key: const Key('employee-home-leave'),
              title: s('leave'),
              subtitle: s('leaveShortcut'),
              icon: Icons.event_available_outlined,
              onTap: () => setState(() => _destination = 'leave'),
            ),
            EmployeeServiceRow(
              title: s('pay'),
              subtitle: s('payShortcut'),
              icon: Icons.receipt_long_outlined,
              onTap: () => setState(() => _destination = 'pay'),
            ),
            EmployeeServiceRow(
              title: s('hrHelp'),
              subtitle: s('helpShortcut'),
              icon: Icons.contact_support_outlined,
              onTap: _help,
            ),
          ],
        ),
      ],
    );
  }

  Widget _activity(EmployeeStrings s) {
    final draft = controller.leaveDraft;
    return EmployeePageBody(
      onRefresh: controller.refresh,
      children: [
        EmployeeHeading(s('activity'), large: true),
        Text(
          s('activityCopy'),
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: context.jentraColors.textSecondary),
        ),
        if (controller.hasPendingCommand)
          EmployeePendingAction(controller: controller),
        EmployeeSectionHeader(title: s('draftSummary')),
        EmployeeSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (draft == null) ...[
                Text(
                  s('noDraftActivity'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(s('noDraftCopy')),
              ] else ...[
                EmployeeStatus(
                  s('notSubmitted'),
                  warning: true,
                  icon: Icons.edit_note_rounded,
                ),
                const SizedBox(height: 14),
                EmployeeHeading(draft.leaveType),
                const SizedBox(height: 6),
                Text(
                  '${DateFormat.yMMMd(s.language).format(draft.startDate)} – ${DateFormat.yMMMd(s.language).format(draft.endDate)}',
                ),
                const SizedBox(height: 8),
                Text(draft.reason),
              ],
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: controller.busy ? null : _draft,
                child: Text(s(draft == null ? 'createDraft' : 'editDraft')),
              ),
              const SizedBox(height: 8),
              Text(
                s('draftExpires'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        EmployeeSectionHeader(
          title: s('activityReviews'),
          actionLabel: s('viewAll'),
          onAction: _reviews,
        ),
        if (controller.reviewsLoading) const LinearProgressIndicator(),
        if (controller.reviewsError != null)
          EmployeeMessage(
            title: s.failure(controller.reviewsError!),
            error: true,
            action: OutlinedButton(
              onPressed: controller.refresh,
              child: Text(s('retry')),
            ),
          ),
        if (!controller.reviewsLoading &&
            controller.reviewsError == null &&
            controller.reviews.isEmpty)
          EmployeeMessage(title: s('noReviews'), message: s('noReviewsCopy')),
        for (final review in controller.reviews)
          EmployeeActionTile(
            key: Key('employee-activity-review-${review.id}'),
            title: employeeReviewPeriod(review, s.language),
            subtitle: s(review.status),
            icon: review.canAcknowledge
                ? Icons.mark_email_unread_outlined
                : Icons.fact_check_outlined,
            onTap: () => _open(
              EmployeeReviewScreen(controller: controller, reviewId: review.id),
            ),
          ),
      ],
    );
  }

  Widget _more(EmployeeStrings s, EmployeeIdentity person) => EmployeePageBody(
    children: [
      EmployeeHeading(s('more'), large: true),
      EmployeeSectionHeader(title: s('teamServices')),
      EmployeeActionTile(
        title: s('profile'),
        icon: Icons.person_outline,
        onTap: () => _open(EmployeeProfileScreen(controller: controller)),
      ),
      EmployeeActionTile(
        title: s('reviews'),
        icon: Icons.fact_check_outlined,
        onTap: _reviews,
      ),
      EmployeeActionTile(
        key: const Key('employee-more-leave'),
        title: s('leave'),
        icon: Icons.event_available_outlined,
        onTap: () => setState(() => _destination = 'leave'),
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
        key: const Key('employee-more-documents'),
        title: s('documents'),
        icon: Icons.folder_outlined,
        onTap: () => _open(
          EmployeePrivateServiceScreen(
            controller: controller.selfService,
            service: EmployeeService.documents,
          ),
        ),
      ),
      EmployeeActionTile(
        key: const Key('employee-more-cases'),
        title: s('casesTitle'),
        icon: Icons.forum_outlined,
        onTap: () => _open(
          EmployeePrivateServiceScreen(
            controller: controller.selfService,
            service: EmployeeService.cases,
          ),
        ),
      ),
      EmployeeActionTile(
        title: s('inboxTitle'),
        icon: Icons.inbox_outlined,
        onTap: _inbox,
      ),
      EmployeeActionTile(
        title: s('hrHelp'),
        icon: Icons.contact_support_outlined,
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
        ? ['home', 'activity', 'more']
        : ['home', 'leave', 'activity', 'more'];
    final effective = !destinations.contains(selected) ? 'more' : selected;
    const icons = {
      'home': Icons.home_outlined,
      'leave': Icons.event_available_outlined,
      'activity': Icons.history_rounded,
      'more': Icons.grid_view_outlined,
    };
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.jentraColors.panel,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: context.jentraColors.border.withValues(alpha: .6),
            ),
            boxShadow: [
              BoxShadow(
                color: context.jentraColors.textPrimary.withValues(alpha: .08),
                blurRadius: 24,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final value in destinations)
                    Expanded(
                      child: Semantics(
                        selected: value == effective,
                        button: true,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            key: Key('employee-nav-$value'),
                            onTap: () => onSelected(value),
                            borderRadius: BorderRadius.circular(20),
                            child: AnimatedContainer(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 64,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 10,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: value == effective
                                              ? context.jentraColors.infoSurface
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: Icon(
                                          icons[value],
                                          size: 22,
                                          color: value == effective
                                              ? context.jentraColors.action
                                              : context
                                                    .jentraColors
                                                    .textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        s(value),
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              fontSize: 12,
                                              fontWeight: value == effective
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
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
                      ),
                    ),
                ],
              ),
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

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import '../data/employee_gateway.dart';
import '../employee_controller.dart';
import '../l10n/employee_strings.dart';
import 'employee_components.dart';

class EmployeeWorkspaceScreen extends StatelessWidget {
  const EmployeeWorkspaceScreen({
    required this.controller,
    required this.onSettings,
    super.key,
  });
  final EmployeeController controller;
  final VoidCallback onSettings;
  @override
  Widget build(BuildContext context) {
    final s = EmployeeStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s('employee')),
        actions: [
          IconButton(
            tooltip: s('settings'),
            onPressed: onSettings,
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: s('signOut'),
            onPressed: controller.signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: EmployeePageBody(
        onRefresh: controller.refresh,
        children: [
          EmployeeHeading(s('chooseWorkspace'), large: true),
          Text(s('workspaceCopy')),
          if (controller.error != null)
            EmployeeMessage(
              title: s.failure(controller.error!),
              error: true,
              action: OutlinedButton(
                onPressed: controller.refresh,
                child: Text(s('retry')),
              ),
            ),
          if (controller.workspaces.isEmpty)
            EmployeeMessage(
              title: s('noWorkspaces'),
              message: s('askHrAccess'),
            ),
          for (final workspace in controller.workspaces)
            EmployeeActionTile(
              title: workspace.tenantName,
              subtitle: '${workspace.entityName}\n${workspace.branchName}',
              icon: Icons.business_outlined,
              onTap: controller.busy
                  ? null
                  : () => controller.selectWorkspace(workspace),
            ),
        ],
      ),
    );
  }
}

class EmployeeLinkScreen extends StatelessWidget {
  const EmployeeLinkScreen({
    required this.controller,
    required this.onSettings,
    super.key,
  });
  final EmployeeController controller;
  final VoidCallback onSettings;

  Future<void> _accept(BuildContext context, EmployeeLink link) async {
    final s = EmployeeStrings.of(context);
    final workspace = controller.workspace;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s('confirmLink')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                link.displayName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(
                '${workspace?.entityName ?? ''}\n${workspace?.branchName ?? ''}',
              ),
              const SizedBox(height: 16),
              Text(s('confirmLinkCopy')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s('cancel')),
          ),
          FilledButton(
            key: const Key('employee-confirm-link'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s('confirm')),
          ),
        ],
      ),
    );
    if (accepted == true && context.mounted) {
      await controller.respondToLink(link, accept: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = EmployeeStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s('employee')),
        actions: [
          IconButton(
            tooltip: s('settings'),
            onPressed: onSettings,
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: s('signOut'),
            onPressed: controller.signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: EmployeePageBody(
        onRefresh: controller.refresh,
        children: [
          EmployeeHeading(s('linkTitle'), large: true),
          Text(s('linkCopy')),
          if (controller.error != null)
            EmployeeMessage(title: s.failure(controller.error!), error: true),
          if (controller.hasPendingCommand)
            EmployeePendingAction(controller: controller),
          if (controller.links.isEmpty)
            EmployeeMessage(
              title: s('noLinks'),
              message: s('askHrAccess'),
              action: OutlinedButton(
                onPressed: controller.refresh,
                child: Text(s('refresh')),
              ),
            ),
          for (final link in controller.links)
            JentraPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EmployeeHeading(link.displayName),
                  const SizedBox(height: 12),
                  Text(
                    '${controller.workspace?.entityName ?? ''}\n${controller.workspace?.branchName ?? ''}',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${s('expires')}: ${DateFormat.yMMMd(s.language).add_Hm().format(link.expiresAt.toUtc())} UTC',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const Key('employee-accept-link'),
                    onPressed: controller.busy || controller.hasPendingCommand
                        ? null
                        : () => _accept(context, link),
                    child: Text(s('acceptLink')),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: controller.busy || controller.hasPendingCommand
                        ? null
                        : () => controller.respondToLink(link, accept: false),
                    child: Text(s('rejectLink')),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class EmployeePendingAction extends StatelessWidget {
  const EmployeePendingAction({required this.controller, super.key});
  final EmployeeController controller;
  @override
  Widget build(BuildContext context) {
    final s = EmployeeStrings.of(context);
    return EmployeeMessage(
      title: s('unknownResult'),
      message: s('unknownCopy'),
      warning: true,
      action: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton(
            onPressed: controller.busy ? null : controller.reconcileCommand,
            child: Text(s('checkResult')),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: controller.busy ? null : controller.retryPendingCommand,
            child: Text(s('retrySaved')),
          ),
        ],
      ),
    );
  }
}

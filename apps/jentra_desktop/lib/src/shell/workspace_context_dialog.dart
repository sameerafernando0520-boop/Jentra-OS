import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_providers.dart';

Future<void> showWorkspaceContext(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const WorkspaceContextDialog(),
);

class WorkspaceContextDialog extends ConsumerWidget {
  const WorkspaceContextDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(businessScopeProvider);
    final controller = ref.read(businessScopeProvider.notifier);
    return AlertDialog(
      title: const Text('Switch workspace'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: value.when(
            skipLoadingOnReload: false,
            skipLoadingOnRefresh: false,
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your permitted workspaces could not be loaded. Check the connection and try again.',
                ),
                TextButton(
                  onPressed: () => ref.invalidate(businessScopeProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
            data: (scope) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Choose the business, legal entity and branch you want to work in.',
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  key: ValueKey('workspace-tenant-${scope.tenantId}'),
                  initialValue: scope.tenantId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Business'),
                  items: [
                    for (final item in scope.tenants)
                      DropdownMenuItem(
                        value: item.id,
                        child: Text(item.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (id) {
                    if (id != null) controller.selectTenant(id);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    'workspace-entity-${scope.tenantId}-${scope.legalEntityId}',
                  ),
                  initialValue: scope.legalEntityId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Legal entity'),
                  items: [
                    for (final item in scope.legalEntities)
                      DropdownMenuItem(
                        value: item.id,
                        child: Text(item.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: scope.legalEntities.isEmpty
                      ? null
                      : (id) {
                          if (id != null) controller.selectLegalEntity(id);
                        },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    'workspace-branch-${scope.legalEntityId}-${scope.branchId}',
                  ),
                  initialValue: scope.branchId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Branch'),
                  items: [
                    for (final item in scope.branches)
                      DropdownMenuItem(
                        value: item.id,
                        child: Text(item.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: scope.branches.isEmpty
                      ? null
                      : (id) {
                          if (id != null) controller.selectBranch(id);
                        },
                ),
                if (scope.legalEntities.isEmpty || scope.branches.isEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'No permitted operational scope is available. Ask a workspace administrator to check your access.',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

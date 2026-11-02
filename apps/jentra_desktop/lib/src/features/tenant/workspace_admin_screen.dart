import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_workspace_admin.dart';

import '../../app_providers.dart';
import '../auth/mfa_required_screen.dart';
import 'workspace_admin_controller.dart';

class WorkspaceAdminScreen extends ConsumerStatefulWidget {
  const WorkspaceAdminScreen({super.key});
  @override
  ConsumerState<WorkspaceAdminScreen> createState() =>
      _WorkspaceAdminScreenState();
}

class _WorkspaceAdminScreenState extends ConsumerState<WorkspaceAdminScreen> {
  bool opening = false;
  Future<void> open(
    WorkspaceAdminController c,
    WorkspaceAdminAction action, [
    WorkspaceAdminRecord? row,
  ]) async {
    if (opening || c.locked) return;
    setState(() => opening = true);
    try {
      final choices = switch (action) {
        WorkspaceAdminAction.createBranch => [WorkspaceAdminResource.entities],
        WorkspaceAdminAction.createRole ||
        WorkspaceAdminAction.updateRole => [WorkspaceAdminResource.permissions],
        WorkspaceAdminAction.setAssignment ||
        WorkspaceAdminAction.createInvitation => [
          WorkspaceAdminResource.roles,
          WorkspaceAdminResource.entities,
          WorkspaceAdminResource.branches,
        ],
        _ => <WorkspaceAdminResource>[],
      };
      for (final choice in choices) {
        await c.loadChoices(choice);
      }
      if (!mounted ||
          ref.read(workspaceAdminControllerProvider) != c ||
          c.locked) {
        return;
      }
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _AdminEditDialog(controller: c, action: action, row: row),
      );
      if (saved == true &&
          mounted &&
          ref.read(workspaceAdminControllerProvider) == c) {
        await c.load(c.resource);
        if (mounted &&
            (action.resource == WorkspaceAdminResource.entities ||
                action.resource == WorkspaceAdminResource.branches)) {
          await ref.read(businessScopeProvider.notifier).refresh();
        }
      }
    } on Object {
      if (mounted && ref.read(workspaceAdminControllerProvider) == c) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Selection records could not be loaded. Check your current access and connection.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  Future<void> change(
    WorkspaceAdminController c,
    WorkspaceAdminAction action,
    WorkspaceAdminRecord row,
    Map<String, Object?> payload,
    String title,
  ) async {
    if (c.locked) return;
    final revision = c.contextRevision;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Consumer(
        builder: (context, ref, _) => ListenableBuilder(
          listenable: c,
          builder: (context, _) =>
              ref.watch(workspaceAdminControllerProvider) != c ||
                  revision != c.contextRevision ||
                  !c.online ||
                  c.denied
              ? _workplaceChanged(context)
              : AlertDialog(
                  title: Text(title),
                  content: Text(
                    'Apply this change to ${row.name}? Existing business and audit records are retained.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Confirm change'),
                    ),
                  ],
                ),
        ),
      ),
    );
    if (confirmed != true ||
        !mounted ||
        ref.read(workspaceAdminControllerProvider) != c) {
      return;
    }
    if (await c.send(action, payload, version: row.version) &&
        mounted &&
        ref.read(workspaceAdminControllerProvider) == c) {
      await c.load(c.resource);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(workspaceAdminControllerProvider);
    if (c == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.admin_panel_settings_outlined, size: 40),
              const SizedBox(height: 16),
              Text(
                'Company & access',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'Connect to your company group with an authorized administrator account and complete MFA.',
              ),
              TextButton(
                onPressed: () => ref.invalidate(businessCapabilitiesProvider),
                child: const Text('Refresh access'),
              ),
            ],
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final records =
            c.pages[c.resource]?.items ?? const <WorkspaceAdminRecord>[];
        final create = switch (c.resource) {
          WorkspaceAdminResource.entities => WorkspaceAdminAction.createEntity,
          WorkspaceAdminResource.branches => WorkspaceAdminAction.createBranch,
          WorkspaceAdminResource.roles => WorkspaceAdminAction.createRole,
          WorkspaceAdminResource.invitations =>
            WorkspaceAdminAction.createInvitation,
          _ => null,
        };
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Company & access',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Manage your company group, branches and individual staff access.',
            ),
            const SizedBox(height: 8),
            Text(
              ref.watch(businessScopeProvider).value?.tenant.name ??
                  'Selected company group',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<WorkspaceAdminResource>(
                    key: ValueKey(c.resource),
                    initialValue: c.resource,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Register'),
                    items: [
                      for (final r in c.resources)
                        DropdownMenuItem(value: r, child: Text(r.label)),
                    ],
                    onChanged: c.busy
                        ? null
                        : (r) {
                            if (r != null) c.load(r);
                          },
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: c.busy || !c.online
                      ? null
                      : () => c.ready ? c.load(c.resource) : c.initialize(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reload'),
                ),
                if (create != null &&
                    c.capabilities.contains(create.resource.permission))
                  FilledButton.icon(
                    onPressed: c.locked || opening
                        ? null
                        : () => open(c, create),
                    icon: const Icon(Icons.add),
                    label: Text(switch (create) {
                      WorkspaceAdminAction.createEntity => 'Add company',
                      WorkspaceAdminAction.createBranch => 'Add branch',
                      WorkspaceAdminAction.createRole => 'Create role',
                      _ => 'Invite staff',
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (!c.online)
              const Text('Reconnect to view or change company access.'),
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  c.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (c.denied)
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () =>
                        ref.invalidate(businessCapabilitiesProvider),
                    child: const Text('Refresh access'),
                  ),
                  if (c.error?.contains('MFA') == true &&
                      ref.watch(foundationGatewayProvider) != null)
                    OutlinedButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => _WorkspaceMfaPrompt(
                          actor: c.scope.actorId,
                          gateway: ref.read(foundationGatewayProvider)!,
                        ),
                      ),
                      child: const Text('Verify MFA again'),
                    ),
                ],
              ),
            if (c.message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(c.message!),
              ),
            if (c.pending != null)
              JentraPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('A saved change needs confirmation.'),
                    const SizedBox(height: 8),
                    const Text(
                      'Retry the original request before creating another change. Its account, company group and fields stay fixed.',
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: !c.online || c.busy || c.denied
                          ? null
                          : c.retry,
                      child: const Text('Retry saved request'),
                    ),
                  ],
                ),
              ),
            if (c.busy)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!c.busy &&
                c.online &&
                c.ready &&
                records.isEmpty &&
                c.error == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No records in this register page.'),
              ),
            for (final row in records)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          [
                            row.data['code'],
                            row.data['email'] != row.name
                                ? row.data['email']
                                : null,
                            row.data['status'],
                            row.data['currency_code'],
                            row.data['timezone'],
                            row.data['requires_mfa'] == true
                                ? 'MFA required'
                                : null,
                            row.data['is_system'] == true
                                ? 'Protected system role'
                                : null,
                            row.data['owner'] == true
                                ? 'Protected owner'
                                : null,
                          ].whereType<String>().join(' · '),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (c.resource == WorkspaceAdminResource.entities &&
                                c.capabilities.contains(c.resource.permission))
                              TextButton(
                                onPressed: c.locked
                                    ? null
                                    : () => open(
                                        c,
                                        WorkspaceAdminAction.updateEntity,
                                        row,
                                      ),
                                child: const Text('Edit company'),
                              ),
                            if (c.resource == WorkspaceAdminResource.branches &&
                                c.capabilities.contains(c.resource.permission))
                              TextButton(
                                onPressed: c.locked
                                    ? null
                                    : () => open(
                                        c,
                                        WorkspaceAdminAction.updateBranch,
                                        row,
                                      ),
                                child: const Text('Edit branch'),
                              ),
                            if (c.resource == WorkspaceAdminResource.roles &&
                                !row.protected &&
                                c.capabilities.contains(c.resource.permission))
                              TextButton(
                                onPressed: c.locked
                                    ? null
                                    : () => open(
                                        c,
                                        WorkspaceAdminAction.updateRole,
                                        row,
                                      ),
                                child: const Text('Edit custom role'),
                              ),
                            if (c.resource == WorkspaceAdminResource.members &&
                                !row.protected &&
                                row.data['user_id'] != c.scope.actorId) ...[
                              if (row.data['status'] == 'active')
                                TextButton(
                                  onPressed: c.locked
                                      ? null
                                      : () => open(
                                          c,
                                          WorkspaceAdminAction.setAssignment,
                                          row,
                                        ),
                                  child: const Text('Manage roles'),
                                ),
                              TextButton(
                                onPressed: c.locked
                                    ? null
                                    : () => change(
                                        c,
                                        WorkspaceAdminAction.setMemberStatus,
                                        row,
                                        {
                                          'id': row.id,
                                          'status':
                                              row.data['status'] == 'active'
                                              ? 'suspended'
                                              : 'active',
                                        },
                                        row.data['status'] == 'active'
                                            ? 'Suspend staff access'
                                            : 'Restore staff access',
                                      ),
                                child: Text(
                                  row.data['status'] == 'active'
                                      ? 'Suspend access'
                                      : 'Restore access',
                                ),
                              ),
                              if (row.data['status'] != 'revoked')
                                TextButton(
                                  onPressed: c.locked
                                      ? null
                                      : () => change(
                                          c,
                                          WorkspaceAdminAction.setMemberStatus,
                                          row,
                                          {'id': row.id, 'status': 'revoked'},
                                          'Revoke staff access',
                                        ),
                                  child: const Text('Revoke access'),
                                ),
                            ],
                            if (c.resource ==
                                    WorkspaceAdminResource.invitations &&
                                {
                                  'pending',
                                  'expired',
                                }.contains(row.data['status']))
                              TextButton(
                                onPressed: c.locked
                                    ? null
                                    : () => change(
                                        c,
                                        WorkspaceAdminAction.revokeInvitation,
                                        row,
                                        {'id': row.id},
                                        'Revoke invitation',
                                      ),
                                child: const Text('Revoke invitation'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: c.busy || !c.online
                      ? null
                      : () => c.load(c.resource),
                  child: const Text('First page'),
                ),
                OutlinedButton(
                  onPressed:
                      c.busy ||
                          !c.online ||
                          c.pages[c.resource]?.nextCursor == null
                      ? null
                      : () => c.load(c.resource, next: true),
                  child: const Text('Next page'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Owner transfer, company removal and changes to accounting currency or timezone require a separate controlled workflow.',
            ),
          ],
        );
      },
    );
  }
}

class _WorkspaceMfaPrompt extends ConsumerWidget {
  const _WorkspaceMfaPrompt({required this.actor, required this.gateway});
  final String actor;
  final Object gateway;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(authenticatedActorProvider).value != actor ||
        ref.watch(foundationGatewayProvider) != gateway) {
      return AlertDialog(
        title: const Text('Account changed'),
        content: const Text('Reopen verification with your current account.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }
    return Dialog(
      child: SizedBox(
        width: 760,
        height: MediaQuery.sizeOf(context).height - 80,
        child: Column(
          children: [
            Expanded(
              child: MfaRequiredScreen(
                onVerified: () => Navigator.pop(context),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close verification'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminEditDialog extends ConsumerStatefulWidget {
  const _AdminEditDialog({
    required this.controller,
    required this.action,
    this.row,
  });
  final WorkspaceAdminController controller;
  final WorkspaceAdminAction action;
  final WorkspaceAdminRecord? row;
  @override
  ConsumerState<_AdminEditDialog> createState() => _AdminEditDialogState();
}

class _AdminEditDialogState extends ConsumerState<_AdminEditDialog> {
  final fields = <String, TextEditingController>{};
  final form = GlobalKey<FormState>();
  final permissions = <String>{};
  String? entity, branch, role, error;
  bool mfa = true, saving = false;
  late final int openedRevision;
  WorkspaceAdminController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    openedRevision = c.contextRevision;
    final d = widget.row?.data ?? <String, Object?>{};
    for (final k in [
      'name',
      'code',
      'currency_code',
      'timezone',
      'email',
      'registration_number',
      'tax_identifier',
    ]) {
      fields[k] = TextEditingController(
        text:
            (d[k] ??
                    (k == 'currency_code'
                        ? 'LKR'
                        : k == 'timezone'
                        ? 'Asia/Colombo'
                        : ''))
                .toString(),
      );
    }
    permissions.addAll((d['permissions'] as List?)?.cast<String>() ?? []);
    mfa = d['requires_mfa'] as bool? ?? true;
  }

  @override
  void dispose() {
    for (final f in fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  bool get current =>
      mounted &&
      ref.read(workspaceAdminControllerProvider) == c &&
      c.contextRevision == openedRevision &&
      c.online &&
      !c.denied;
  List<WorkspaceAdminRecord> choices(WorkspaceAdminResource r) =>
      c.catalogues[r] ?? [];
  Future<void> save([Map<String, Object?>? assignmentRemoval]) async {
    if (!current ||
        saving ||
        c.locked ||
        assignmentRemoval == null && !form.currentState!.validate()) {
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final a = widget.action, p = <String, Object?>{};
    if (widget.row != null) p['id'] = widget.row!.id;
    if (assignmentRemoval != null) {
      p.addAll(assignmentRemoval);
    } else {
      final keys = switch (a) {
        WorkspaceAdminAction.createEntity => [
          'name',
          'code',
          'currency_code',
          'timezone',
          'registration_number',
          'tax_identifier',
        ],
        WorkspaceAdminAction.updateEntity => [
          'name',
          'registration_number',
          'tax_identifier',
        ],
        WorkspaceAdminAction.createBranch => ['name', 'code', 'timezone'],
        WorkspaceAdminAction.updateBranch => ['name'],
        WorkspaceAdminAction.createRole => ['name', 'code'],
        WorkspaceAdminAction.updateRole => ['name'],
        WorkspaceAdminAction.createInvitation => ['email'],
        _ => <String>[],
      };
      for (final k in keys) {
        var v = fields[k]!.text.trim();
        if (k == 'code') {
          v = a.resource == WorkspaceAdminResource.roles
              ? v.toLowerCase()
              : v.toUpperCase();
        }
        if (k == 'currency_code') v = v.toUpperCase();
        if (k == 'email') v = v.toLowerCase();
        p[k] = v;
      }
      if (a == WorkspaceAdminAction.createBranch) p['legal_entity_id'] = entity;
      if (a == WorkspaceAdminAction.createRole ||
          a == WorkspaceAdminAction.updateRole) {
        p['permissions'] = permissions.toList()..sort();
        p['requires_mfa'] = mfa;
      }
      if (a == WorkspaceAdminAction.setAssignment ||
          a == WorkspaceAdminAction.createInvitation) {
        p.addAll({
          'role_id': role,
          'legal_entity_id': entity,
          'branch_id': branch,
        });
      }
      if (a == WorkspaceAdminAction.setAssignment) p['granted'] = true;
    }
    final success = await c.send(a, p, version: widget.row?.version);
    if (!mounted || !current) return;
    if (success) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      saving = false;
      error = c.error ?? 'This change was not confirmed.';
    });
  }

  Widget input(String key, String label, {bool optional = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: fields[key],
      enabled: !saving,
      decoration: InputDecoration(labelText: label),
      validator: (v) =>
          !optional && (v == null || v.trim().isEmpty) ? 'Enter $label.' : null,
    ),
  );
  String label(WorkspaceAdminResource r, Object? id) => id == null
      ? 'All'
      : choices(r).where((x) => x.id == id).firstOrNull?.name ??
            'Unavailable selection';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => formBody(context),
  );
  Widget formBody(BuildContext context) {
    if (ref.watch(workspaceAdminControllerProvider) != c ||
        c.contextRevision != openedRevision ||
        !c.online ||
        c.denied) {
      return _workplaceChanged(context);
    }
    final a = widget.action,
        isRole = a.resource == WorkspaceAdminResource.roles,
        isScope =
            a == WorkspaceAdminAction.setAssignment ||
            a == WorkspaceAdminAction.createInvitation;
    final selectedPrivileged = choices(WorkspaceAdminResource.permissions)
        .any((r) => permissions.contains(r.id) && r.data['privileged'] == true);
    return AlertDialog(
      title: Text(switch (a) {
        WorkspaceAdminAction.createEntity => 'Add company',
        WorkspaceAdminAction.updateEntity => 'Edit company',
        WorkspaceAdminAction.createBranch => 'Add branch',
        WorkspaceAdminAction.updateBranch => 'Edit branch',
        WorkspaceAdminAction.createRole => 'Create custom role',
        WorkspaceAdminAction.updateRole => 'Edit custom role',
        WorkspaceAdminAction.createInvitation => 'Invite staff',
        _ => 'Manage staff roles',
      }),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.row != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(widget.row!.name),
                  ),
                if (a == WorkspaceAdminAction.createInvitation) ...[
                  input('email', 'Staff email'),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      'The person signs in with this verified email and accepts the invitation in their own workspace.',
                    ),
                  ),
                ],
                if (!isScope)
                  input(
                    'name',
                    isRole
                        ? 'Role name'
                        : a.resource == WorkspaceAdminResource.entities
                        ? 'Registered company name'
                        : 'Branch name',
                  ),
                if (a.creates && a != WorkspaceAdminAction.createInvitation)
                  input('code', 'Code'),
                if (a == WorkspaceAdminAction.createEntity)
                  input('currency_code', 'Accounting currency'),
                if (a == WorkspaceAdminAction.createEntity ||
                    a == WorkspaceAdminAction.createBranch)
                  input('timezone', 'Timezone'),
                if (a.resource == WorkspaceAdminResource.entities) ...[
                  input(
                    'registration_number',
                    'Registration number',
                    optional: true,
                  ),
                  input('tax_identifier', 'Tax identifier', optional: true),
                ],
                if (isScope)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: DropdownButtonFormField<String>(
                      initialValue: role,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Role'),
                      items: [
                        for (final r in choices(
                          WorkspaceAdminResource.roles,
                        ).where((r) => r.data['code'] != 'tenant_owner'))
                          DropdownMenuItem(
                            value: r.id,
                            child: Text(
                              r.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      validator: (v) => v == null ? 'Select a role.' : null,
                      onChanged: saving
                          ? null
                          : (v) => setState(() => role = v),
                    ),
                  ),
                if (isScope || a == WorkspaceAdminAction.createBranch)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('company-$entity'),
                      initialValue: entity,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Company scope',
                      ),
                      hint: Text(
                        isScope ? 'All companies' : 'Select a company',
                      ),
                      items: [
                        if (isScope)
                          const DropdownMenuItem(child: Text('All companies')),
                        for (final r in choices(
                          WorkspaceAdminResource.entities,
                        ).where((r) => r.data['status'] == 'active'))
                          DropdownMenuItem(
                            value: r.id,
                            child: Text(
                              r.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      validator: (v) =>
                          a == WorkspaceAdminAction.createBranch && v == null
                          ? 'Select a company.'
                          : null,
                      onChanged: saving
                          ? null
                          : (v) => setState(() {
                              entity = v;
                              branch = null;
                            }),
                    ),
                  ),
                if (isScope && entity != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('branch-$entity-$branch'),
                      initialValue: branch,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Branch scope',
                      ),
                      hint: const Text('All branches in this company'),
                      items: [
                        const DropdownMenuItem(
                          child: Text('All branches in this company'),
                        ),
                        for (final r
                            in choices(WorkspaceAdminResource.branches).where(
                              (r) =>
                                  r.data['legal_entity_id'] == entity &&
                                  r.data['status'] == 'active',
                            ))
                          DropdownMenuItem(
                            value: r.id,
                            child: Text(
                              r.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: saving
                          ? null
                          : (v) => setState(() => branch = v),
                    ),
                  ),
                if (isRole) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Require MFA'),
                    subtitle: const Text(
                      'Required whenever a privileged permission is selected.',
                    ),
                    value: mfa,
                    onChanged: saving || selectedPrivileged
                        ? null
                        : (v) => setState(() => mfa = v),
                  ),
                  const Text('Delegated permissions'),
                  for (final r in choices(WorkspaceAdminResource.permissions))
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(r.data['code']! as String),
                      subtitle: Text(r.name),
                      value: permissions.contains(r.id),
                      onChanged: saving
                          ? null
                          : (v) => setState(() {
                              if (v == true) {
                                permissions.add(r.id);
                                if (r.data['privileged'] == true) mfa = true;
                              } else {
                                permissions.remove(r.id);
                              }
                            }),
                    ),
                ],
                if (a == WorkspaceAdminAction.setAssignment) ...[
                  const SizedBox(height: 16),
                  const Text('Existing assignments'),
                  for (final assignment
                      in (widget.row?.data['assignments'] as List? ?? []))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${label(WorkspaceAdminResource.roles, (assignment as Map)['role_id'])} · ${label(WorkspaceAdminResource.entities, assignment['legal_entity_id'])} · ${label(WorkspaceAdminResource.branches, assignment['branch_id'])}',
                          ),
                          TextButton(
                            onPressed: saving
                                ? null
                                : () => save({
                                    'role_id': assignment['role_id'],
                                    'legal_entity_id':
                                        assignment['legal_entity_id'],
                                    'branch_id': assignment['branch_id'],
                                    'granted': false,
                                  }),
                            child: const Text('Remove this assignment'),
                          ),
                        ],
                      ),
                    ),
                ],
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving || c.locked ? null : () => save(),
          child: Text(
            saving
                ? 'Confirming…'
                : a == WorkspaceAdminAction.setAssignment
                ? 'Grant selected role'
                : 'Save change',
          ),
        ),
      ],
    );
  }
}

Widget _workplaceChanged(BuildContext context) => AlertDialog(
  title: const Text('Workplace changed'),
  content: const Text(
    'Close this dialog, reconnect and reopen it in your current account and company group.',
  ),
  actions: [
    TextButton(
      onPressed: () => Navigator.pop(context),
      child: const Text('Close'),
    ),
  ],
);

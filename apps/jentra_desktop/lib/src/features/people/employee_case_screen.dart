import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'employee_case_controller.dart';
import 'organization_screen.dart' show organizationPicker, OrganizationChoice;

typedef EmployeeCaseOwnerPicker = Future<String?> Function(
  BuildContext context,
);

/// The provider is deliberately watched inside the route, so a session, MFA,
/// capability or scope change disposes the controller and removes private text.
class EmployeeCaseScreen extends ConsumerWidget {
  const EmployeeCaseScreen({this.pickOwner, super.key});
  final EmployeeCaseOwnerPicker? pickOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(employeeCaseControllerProvider);
    if (controller == null) return const _AccessChanged();
    return EmployeeCaseWorkspace(
      key: ObjectKey(controller),
      controller: controller,
      pickOwner: pickOwner,
    );
  }
}

class EmployeeCaseWorkspace extends StatefulWidget {
  const EmployeeCaseWorkspace({
    required this.controller,
    this.pickOwner,
    super.key,
  });
  final EmployeeCaseController controller;
  final EmployeeCaseOwnerPicker? pickOwner;

  @override
  State<EmployeeCaseWorkspace> createState() => _EmployeeCaseWorkspaceState();
}

class _EmployeeCaseWorkspaceState extends State<EmployeeCaseWorkspace> {
  final _reply = TextEditingController();
  EmployeeCaseController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_wipeIfUnavailable);
    unawaited(c.initialize());
  }

  void _wipeIfUnavailable() {
    if (!c.current || !c.online || !c.isOwner) _reply.clear();
  }

  @override
  void dispose() {
    c.removeListener(_wipeIfUnavailable);
    _reply.clear();
    _reply.dispose();
    super.dispose();
  }

  Future<void> _sendReply() async {
    await c.act('reply', body: _reply.text);
    if (mounted && c.pendingCase == null && c.error == null) _reply.clear();
  }

  Future<void> _assign() async {
    final owner = widget.pickOwner == null
        ? await _pickEligibleOwner()
        : await widget.pickOwner!(context);
    if (mounted && c.current && !c.locked && owner != null) {
      await c.act('assign', ownerUserId: owner);
    }
  }

  Future<String?> _pickEligibleOwner() async {
    final choices = <Map<String, Object?>>[];
    final choice = await organizationPicker(
      context,
      'accountable HR colleague',
      (query, after) async {
        final page = await c.ownerChoices(after: after);
        choices.addAll(page.$1);
        return (
          [
            for (final row in page.$1)
              if (query.isEmpty ||
                  (row['label']! as String).toLowerCase().contains(
                    query.toLowerCase(),
                  ))
                OrganizationChoice(
                  row['id']! as String,
                  row['label']! as String,
                ),
          ],
          page.$2,
        );
      },
      () => c.current && c.online && c.isOwner,
    );
    if (choice == null || !c.current || !c.online) return null;
    return choices
            .where((row) => row['id'] == choice.id)
            .firstOrNull?['user_id']
        as String?;
  }

  Widget _detail(Map<String, Object?> row) {
    final status = row['status']! as String;
    final messages = row['messages']! as List;
    final history = row['history']! as List;
    return _Section(
      title: row['subject'] as String? ?? 'Employee enquiry',
      children: [
        Text('${_category(row['category'])} · ${_status(status)}'),
        const SizedBox(height: 8),
        SelectableText('Employee reference: ${row['employee_id']}'),
        Text(
          row['owner_user_id'] == null
              ? 'Unassigned — claim this enquiry before responding.'
              : row['owner_available'] == false
              ? 'The previous owner no longer has HR access. Take ownership to respond.'
              : c.isOwner
              ? 'You are the accountable HR owner.'
              : 'Assigned to another HR colleague.',
        ),
        if (row['category'] == 'payroll') ...[
          const SizedBox(height: 8),
          SelectableText('Payslip reference: ${row['payslip_id']}'),
          const Text(
            'This enquiry is bound to the employee’s exact published payslip revision. '
            'A reply does not change payroll.',
          ),
        ],
        const Divider(height: 32),
        Text('Conversation', style: Theme.of(context).textTheme.titleMedium),
        if (messages.isEmpty) const Text('No messages are available.'),
        for (final raw in messages)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: _CaseMessage(row: Map<String, Object?>.from(raw as Map)),
          ),
        if (status != 'closed' && c.isOwner) ...[
          const SizedBox(height: 12),
          TextField(
            key: const Key('employee-case-reply'),
            controller: _reply,
            enabled: !c.locked,
            maxLength: 4000,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Reply to employee',
              helperText: 'Keep the reply relevant to this private enquiry.',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (status != 'closed' && row['owner_available'] == false)
              FilledButton.icon(
                onPressed: c.locked ? null : () => c.act('claim'),
                icon: const Icon(Icons.assignment_ind_outlined),
                label: Text(
                  row['owner_user_id'] == null
                      ? 'Claim enquiry'
                      : 'Take ownership',
                ),
              ),
            if (status != 'closed' && c.isOwner) ...[
              FilledButton.icon(
                onPressed: c.locked ? null : _sendReply,
                icon: const Icon(Icons.send_outlined),
                label: const Text('Send reply'),
              ),
              OutlinedButton(
                onPressed: c.locked ? null : _assign,
                child: const Text('Assign to colleague'),
              ),
              if (status == 'open' || status == 'in_progress')
                OutlinedButton(
                  onPressed: c.locked ? null : () => c.act('resolve'),
                  child: const Text('Mark resolved'),
                ),
              if (status == 'resolved')
                OutlinedButton(
                  onPressed: c.locked ? null : () => c.act('close'),
                  child: const Text('Close enquiry'),
                ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Status history'),
          children: [
            for (final raw in history)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_status((raw as Map)['status'])),
                subtitle: Text(_date(raw['created_at'])),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      if (!c.current) return _AccessChanged(message: c.error);
      return PopScope(
        canPop:
            !c.busy && c.pendingCase == null && c.pendingPublication == null,
        child: ListView(
          key: const Key('employee-case-workspace'),
          padding: const EdgeInsets.all(24),
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Employee enquiries',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                OutlinedButton.icon(
                  onPressed: c.busy || !c.online || c.pendingCase != null
                      ? null
                      : c.refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reload enquiries'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Respond to general HR and payroll enquiries for the selected entity and branch. '
              'The assigned owner is accountable for replies and closure.',
            ),
            _Status(controller: c),
            if (c.pendingCase != null)
              _Section(
                title: 'HR action unconfirmed',
                children: [
                  const Text(
                    'The server may have received this action. Retry the same request to verify its result. '
                    'Other changes stay locked until it is confirmed.',
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      onPressed: c.busy || !c.online ? null : c.retryCase,
                      child: const Text('Retry original HR action'),
                    ),
                  ),
                ],
              ),
            if (c.rows.isEmpty && !c.busy && c.error == null)
              const _Section(
                title: 'No enquiries',
                children: [
                  Text('No employee enquiries are available in this branch.'),
                ],
              ),
            for (final row in c.rows)
              Card(
                child: ListTile(
                  selected: c.selected?['id'] == row['id'],
                  leading: Icon(
                    row['category'] == 'payroll'
                        ? Icons.receipt_long_outlined
                        : Icons.support_agent_outlined,
                  ),
                  title: Text(row['subject'] as String? ?? 'Employee enquiry'),
                  subtitle: Text(
                    '${_category(row['category'])} · ${_status(row['status'])}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: c.locked
                      ? null
                      : () {
                          _reply.clear();
                          unawaited(c.open(row['id']! as String));
                        },
                ),
              ),
            if (c.cursor != null)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: c.locked ? null : c.more,
                  child: const Text('More enquiries'),
                ),
              ),
            if (c.selected != null) _detail(c.selected!),
          ],
        ),
      );
    },
  );
}

class EmployeeDocumentPublicationScreen extends ConsumerWidget {
  const EmployeeDocumentPublicationScreen({
    required this.documentId,
    required this.documentVersion,
    super.key,
  });
  final String documentId;
  final int documentVersion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(employeeCaseControllerProvider);
    if (controller == null) return const _AccessChanged();
    return EmployeeDocumentPublicationWorkspace(
      key: ObjectKey(controller),
      controller: controller,
      documentId: documentId,
      documentVersion: documentVersion,
    );
  }
}

class EmployeeDocumentPublicationWorkspace extends StatefulWidget {
  const EmployeeDocumentPublicationWorkspace({
    required this.controller,
    required this.documentId,
    required this.documentVersion,
    super.key,
  });
  final EmployeeCaseController controller;
  final String documentId;
  final int documentVersion;

  @override
  State<EmployeeDocumentPublicationWorkspace> createState() =>
      _EmployeeDocumentPublicationWorkspaceState();
}

class _EmployeeDocumentPublicationWorkspaceState
    extends State<EmployeeDocumentPublicationWorkspace> {
  final _label = TextEditingController();
  EmployeeCaseController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_wipeIfUnavailable);
    unawaited(_load());
  }

  void _wipeIfUnavailable() {
    if (!c.current || !c.online) _label.clear();
  }

  Future<void> _load() async {
    await c.openPublication(widget.documentId, widget.documentVersion);
    if (mounted && c.current) {
      _label.text = c.publication?['label'] as String? ?? '';
    }
  }

  @override
  void dispose() {
    c.removeListener(_wipeIfUnavailable);
    _label.clear();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      if (!c.current) return _AccessChanged(message: c.error);
      final row = c.publication;
      return PopScope(
        canPop:
            !c.busy && c.pendingCase == null && c.pendingPublication == null,
        child: ListView(
          key: const Key('employee-document-publication'),
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Employee document access',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'Private uploads stay hidden from the employee until an authorized HR publisher shares '
              'this exact revision. Removing access prevents future opens; a previously saved copy '
              'cannot be recalled.',
            ),
            _Status(controller: c),
            if (row == null && !c.busy && c.pendingPublication == null)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: c.online ? _load : null,
                  child: const Text('Load current document access'),
                ),
              ),
            if (row != null) ...[
              const SizedBox(height: 16),
              Text(
                row['visible'] == true
                    ? 'Shared with the linked employee'
                    : 'Hidden from the employee',
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('employee-document-label'),
                controller: _label,
                enabled: !c.locked,
                maxLength: 160,
                decoration: const InputDecoration(
                  labelText: 'Employee-facing document title',
                  helperText: 'Use a clear title without unrelated private information.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: c.locked
                        ? null
                        : () => c.setPublication(
                            visible: true,
                            label: _label.text,
                          ),
                    icon: const Icon(Icons.share_outlined),
                    label: Text(
                      row['visible'] == true
                          ? 'Update shared title'
                          : 'Share with employee',
                    ),
                  ),
                  if (row['visible'] == true)
                    OutlinedButton(
                      onPressed: c.locked
                          ? null
                          : () => c.setPublication(visible: false),
                      child: const Text('Remove employee access'),
                    ),
                ],
              ),
            ],
            if (c.pendingPublication != null)
              _Section(
                title: 'Document access change unconfirmed',
                children: [
                  const Text(
                    'Retry the original request to verify its result before making another change.',
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      onPressed: c.busy || !c.online
                          ? null
                          : c.retryPublication,
                      child: const Text('Retry original access change'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      );
    },
  );
}

class _AccessChanged extends StatelessWidget {
  const _AccessChanged({this.message});
  final String? message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        message ??
            'Verify MFA and select an entity and branch with current HR staff permission. '
                'Reopen this screen after access is refreshed.',
      ),
    ),
  );
}

class _Status extends StatelessWidget {
  const _Status({required this.controller});
  final EmployeeCaseController controller;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (controller.busy)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: LinearProgressIndicator(),
        ),
      if (!controller.online)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Offline — reconnect and reload current private HR access.',
          ),
        ),
      if (controller.error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Semantics(
            liveRegion: true,
            child: Text(
              controller.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      if (controller.message != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Semantics(liveRegion: true, child: Text(controller.message!)),
        ),
    ],
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(vertical: 12),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
}

class _CaseMessage extends StatelessWidget {
  const _CaseMessage({required this.row});
  final Map<String, Object?> row;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '${row['author_kind'] == 'hr' ? 'HR' : 'Employee'} · ${_date(row['created_at'])}',
        style: Theme.of(context).textTheme.labelLarge,
      ),
      const SizedBox(height: 6),
      SelectableText(row['body'] as String? ?? 'Content no longer available'),
    ],
  );
}

String _category(Object? value) =>
    value == 'payroll' ? 'Payroll enquiry' : 'HR enquiry';
String _status(Object? value) => switch (value) {
  'in_progress' => 'In progress',
  'resolved' => 'Resolved',
  'closed' => 'Closed',
  _ => 'Open',
};
String _date(Object? value) {
  final parsed = DateTime.tryParse(value as String? ?? '');
  if (parsed == null) return '';
  return '${parsed.toUtc().toIso8601String().replaceFirst('T', ' ').substring(0, 16)} UTC';
}

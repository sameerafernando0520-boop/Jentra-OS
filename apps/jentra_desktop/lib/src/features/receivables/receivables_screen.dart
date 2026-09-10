import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_receivables.dart';
import '../../app_providers.dart';
import 'receivables_controller.dart';
import 'receivable_editor.dart';
import 'receivable_statement.dart';
import 'receivable_setup.dart';
import 'receivable_picker.dart';

class ReceivablesScreen extends ConsumerWidget {
  const ReceivablesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(businessCapabilitiesProvider),
        scope = ref.watch(activeTenantContextProvider);
    if (caps.isLoading) return const Center(child: CircularProgressIndicator());
    if (caps.hasError) {
      return Center(
        child: TextButton(
          onPressed: () => ref.invalidate(businessCapabilitiesProvider),
          child: const Text('Access check failed · retry'),
        ),
      );
    }
    if (scope == null || !scope.hasOperationalScope) {
      return const Center(
        child: Text(
          'Choose a legal entity and branch to open fulfillment & receivables.',
        ),
      );
    }
    if (!ReceivableKind.values.any((k) => k.canRead(caps.value!)) &&
        !caps.value!.contains('finance.receivables.view')) {
      return const Center(
        child: Text('Your role cannot open fulfillment & receivables.'),
      );
    }
    final controller = ref.watch(receivablesControllerProvider);
    if (controller == null) {
      return const Center(
        child: Text(
          'Connect to the development workspace to use fulfillment & receivables.',
        ),
      );
    }
    return ReceivablesWorkspace(
      key: ValueKey(controller),
      controller: controller,
    );
  }
}

class ReceivablesWorkspace extends StatefulWidget {
  const ReceivablesWorkspace({super.key, required this.controller});
  final ReceivablesController controller;
  @override
  State<ReceivablesWorkspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<ReceivablesWorkspace> {
  bool reporting = false;
  ReceivablesController get c => widget.controller;
  Future<void> reasonedAction(String action) async {
    final text = TextEditingController();
    final reason = await showScopedReceivableDialog<String>(
      context: context,
      controller: c,
      builder: (context) => AlertDialog(
        title: Text(
          '${action[0].toUpperCase()}${action.substring(1)} document',
        ),
        content: TextField(
          controller: text,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () {
              if (text.text.trim().isNotEmpty) {
                Navigator.pop(context, text.text.trim());
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    text.dispose();
    if (reason != null) await c.action(action, reason: reason);
  }

  Future<void> recovery() async {
    var cursor = '';
    final slots = <String>[];
    try {
      final page = await c.drafts.recovery(c.scope);
      slots.addAll(page.items);
      cursor = page.nextCursor ?? '';
      if (!mounted) return;
      final selected = await showScopedReceivableDialog<String>(
        context: context,
        controller: c,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('Saved drafts & interrupted commands'),
            content: SizedBox(
              width: 600,
              height: 380,
              child: ListView(
                children: [
                  for (final slot in slots)
                    ListTile(
                      title: Text(slot.split(':').first.replaceAll('_', ' ')),
                      subtitle: Text(slot.split(':').last),
                      onTap: () => Navigator.pop(context, slot),
                    ),
                  if (slots.isEmpty)
                    const ListTile(
                      title: Text('No saved drafts in this scope'),
                    ),
                  if (cursor.isNotEmpty)
                    TextButton(
                      onPressed: () async {
                        final more = await c.drafts.recovery(
                          c.scope,
                          cursor: cursor,
                        );
                        if (context.mounted) {
                          setDialog(() {
                            slots.addAll(more.items);
                            cursor = more.nextCursor ?? '';
                          });
                        }
                      },
                      child: const Text('Load more'),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
      if (selected != null) await c.recover(selected);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> discard() async {
    final yes = await showScopedReceivableDialog<bool>(
      context: context,
      controller: c,
      builder: (context) => AlertDialog(
        title: const Text('Discard local changes?'),
        content: const Text(
          'This removes this local draft and reloads the latest server document. Posted records are not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep draft'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard local draft'),
          ),
        ],
      ),
    );
    if (yes == true) await c.discardAndReload();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fulfillment & receivables',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Deliver · invoice · collect · credit',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final kind in ReceivableKind.values.where(
                (k) => k.canRead(c.capabilities),
              ))
                ChoiceChip(
                  label: Text(kind.label),
                  selected: !reporting && c.kind == kind,
                  onSelected: c.busy || c.form != null || c.pending
                      ? null
                      : (_) {
                          setState(() => reporting = false);
                          c.selectKind(kind);
                        },
                ),
              if (c.capabilities.contains('finance.receivables.view'))
                ChoiceChip(
                  label: const Text('Statements & aging'),
                  selected: reporting,
                  onSelected: c.busy || c.form != null || c.pending
                      ? null
                      : (_) => setState(() => reporting = true),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (!c.online)
            const MaterialBanner(
              content: Text(
                'Offline · local drafting is available. Posting and reference reads require a connection.',
              ),
              actions: [SizedBox.shrink()],
            ),
          if (c.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SelectableText(
                c.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (c.message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SelectableText(c.message!),
            ),
          if (c.busy) const LinearProgressIndicator(),
          if (c.pending)
            JentraPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Interrupted command · saved for safe retry',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Text(
                    'The server may already have committed this request. Retry uses the same command identity; do not create a replacement.',
                  ),
                  SelectableText(c.local!.envelope.commandId),
                  FilledButton(
                    onPressed: c.online && !c.busy ? c.retry : null,
                    child: const Text('Retry saved command'),
                  ),
                ],
              ),
            ),
          if (c.local != null && !c.pending && !c.conflict && c.form == null)
            JentraPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'The last command was rejected. No posting from that request was committed.',
                  ),
                  TextButton(
                    onPressed: c.busy ? null : discard,
                    child: const Text('Clear rejected command & reload'),
                  ),
                ],
              ),
            ),
          if (c.conflict)
            JentraPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This document changed on the server. Your local fields have been preserved.',
                  ),
                  Text(
                    'Local expected version ${c.local?.version} · observed server version ${c.document?.version ?? 'reload required'}',
                  ),
                  TextButton(
                    onPressed: c.busy ? null : discard,
                    child: const Text('Discard local edits & reload server'),
                  ),
                ],
              ),
            ),
          if (reporting)
            JentraPanel(child: ReceivableStatement(controller: c))
          else ...[
            const SizedBox(height: 12),
            if (c.form != null)
              JentraPanel(
                child: ReceivableEditor(
                  key: ValueKey('${c.slot}:${c.epoch}'),
                  controller: c,
                ),
              )
            else if (c.document != null) ...[
              JentraPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          c.document!.number,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        Chip(label: Text(c.document!.status)),
                        Text(
                          '${c.document!.currency} ${c.document!.total}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    Text(
                      'Document ${c.document!.data['document_date']} · due ${c.document!.data['due_date']} · version ${c.document!.version}',
                    ),
                    Text(
                      'Customer · ${c.document!.data['customer_name'] ?? c.document!.data['customer_id']}',
                    ),
                    if (c.kind == ReceivableKind.receipt)
                      const Text(
                        'Bank reconciliation: unreconciled · posting a receipt does not confirm bank clearance.',
                      ),
                    const Divider(),
                    for (final line in c.document!.lines)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${line['description']}'),
                        subtitle: Text(
                          '${line['base_quantity']} base units · net ${line['taxable_amount']} · tax ${line['tax_amount']}',
                        ),
                        trailing: Text('${line['line_total']}'),
                      ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (c.document!.editable && c.canManage)
                          OutlinedButton(
                            onPressed: c.busy ? null : c.edit,
                            child: const Text('Edit draft'),
                          ),
                        if (c.document!.editable && c.canManage)
                          FilledButton(
                            onPressed: c.canAct
                                ? () => c.action('submit')
                                : null,
                            child: const Text('Submit'),
                          ),
                        if (c.canPost)
                          FilledButton.icon(
                            onPressed: () => c.action('post'),
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Post document'),
                          ),
                        if (c.document!.status == 'pending_approval' &&
                            c.capabilities.contains(
                              'workflow.approvals.decide',
                            )) ...[
                          FilledButton(
                            onPressed: c.canAct
                                ? () => c.action('approve')
                                : null,
                            child: const Text('Approve'),
                          ),
                          OutlinedButton(
                            onPressed: c.canAct
                                ? () => reasonedAction('reject')
                                : null,
                            child: const Text('Reject'),
                          ),
                        ],
                        if ([
                              'submitted',
                              'pending_approval',
                              'approved',
                              'rejected',
                            ].contains(c.document!.status) &&
                            c.canManage)
                          TextButton(
                            onPressed: c.canAct
                                ? () => reasonedAction('recall')
                                : null,
                            child: const Text('Recall'),
                          ),
                        if (c.document!.status != 'posted' &&
                            c.document!.status != 'cancelled' &&
                            c.canManage)
                          TextButton(
                            onPressed: c.canAct
                                ? () => reasonedAction('cancel')
                                : null,
                            child: const Text('Cancel document'),
                          ),
                        TextButton(
                          onPressed: c.busy || c.pending ? null : c.closeEditor,
                          child: const Text('Back to register'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else ...[
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (c.canManage)
                    FilledButton.icon(
                      onPressed: c.busy ? null : c.create,
                      icon: const Icon(Icons.add),
                      label: Text('New ${c.kind.wire.replaceAll('_', ' ')}'),
                    ),
                  OutlinedButton.icon(
                    onPressed: c.busy ? null : recovery,
                    icon: const Icon(Icons.restore),
                    label: const Text('Recover local work'),
                  ),
                  if (c.capabilities.contains('finance.receipts.allocate'))
                    OutlinedButton(
                      onPressed: c.online && !c.busy
                          ? () => showReceivableAllocation(context, c)
                          : null,
                      child: const Text('Allocate receipt / credit'),
                    ),
                  if (c.capabilities.contains('finance.setup.manage'))
                    OutlinedButton(
                      onPressed:
                          c.online && !c.busy && !c.pending && c.local == null
                          ? () => showReceivableSetup(context, c)
                          : null,
                      child: const Text('Posting setup'),
                    ),
                  IconButton(
                    tooltip: 'Refresh register',
                    onPressed: c.online && !c.busy ? c.refresh : null,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (c.page.items.isEmpty && !c.busy)
                JentraPanel(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No ${c.kind.label.toLowerCase()} loaded',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Text(
                          'Create a draft or refresh the register. Posting requires configured workflows, sequences, fiscal periods, and account mappings.',
                        ),
                      ],
                    ),
                  ),
                ),
              for (final doc in c.page.items)
                Card(
                  child: ListTile(
                    title: Text(doc.number),
                    subtitle: Text(
                      '${doc.data['document_date']} · ${doc.status}',
                    ),
                    trailing: Text('${doc.currency} ${doc.total}'),
                    onTap: c.busy ? null : () => c.open(doc),
                  ),
                ),
              if (c.page.nextCursor != null)
                TextButton(
                  onPressed: c.busy ? null : () => c.refresh(more: true),
                  child: const Text('Load more documents'),
                ),
            ],
          ],
        ],
      ),
    ),
  );
}

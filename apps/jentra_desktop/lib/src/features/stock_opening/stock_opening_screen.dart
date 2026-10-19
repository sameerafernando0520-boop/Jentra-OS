import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_stock_opening.dart';

import '../../app_providers.dart';
import 'stock_opening_controller.dart';
import 'stock_opening_editor.dart';
import 'stock_opening_picker.dart';

class StockOpeningScreen extends ConsumerWidget {
  const StockOpeningScreen({super.key});
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
        child: Text('Choose a legal entity and branch to open stock openings.'),
      );
    }
    if (!canReadStockOpenings(caps.value!)) {
      return const Center(
        child: Text(
          'Stock openings require cost visibility and opening or approval access.',
        ),
      );
    }
    final c = ref.watch(stockOpeningControllerProvider);
    if (c == null) {
      return const Center(
        child: Text(
          'Connect to the development workspace to open stock openings.',
        ),
      );
    }
    return StockOpeningWorkspace(key: ValueKey(c), controller: c);
  }
}

class StockOpeningWorkspace extends StatefulWidget {
  const StockOpeningWorkspace({super.key, required this.controller});
  final StockOpeningController controller;
  @override
  State<StockOpeningWorkspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<StockOpeningWorkspace> {
  StockOpeningController get c => widget.controller;
  Future<void> confirmAction(String action) async {
    final reason = TextEditingController();
    final reasoned = {'reject', 'recall', 'cancel'}.contains(action);
    final accepted = await showStockOpeningDialog<bool>(
      context: context,
      controller: c,
      builder: (context) => AlertDialog(
        title: Text(
          action == 'post'
              ? 'Post this opening count?'
              : '${action[0].toUpperCase()}${action.substring(1)} opening',
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (action == 'post')
                Text(
                  '${c.document!.currency} ${c.document!.total} will establish the counted stock and a balanced inventory/equity journal. Posted openings are permanent.',
                ),
              if (action == 'approve')
                const Text(
                  'Confirm that you have reviewed this warehouse count and its opening values.',
                ),
              if (reasoned)
                TextField(
                  controller: reason,
                  autofocus: true,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Reason'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () {
              if (!reasoned || reason.text.trim().isNotEmpty) {
                Navigator.pop(context, true);
              }
            },
            child: Text(action == 'post' ? 'Post opening' : 'Confirm'),
          ),
        ],
      ),
    );
    final note = reason.text.trim();
    reason.dispose();
    if (accepted == true && mounted && c.active) {
      await c.action(action, reason: reasoned ? note : null);
    }
  }

  Future<void> discard() async {
    final yes = await showStockOpeningDialog<bool>(
      context: context,
      controller: c,
      builder: (context) => AlertDialog(
        title: const Text('Discard local changes?'),
        content: const Text(
          'Your local edits will be removed. The latest saved opening will be reloaded when connected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep draft'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard & reload'),
          ),
        ],
      ),
    );
    if (yes == true && c.active) await c.discardAndReload();
  }

  Future<void> recover() async {
    try {
      final first = await c.drafts.recovery(c.scope);
      if (!mounted || !c.active) return;
      final slots = [...first.items];
      String? cursor = first.nextCursor, error;
      var loading = false;
      final slot = await showStockOpeningDialog<String>(
        context: context,
        controller: c,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('Recover local opening work'),
            content: SizedBox(
              width: 600,
              height: 360,
              child: ListView(
                children: [
                  if (slots.isEmpty)
                    const ListTile(
                      title: Text('No saved openings in this scope'),
                    ),
                  for (final id in slots)
                    ListTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: const Text('Saved opening'),
                      subtitle: Text(id),
                      onTap: () => Navigator.pop(context, id),
                    ),
                  if (error != null) Text(error!),
                  if (loading) const LinearProgressIndicator(),
                  if (cursor != null && !loading)
                    TextButton(
                      onPressed: () async {
                        setDialog(() {
                          loading = true;
                          error = null;
                        });
                        try {
                          final next = await c.drafts.recovery(
                            c.scope,
                            cursor: cursor,
                          );
                          if (context.mounted && c.active) {
                            setDialog(() {
                              slots.addAll(next.items);
                              cursor = next.nextCursor;
                            });
                          }
                        } catch (e) {
                          if (context.mounted) {
                            setDialog(() => error = e.toString());
                          }
                        } finally {
                          if (context.mounted) setDialog(() => loading = false);
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
      if (slot != null && c.active) await c.recover(slot);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Widget notice(String title, String body, {Widget? action}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: JentraPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(body),
          if (action != null) ...[const SizedBox(height: 12), action],
        ],
      ),
    ),
  );
  String stateLabel(String state) => switch (state) {
    'pending_approval' => 'Awaiting approval',
    'draft' => 'Draft',
    'approved' => 'Approved',
    'posted' => 'Posted',
    'rejected' => 'Rejected',
    'cancelled' => 'Cancelled',
    _ => state,
  };
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      if (!c.active || !canReadStockOpenings(c.capabilities)) {
        return const Center(
          child: Text('Opening access is unavailable in this scope.'),
        );
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('INVENTORY', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(
              'Opening stock',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Establish your starting quantities and stock value.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final text in [
                  '1  Count',
                  '2  Independent approval',
                  '3  Post stock & journal',
                ])
                  Chip(label: Text(text)),
              ],
            ),
            const SizedBox(height: 20),
            if (!c.online)
              notice(
                'Working offline',
                'Your local drafts remain available. Reconnect to load products, save to the server, approve or post.',
              ),
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: SelectableText(
                  c.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (c.message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: SelectableText(c.message!),
              ),
            if (c.busy) const LinearProgressIndicator(),
            if (c.pending)
              notice(
                'Opening command awaiting confirmation',
                'The request may already have completed. Retry the saved request to confirm its result.',
                action: FilledButton.icon(
                  onPressed: c.online && !c.busy ? c.retry : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry saved command'),
                ),
              ),
            if (c.conflict)
              notice(
                'The saved opening has changed',
                'Your local count is preserved. Review your fields before discarding them and reloading the latest version.',
                action: TextButton(
                  onPressed: c.busy ? null : discard,
                  child: const Text('Discard local edits & reload'),
                ),
              ),
            if (c.local != null && !c.pending && !c.conflict && c.form == null)
              notice(
                'The last request was rejected',
                'Clear the rejected request and reload before taking another action.',
                action: TextButton(
                  onPressed: c.busy ? null : discard,
                  child: const Text('Clear rejected request & reload'),
                ),
              ),
            if (c.form != null)
              JentraPanel(
                child: StockOpeningEditor(
                  key: ValueKey('${c.slot}:${c.epoch}'),
                  controller: c,
                ),
              )
            else if (c.document != null)
              detail()
            else
              register(),
          ],
        ),
      );
    },
  );
  Widget register() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (c.canManage)
            FilledButton.icon(
              onPressed: c.busy ? null : c.create,
              icon: const Icon(Icons.add),
              label: const Text('New opening'),
            ),
          OutlinedButton.icon(
            onPressed: c.busy ? null : recover,
            icon: const Icon(Icons.restore),
            label: const Text('Recover local work'),
          ),
          PopupMenuButton<String>(
            enabled: !c.busy && c.online,
            tooltip: 'Filter opening status',
            onSelected: (value) {
              c.statusFilter = value == 'all' ? null : value;
              c.refresh();
            },
            itemBuilder: (_) => [
              for (final state in [
                'all',
                'draft',
                'pending_approval',
                'approved',
                'posted',
                'rejected',
                'cancelled',
              ])
                PopupMenuItem(
                  value: state,
                  child: Text(
                    state == 'all' ? 'All statuses' : stateLabel(state),
                  ),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                c.statusFilter == null
                    ? 'All statuses ▾'
                    : '${stateLabel(c.statusFilter!)} ▾',
              ),
            ),
          ),
          IconButton(
            tooltip: 'Refresh openings',
            onPressed: c.online && !c.busy ? c.refresh : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      const SizedBox(height: 20),
      if (c.page.items.isEmpty && !c.busy)
        notice(
          'No opening counts loaded',
          'Create an opening after setting up the warehouse, stocked products, inventory and equity accounts, period, sequences and approval workflow.',
        ),
      for (final doc in c.page.items)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: JentraPanel(
            child: InkWell(
              onTap: c.busy ? null : () => c.open(doc),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Wrap(
                  spacing: 28,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 220,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            doc.number,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '${doc.data['document_date']} · ${doc.lines.length} products',
                          ),
                        ],
                      ),
                    ),
                    Chip(label: Text(stateLabel(doc.status))),
                    Text(
                      '${doc.currency} ${doc.total}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Icon(Icons.arrow_forward),
                  ],
                ),
              ),
            ),
          ),
        ),
      if (c.page.nextCursor != null)
        TextButton(
          onPressed: c.busy ? null : () => c.refresh(more: true),
          child: const Text('Load more openings'),
        ),
    ],
  );
  Widget detail() {
    final doc = c.document!, data = doc.data;
    return JentraPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 20,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                doc.number,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Chip(label: Text(stateLabel(doc.status))),
              Text(
                '${doc.currency} ${doc.total}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Opening date · ${data['document_date']}    Revision ${doc.version}',
          ),
          Text(
            'Warehouse · ${c.labels[data['warehouse_id']] ?? data['warehouse_id']}',
          ),
          Text(
            'Equity account · ${c.labels[data['offset_account_id']] ?? data['offset_account_id']}',
          ),
          const SizedBox(height: 12),
          Text('${data['reason']}'),
          const Divider(height: 32),
          for (final line in doc.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${line['sku']} · ${line['product_name']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${line['base_quantity']} base units · ${doc.currency} ${line['base_value']}',
                  ),
                  if (line['lot_code'] != null)
                    Text(
                      'Lot ${line['lot_code']}${line['expiry_date'] == null ? '' : ' · expires ${line['expiry_date']}'}',
                    ),
                  if ((line['serial_codes'] as List? ?? []).isNotEmpty)
                    Text(
                      'Serials · ${(line['serial_codes']! as List).join(', ')}',
                    ),
                ],
              ),
            ),
          if (doc.status == 'pending_approval')
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                doc.preparedBy(c.scope.actorId)
                    ? 'A separate approver must review this count. You prepared or submitted this opening.'
                    : 'Approval follows the configured roles and steps.',
              ),
            ),
          if (doc.status == 'posted') ...[
            const Text(
              'Stock and the inventory/equity journal were posted together.',
            ),
            SelectableText('Movement reference · ${data['stock_movement_id']}'),
            SelectableText('Journal reference · ${data['journal_entry_id']}'),
            const SizedBox(height: 16),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (doc.editable && c.canManage)
                OutlinedButton(
                  onPressed: c.busy ? null : c.edit,
                  child: const Text('Edit count'),
                ),
              for (final entry in {
                'submit': 'Submit for approval',
                'approve': 'Approve',
                'reject': 'Reject',
                'post': 'Post opening',
                'recall': 'Recall',
                'cancel': 'Cancel opening',
              }.entries)
                if (c.allows(entry.key))
                  FilledButton.tonal(
                    onPressed: c.canAct
                        ? () => entry.key == 'submit'
                              ? c.action('submit')
                              : confirmAction(entry.key)
                        : null,
                    child: Text(entry.value),
                  ),
              TextButton(
                onPressed: c.busy || c.pending ? null : c.closeEditor,
                child: const Text('Back to register'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

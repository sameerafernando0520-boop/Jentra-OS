import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart' show DomainError;

import '../../app_providers.dart';
import '../operations/operational_read_access.dart';
import 'disposition_controller.dart';
import '../journal_evidence/posted_journal_screen.dart';
import '../operations/operational_controller.dart';
import '../operations/operational_link.dart';

class DispositionScreen extends ConsumerWidget {
  const DispositionScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(businessCapabilitiesProvider);
    if (access.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (access.hasError) {
      return Center(
        child: TextButton(
          onPressed: () => ref.invalidate(businessCapabilitiesProvider),
          child: const Text('Retry access check'),
        ),
      );
    }
    final c = ref.watch(dispositionControllerProvider);
    if (c == null) {
      return const Center(
        child: Text(
          'Choose a branch with disposition or approval access and cost permission.',
        ),
      );
    }
    return DispositionWorkspace(
      key: ValueKey(c),
      controller: c,
      capabilities: access.value ?? {},
    );
  }
}

class DispositionWorkspace extends StatelessWidget {
  const DispositionWorkspace({
    required this.controller,
    this.capabilities = const {},
    super.key,
  });
  final DispositionController controller;
  final Set<String> capabilities;
  Future<void> pick(
    BuildContext context,
    String resource,
    void Function(Map<String, Object?>) select, {
    String? product,
  }) async {
    final access = controller.readAccessEpoch;
    final row = await showOperationalReadDialog<Map<String, Object?>>(
      context,
      controller,
      (_) => _DispositionPicker(
        controller: controller,
        resource: resource,
        product: product,
      ),
    );
    if (row != null && !controller.locked && controller.currentRead(access)) {
      select(row);
    }
  }

  Future<void> serials(BuildContext context, int i, Map line) async {
    final access = controller.readAccessEpoch;
    final rows = await showOperationalReadDialog<List<Map<String, Object?>>>(
      context,
      controller,
      (_) => _DispositionPicker(
        controller: controller,
        resource: 'serials',
        product: line['product_id'] as String,
        selectedIds: (line['serial_ids'] as List).cast<String>(),
      ),
    );
    if (rows != null && !controller.locked && controller.currentRead(access)) {
      controller.setSerials(i, rows);
    }
  }

  Future<void> action(BuildContext context, String verb) async {
    if (!['recall', 'cancel', 'reject'].contains(verb)) {
      await controller.act(verb);
      return;
    }
    var reason = '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$verb disposition'),
        content: TextField(
          maxLength: 1000,
          decoration: const InputDecoration(labelText: 'Reason'),
          onChanged: (v) => reason = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, reason),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (result != null) await controller.act(verb, note: result);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller, f = c.form;
      if (c.accessDenied) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Access changed. Saved work is retained securely.'),
              TextButton(
                onPressed: c.busy || !c.online ? null : c.refresh,
                child: const Text('Recheck access'),
              ),
            ],
          ),
        );
      }
      Widget field(String key, String label, {int? max}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          key: ValueKey('${f?['id']}-${f?['version']}-$key'),
          initialValue: f?[key]?.toString() ?? '',
          enabled: c.editable,
          maxLength: max,
          decoration: InputDecoration(labelText: label),
          onChanged: (v) => c.update(key, v),
        ),
      );
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Stock disposition',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Dispose of damaged, quarantined or expired held stock with a reason and independent approval.',
          ),
          const Text(
            'Inventory and variance are posted at the exact pooled carrying cost. Disposed serial identities remain disposed.',
          ),
          if (c.busy) const LinearProgressIndicator(),
          if (!c.online)
            const Text(
              'Offline — save locally and reconnect for server actions.',
            ),
          if (c.error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                c.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (c.message != null)
            Semantics(liveRegion: true, child: Text(c.message!)),
          const SizedBox(height: 16),
          if (f == null) ...[
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (c.canManage)
                  FilledButton(
                    onPressed: c.busy ? null : c.create,
                    child: const Text('New disposition'),
                  ),
                OutlinedButton(
                  onPressed: c.busy || !c.online ? null : c.refresh,
                  child: const Text('Refresh'),
                ),
              ],
            ),
            if (c.items.isEmpty && !c.busy)
              const Text('No dispositions in this branch.'),
            for (final row in c.items)
              Card(
                child: ListTile(
                  title: Text(
                    '${row['document_number'] ?? 'Draft disposition'} · ${row['status']}',
                  ),
                  subtitle: Text(
                    '${row['warehouse_name']} · ${row['document_date']} · ${row['currency_code']} ${row['grand_total']}',
                  ),
                  onTap: c.busy ? null : () => c.open(row),
                ),
              ),
            if (c.cursor != null)
              OutlinedButton(
                onPressed: c.busy || !c.online
                    ? null
                    : () => c.refresh(more: true),
                child: const Text('Load more dispositions'),
              ),
          ] else ...[
            Text(
              '${f['document_number'] ?? 'New disposition'} · ${f['status']}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (f['status'] == 'posted' && c.online)
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (canReadOperational('inventory_disposition', capabilities))
                    OperationalLink(
                      scope: c.scope,
                      kind: 'inventory_disposition',
                      id: f['id'] as String,
                    ),
                  if (capabilities.contains('finance.view') &&
                      f['journal_entry_id'] is String)
                    PostedJournalLink(
                      scope: c.scope,
                      journalId: f['journal_entry_id'] as String,
                    ),
                ],
              ),
            if (f['corrects_disposition_id'] != null)
              SelectableText(
                'Corrects disposition ${f['corrects_disposition_id']}',
              ),
            if (f['reverses_disposition_id'] != null) ...[
              SelectableText(
                'Reverses disposition ${f['reverses_disposition_id']}',
              ),
              const Text(
                'The server restores the original lot or untracked quantity, value and receipt attribution only if later stock history permits it.',
              ),
            ],
            if (c.local?.pending != null)
              const Text(
                'A saved command awaits confirmation. Retry preserves its identity and approved version.',
              ),
            const SizedBox(height: 16),
            field('document_date', 'Posting date (YYYY-MM-DD)'),
            field('reason', 'Disposition reason', max: 1000),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed:
                      !c.editable ||
                          !c.online ||
                          f['version'] != null ||
                          (f['lines'] as List).isNotEmpty ||
                          f['reverses_disposition_id'] != null
                      ? null
                      : () => pick(context, 'warehouses', (w) {
                          c.update('warehouse_id', w['id']);
                          c.update('_warehouse_name', w['name']);
                        }),
                  child: Text(
                    'Warehouse: ${f['_warehouse_name'] ?? f['warehouse_name'] ?? 'Select'}',
                  ),
                ),
                OutlinedButton(
                  onPressed:
                      !c.editable ||
                          !c.online ||
                          f['reverses_disposition_id'] != null
                      ? null
                      : () => pick(context, 'accounts', (a) {
                          c.update('offset_account_id', a['id']);
                          c.update('_account_name', a['name']);
                        }),
                  child: Text(
                    'Variance account: ${f['_account_name'] ?? f['offset_account_name'] ?? 'Select'}',
                  ),
                ),
              ],
            ),
            for (var i = 0; i < (f['lines'] as List).length; i++)
              _line(context, i, (f['lines'] as List)[i] as Map),
            if (f['reverses_disposition_id'] == null)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed:
                      !c.editable || !c.online || f['warehouse_id'] == null
                      ? null
                      : () => pick(context, 'products', c.addProduct),
                  child: const Text('Add held product'),
                ),
              ),
            if (f['grand_total'] != null)
              Text(
                '${f['status'] == 'posted' ? 'Posted carrying value' : 'Saved carrying value for approval'}: ${f['currency_code']} ${f['grand_total']}',
              ),
            if (f['_dirty'] == true)
              const Text(
                'Save these changes to obtain the current exact server preview.',
              ),
            if (f['version'] != null && f['grand_total'] == null)
              OutlinedButton(
                onPressed: c.canReloadEvidence ? c.reloadEvidence : null,
                child: const Text('Reload permitted value evidence'),
              ),
            if (f['journal_entry_id'] != null)
              SelectableText('Journal ${f['journal_entry_id']}'),
            if (f['stock_movement_id'] != null)
              SelectableText('Stock movement ${f['stock_movement_id']}'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (c.local?.pending != null)
                  FilledButton(
                    onPressed: c.busy || !c.online
                        ? null
                        : () => c.act('retry'),
                    child: const Text('Retry saved action'),
                  )
                else ...[
                  if (c.canManage && f['status'] == 'posted') ...[
                    FilledButton(
                      onPressed: c.busy ? null : () => c.correct(),
                      child: const Text('New linked correction'),
                    ),
                    if (!(f['lines'] as List).any(
                      (l) => (l as Map)['tracking_mode'] == 'serial',
                    ))
                      OutlinedButton(
                        onPressed: c.busy
                            ? null
                            : () => c.correct(reverse: true),
                        child: const Text('Prepare linked reversal'),
                      ),
                  ],
                  if (c.editable)
                    FilledButton(
                      onPressed: !c.online ? null : () => c.act('save'),
                      child: const Text('Save exact preview'),
                    ),
                  if (c.canManage &&
                      f['status'] == 'draft' &&
                      f['version'] != null)
                    OutlinedButton(
                      onPressed: c.busy || !c.online || f['_dirty'] == true
                          ? null
                          : () => action(context, 'submit'),
                      child: const Text('Submit for approval'),
                    ),
                  if (f['status'] == 'pending_approval' &&
                      c.permissions.contains('workflow.approvals.decide')) ...[
                    FilledButton(
                      onPressed: c.busy || !c.online
                          ? null
                          : () => action(context, 'approve'),
                      child: const Text('Approve disposition'),
                    ),
                    OutlinedButton(
                      onPressed: c.busy || !c.online
                          ? null
                          : () => action(context, 'reject'),
                      child: const Text('Reject disposition'),
                    ),
                  ],
                  if (c.canManage && f['status'] == 'approved')
                    FilledButton(
                      onPressed: c.busy || !c.online
                          ? null
                          : () => action(context, 'post'),
                      child: const Text('Post approved disposition'),
                    ),
                  if (c.canManage &&
                      [
                        'pending_approval',
                        'approved',
                        'rejected',
                      ].contains(f['status']))
                    OutlinedButton(
                      onPressed: c.busy || !c.online
                          ? null
                          : () => action(context, 'recall'),
                      child: const Text('Recall for revision'),
                    ),
                  if (c.canManage &&
                      ['draft', 'pending_approval'].contains(f['status']) &&
                      f['version'] != null)
                    OutlinedButton(
                      onPressed: c.busy || !c.online
                          ? null
                          : () => action(context, 'cancel'),
                      child: const Text('Cancel disposition'),
                    ),
                  OutlinedButton(
                    onPressed: c.locked ? null : c.saveLocal,
                    child: const Text('Save locally'),
                  ),
                  TextButton(
                    onPressed: c.locked ? null : c.close,
                    child: const Text('Discard local copy / close'),
                  ),
                ],
              ],
            ),
          ],
        ],
      );
    },
  );
  Widget _line(BuildContext context, int i, Map line) {
    final c = controller;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${line['product_name']} · ${line['tracking_mode']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            TextFormField(
              key: ValueKey(
                '${line['line_id']}-${c.form?['version']}-quantity',
              ),
              initialValue: line['quantity'] as String,
              enabled:
                  c.editable &&
                  line['tracking_mode'] != 'serial' &&
                  c.form?['reverses_disposition_id'] == null,
              decoration: const InputDecoration(
                labelText: 'Quantity in base units',
              ),
              onChanged: (v) => c.updateLine(i, 'quantity', v),
            ),
            if (line['tracking_mode'] == 'lot')
              OutlinedButton(
                onPressed:
                    !c.editable ||
                        !c.online ||
                        c.form?['reverses_disposition_id'] != null
                    ? null
                    : () => pick(
                        context,
                        'lots',
                        (l) => c.setLot(i, l),
                        product: line['product_id'] as String,
                      ),
                child: Text(
                  'Held lot: ${line['lot_code'] ?? line['lot_id'] ?? 'Select'}',
                ),
              ),
            if (line['tracking_mode'] == 'serial') ...[
              Text(
                'Selected serials: ${(line['serial_codes'] as List? ?? line['serial_ids'] as List).join(', ')}',
              ),
              OutlinedButton(
                onPressed: !c.editable || !c.online
                    ? null
                    : () => serials(context, i, line),
                child: const Text('Select held serials'),
              ),
            ],
            if (line['carrying_value'] != null)
              Text('Saved exact carrying value: ${line['carrying_value']}'),
            if (c.editable && c.form?['reverses_disposition_id'] == null)
              TextButton(
                onPressed: () => c.removeLine(i),
                child: const Text('Remove line'),
              ),
          ],
        ),
      ),
    );
  }
}

class _DispositionPicker extends StatefulWidget {
  const _DispositionPicker({
    required this.controller,
    required this.resource,
    this.product,
    this.selectedIds,
  });
  final DispositionController controller;
  final String resource;
  final String? product;
  final List<String>? selectedIds;
  @override
  State<_DispositionPicker> createState() => _DispositionPickerState();
}

class _DispositionPickerState extends State<_DispositionPicker> {
  final rows = <Map<String, Object?>>[];
  final selected = <String, Map<String, Object?>>{};
  String? cursor, error;
  bool busy = false;
  late int accessEpoch;
  @override
  void initState() {
    super.initState();
    accessEpoch = widget.controller.accessEpoch;
    widget.controller.addListener(accessChanged);
    load();
  }

  void accessChanged() {
    if (!mounted || widget.controller.isCurrent(accessEpoch)) return;
    setState(() {
      rows.clear();
      selected.clear();
      cursor = null;
      error = 'Access or connection changed. Close and reopen this picker.';
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(accessChanged);
    super.dispose();
  }

  Future<void> load() async {
    if (!widget.controller.isCurrent(accessEpoch) ||
        widget.controller.accessDenied) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final page = await widget.controller.gateway.options(
        widget.controller.scope,
        widget.resource,
        warehouse: widget.controller.form?['warehouse_id'] as String?,
        product: widget.product,
        after: cursor,
      );
      if (!mounted || !widget.controller.isCurrent(accessEpoch)) return;
      for (final raw in page['items'] as List) {
        final row = (raw as Map).cast<String, Object?>();
        rows.add(row);
        if (widget.selectedIds?.contains(row['id']) == true) {
          selected[row['id'] as String] = row;
        }
      }
      cursor = page['next_cursor'] as String?;
    } catch (e) {
      if (!mounted || !widget.controller.isCurrent(accessEpoch)) return;
      if (e is DomainError &&
          const {
            'PERMISSION_DENIED',
            'ACCESS_DENIED',
            'MFA_REQUIRED',
            'AUTHENTICATION_REQUIRED',
          }.contains(e.code)) {
        widget.controller.denyAccess();
      }
      if (mounted) error = 'Unable to load held identities. Retry with the current branch access.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Select ${widget.resource}'),
    content: SizedBox(
      width: 640,
      height: 420,
      child: Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          Expanded(
            child: ListView(
              children: [
                for (final row in rows)
                  if (widget.resource == 'serials')
                    CheckboxListTile(
                      title: Text('${row['code']} · ${row['status']}'),
                      value: selected.containsKey(row['id']),
                      onChanged:
                          busy || !widget.controller.isCurrent(accessEpoch)
                          ? null
                          : (v) => setState(() {
                              if (v == true && selected.length < 500) {
                                selected[row['id'] as String] = row;
                              } else {
                                selected.remove(row['id']);
                              }
                            }),
                    )
                  else
                    ListTile(
                      title: Text('${row['name'] ?? row['code']}'),
                      subtitle: row['expiry_date'] != null
                          ? Text(
                              'Expiry ${row['expiry_date']} · Held ${row['held_quantity']}',
                            )
                          : null,
                      onTap: busy || !widget.controller.isCurrent(accessEpoch)
                          ? null
                          : () => Navigator.pop(context, row),
                    ),
              ],
            ),
          ),
          if (cursor != null || error != null)
            TextButton(
              onPressed: busy ? null : load,
              child: Text(error != null ? 'Retry' : 'Load more'),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Back'),
      ),
      if (widget.resource == 'serials')
        FilledButton(
          onPressed:
              busy ||
                  !widget.controller.isCurrent(accessEpoch) ||
                  widget.controller.accessDenied
              ? null
              : () => Navigator.pop(context, selected.values.toList()),
          child: Text('Use ${selected.length} serials'),
        ),
    ],
  );
}

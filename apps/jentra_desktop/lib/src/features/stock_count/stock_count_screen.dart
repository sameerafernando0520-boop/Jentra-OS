import 'package:flutter/material.dart';
import 'package:jentra_domain/jentra_domain.dart' show DomainError;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../operations/operational_read_access.dart';
import 'stock_count_controller.dart';

class StockCountScreen extends ConsumerWidget {
  const StockCountScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(businessCapabilitiesProvider);
    if (caps.isLoading) return const Center(child: CircularProgressIndicator());
    if (caps.hasError) {
      return Center(
        child: TextButton(
          onPressed: () => ref.invalidate(businessCapabilitiesProvider),
          child: const Text('Retry access check'),
        ),
      );
    }
    final c = ref.watch(stockCountControllerProvider);
    if (c == null) {
      return const Center(
        child: Text(
          'Choose a scope with stock count and cost-view permission.',
        ),
      );
    }
    return StockCountWorkspace(key: ValueKey(c), controller: c);
  }
}

class StockCountWorkspace extends StatelessWidget {
  const StockCountWorkspace({required this.controller, super.key});
  final StockCountController controller;
  Future<void> pick(
    BuildContext context,
    String resource,
    void Function(Map<String, Object?>) selected,
  ) async {
    final access = controller.readAccessEpoch;
    final result = await showOperationalReadDialog<Map<String, Object?>>(
      context,
      controller,
      (_) => _CountPicker(controller: controller, resource: resource),
    );
    if (result != null &&
        !controller.locked &&
        controller.currentRead(access)) {
      selected(result);
    }
  }

  Future<void> action(BuildContext context, String verb) async {
    if (!['recall', 'cancel', 'reject'].contains(verb)) {
      await controller.act(verb);
      return;
    }
    var input = '';
    final access = controller.readAccessEpoch;
    final reason = await showOperationalReadDialog<String>(
      context,
      controller,
      (context) => AlertDialog(
        title: Text('$verb count'),
        content: TextField(
          onChanged: (value) => input = value,
          maxLength: 1000,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (reason != null && controller.currentRead(access)) {
      await controller.act(verb, note: reason);
    }
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
          maxLength: max,
          enabled: c.editable,
          decoration: InputDecoration(labelText: label),
          onChanged: (v) => c.update(key, v),
        ),
      );
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Stock counts',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Capture a cutoff, record physical quantities and post independently approved variances.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Capture stock first, then count quantities by product, lot or serial identity.',
          ),
          if (c.busy) const LinearProgressIndicator(),
          if (!c.online)
            const Text(
              'Offline — save locally; server actions require a connection.',
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
          if (c.partitionPending) ...[
            const Text(
              'A shared cutoff capture awaits confirmation. Retry preserves the saved request; editing is locked.',
            ),
            FilledButton(
              onPressed: c.busy || !c.online ? null : c.capturePartitions,
              child: const Text('Retry shared cutoff capture'),
            ),
          ],
          if (c.partitionProgress case final progress?)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Shared cutoff ${progress.cutoff.toIso8601String()}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    SelectableText('Group ${progress.id}'),
                    Text(
                      'Captured ${progress.capturedIdentities} of ${progress.expectedIdentities} identities in ${progress.capturedPartitions} of ${progress.expectedPartitions} partitions',
                    ),
                    Text(
                      'Posted ${progress.postedPartitions} of ${progress.expectedPartitions} · Cancelled ${progress.cancelledPartitions}',
                    ),
                    Text(
                      'Baseline ${progress.baseline} · Counted ${progress.counted} · Variance ${progress.variance} · Approval value ${progress.approvalValue}',
                    ),
                    Text(
                      progress.postingComplete
                          ? 'Posting complete for every partition.'
                          : 'Posting incomplete. Every partition requires its own count and approval.',
                    ),
                    if (!progress.captureComplete)
                      Text(
                        'Capture incomplete · Missing partitions ${progress.missingOrdinals.join(', ')}',
                      ),
                    for (final row in progress.items)
                      ListTile(
                        title: Text(
                          'Partition ${row['partition_ordinal']} · ${row['status']} · ${row['identity_count']} identities',
                        ),
                        subtitle: Text(
                          'Variance ${row['variance_quantity']} · Approval value ${row['grand_total']}',
                        ),
                        trailing: TextButton(
                          onPressed: c.busy || !c.online || f != null
                              ? null
                              : () => c.open(row),
                          child: const Text('Open count'),
                        ),
                      ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: c.busy || !c.online
                              ? null
                              : c.refreshPartitions,
                          child: const Text('Refresh group progress'),
                        ),
                        TextButton(
                          onPressed: c.busy ? null : c.closePartitions,
                          child: const Text('Close group view'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (c.partitionProgress == null &&
              c.partitionLocal?.form['confirmed_group_id'] != null)
            Text(
              'Saved count group ${c.partitionLocal!.form['confirmed_group_id']} · Connect and refresh to verify current progress.',
            ),
          if (f == null) ...[
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (c.canManage)
                  FilledButton(
                    onPressed: c.busy ? null : c.create,
                    child: const Text('New count'),
                  ),
                OutlinedButton(
                  onPressed: c.busy || !c.online ? null : c.refresh,
                  child: const Text('Refresh'),
                ),
              ],
            ),
            if (c.items.isEmpty && !c.busy && c.partitionProgress == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No counts in this branch.'),
              ),
            for (final row in c.items)
              Card(
                child: ListTile(
                  title: Text(
                    '${row['document_number'] ?? 'Draft count'} · ${row['status']}',
                  ),
                  subtitle: Text(
                    '${row['warehouse_name']} · ${row['document_date']} · ${row['currency_code']} ${row['grand_total']} absolute variance',
                  ),
                  onTap: c.busy ? null : () => c.open(row),
                ),
              ),
            if (c.cursor != null)
              OutlinedButton(
                onPressed: c.busy || !c.online
                    ? null
                    : () => c.refresh(more: true),
                child: const Text('Load more counts'),
              ),
          ] else ...[
            Text(
              '${f['document_number'] ?? 'New count'} · ${f['status']}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (f['cutoff_at'] != null)
              Text('Cutoff ${f['cutoff_at']} · Version ${f['version']}'),
            if (f['corrects_count_id'] != null)
              SelectableText('Corrects count ${f['corrects_count_id']}'),
            if (c.local?.pending != null)
              const Text(
                'A saved command awaits confirmation. Retry retains its identity and approved version.',
              ),
            const SizedBox(height: 16),
            field('document_date', 'Posting date (YYYY-MM-DD)'),
            field('reason', 'Count reason', max: 1000),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed:
                      !c.editable ||
                          !c.online ||
                          f['version'] != null ||
                          (f['lines'] as List).isNotEmpty
                      ? null
                      : () => pick(context, 'warehouses', (w) {
                          c.update('warehouse_id', w['id']);
                          c.update('_warehouse_name', w['name']);
                        }),
                  child: Text(
                    'Warehouse: ${f['_warehouse_name'] ?? f['warehouse_name'] ?? f['warehouse_id'] ?? 'Select'}',
                  ),
                ),
                OutlinedButton(
                  onPressed: !c.editable || !c.online
                      ? null
                      : () => pick(context, 'accounts', (a) {
                          c.update('offset_account_id', a['id']);
                          c.update('_account_name', a['name']);
                        }),
                  child: Text(
                    'Variance account: ${f['_account_name'] ?? f['offset_account_name'] ?? f['offset_account_id'] ?? 'Select'}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (f['version'] == null)
              const Text(
                'Select products, then capture the cutoff before entering counted quantities.',
              ),
            for (var i = 0; i < (f['lines'] as List).length; i++)
              _line(context, i, (f['lines'] as List)[i] as Map),
            if (f['version'] == null)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed:
                      !c.editable || !c.online || f['warehouse_id'] == null
                      ? null
                      : () => pick(context, 'products', c.addProduct),
                  child: const Text('Add product'),
                ),
              ),
            if (f['grand_total'] != null)
              Text(
                'Absolute variance for approval: ${f['currency_code']} ${f['grand_total']}',
              ),
            if (f['version'] != null && f['grand_total'] == null)
              OutlinedButton(
                onPressed: c.canReloadEvidence ? c.reloadEvidence : null,
                child: const Text('Reload permitted value evidence'),
              ),
            if (f['_dirty'] == true)
              const Text('Local changes are not yet saved to the server.'),
            if (f['journal_entry_id'] != null)
              SelectableText('Journal ${f['journal_entry_id']}'),
            if (f['stock_movement_id'] != null)
              SelectableText('Stock movement ${f['stock_movement_id']}'),
            const SizedBox(height: 20),
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
                  if (c.canManage && f['status'] == 'posted')
                    FilledButton(
                      onPressed: c.busy || !c.online ? null : c.correct,
                      child: const Text('New linked correction'),
                    ),
                  if (c.editable)
                    FilledButton(
                      onPressed: !c.online ? null : () => c.act('save'),
                      child: Text(
                        f['version'] == null ? 'Capture cutoff' : 'Save count',
                      ),
                    ),
                  if (c.editable &&
                      f['version'] == null &&
                      c.partitionGateway != null &&
                      (f['lines'] as List).length == 1)
                    OutlinedButton(
                      onPressed: !c.online ? null : c.capturePartitions,
                      child: const Text(
                        'Capture tracked identities in partitions',
                      ),
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
                      child: const Text('Approve count'),
                    ),
                    OutlinedButton(
                      onPressed: c.busy || !c.online
                          ? null
                          : () => action(context, 'reject'),
                      child: const Text('Reject count'),
                    ),
                  ],
                  if (c.canManage && f['status'] == 'approved')
                    FilledButton(
                      onPressed: c.busy || !c.online
                          ? null
                          : () => action(context, 'post'),
                      child: const Text('Post approved adjustment'),
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
                      child: const Text('Cancel count'),
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
              '${line['product_name']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (line['baseline_quantity'] != null)
              Text('Cutoff balance: ${line['baseline_quantity']} base units'),
            const SizedBox(height: 12),
            if (line['identities'] is List) ...[
              Text(
                'Counted total: ${line['counted_quantity'] == '' ? 'Complete identity quantities' : line['counted_quantity']} base units',
              ),
              for (
                var identityIndex = 0;
                identityIndex < (line['identities'] as List).length;
                identityIndex++
              )
                _identity(
                  context,
                  i,
                  identityIndex,
                  line,
                  (line['identities'] as List)[identityIndex] as Map,
                ),
            ] else
              TextFormField(
                key: ValueKey('${line['line_id']}-${c.form?['version']}-count'),
                initialValue: line['counted_quantity'] as String,
                enabled: c.editable && c.form?['version'] != null,
                decoration: const InputDecoration(
                  labelText: 'Counted quantity in base units',
                ),
                onChanged: (v) => c.updateLine(i, 'counted_quantity', v),
              ),
            const SizedBox(height: 12),
            TextFormField(
              key: ValueKey('${line['line_id']}-${c.form?['version']}-cost'),
              initialValue: line['empty_unit_cost'] as String,
              enabled: c.editable && c.form?['version'] != null,
              decoration: const InputDecoration(
                labelText:
                    'Unit cost for a positive adjustment into empty stock',
              ),
              onChanged: (v) => c.updateLine(i, 'empty_unit_cost', v),
            ),
            if (line['variance_quantity'] != null)
              Text(
                'Saved variance: ${line['variance_quantity']} units'
                '${line['variance_value'] == null ? '' : ' · ${line['variance_value']} value'}',
              ),
            if (c.form?['version'] == null)
              TextButton(
                onPressed: c.locked
                    ? null
                    : () => c.update(
                        'lines',
                        [...c.form!['lines'] as List]..removeAt(i),
                      ),
                child: const Text('Remove product'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _identity(
    BuildContext context,
    int lineIndex,
    int identityIndex,
    Map line,
    Map identity,
  ) {
    final c = controller;
    final editable = c.editable && c.form?['version'] != null;
    final label =
        '${identity['code']} · cutoff ${identity['baseline_quantity']} · ${identity['disposition']}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: line['tracking_mode'] == 'serial'
          ? CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(label),
              subtitle: const Text('Present at the count cutoff'),
              value:
                  identity['counted_quantity'] == '1' ||
                  identity['counted_quantity'] == '1.000000',
              onChanged: editable
                  ? (present) => c.updateIdentity(
                      lineIndex,
                      identityIndex,
                      present == true ? '1' : '0',
                    )
                  : null,
            )
          : TextFormField(
              key: ValueKey(
                '${line['line_id']}-${identity['id']}-${c.form?['version']}',
              ),
              initialValue: identity['counted_quantity'] as String,
              enabled: editable,
              decoration: InputDecoration(labelText: label),
              onChanged: (value) =>
                  c.updateIdentity(lineIndex, identityIndex, value),
            ),
    );
  }
}

class _CountPicker extends StatefulWidget {
  const _CountPicker({required this.controller, required this.resource});
  final StockCountController controller;
  final String resource;
  @override
  State<_CountPicker> createState() => _CountPickerState();
}

class _CountPickerState extends State<_CountPicker> {
  List<Map<String, Object?>> rows = [];
  String? cursor, error;
  String search = '';
  bool busy = false;
  late int accessEpoch;
  @override
  void initState() {
    super.initState();
    accessEpoch = widget.controller.readAccessEpoch;
    load();
  }

  Future<void> load({bool more = false}) async {
    if (busy || !widget.controller.currentRead(accessEpoch)) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final c = widget.controller;
      final r = await c.gateway.options(
        c.scope,
        widget.resource,
        warehouse: c.form?['warehouse_id'] as String?,
        after: more ? cursor : null,
        search: search,
      );
      if (!mounted || !widget.controller.currentRead(accessEpoch)) return;
      setState(() {
        rows = [
          if (more) ...rows,
          for (final raw in r['items'] as List)
            (raw as Map).cast<String, Object?>(),
        ];
        cursor = r['next_cursor'] as String?;
      });
    } catch (failure) {
      if (mounted && widget.controller.currentRead(accessEpoch)) {
        if (failure is DomainError &&
            const {
              'PERMISSION_DENIED',
              'ACCESS_DENIED',
              'MFA_REQUIRED',
              'AUTHENTICATION_REQUIRED',
            }.contains(failure.code)) {
          widget.controller.denyReadAccess();
          return;
        }
        setState(() => error = 'Unable to load choices. Retry when connected.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Select ${widget.resource}'),
    content: SizedBox(
      width: 540,
      height: 420,
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(labelText: 'Search'),
            maxLength: 100,
            onChanged: (v) => search = v,
            onSubmitted: (_) => load(),
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          Expanded(
            child: ListView(
              children: [
                for (final row in rows)
                  ListTile(
                    title: Text('${row['name']}'),
                    subtitle: Text(
                      '${row['on_hand_quantity'] ?? row['code'] ?? row['sku'] ?? ''}',
                    ),
                    onTap: busy
                        ? null
                        : () {
                            if (widget.controller.currentRead(accessEpoch)) {
                              Navigator.pop(context, row);
                            }
                          },
                  ),
                if (rows.isEmpty && !busy) const Text('No eligible choices.'),
              ],
            ),
          ),
          Wrap(
            children: [
              TextButton(
                onPressed: busy ? null : () => load(),
                child: const Text('Search / retry'),
              ),
              if (cursor != null)
                TextButton(
                  onPressed: busy ? null : () => load(more: true),
                  child: const Text('Load more'),
                ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app_providers.dart';
import 'purchase_order_controller.dart';
import 'procurement_picker.dart';
import 'sourcing_screen.dart' show sourcingReason;

class PurchaseOrderScreen extends ConsumerWidget {
  const PurchaseOrderScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(businessCapabilitiesProvider);
    if (caps.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (caps.hasError) {
      return Center(
        child: TextButton(
          onPressed: () => ref.invalidate(businessCapabilitiesProvider),
          child: const Text('Retry access check'),
        ),
      );
    }
    final c = ref.watch(purchaseOrderControllerProvider);
    if (c == null) {
      return const Center(
        child: Text('Choose a business scope with purchase-order permission.'),
      );
    }
    return PurchaseOrderWorkspace(key: ValueKey(c), controller: c);
  }
}

class PurchaseOrderWorkspace extends StatelessWidget {
  const PurchaseOrderWorkspace({super.key, required this.controller});
  final PurchaseOrderController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Purchase orders',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Supplier commitments, source traceability and approved revisions',
            ),
            const SizedBox(height: 16),
            if (c.busy) const LinearProgressIndicator(),
            if (!c.online)
              const Text('Offline · save your work securely on this device.'),
            if (c.error != null)
              Text(
                c.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (c.message != null) Text(c.message!),
            const SizedBox(height: 16),
            if (c.form == null) ...[
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: c.busy || !c.online
                        ? null
                        : () async {
                            final source = await pickSourcingReference(
                              context,
                              c.references,
                              c.scope,
                              'selected_rfqs',
                            );
                            if (source != null) {
                              await c.create(
                                (source['detail'] as Map)
                                    .cast<String, Object?>(),
                              );
                            }
                          },
                    icon: const Icon(Icons.add),
                    label: const Text('Create from selected quotation'),
                  ),
                  OutlinedButton(
                    onPressed: c.busy || !c.online
                        ? null
                        : () async {
                            final source = await pickSourcingReference(
                              context,
                              c.references,
                              c.scope,
                              'requisitions',
                            );
                            if (source != null) {
                              await c.createFromRequisition(
                                (source['detail'] as Map)
                                    .cast<String, Object?>(),
                              );
                            }
                          },
                    child: const Text('Create from approved requisition'),
                  ),
                  OutlinedButton(
                    onPressed: c.busy || !c.online ? null : c.refresh,
                    child: const Text('Refresh'),
                  ),
                  TextButton(
                    onPressed: () => context.go('/procurement'),
                    child: const Text('Procurement'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (c.page.items.isEmpty && !c.busy)
                const Text('No purchase orders loaded.'),
              for (final row in c.page.items)
                Card(
                  child: ListTile(
                    title: Text(
                      '${row['document_number'] ?? 'Draft order'} · ${row['status']}',
                    ),
                    subtitle: Text(
                      '${row['currency_code']} ${row['total']} · revision ${row['revision']} · promised ${row['promised_date']}',
                    ),
                    onTap: c.busy ? null : () => c.select(row),
                  ),
                ),
              if (c.page.nextCursor != null)
                TextButton(
                  onPressed: c.busy ? null : () => c.refresh(more: true),
                  child: const Text('Load more'),
                ),
              if (c.selected != null) _OrderDetail(controller: c),
            ] else
              _OrderEditor(
                key: ValueKey((c.form!['id'], c.version)),
                controller: c,
              ),
          ],
        ),
      );
    },
  );
}

class _OrderDetail extends StatelessWidget {
  const _OrderDetail({required this.controller});
  final PurchaseOrderController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller, r = c.selected!;
    Future<void> action(String verb) async {
      String? reason;
      if (['revise', 'recall', 'cancel', 'reject'].contains(verb)) {
        reason = await sourcingReason(
          context,
          '${verb[0].toUpperCase()}${verb.substring(1)} purchase order',
        );
        if (reason == null || reason.isEmpty) {
          return;
        }
      }
      await c.transition(verb, reason: reason);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${r['document_number'] ?? 'Draft'} · ${r['status']} · revision ${r['revision']}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'Source ${(r['source_snapshot'] as Map?)?['document_number'] ?? r['source_rfq_id'] ?? r['source_requisition_id']}',
            ),
            Text(
              'Payment: ${r['payment_terms']} · Delivery: ${r['delivery_terms']}',
            ),
            Text(
              'Currency ${r['currency_code']} · Rate ${r['exchange_rate']} · Base total ${r['base_total']}',
            ),
            if (r['revision_reason'] != null)
              Text('Revision reason: ${r['revision_reason']}'),
            const SizedBox(height: 16),
            for (final line in (r['lines'] as List))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${line['description']} · ${line['quantity']} × ${line['unit_price']} · Total ${line['line_total']}',
                    ),
                    Text(
                      'Received ${line['received_quantity']} · Billed ${line['billed_quantity']} · Cancelled ${line['cancelled_quantity']} · Remaining ${line['remaining_quantity']}',
                    ),
                    SelectableText(
                      'Source line ${line['source_line_id']}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (r['status'] == 'draft') ...[
                  OutlinedButton(
                    onPressed: c.busy ? null : () => c.edit(r),
                    child: const Text('Edit draft'),
                  ),
                  FilledButton(
                    onPressed: c.busy || !c.online
                        ? null
                        : () => action('submit'),
                    child: const Text('Submit for approval'),
                  ),
                ],
                if (r['status'] == 'pending_approval' &&
                    c.canApprove &&
                    !c.ownOrder) ...[
                  FilledButton(
                    onPressed: c.busy || !c.online
                        ? null
                        : () => action('approve'),
                    child: const Text('Approve'),
                  ),
                  OutlinedButton(
                    onPressed: c.busy || !c.online
                        ? null
                        : () => action('reject'),
                    child: const Text('Reject with reason'),
                  ),
                ],
                if (['pending_approval', 'rejected'].contains(r['status']))
                  OutlinedButton(
                    onPressed: c.busy || !c.online
                        ? null
                        : () => action('recall'),
                    child: const Text('Recall to draft'),
                  ),
                if (r['status'] == 'approved')
                  FilledButton(
                    onPressed: c.busy || !c.online
                        ? null
                        : () => action('revise'),
                    child: const Text('Create revision'),
                  ),
                if (!['cancelled', 'closed'].contains(r['status']))
                  TextButton(
                    onPressed: c.busy || !c.online
                        ? null
                        : () => action('cancel'),
                    child: const Text('Cancel remaining order'),
                  ),
              ],
            ),
            if (r['status'] == 'pending_approval' && c.ownOrder)
              const Text('An independent approver must decide this order.'),
          ],
        ),
      ),
    );
  }
}

class _OrderEditor extends StatelessWidget {
  const _OrderEditor({super.key, required this.controller});
  final PurchaseOrderController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller, f = c.form!;
    final editable =
        !c.locked && (f['status'] == null || f['status'] == 'draft');
    Widget field(String key, String label) => TextFormField(
      initialValue: '${f[key] ?? ''}',
      enabled: editable,
      decoration: InputDecoration(labelText: label),
      onChanged: (v) => c.update(key, v),
    );
    Future<Map<String, Object?>?> pick(String resource) =>
        pickSourcingReference(context, c.references, c.scope, resource);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          f['status'] == null
              ? 'Create purchase order'
              : 'Purchase order · ${f['status']} · revision ${f['revision']}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        if (f['_source_number'] != null) ...[
          Text('Source ${f['_source_number']} · ${f['_supplier_name']}'),
          if (f['_source_total'] != null)
            Text('Selected quotation ${f['_source_total']}'),
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(width: 250, child: field('document_date', 'Order date')),
            SizedBox(
              width: 250,
              child: field('promised_date', 'Promised date'),
            ),
            OutlinedButton(
              onPressed: !editable || !c.online
                  ? null
                  : () async {
                      final row = await pick('warehouses');
                      if (row == null || !editable) {
                        return;
                      }
                      c.update('warehouse_id', row['id']);
                      c.update('_warehouse_name', row['name']);
                    },
              child: Text(
                '${f['_warehouse_name'] ?? (f['warehouse_id'] == null ? 'Choose receiving warehouse' : 'Change receiving warehouse')}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (f['lines'] case final List lines) ...[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton(
                onPressed: !editable || !c.online
                    ? null
                    : () async {
                        final row = await pick('suppliers');
                        if (row != null) {
                          c.update('supplier_id', row['id']);
                          c.update('_supplier_name', row['name']);
                        }
                      },
                child: Text('${f['_supplier_name'] ?? 'Change supplier'}'),
              ),
              OutlinedButton(
                onPressed: !editable || !c.online
                    ? null
                    : () async {
                        final row = await pick('rates');
                        if (row == null) {
                          return;
                        }
                        for (final key in [
                          'currency_code',
                          'exchange_rate',
                          'rate_date',
                        ]) {
                          c.update(key, row[key]);
                        }
                        c.update('exchange_rate_id', row['id']);
                      },
                child: const Text('Choose governed FX rate'),
              ),
              TextButton(
                onPressed: !editable || !c.online ? null : c.useBaseCurrency,
                child: const Text('Use base currency'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Currency ${f['currency_code']} · Rate ${f['exchange_rate']} · ${f['rate_date']}',
          ),
          const SizedBox(height: 16),
          field('payment_terms', 'Payment terms'),
          const SizedBox(height: 16),
          field('delivery_terms', 'Delivery terms'),
          const SizedBox(height: 16),
          for (var i = 0; i < lines.length; i++)
            Builder(
              builder: (context) {
                final line = (lines[i] as Map).cast<String, Object?>();
                void change(String key, Object? value) {
                  if (c.locked || c.form?['id'] != f['id']) return;
                  final fresh = List<Object?>.from(c.form!['lines'] as List);
                  if (i >= fresh.length ||
                      (fresh[i] as Map)['line_id'] != line['line_id']) {
                    return;
                  }
                  fresh[i] = {
                    ...(fresh[i] as Map).cast<String, Object?>(),
                    key: value,
                  };
                  c.update('lines', fresh);
                }

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${line['description']}'),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            for (final entry in const {
                              'quantity': 'Quantity',
                              'unit_price': 'Unit price',
                              'discount_percent': 'Discount %',
                            }.entries)
                              SizedBox(
                                width: 230,
                                child: TextFormField(
                                  initialValue: '${line[entry.key]}',
                                  enabled: editable,
                                  decoration: InputDecoration(
                                    labelText: entry.value,
                                  ),
                                  onChanged: (v) => change(entry.key, v),
                                ),
                              ),
                            OutlinedButton(
                              onPressed: !editable || !c.online
                                  ? null
                                  : () async {
                                      final row = await pick('taxes');
                                      if (row != null) {
                                        change('tax_definition_id', row['id']);
                                        change('_tax_name', row['name']);
                                      }
                                    },
                              child: Text(
                                '${line['_tax_name'] ?? 'Choose input tax'}',
                              ),
                            ),
                            if (line['tax_definition_id'] != null)
                              TextButton(
                                onPressed: !editable
                                    ? null
                                    : () {
                                        change('tax_definition_id', null);
                                        change('_tax_name', null);
                                      },
                                child: const Text('No tax'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Received ${line['received_quantity']} · Billed ${line['billed_quantity']}',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ] else
          for (final line in f['_source_lines'] as List? ?? [])
            Text(
              '${line['description']} · ${line['quantity']} × ${line['unit_price']} · ${line['line_total']}',
            ),
        const SizedBox(height: 20),
        if (c.local?.pending != null)
          const Text(
            'A saved command needs confirmation. Retry preserves its original IDs and exact inputs.',
          ),
        if (c.local?.errorCode == 'VERSION_CONFLICT')
          const Text(
            'This order changed. Compare the current revision before discarding this local edit and refreshing.',
          ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton(
              onPressed:
                  c.busy ||
                      !c.online ||
                      c.local?.errorCode == 'VERSION_CONFLICT'
                  ? null
                  : c.saveServer,
              child: Text(
                c.local?.pending != null
                    ? 'Retry saved command'
                    : 'Save to server',
              ),
            ),
            OutlinedButton(
              onPressed: editable ? c.saveLocal : null,
              child: const Text('Save on this device'),
            ),
            TextButton(
              onPressed: c.busy || c.local?.pending != null
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Discard local order draft?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Keep editing'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Discard'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await c.discard();
                      }
                    },
              child: const Text('Discard local draft'),
            ),
          ],
        ),
      ],
    );
  }
}

import '../operations/access_changed.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:jentra_domain/jentra_procurement.dart';

import '../../app_providers.dart';
import 'procurement_controller.dart';
import 'conflict_comparison.dart';
import 'procurement_picker.dart';
import '../operations/operational_read_access.dart';

class ProcurementScreen extends ConsumerWidget {
  const ProcurementScreen({super.key});
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
    final scope = ref.watch(activeTenantContextProvider);
    if (scope == null || !scope.hasOperationalScope) {
      return const Center(child: Text('Choose a legal entity and branch.'));
    }
    if (!(caps.value?.contains('procurement.requisitions.manage') ?? false)) {
      final destinations = <(String, String)>[
        if (caps.value?.contains('procurement.returns.post') ?? false)
          ('returns', 'Purchase returns'),
        if ([
          'finance.payments.manage',
          'finance.payments.post',
          'finance.payments.allocate',
          'finance.payments.reverse',
        ].any((p) => caps.value?.contains(p) ?? false))
          ('payments', 'Supplier payments'),
        if ([
          'procurement.bills.view',
          'procurement.bills.manage',
          'procurement.bills.post',
        ].any((p) => caps.value?.contains(p) ?? false))
          ('bills', 'Supplier bills'),
        if (caps.value?.contains('procurement.receipts.post') ?? false)
          ('receipts', 'Goods receipts'),
        if (caps.value?.contains('procurement.orders.manage') ?? false)
          ('orders', 'Purchase orders'),
        if (caps.value?.contains('procurement.rfq.manage') ?? false)
          ('sourcing', 'Supplier sourcing'),
        if (caps.value?.contains('inventory.catalog.manage') ?? false)
          ('units', 'Product units'),
      ];
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              if (destinations.isEmpty)
                const Text(
                  'Your role has no procurement workspace permission.',
                ),
              for (final destination in destinations)
                FilledButton(
                  onPressed: () => context.go('/procurement/${destination.$1}'),
                  child: Text(destination.$2),
                ),
            ],
          ),
        ),
      );
    }
    final controller = ref.watch(procurementControllerProvider);
    if (controller == null) {
      return const Center(
        child: Text('Connect to your workspace to open procurement.'),
      );
    }
    return ProcurementWorkspace(
      key: ValueKey(controller),
      controller: controller,
      canSource: caps.value?.contains('procurement.rfq.manage') ?? false,
      canOrder: caps.value?.contains('procurement.orders.manage') ?? false,
      canManageUnits: caps.value?.contains('inventory.catalog.manage') ?? false,
      canReceive: caps.value?.contains('procurement.receipts.post') ?? false,
      canReturn: caps.value?.contains('procurement.returns.post') ?? false,
      canPay: [
        'finance.payments.manage',
        'finance.payments.post',
        'finance.payments.allocate',
        'finance.payments.reverse',
      ].any((p) => caps.value?.contains(p) ?? false),
      canBill: [
        'procurement.bills.view',
        'procurement.bills.manage',
        'procurement.bills.post',
      ].any((p) => caps.value?.contains(p) ?? false),
    );
  }
}

class ProcurementWorkspace extends StatelessWidget {
  const ProcurementWorkspace({
    super.key,
    required this.controller,
    this.canSource = false,
    this.canOrder = false,
    this.canManageUnits = false,
    this.canReceive = false,
    this.canBill = false,
    this.canPay = false,
    this.canReturn = false,
  });
  final ProcurementController controller;
  final bool canSource;
  final bool canOrder;
  final bool canManageUnits;
  final bool canReceive;
  final bool canBill;
  final bool canPay;
  final bool canReturn;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      if (c.accessDenied) {
        return OperationalAccessChanged(
          retry: c.initialize,
          enabled: c.online && !c.busy,
        );
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Procurement',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Purchase requisitions · record needs and exact estimates',
            ),
            const SizedBox(height: 16),
            if (!c.online)
              const Text(
                'Offline · drafts can be saved securely on this device.',
              ),
            if (c.busy) const LinearProgressIndicator(),
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  c.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (c.message != null) Text(c.message!),
            if (c.form == null) ...[
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: c.busy || c.baseCurrency == null
                        ? null
                        : () => c.create(c.baseCurrency!),
                    icon: const Icon(Icons.add),
                    label: const Text('New requisition'),
                  ),
                  OutlinedButton(
                    onPressed: c.busy || !c.online ? null : c.refresh,
                    child: const Text('Refresh'),
                  ),
                  if (canSource)
                    TextButton(
                      onPressed: c.busy
                          ? null
                          : () => context.go('/procurement/sourcing'),
                      child: const Text('Supplier sourcing'),
                    ),
                  if (canOrder)
                    TextButton(
                      onPressed: c.busy
                          ? null
                          : () => context.go('/procurement/orders'),
                      child: const Text('Purchase orders'),
                    ),
                  if (canReceive)
                    TextButton(
                      onPressed: c.busy
                          ? null
                          : () => context.go('/procurement/receipts'),
                      child: const Text('Goods receipts'),
                    ),
                  if (canBill)
                    TextButton(
                      onPressed: c.busy
                          ? null
                          : () => context.go('/procurement/bills'),
                      child: const Text('Supplier bills'),
                    ),
                  if (canPay)
                    TextButton(
                      onPressed: c.busy
                          ? null
                          : () => context.go('/procurement/payments'),
                      child: const Text('Supplier payments'),
                    ),
                  if (canReturn)
                    TextButton(
                      onPressed: c.busy
                          ? null
                          : () => context.go('/procurement/returns'),
                      child: const Text('Purchase returns'),
                    ),
                  if (canManageUnits)
                    TextButton(
                      onPressed: c.busy
                          ? null
                          : () => context.go('/procurement/units'),
                      child: const Text('Product units'),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              if (c.page.items.isEmpty && !c.busy)
                const Text(
                  'No requisitions loaded. Create a requisition or refresh the register.',
                ),
              for (final document in c.page.items)
                Card(
                  child: ListTile(
                    title: Text('${document['justification']}'),
                    subtitle: Text(
                      '${document['status']} · Needed ${document['need_by']} · ${document['currency_code']} ${document['estimated_total']} · v${document['version']}',
                    ),
                    onTap: c.busy ? null : () => c.select(document),
                    trailing: document['status'] == 'draft'
                        ? TextButton(
                            onPressed: c.busy ? null : () => c.edit(document),
                            child: const Text('Edit'),
                          )
                        : null,
                  ),
                ),
              if (c.page.nextCursor != null)
                TextButton(
                  onPressed: c.busy ? null : () => c.refresh(more: true),
                  child: const Text('Load more'),
                ),
              if (c.selected != null) _RequisitionDetail(controller: c),
            ] else
              _RequisitionEditor(key: ValueKey(c.form!['id']), controller: c),
          ],
        ),
      );
    },
  );
}

class _RequisitionDetail extends StatelessWidget {
  const _RequisitionDetail({required this.controller});
  final ProcurementController controller;
  Future<void> action(BuildContext context, String verb) async {
    final epoch = controller.readAccessEpoch;
    if (!controller.currentRead(epoch)) return;
    String? reason;
    if (['recall', 'cancel', 'reject'].contains(verb)) {
      final input = TextEditingController();
      reason = await showOperationalReadDialog<String>(
        context,
        controller,
        (context) => AlertDialog(
          title: Text(
            '${verb[0].toUpperCase()}${verb.substring(1)} requisition',
          ),
          content: TextField(
            controller: input,
            autofocus: true,
            maxLength: 1000,
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Keep document'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, input.text.trim()),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      // Let the dialog finish disposing its field before disposing the controller.
      WidgetsBinding.instance.addPostFrameCallback((_) => input.dispose());
      if (reason == null || reason.isEmpty) return;
    }
    if (!context.mounted || !controller.currentRead(epoch)) return;
    await controller.transition(verb, reason: reason);
  }

  @override
  Widget build(BuildContext context) {
    final c = controller, doc = controller.selected!;
    final status = doc['status'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${doc['document_number'] ?? 'Unnumbered draft'} · $status',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text('${doc['justification']}'),
            Text(
              'Need by ${doc['need_by']} · ${doc['currency_code']} ${doc['estimated_total']}',
            ),
            for (final line in (doc['lines'] as List? ?? []))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '${(line as Map)['description']} · ${line['quantity']} × ${line['estimated_unit_price']} = ${line['estimated_total']}',
                ),
              ),
            if (status == 'pending_approval')
              const Text(
                'Awaiting the configured approval. Material fields are frozen.',
              ),
            if (status == 'approved') const Text('Approved for sourcing.'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (status == 'draft')
                  FilledButton(
                    onPressed: c.busy || !c.online
                        ? null
                        : () => action(context, 'submit'),
                    child: const Text('Submit for approval'),
                  ),
                if (c.canDecide) ...[
                  FilledButton(
                    onPressed: c.busy || !c.online
                        ? null
                        : () => action(context, 'approve'),
                    child: const Text('Approve'),
                  ),
                  OutlinedButton(
                    onPressed: c.busy || !c.online
                        ? null
                        : () => action(context, 'reject'),
                    child: const Text('Reject'),
                  ),
                ],
                if (['pending_approval', 'rejected'].contains(status))
                  OutlinedButton(
                    onPressed: c.busy || !c.online
                        ? null
                        : () => action(context, 'recall'),
                    child: const Text('Recall to draft'),
                  ),
                if (['draft', 'pending_approval', 'rejected'].contains(status))
                  TextButton(
                    onPressed: c.busy || !c.online
                        ? null
                        : () => action(context, 'cancel'),
                    child: const Text('Cancel requisition'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RequisitionEditor extends StatelessWidget {
  const _RequisitionEditor({super.key, required this.controller});
  final ProcurementController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller, form = controller.form!;
    final lines = (form['lines'] as List)
        .map((l) => (l as Map).cast<String, Object?>())
        .toList();
    String estimate() {
      try {
        var total = ExactDecimal.zero(scale: 6);
        for (final line in lines) {
          total = total + ProcurementLine.fromJson(line).estimatedTotal;
        }
        return '${form['currency_code']} ${total.toDecimalString()}';
      } on FormatException {
        return 'Complete the item values to calculate an estimate.';
      }
    }

    Widget field(String key, String label, {int maxLines = 1}) => TextFormField(
      initialValue: '${form[key] ?? ''}',
      enabled: !c.locked,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
      onChanged: (value) => c.update(key, value),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          c.version == null
              ? 'New purchase requisition'
              : 'Edit requisition · v${c.version}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(width: 250, child: field('need_by', 'Need-by date')),
            SizedBox(
              width: 250,
              child: field('currency_code', 'Base currency'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        field('justification', 'Why is this purchase needed?', maxLines: 3),
        const SizedBox(height: 24),
        Text('Requested items', style: Theme.of(context).textTheme.titleMedium),
        for (var index = 0; index < lines.length; index++)
          Padding(
            key: ValueKey(lines[index]['line_id']),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextFormField(
                      key: ValueKey((
                        lines[index]['line_id'],
                        lines[index]['product_id'],
                      )),
                      initialValue: '${lines[index]['description'] ?? ''}',
                      enabled: !c.locked,
                      decoration: InputDecoration(
                        labelText: 'Item ${index + 1} description',
                      ),
                      onChanged: (v) {
                        lines[index] = {...lines[index], 'description': v};
                        c.update('lines', lines);
                      },
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: c.locked || !c.online
                            ? null
                            : () async {
                                final product = await pickProcurementReference(
                                  context,
                                  c,
                                  'products',
                                );
                                if (product == null || c.locked) return;
                                lines[index] = {
                                  ...lines[index],
                                  'product_id': product['id'],
                                  'description': product['name'],
                                  'unit_id': product['unit_id'],
                                  'unit_label': null,
                                  'conversion_numerator': '1',
                                  'conversion_denominator': '1',
                                };
                                c.update('lines', lines);
                              },
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: Text(
                          lines[index]['product_id'] == null
                              ? 'Choose catalogue product (optional)'
                              : 'Change catalogue product',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: 220,
                          child: OutlinedButton(
                            onPressed: c.locked || !c.online
                                ? null
                                : () async {
                                    final unit = await pickProcurementReference(
                                      context,
                                      c,
                                      lines[index]['product_id'] == null
                                          ? 'units'
                                          : 'product_units:${lines[index]['product_id']}',
                                    );
                                    if (unit == null || c.locked) return;
                                    lines[index] = {
                                      ...lines[index],
                                      'unit_id': unit['id'],
                                      'conversion_numerator':
                                          unit['conversion_numerator'] ?? '1',
                                      'conversion_denominator':
                                          unit['conversion_denominator'] ?? '1',
                                      'unit_label':
                                          '${unit['code']} · ${unit['name']}',
                                    };
                                    c.update('lines', lines);
                                  },
                            child: Text(
                              '${lines[index]['unit_label'] ?? c.units.where((u) => u['id'] == lines[index]['unit_id']).map((u) => u['name']).firstOrNull ?? (lines[index]['unit_id'] == null ? 'Choose unit' : 'Selected unit')}',
                            ),
                          ),
                        ),
                        for (final entry in const {
                          'quantity': 'Quantity',
                          'estimated_unit_price': 'Unit estimate',
                        }.entries)
                          SizedBox(
                            width: 220,
                            child: TextFormField(
                              initialValue: '${lines[index][entry.key] ?? ''}',
                              enabled: !c.locked,
                              decoration: InputDecoration(
                                labelText: entry.value,
                              ),
                              onChanged: (v) {
                                lines[index] = {...lines[index], entry.key: v};
                                c.update('lines', lines);
                              },
                            ),
                          ),
                        IconButton(
                          tooltip: 'Remove item ${index + 1}',
                          onPressed: c.locked
                              ? null
                              : () {
                                  lines.removeAt(index);
                                  c.update('lines', lines);
                                },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        TextButton.icon(
          onPressed: c.locked || lines.length >= 500
              ? null
              : () => c.update('lines', [
                  ...lines,
                  {
                    'line_id': const Uuid().v4(),
                    'description': '',
                    'quantity': '1',
                    'estimated_unit_price': '0',
                    'unit_id': null,
                    'conversion_numerator': '1',
                    'conversion_denominator': '1',
                  },
                ]),
          icon: const Icon(Icons.add),
          label: const Text('Add item'),
        ),
        const SizedBox(height: 24),
        Text('Estimated total · ${estimate()}'),
        const SizedBox(height: 16),
        if (c.recovery?.errorCode == 'VERSION_CONFLICT')
          OutlinedButton(
            onPressed: c.busy || !c.online
                ? null
                : () => reviewAndReloadProcurementConflict(
                    context,
                    access: c,
                    gateway: c.gateway,
                    scope: c.scope,
                    kind: 'purchase_requisition',
                    local: form,
                    discard: c.discard,
                    hasForm: () => c.form != null,
                    select: c.select,
                    edit: c.edit,
                  ),
            child: const Text('Compare current revision'),
          ),
        if (c.recovery?.pending != null)
          const Text(
            'A saved command needs confirmation. Retry sends the same command and exact values.',
          ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton(
              onPressed:
                  c.busy ||
                      !c.online ||
                      c.recovery?.errorCode == 'VERSION_CONFLICT'
                  ? null
                  : c.saveServer,
              child: Text(
                c.recovery?.pending != null
                    ? 'Retry saved command'
                    : 'Save to server',
              ),
            ),
            OutlinedButton(
              onPressed: c.locked ? null : c.saveLocal,
              child: const Text('Save on this device'),
            ),
            TextButton(
              onPressed: c.busy || c.recovery?.pending != null
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Discard local edits?'),
                          content: const Text(
                            'The server requisition remains available.',
                          ),
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
                      if (confirmed == true) await c.discard();
                    },
              child: const Text('Discard local edits'),
            ),
          ],
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../operations/access_changed.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_providers.dart';
import 'supplier_bill_controller.dart';
import 'conflict_comparison.dart';
import 'procurement_picker.dart';
import 'sourcing_screen.dart';

class SupplierBillScreen extends ConsumerWidget {
  const SupplierBillScreen({super.key});
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
    final c = ref.watch(supplierBillControllerProvider);
    if (c == null) {
      return const Center(
        child: Text('Choose a business scope with supplier bill permission.'),
      );
    }
    return SupplierBillWorkspace(key: ValueKey(c), controller: c);
  }
}

class SupplierBillWorkspace extends StatelessWidget {
  const SupplierBillWorkspace({super.key, required this.controller});
  final SupplierBillController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller, f = controller.form;
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
              'Supplier bills',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Match supplier invoices to accepted receipts, then post the payable and tax.',
            ),
            const SizedBox(height: 16),
            if (c.busy) const LinearProgressIndicator(),
            if (!c.online)
              const Text(
                'Offline · drafts can be saved securely on this device.',
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
                runSpacing: 12,
                children: [
                  if (c.canManage)
                    FilledButton.icon(
                      onPressed: c.busy || !c.online
                          ? null
                          : () async {
                              final row = await pickSourcingReference(
                                context,
                                c.references,
                                c.scope,
                                'bill_receipts',
                                access: c,
                              );
                              if (row != null) {
                                await c.create(
                                  receipt: (row['detail'] as Map)
                                      .cast<String, Object?>(),
                                );
                              }
                            },
                      icon: const Icon(Icons.add),
                      label: const Text('Bill accepted receipt'),
                    ),
                  if (c.canManage && c.canPost)
                    OutlinedButton(
                      onPressed: c.busy || !c.online ? null : () => c.create(),
                      child: const Text('Direct expense bill'),
                    ),
                  OutlinedButton(
                    onPressed: c.busy || !c.online ? null : c.refresh,
                    child: const Text('Refresh'),
                  ),
                  if (c.canSetup)
                    TextButton(
                      onPressed: c.busy || !c.online ? null : c.configure,
                      child: const Text('Bill posting controls'),
                    ),
                  TextButton(
                    onPressed: () => context.go('/procurement'),
                    child: const Text('Procurement'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (c.page.items.isEmpty && !c.busy)
                const Text('No supplier bills loaded.'),
              for (final row in c.page.items)
                Card(
                  child: ListTile(
                    title: Text(
                      '${row['document_number'] ?? row['supplier_reference']} · ${row['status']}',
                    ),
                    subtitle: Text(
                      '${row['document_date']} · Due ${row['due_date']}\n${row['currency_code']} ${row['total']}',
                    ),
                    selected: c.selected?['id'] == row['id'],
                    onTap: c.busy ? null : () => c.select(row),
                  ),
                ),
              if (c.page.nextCursor != null)
                TextButton(
                  onPressed: c.busy ? null : () => c.refresh(more: true),
                  child: const Text('Load more'),
                ),
              if (c.selected case final row?) ...[
                const Divider(height: 32),
                Text(
                  '${row['supplier_reference']} · ${row['status']}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  'Net ${row['subtotal']} · Tax ${row['tax_total']} · Total ${row['currency_code']} ${row['total']}',
                ),
                const SizedBox(height: 16),
                _MatchDetails(row: row),
                for (final raw in row['lines'] as List? ?? [])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      '${(raw as Map)['description']}\nQuantity ${raw['quantity']} · Unit price ${raw['unit_price']} · Discount ${raw['discount_percent']}%\nNet ${raw['net_amount']} · Tax ${raw['tax_amount']}',
                    ),
                  ),
                if (row['status'] == 'draft')
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (c.canManage)
                        OutlinedButton(
                          onPressed: c.busy ? null : () => c.edit(row),
                          child: const Text('Edit bill'),
                        ),
                      if (c.canPost)
                        FilledButton(
                          onPressed: c.busy || !c.online
                              ? null
                              : () => c.action('post'),
                          child: const Text('Post supplier bill'),
                        ),
                      if (c.canPost && c.canApprove)
                        OutlinedButton(
                          onPressed: c.busy || !c.online || c.ownBill
                              ? null
                              : () async {
                                  final reason = await sourcingReason(
                                    context,
                                    'Approve match exceptions',
                                    access: c,
                                  );
                                  if (reason != null) {
                                    await c.action('approve', reason: reason);
                                  }
                                },
                          child: const Text('Approve match exceptions'),
                        ),
                      if (c.canManage)
                        TextButton(
                          onPressed: c.busy || !c.online
                              ? null
                              : () async {
                                  final reason = await sourcingReason(
                                    context,
                                    'Cancel draft bill',
                                    access: c,
                                  );
                                  if (reason != null) {
                                    await c.action('cancel', reason: reason);
                                  }
                                },
                          child: const Text('Cancel draft bill'),
                        ),
                    ],
                  ),
              ],
            ] else ...[
              if (c.local?.pending != null)
                const Text(
                  'Confirmation pending. Retry the saved command before editing.',
                ),
              if (c.local?.errorCode == 'VERSION_CONFLICT')
                OutlinedButton(
                  onPressed: c.busy || !c.online
                      ? null
                      : () => reviewAndReloadProcurementConflict(
                          context,
                          access: c,
                          gateway: c.references,
                          scope: c.scope,
                          kind: 'supplier_bill',
                          local: f,
                          discard: c.discard,
                          hasForm: () => c.form != null,
                          select: c.select,
                          edit: c.edit,
                        ),
                  child: const Text('Compare current revision'),
                ),
              const SizedBox(height: 16),
              if (f['_mode'] == 'controls')
                _BillControls(controller: c)
              else if (f['_mode'] == 'action')
                Text('${f['supplier_reference']} · Saved bill action')
              else
                _BillEditor(controller: c),
              const SizedBox(height: 24),
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
                          : f['_mode'] == 'controls'
                          ? 'Save bill controls'
                          : 'Save and match bill',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: c.locked ? null : c.saveLocal,
                    child: const Text('Save on this device'),
                  ),
                  TextButton(
                    onPressed: c.busy || c.local?.pending != null
                        ? null
                        : () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Discard this local draft?'),
                                content: const Text(
                                  'Unsent edits will be removed from this device.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Keep draft'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Discard'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) await c.discard();
                          },
                    child: const Text('Discard draft'),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _MatchDetails extends StatelessWidget {
  const _MatchDetails({required this.row});
  final Map<String, Object?> row;
  @override
  Widget build(BuildContext context) {
    final match = row['match_result'] as Map? ?? {},
        exceptions = match['exceptions'] as List? ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          match['blocked'] == true
              ? 'Receipt quantity unavailable'
              : exceptions.isEmpty
              ? 'Within matching tolerances'
              : 'Match exceptions require review',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final group in exceptions)
          for (final raw in (group as Map)['exceptions'] as List)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${(raw as Map)['code'].toString().replaceAll('_', ' ')} · Expected ${raw['expected'] ?? raw['expected_rate'] ?? raw['available_quantity']} · Actual ${raw['actual'] ?? raw['actual_rate'] ?? raw['requested_quantity']}',
              ),
            ),
        for (final approval in row['match_approvals'] as List? ?? [])
          Text('Approval recorded · ${(approval as Map)['reason']}'),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _BillEditor extends StatelessWidget {
  const _BillEditor({required this.controller});
  final SupplierBillController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller, f = controller.form!;
    Widget field(String key, String label) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        key: ValueKey('${f['id']}:$key'),
        initialValue: f[key] as String? ?? '',
        enabled: !c.locked,
        decoration: InputDecoration(labelText: label),
        onChanged: (v) => c.update(key, v),
      ),
    );
    return Column(
      key: ValueKey(f['id']),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Invoice details', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: c.locked || !c.online
              ? null
              : () async {
                  final row = await pickSourcingReference(
                    context,
                    c.references,
                    c.scope,
                    'bill_suppliers',
                    access: c,
                  );
                  if (row != null && c.form?['id'] == f['id']) {
                    c.update('supplier_id', row['id']);
                    c.update('_supplier_name', row['name']);
                  }
                },
          child: Text(
            f['_supplier_name'] as String? ??
                (f['supplier_id'] == null
                    ? 'Choose supplier'
                    : 'Supplier from receipt'),
          ),
        ),
        const SizedBox(height: 16),
        field('supplier_reference', 'Supplier invoice reference'),
        field('document_date', 'Posting date (YYYY-MM-DD)'),
        field('due_date', 'Due date (YYYY-MM-DD)'),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            Text('Currency ${f['currency_code']}'),
            OutlinedButton(
              onPressed: c.locked || !c.online
                  ? null
                  : () async {
                      final row = await pickSourcingReference(
                        context,
                        c.references,
                        c.scope,
                        'bill_rates',
                        access: c,
                      );
                      if (row != null && c.form?['id'] == f['id']) {
                        c.update('currency_code', row['currency_code']);
                        c.update('exchange_rate_id', row['id']);
                      }
                    },
              child: const Text('Choose governed FX rate'),
            ),
            TextButton(
              onPressed: c.locked
                  ? null
                  : () {
                      c.update(
                        'currency_code',
                        f['_base_currency'] ?? f['base_currency_code'],
                      );
                      c.update('exchange_rate_id', null);
                    },
              child: const Text('Use base currency'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (final raw in f['lines'] as List)
          Builder(
            builder: (context) {
              final l = (raw as Map).cast<String, Object?>(),
                  id = l['line_id'] as String;
              Widget lineField(String key, String label) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextFormField(
                  key: ValueKey('$id:$key'),
                  initialValue: l[key] as String? ?? '',
                  enabled: !c.locked,
                  decoration: InputDecoration(labelText: label),
                  onChanged: (v) => c.updateLine(id, key, v),
                ),
              );
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l['receipt_line_id'] == null
                            ? 'Direct expense'
                            : 'Accepted receipt line',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      if (l['receipt_line_id'] == null)
                        lineField('description', 'Description')
                      else
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text('${l['description']}'),
                        ),
                      lineField('quantity', 'Quantity'),
                      lineField('unit_price', 'Unit price'),
                      lineField('discount_percent', 'Discount percentage'),
                      if (l['receipt_line_id'] == null)
                        OutlinedButton(
                          onPressed: c.locked || !c.online
                              ? null
                              : () async {
                                  final row = await pickSourcingReference(
                                    context,
                                    c.references,
                                    c.scope,
                                    'bill_expenses',
                                    access: c,
                                  );
                                  if (row != null) {
                                    c.updateLine(
                                      id,
                                      'expense_account_id',
                                      row['id'],
                                    );
                                    c.updateLine(
                                      id,
                                      '_expense_name',
                                      row['name'],
                                    );
                                  }
                                },
                          child: Text(
                            l['_expense_name'] as String? ??
                                (l['expense_account_id'] == null
                                    ? 'Choose expense account'
                                    : 'Configured expense account'),
                          ),
                        ),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          OutlinedButton(
                            onPressed: c.locked || !c.online
                                ? null
                                : () async {
                                    final row = await pickSourcingReference(
                                      context,
                                      c.references,
                                      c.scope,
                                      'bill_taxes',
                                      access: c,
                                    );
                                    if (row != null) {
                                      c.updateLine(
                                        id,
                                        'tax_definition_id',
                                        row['id'],
                                      );
                                      c.updateLine(
                                        id,
                                        '_tax_name',
                                        row['name'],
                                      );
                                    }
                                  },
                            child: Text(
                              l['_tax_name'] as String? ??
                                  (l['tax_definition_id'] == null
                                      ? 'Choose input tax'
                                      : 'Selected tax'),
                            ),
                          ),
                          TextButton(
                            onPressed: c.locked
                                ? null
                                : () {
                                    c.updateLine(id, 'tax_definition_id', null);
                                    c.updateLine(id, '_tax_name', 'No tax');
                                  },
                            child: const Text('No tax'),
                          ),
                          TextButton(
                            onPressed: c.locked ? null : () => c.removeLine(id),
                            child: const Text('Remove line'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton(
              onPressed: c.locked || !c.online
                  ? null
                  : () async {
                      final row = await pickSourcingReference(
                        context,
                        c.references,
                        c.scope,
                        'bill_receipts',
                        access: c,
                      );
                      if (row != null && c.form?['id'] == f['id']) {
                        c.addReceipt(
                          (row['detail'] as Map).cast<String, Object?>(),
                        );
                      }
                    },
              child: const Text('Add receipt line'),
            ),
            if (c.canPost)
              OutlinedButton(
                onPressed: c.locked ? null : c.addDirect,
                child: const Text('Add direct expense'),
              ),
          ],
        ),
      ],
    );
  }
}

class _BillControls extends StatelessWidget {
  const _BillControls({required this.controller});
  final SupplierBillController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller, f = controller.form!;
    return Column(
      key: ValueKey(f['id']),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Supplier bill controls',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Entity-wide accounts and exact match tolerances. Price and receipt-value differences post to the variance expense account.',
        ),
        const SizedBox(height: 16),
        for (final entry in {
          'payable_account_id': 'AP control liability',
          'input_tax_account_id': 'Input tax asset',
          'variance_account_id': 'Purchase variance expense',
        }.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: OutlinedButton(
              onPressed: c.locked || !c.online
                  ? null
                  : () async {
                      final row = await pickSourcingReference(
                        context,
                        c.references,
                        c.scope,
                        'bill_accounts',
                        access: c,
                      );
                      if (row != null && c.form?['_mode'] == 'controls') {
                        c.update(entry.key, row['id']);
                        c.update(
                          '_${entry.key}_label',
                          '${row['code']} · ${row['name']}',
                        );
                      }
                    },
              child: Text(
                '${entry.value}: ${f['_${entry.key}_label'] ?? (f[entry.key] == null ? 'Choose account' : 'Configured account')}',
              ),
            ),
          ),
        for (final entry in {
          'amount_tolerance': 'Net amount tolerance in bill currency',
          'price_percent_tolerance': 'Unit price tolerance percentage',
        }.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextFormField(
              key: ValueKey(entry.key),
              initialValue: f[entry.key] as String? ?? '0',
              enabled: !c.locked,
              decoration: InputDecoration(labelText: entry.value),
              onChanged: (v) => c.update(entry.key, v),
            ),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../operations/access_changed.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_providers.dart';
import 'supplier_payment_controller.dart';
import '../operations/operational_report_export.dart';
import 'procurement_picker.dart';
import 'sourcing_screen.dart';

import 'package:jentra_domain/jentra_procurement.dart';

class SupplierPaymentScreen extends ConsumerWidget {
  const SupplierPaymentScreen({super.key});
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
    final c = ref.watch(supplierPaymentControllerProvider);
    if (c == null) {
      return const Center(
        child: Text(
          'Choose a business scope with supplier payment permission.',
        ),
      );
    }
    return SupplierPaymentWorkspace(
      key: ValueKey(c),
      controller: c,
      showOperationalReports: true,
    );
  }
}

class SupplierPaymentWorkspace extends StatelessWidget {
  const SupplierPaymentWorkspace({
    super.key,
    required this.controller,
    this.showOperationalReports = false,
  });
  final SupplierPaymentController controller;
  final bool showOperationalReports;
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
              'Supplier payments',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Prepare due payables for approval and record completed payments with their references.',
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
                      onPressed: c.busy ? null : c.create,
                      icon: const Icon(Icons.add),
                      label: const Text('New payment proposal'),
                    ),
                  OutlinedButton(
                    onPressed: c.busy || !c.online
                        ? null
                        : () => c.refresh(payments: false),
                    child: const Text('Proposals'),
                  ),
                  OutlinedButton(
                    onPressed: c.busy || !c.online
                        ? null
                        : () => c.refresh(payments: true),
                    child: const Text('Recorded payments'),
                  ),
                  TextButton(
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
              Text(
                c.showingPayments ? 'Recorded payments' : 'Payment proposals',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (c.canManage || c.canPost || c.canAllocate || c.canReverse)
                _StatementPanel(
                  controller: c,
                  showOperationalReports: showOperationalReports,
                ),
              if (c.page.items.isEmpty && !c.busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No records loaded.'),
                ),
              for (final row in c.page.items)
                Card(
                  child: ListTile(
                    title: Text(
                      '${row['document_number'] ?? 'Draft proposal'} · ${row['status']}',
                    ),
                    subtitle: Text(
                      '${row['document_date']} · ${row['currency_code']} ${row['amount'] ?? row['total']}',
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
                  '${row['document_number'] ?? 'Draft proposal'} · ${row['status']}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  'Payment ${row['currency_code']} ${row['amount'] ?? row['total']} · Base ${row['base_currency_code']} ${row['base_amount'] ?? row['base_total']}',
                ),
                if (c.showingPayments) ...[
                  OutlinedButton(
                    onPressed: c.busy || !c.online
                        ? null
                        : () => c.inspectItem(row['open_item_id'] as String),
                    child: const Text('Open payment allocations'),
                  ),
                  Text('Reference: ${row['reference']}'),
                  Text('Bank reconciliation: ${row['reconciliation_status']}'),
                  for (final raw in row['allocations'] as List? ?? [])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Allocated ${(raw as Map)['transaction_amount']} · Exchange difference ${raw['exchange_difference']}',
                      ),
                    ),
                ] else ...[
                  for (final raw in row['lines'] as List? ?? [])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '${(raw as Map)['document_number']} · ${raw['kind']} · ${raw['amount']} · Due ${raw['due_date']}',
                      ),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (c.canManage && row['status'] == 'draft') ...[
                        OutlinedButton(
                          onPressed: c.busy ? null : () => c.edit(row),
                          child: const Text('Edit proposal'),
                        ),
                        FilledButton(
                          onPressed: c.busy || !c.online
                              ? null
                              : () => c.action('submit'),
                          child: const Text('Submit for approval'),
                        ),
                      ],
                      if (c.canManage &&
                          c.canApprove &&
                          row['status'] == 'pending_approval') ...[
                        FilledButton(
                          onPressed: c.busy || !c.online || c.ownProposal
                              ? null
                              : () => c.action('approve'),
                          child: const Text('Approve proposal'),
                        ),
                        OutlinedButton(
                          onPressed: c.busy || !c.online || c.ownProposal
                              ? null
                              : () => _reason(
                                  context,
                                  c,
                                  'reject',
                                  'Reject proposal',
                                ),
                          child: const Text('Reject proposal'),
                        ),
                      ],
                      if (c.canPost && row['status'] == 'approved')
                        FilledButton(
                          onPressed: c.busy || !c.online
                              ? null
                              : () async {
                                  final reference = await sourcingReason(
                                    context,
                                    'Enter the recorded payment reference',
                                    access: c,
                                    label: 'Payment reference',
                                    maxLength: 140,
                                  );
                                  if (reference != null) {
                                    await c.action(
                                      'post',
                                      reference: reference,
                                    );
                                  }
                                },
                          child: const Text('Record payment'),
                        ),
                      if (c.canManage &&
                          [
                            'pending_approval',
                            'approved',
                            'rejected',
                          ].contains(row['status']))
                        OutlinedButton(
                          onPressed: c.busy || !c.online
                              ? null
                              : () => _reason(
                                  context,
                                  c,
                                  'recall',
                                  'Recall for editing',
                                ),
                          child: const Text('Recall for editing'),
                        ),
                      if (c.canManage &&
                          [
                            'draft',
                            'pending_approval',
                            'approved',
                            'rejected',
                          ].contains(row['status']))
                        TextButton(
                          onPressed: c.busy || !c.online
                              ? null
                              : () => _reason(
                                  context,
                                  c,
                                  'cancel',
                                  'Cancel proposal',
                                ),
                          child: const Text('Cancel proposal'),
                        ),
                    ],
                  ),
                  if (c.ownProposal && row['status'] == 'pending_approval')
                    const Text(
                      'An independent approver must review this proposal.',
                    ),
                ],
              ],
              if (c.itemDetail != null) _AllocationDetail(controller: c),
            ] else ...[
              Text(
                f['_mode'] == 'action'
                    ? 'Saved payment action'
                    : ['allocation', 'correction'].contains(f['_mode'])
                    ? 'Allocation correction'
                    : 'Payment proposal',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              if (f['_mode'] == 'proposal') ...[
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton(
                      onPressed: c.locked || !c.online
                          ? null
                          : () async {
                              final id = f['id'];
                              final row = await pickSourcingReference(
                                context,
                                c.references,
                                c.scope,
                                'payment_suppliers',
                                access: c,
                              );
                              if (row != null && c.form?['id'] == id) {
                                c.chooseSupplier(row);
                              }
                            },
                      child: Text(
                        f['_supplier_name'] as String? ?? 'Choose supplier',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: c.locked || !c.online
                          ? null
                          : () async {
                              final id = f['id'];
                              final row = await pickSourcingReference(
                                context,
                                c.references,
                                c.scope,
                                'payment_banks',
                                access: c,
                              );
                              if (row != null && c.form?['id'] == id) {
                                c.chooseBank(row);
                              }
                            },
                      child: Text(
                        f['_bank_name'] as String? ?? 'Choose payment bank',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: c.locked || !c.online
                          ? null
                          : () async {
                              final id = f['id'];
                              final row = await pickSourcingReference(
                                context,
                                c.references,
                                c.scope,
                                'payment_rates',
                                access: c,
                              );
                              if (row != null && c.form?['id'] == id) {
                                c.update('exchange_rate_id', row['id']);
                                c.update('_rate_name', row['name']);
                              }
                            },
                      child: Text(
                        f['_rate_name'] as String? ??
                            'Choose FX rate if required',
                      ),
                    ),
                    TextButton(
                      onPressed: c.locked
                          ? null
                          : () {
                              c.update('exchange_rate_id', null);
                              c.update('_rate_name', null);
                            },
                      child: const Text('Clear FX rate'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: ValueKey('${f['id']}-date'),
                  initialValue: f['document_date'] as String?,
                  enabled: !c.locked,
                  decoration: const InputDecoration(
                    labelText: 'Payment date',
                    hintText: 'YYYY-MM-DD',
                  ),
                  onChanged: (v) => c.update('document_date', v),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: c.locked || !c.online ? null : c.loadItems,
                  child: const Text('Find due bills and credits'),
                ),
                for (final row in c.eligible)
                  Card(
                    child: ListTile(
                      isThreeLine: true,
                      title: Text('${row['document_number']} · ${row['kind']}'),
                      subtitle: Text(
                        'Due ${row['due_date']} · ${row['currency_code']} ${(row['residual'] as Map)['amount']}\n${row['claimed'] == true ? 'Selected by another proposal' : 'Available for selection'}',
                      ),
                      onTap: c.locked || row['claimed'] == true
                          ? null
                          : () => c.addItem(row),
                    ),
                  ),
                if (c.itemCursor != null)
                  TextButton(
                    onPressed: c.locked ? null : () => c.loadItems(more: true),
                    child: const Text('More open items'),
                  ),
                const SizedBox(height: 16),
                Text(
                  'Selected items',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if ((f['lines'] as List).isEmpty)
                  const Text('Choose due bills and any credits to apply.'),
                for (final raw in f['lines'] as List)
                  _SelectedItem(
                    controller: c,
                    row: (raw as Map).cast<String, Object?>(),
                  ),
                const SizedBox(height: 16),
                Text(
                  'Proposed payment ${f['currency_code'] ?? ''} ${c.proposedTotal}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text(
                  'The server rechecks amounts, due dates and availability before approval and recording.',
                ),
              ],
              if (['allocation', 'correction'].contains(f['_mode']))
                _AllocationEditor(controller: c),
              if (c.local?.pending != null)
                const Text(
                  'The result is not confirmed. Retry uses the same saved command and reference.',
                ),
              if (c.local?.errorCode == 'VERSION_CONFLICT')
                const Text(
                  'This proposal changed on the server. Keep the saved draft or discard it and reload the current version.',
                ),
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
                          : ['allocation', 'correction'].contains(f['_mode'])
                          ? 'Record allocation correction'
                          : 'Save proposal',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: c.locked ? null : c.saveLocal,
                    child: const Text('Save on this device'),
                  ),
                  TextButton(
                    onPressed: c.busy || c.local?.pending != null
                        ? null
                        : c.discard,
                    child: const Text('Discard local draft'),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    },
  );
  Future<void> _reason(
    BuildContext context,
    SupplierPaymentController c,
    String action,
    String title,
  ) async {
    final reason = await sourcingReason(context, title, access: c);
    if (reason != null) await c.action(action, reason: reason);
  }
}

class _SelectedItem extends StatelessWidget {
  const _SelectedItem({required this.controller, required this.row});
  final SupplierPaymentController controller;
  final Map<String, Object?> row;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${row['document_number']} · ${row['kind']} · Due ${row['due_date']}',
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey('${controller.form!['id']}-${row['open_item_id']}'),
            initialValue: row['amount'] as String?,
            enabled: !controller.locked,
            decoration: const InputDecoration(labelText: 'Amount to allocate'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (v) =>
                controller.amount(row['open_item_id'] as String, v),
          ),
          TextButton(
            onPressed: controller.locked
                ? null
                : () => controller.remove(row['open_item_id'] as String),
            child: const Text('Remove item'),
          ),
        ],
      ),
    ),
  );
}

class _StatementPanel extends StatefulWidget {
  const _StatementPanel({
    required this.controller,
    required this.showOperationalReports,
  });
  final SupplierPaymentController controller;
  final bool showOperationalReports;
  @override
  State<_StatementPanel> createState() => _StatementPanelState();
}

class _StatementPanelState extends State<_StatementPanel> {
  String? supplierId, supplierName, validation;
  final date = TextEditingController(
    text: DateTime.now().toIso8601String().substring(0, 10),
  );
  final currency = TextEditingController();
  final buckets = TextEditingController(text: '30,60,90');
  @override
  void initState() {
    super.initState();
    final report = widget.controller.statementReport;
    if (report != null) {
      supplierId = report['supplier_id'] as String?;
      supplierName = report['supplier_name'] as String?;
      date.text = report['as_of'] as String;
      currency.text = report['currency_code'] as String;
      buckets.text = (report['bucket_days'] as List).join(',');
    }
  }

  @override
  void dispose() {
    date.dispose();
    currency.dispose();
    buckets.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final parsed = DateTime.tryParse(date.text);
    final days = buckets.text
        .split(',')
        .map((x) => int.tryParse(x.trim()))
        .toList();
    if (supplierId == null ||
        parsed == null ||
        parsed.toIso8601String().substring(0, 10) != date.text ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(currency.text) ||
        days.isEmpty ||
        days.length > 12 ||
        days.any((v) => v == null || v <= 0) ||
        List.generate(
          days.length,
          (i) => i,
        ).skip(1).any((i) => days[i]! <= days[i - 1]!)) {
      setState(
        () => validation = 'Choose a supplier, date, currency and increasing positive bucket days.',
      );
      return;
    }
    setState(() => validation = null);
    await widget.controller.loadStatement(
      supplierId: supplierId!,
      supplierName: supplierName,
      currency: currency.text,
      asOf: date.text,
      buckets: days.cast<int>(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, r = c.statementReport;
    return ExpansionTile(
      title: const Text('Supplier statement and AP aging'),
      childrenPadding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: c.busy || !c.online
                ? null
                : () async {
                    final row = await pickSourcingReference(
                      context,
                      c.references,
                      c.scope,
                      'payment_suppliers',
                      access: c,
                    );
                    if (mounted && row != null) {
                      setState(() {
                        supplierId = row['id'] as String;
                        supplierName = row['name'] as String;
                      });
                    }
                  },
            child: Text(supplierName ?? 'Choose statement supplier'),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: date,
          enabled: !c.busy,
          decoration: const InputDecoration(
            labelText: 'Statement as of',
            hintText: 'YYYY-MM-DD',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: currency,
          enabled: !c.busy,
          decoration: const InputDecoration(
            labelText: 'Currency code',
            hintText: 'LKR',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: buckets,
          enabled: !c.busy,
          decoration: const InputDecoration(
            labelText: 'Aging boundaries in days',
            hintText: '30,60,90',
          ),
        ),
        if (validation != null) Text(validation!),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: c.busy || !c.online ? null : load,
          child: const Text('Load dated statement'),
        ),
        if (r != null) ...[
          if (widget.showOperationalReports)
            OperationalReportExport(
              kind: 'supplier_statement',
              label: 'Save dated supplier statement for export',
              inputs: {
                'party_id': r['supplier_id'],
                'currency_code': r['currency_code'],
                'as_of': r['as_of'],
                'bucket_days': r['bucket_days'],
              },
            ),
          const Divider(),
          Text(
            '${r['supplier_name']} · ${r['currency_code']} · As of ${r['as_of']}',
          ),
          Text('Open ${r['open_amount']} · Base ${r['open_base_amount']}'),
          for (final raw in r['aging'] as List? ?? [])
            Builder(
              builder: (context) {
                final row = (raw as Map),
                    index = row['bucket'] as int,
                    limits = (r['bucket_days'] as List).cast<int>();
                final label = index == -1
                    ? 'Unapplied credits'
                    : index == 0
                    ? 'Not overdue'
                    : index > limits.length
                    ? 'Over ${limits.last} days'
                    : '${index == 1 ? 1 : limits[index - 2] + 1}–${limits[index - 1]} days';
                return ListTile(
                  title: Text(label),
                  subtitle: Text(
                    '${r['currency_code']} ${row['amount']} · Base ${row['base_amount']}',
                  ),
                );
              },
            ),
          for (final raw in r['rows'] as List? ?? [])
            ListTile(
              onTap: c.busy || !c.online
                  ? null
                  : () => c.inspectItem((raw as Map)['id'] as String),
              title: Text(
                '${(raw as Map)['document_number']} · ${switch (raw['source_type']) {
                  'supplier_bill' => 'Supplier bill',
                  'supplier_payment' => 'Recorded payment',
                  'purchase_return' => 'Purchase return',
                  _ => 'Supplier document',
                }}',
              ),
              subtitle: Text(
                'Posted ${raw['posting_date']} · Due ${raw['due_date']}\nOpen ${raw['open_amount']} · Base ${raw['open_base_amount']}',
              ),
            ),
        ],
      ],
    );
  }
}

class _AllocationDetail extends StatelessWidget {
  const _AllocationDetail({required this.controller});
  final SupplierPaymentController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller,
        detail = c.itemDetail!,
        item = (detail['item'] as Map);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),
        Text(
          'Open-item history · ${item['document_number']}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(
          'Current open ${item['currency_code']} ${item['amount']} · Base ${item['base_amount']}',
        ),
        if (c.canAllocate &&
            ExactDecimal.parse(item['amount'] as String, scale: 6).isNegative)
          FilledButton(
            onPressed: c.busy ? null : c.beginAllocation,
            child: const Text('Allocate unapplied credit'),
          ),
        for (final raw in detail['allocations'] as List)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${(raw as Map)['source_document_number']} → ${raw['target_document_number']}',
                  ),
                  Text(
                    'Allocated ${raw['source_amount']} → ${raw['transaction_amount']} · ${raw['posting_date']}',
                  ),
                  Text('Exchange difference ${raw['exchange_difference']}'),
                  if (raw['reversal'] is Map)
                    Text(
                      'Reversed ${(raw['reversal'] as Map)['posting_date']} · ${(raw['reversal'] as Map)['reason']}',
                    )
                  else if (c.canReverse)
                    OutlinedButton(
                      onPressed: c.busy || !c.online
                          ? null
                          : () async {
                              final epoch = c.readAccessEpoch;
                              final reason = await sourcingReason(
                                context,
                                'Reverse allocation',
                                access: c,
                              );
                              if (reason != null) {
                                await c.reverseAllocation(
                                  raw.cast<String, Object?>(),
                                  date: DateTime.now()
                                      .toIso8601String()
                                      .substring(0, 10),
                                  reason: reason,
                                  readEpoch: epoch,
                                );
                              }
                            },
                      child: const Text('Reverse allocation'),
                    ),
                ],
              ),
            ),
          ),
        if ((detail['allocations'] as List).isEmpty)
          const Text('No allocations recorded.'),
        if (detail['next_cursor'] != null)
          TextButton(
            onPressed: c.busy
                ? null
                : () => c.inspectItem(item['id'] as String, more: true),
            child: const Text('More allocation history'),
          ),
      ],
    );
  }
}

class _AllocationEditor extends StatelessWidget {
  const _AllocationEditor({required this.controller});
  final SupplierPaymentController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller,
        f = c.form!,
        reverse = f['_correction_action'] == 'reverse';
    Widget field(String key, String label) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        key: ValueKey('${f['id']}-$key'),
        initialValue: f[key] as String? ?? '',
        enabled: !c.locked,
        decoration: InputDecoration(labelText: label),
        onChanged: (v) => c.update(key, v),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          reverse
              ? 'Reverse the selected allocation'
              : 'Allocate ${f['_source_number']}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        field('posting_date', 'Correction posting date (YYYY-MM-DD)'),
        field('reason', 'Reason'),
        if (!reverse) ...[
          field('source_amount', 'Credit amount (${f['_currency']})'),
          OutlinedButton(
            onPressed: c.locked || !c.online ? null : c.loadAllocationTargets,
            child: const Text('Find eligible bills'),
          ),
          for (final row in c.allocationTargets)
            ListTile(
              title: Text(
                '${row['document_number']} · ${row['currency_code']} ${row['amount']}',
              ),
              subtitle: Text(
                row['currency_code'] == f['_currency']
                    ? 'Available bill'
                    : 'Different currency · conversion rate required',
              ),
              selected: f['target_open_item_id'] == row['id'],
              onTap: c.locked
                  ? null
                  : () {
                      c.update('target_open_item_id', row['id']);
                      c.update('_target_number', row['document_number']);
                      c.update('_target_currency', row['currency_code']);
                    },
            ),
          if (c.targetCursor != null)
            TextButton(
              onPressed: c.locked
                  ? null
                  : () => c.loadAllocationTargets(more: true),
              child: const Text('More eligible bills'),
            ),
          Text('Selected bill: ${f['_target_number'] ?? 'Choose a bill'}'),
          const SizedBox(height: 16),
          field(
            'transaction_amount',
            'Bill amount (${f['_target_currency'] ?? ''})',
          ),
          if (f['_target_currency'] != null &&
              f['_target_currency'] != f['_currency']) ...[
            OutlinedButton(
              onPressed: c.locked || !c.online ? null : c.loadAllocationRates,
              child: const Text('Find conversion rates'),
            ),
            for (final row in c.allocationRates)
              ListTile(
                title: Text(
                  '${f['_currency']} → ${f['_target_currency']} · ${row['rate']}',
                ),
                subtitle: Text('Effective ${row['date']}'),
                selected: f['exchange_rate_id'] == row['id'],
                onTap: c.locked
                    ? null
                    : () => c.update('exchange_rate_id', row['id']),
              ),
            if (c.rateCursor != null)
              TextButton(
                onPressed: c.locked
                    ? null
                    : () => c.loadAllocationRates(more: true),
                child: const Text('More conversion rates'),
              ),
          ],
          const Text(
            'Amounts and remaining balances are checked again when recorded.',
          ),
        ],
      ],
    );
  }
}

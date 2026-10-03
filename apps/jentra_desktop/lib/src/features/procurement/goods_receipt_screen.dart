import 'package:flutter/material.dart';

import '../operations/access_changed.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_providers.dart';
import 'goods_receipt_controller.dart';
import 'procurement_picker.dart';
import '../operations/operational_read_access.dart';

class GoodsReceiptScreen extends ConsumerWidget {
  const GoodsReceiptScreen({super.key});
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
    final c = ref.watch(goodsReceiptControllerProvider);
    if (c == null) {
      return const Center(
        child: Text('Choose a business scope with goods receipt permission.'),
      );
    }
    return GoodsReceiptWorkspace(key: ValueKey(c), controller: c);
  }
}

class GoodsReceiptWorkspace extends StatelessWidget {
  const GoodsReceiptWorkspace({super.key, required this.controller});
  final GoodsReceiptController controller;
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
              'Goods receipts',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Record accepted and rejected deliveries against approved purchase orders.',
            ),
            const SizedBox(height: 16),
            if (c.busy) const LinearProgressIndicator(),
            if (!c.online)
              const Text(
                'Offline · drafts can be saved on this device. Posting requires a connection.',
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
                  if (c.canPost)
                    FilledButton.icon(
                      onPressed: c.busy || !c.online
                          ? null
                          : () async {
                              final row = await pickSourcingReference(
                                context,
                                c.references,
                                c.scope,
                                'receipt_orders',
                                access: c,
                              );
                              if (row != null) {
                                await c.create(
                                  (row['detail'] as Map)
                                      .cast<String, Object?>(),
                                );
                              }
                            },
                      icon: const Icon(Icons.add),
                      label: const Text('Receive purchase order'),
                    ),
                  if (c.canPost)
                    OutlinedButton(
                      onPressed: c.busy || !c.online ? null : c.refresh,
                      child: const Text('Refresh'),
                    ),
                  if (c.canAllow)
                    OutlinedButton(
                      onPressed: c.busy || !c.online
                          ? null
                          : () async {
                              final row = await pickSourcingReference(
                                context,
                                c.references,
                                c.scope,
                                'receipt_orders',
                                access: c,
                              );
                              if (row != null) {
                                await c.createAllowance(
                                  (row['detail'] as Map)
                                      .cast<String, Object?>(),
                                );
                              }
                            },
                      child: const Text('Approve extra quantity'),
                    ),
                  if (c.canSetup)
                    TextButton(
                      onPressed: c.busy || !c.online ? null : c.configure,
                      child: const Text('Receipt posting accounts'),
                    ),
                  TextButton(
                    onPressed: () => context.go('/procurement'),
                    child: const Text('Procurement'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (c.page.items.isEmpty && !c.busy && c.canPost)
                const Text(
                  'No receipts loaded. Receive an approved purchase order to begin.',
                ),
              for (final row in c.page.items)
                Card(
                  child: ListTile(
                    title: Text('${row['document_number']} · ${row['status']}'),
                    subtitle: Text(
                      '${row['document_date']} · ${row['reference']}\n${row['currency_code']} ${row['net_amount']}',
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
                  '${row['document_number']} · ${row['status']}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                for (final raw in row['lines'] as List? ?? [])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      '${(raw as Map)['description']}\nAccepted ${raw['accepted_quantity']} · Rejected ${raw['rejected_quantity']}\nBase quantity ${raw['base_quantity']} · Net ${raw['net_amount']}'
                      '${raw['lot_code'] == null ? '' : '\nLot ${raw['lot_code']}'}'
                      '${(raw['serial_codes'] as List? ?? []).isEmpty ? '' : '\nSerials ${(raw['serial_codes'] as List).join(', ')}'}'
                      '${raw['rejection_reason'] == null || raw['rejection_reason'] == '' ? '' : '\nRejection: ${raw['rejection_reason']}'}',
                    ),
                  ),
                if (row['reversal'] case final Map reversal)
                  Text(
                    'Reversed ${reversal['document_date']} · ${reversal['reason']}',
                  ),
                if (row['status'] == 'posted')
                  OutlinedButton(
                    onPressed: c.busy || !c.online
                        ? null
                        : () async {
                            final epoch = c.readAccessEpoch;
                            final result =
                                await showOperationalReadDialog<
                                  Map<String, String>
                                >(
                                  context,
                                  c,
                                  (_) => const _ReverseReceiptDialog(),
                                );
                            if (result != null &&
                                context.mounted &&
                                c.currentRead(epoch)) {
                              await c.reverse(
                                result['date']!,
                                result['reason']!,
                              );
                            }
                          },
                    child: const Text('Reverse receipt'),
                  ),
              ],
            ] else ...[
              if (c.local?.pending != null)
                const Text(
                  'Confirmation pending. Retry the saved command before making changes.',
                ),
              if (c.local?.errorCode == 'VERSION_CONFLICT')
                const Text(
                  'The source changed. Keep this draft for reference or discard it and reload the current order.',
                ),
              const SizedBox(height: 16),
              if (f['_mode'] == 'controls') ...[
                Text(
                  'Receipt posting accounts',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'These accounts apply across the legal entity. Choose a GRNI liability account and a default expense account for non-stock purchases.',
                ),
                const SizedBox(height: 16),
                for (final entry in {
                  'grni_account_id': 'GRNI liability account',
                  'expense_account_id': 'Default expense account',
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
                                'receipt_accounts',
                                access: c,
                              );
                              if (row == null ||
                                  c.form?['id'] != f['id'] ||
                                  c.form?['_mode'] != 'controls') {
                                return;
                              }
                              c.update(entry.key, row['id']);
                              c.update(
                                '_${entry.key}_label',
                                '${row['code']} · ${row['name']}',
                              );
                            },
                      child: Text(
                        '${entry.value}: ${f['_${entry.key}_label'] ?? (f[entry.key] == null ? 'Choose account' : 'Configured account')}',
                      ),
                    ),
                  ),
                TextFormField(
                  key: ValueKey('${f['id']}:percent'),
                  initialValue:
                      f['maximum_over_receipt_percent'] as String? ?? '0',
                  enabled: !c.locked,
                  decoration: const InputDecoration(
                    labelText: 'Maximum over-receipt percentage',
                  ),
                  onChanged: (v) => c.update('maximum_over_receipt_percent', v),
                ),
              ] else if (f['_mode'] == 'allowance') ...[
                Text(
                  'Approve extra quantity · ${f['_order_number']}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                const Text(
                  'An allowance applies to this PO version. A different user must post it. Any source change expires the allowance.',
                ),
                const SizedBox(height: 16),
                for (final raw in f['_source_lines'] as List)
                  ListTile(
                    title: Text('${(raw as Map)['description']}'),
                    subtitle: Text(
                      'Ordered ${raw['quantity']} · Received ${raw['received_quantity']}',
                    ),
                    leading: Icon(
                      f['order_line_id'] == raw['line_id']
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                    ),
                    onTap: c.locked
                        ? null
                        : () => c.update('order_line_id', raw['line_id']),
                  ),
                const SizedBox(height: 16),
                for (final entry in {
                  'extra_quantity': 'Extra quantity above the order',
                  'reason': 'Approval reason',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TextFormField(
                      key: ValueKey('${f['id']}:${entry.key}'),
                      initialValue: f[entry.key] as String? ?? '',
                      enabled: !c.locked,
                      decoration: InputDecoration(labelText: entry.value),
                      onChanged: (v) => c.update(entry.key, v),
                    ),
                  ),
              ] else if (f['_mode'] == 'reversal')
                Text('Reversal · ${f['document_date']}\n${f['reason']}')
              else
                _ReceiptEditor(controller: c),
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
                          ? 'Save posting accounts'
                          : f['_mode'] == 'allowance'
                          ? 'Approve allowance'
                          : 'Post goods receipt',
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
                            final discard = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Discard this local draft?'),
                                content: const Text(
                                  'Your unsent changes will be removed from this device.',
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
                            if (discard == true) await c.discard();
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

class _ReceiptEditor extends StatelessWidget {
  const _ReceiptEditor({required this.controller});
  final GoodsReceiptController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller, f = controller.form!;
    return Column(
      key: ValueKey(f['id']),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Receive ${f['_order_number']}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter zero for lines not received. Rejected quantities require a reason and do not enter stock.',
        ),
        const SizedBox(height: 16),
        for (final entry in {
          'document_date': 'Posting date (YYYY-MM-DD)',
          'reference': 'Supplier delivery reference',
        }.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextFormField(
              initialValue: f[entry.key] as String? ?? '',
              enabled: !c.locked,
              decoration: InputDecoration(labelText: entry.value),
              onChanged: (v) => c.update(entry.key, v),
            ),
          ),
        for (final raw in f['lines'] as List)
          Builder(
            builder: (context) {
              final l = (raw as Map).cast<String, Object?>();
              Widget field(String key, String label, {int lines = 1}) =>
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TextFormField(
                      key: ValueKey('${l['line_id']}:$key'),
                      initialValue: key == 'serial_codes'
                          ? (l[key] as List? ?? []).join('\n')
                          : l[key] as String? ?? '',
                      enabled: !c.locked,
                      minLines: lines,
                      maxLines: lines == 1 ? 1 : 5,
                      decoration: InputDecoration(labelText: label),
                      onChanged: (v) => c.updateLine(
                        l['line_id'] as String,
                        key,
                        key == 'serial_codes'
                            ? v
                                  .split(RegExp(r'[\n,]'))
                                  .map((s) => s.trim())
                                  .where((s) => s.isNotEmpty)
                                  .toList()
                            : [
                                    'lot_code',
                                    'manufacture_date',
                                    'expiry_date',
                                  ].contains(key) &&
                                  v.trim().isEmpty
                            ? null
                            : v,
                      ),
                    ),
                  );
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${l['description']}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Remaining ${l['remaining_quantity']} · ${l['conversion_numerator']} / ${l['conversion_denominator']} base units per order unit',
                      ),
                      if (l['_allowance'] case final Map allowance)
                        Text(
                          'Approved receipt ceiling ${allowance['maximum_received_quantity']} · ${allowance['reason']}',
                        ),
                      const SizedBox(height: 16),
                      field('accepted_quantity', 'Accepted quantity'),
                      field('rejected_quantity', 'Rejected quantity'),
                      field('rejection_reason', 'Rejection reason'),
                      if (l['_tracking_mode'] == 'lot') ...[
                        field('lot_code', 'Lot code'),
                        field(
                          'manufacture_date',
                          'Manufacture date (optional)',
                        ),
                        field('expiry_date', 'Expiry date (optional)'),
                      ],
                      if (l['_tracking_mode'] == 'serial')
                        field(
                          'serial_codes',
                          'Serial numbers (one per line)',
                          lines: 3,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _ReverseReceiptDialog extends StatefulWidget {
  const _ReverseReceiptDialog();
  @override
  State<_ReverseReceiptDialog> createState() => _ReverseReceiptDialogState();
}

class _ReverseReceiptDialogState extends State<_ReverseReceiptDialog> {
  final date = TextEditingController(
    text: DateTime.now().toIso8601String().substring(0, 10),
  );
  final reason = TextEditingController();
  @override
  void dispose() {
    date.dispose();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Reverse goods receipt'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'The receipt stays in history. Available stock and the original accrual will be reversed. Billed or consumed receipts require a purchase return.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: date,
              decoration: const InputDecoration(
                labelText: 'Posting date (YYYY-MM-DD)',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'Reason'),
              maxLines: 3,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Keep receipt'),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.pop(context, {'date': date.text, 'reason': reason.text}),
        child: const Text('Reverse receipt'),
      ),
    ],
  );
}

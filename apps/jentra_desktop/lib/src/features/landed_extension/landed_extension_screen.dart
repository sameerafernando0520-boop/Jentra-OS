import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import '../../app_providers.dart';
import 'landed_extension_controller.dart';
import '../journal_evidence/posted_journal_screen.dart';
import '../operations/operational_controller.dart';
import '../operations/operational_link.dart';
import '../operations/operational_read_access.dart';

class LandedExtensionScreen extends ConsumerWidget {
  const LandedExtensionScreen({super.key});
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
    final controller = ref.watch(landedExtensionControllerProvider);
    return controller == null
        ? const Center(
            child: Text(
              'Choose a scope with valuation and inventory cost access.',
            ),
          )
        : LandedExtensionWorkspace(
            key: ValueKey(controller),
            controller: controller,
            capabilities: caps.value ?? {},
          );
  }
}

class LandedExtensionWorkspace extends StatelessWidget {
  const LandedExtensionWorkspace({
    super.key,
    required this.controller,
    this.capabilities = const {},
  });
  final LandedExtensionController controller;
  final Set<String> capabilities;
  Future<void> confirm(BuildContext context) async {
    if (controller.local?.pending != null) {
      await controller.post();
      return;
    }
    final preview = controller.preview;
    if (preview == null) return;
    final access = controller.readAccessEpoch;
    final accepted = await showOperationalReadDialog<bool>(
      context,
      controller,
      (context) => AlertDialog(
        title: Text(
          controller.correcting
              ? 'Post this landed value correction?'
              : 'Post this landed value allocation?',
        ),
        content: SingleChildScrollView(
          child: Text(
            '${controller.form?['reference']}\n${controller.form?['reason']}\n\n'
            '${preview['currency_code']} Incremental amount: ${preview['amount']}\nHeld inventory: ${preview['inventory_amount']}\n'
            'In transit: ${preview['transit_amount']}\nConsumed variance: ${preview['variance_amount']}\n\n'
            'This changes carrying value and records balanced journals.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm posting'),
          ),
        ],
      ),
    );
    if (accepted == true && controller.currentRead(access)) {
      await controller.post();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller, f = c.form, p = c.preview;
      if (c.accessDenied) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Access changed. Saved work is retained securely.'),
              TextButton(
                onPressed: c.busy || !c.online ? null : c.initialize,
                child: const Text('Recheck access'),
              ),
            ],
          ),
        );
      }
      Widget field(String key, String label) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextFormField(
          key: ValueKey('${f?['id']}-$key'),
          initialValue: f?[key] as String? ?? '',
          enabled: !c.locked,
          maxLength: key == 'reason'
              ? 1000
              : key == 'reference'
              ? 140
              : 32,
          decoration: InputDecoration(labelText: label),
          onChanged: (value) => c.update(key, value),
        ),
      );
      Widget account(String key, String label) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: DropdownButtonFormField<String>(
          key: ValueKey('${f?['id']}-$key-${c.options['accounts']?.length}'),
          initialValue:
              (c.options['accounts'] ?? []).any((row) => row['id'] == f?[key])
              ? (f?[key] as String?)
              : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final row in c.options['accounts'] ?? [])
              DropdownMenuItem(
                value: row['id'] as String,
                child: Text(
                  '${row['code']} ${row['name']}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: c.locked
              ? null
              : (value) {
                  if (value != null) c.update(key, value);
                },
        ),
      );
      return PopScope(
        canPop: !c.busy,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Landed value allocations',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Text(
                'Allocate recorded freight across eligible receipt lines. Later corrections retain the original basis and use current quantities.',
              ),
              if (!c.online)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Offline. Saved inputs remain available; refresh evidence after reconnecting.',
                  ),
                ),
              if (c.busy) const LinearProgressIndicator(),
              if (c.error != null)
                Text(
                  c.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (c.message != null) Text(c.message!),
              if (c.local?.pending != null)
                const Text(
                  'A posting result is uncertain. Inputs are locked; retry the identical saved request.',
                ),
              if (f == null && c.posted == null) ...[
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: c.busy ? null : c.create,
                      child: const Text('New allocation'),
                    ),
                    OutlinedButton(
                      onPressed: c.busy || !c.online
                          ? null
                          : () => c.refresh('posted'),
                      child: const Text('Refresh posted allocations'),
                    ),
                  ],
                ),
                for (final draft in c.recovered)
                  ListTile(
                    title: Text(
                      'Saved ${draft.form['reference'] ?? 'allocation'}',
                    ),
                    subtitle: Text(
                      draft.pending != null
                          ? 'Uncertain posting — restore and retry'
                          : 'Saved inputs',
                    ),
                    trailing: TextButton(
                      onPressed: c.busy ? null : () => c.restore(draft),
                      child: const Text('Restore'),
                    ),
                  ),
                if (c.recoveryCursor != null)
                  TextButton(
                    onPressed: c.busy ? null : c.moreRecovery,
                    child: const Text('More saved inputs'),
                  ),
                if (c.online &&
                    !c.busy &&
                    c.error == null &&
                    (c.options['posted'] ?? []).isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: JentraPanel(
                      child: JentraEmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: c.options.containsKey('posted')
                            ? 'No posted landed allocations'
                            : 'Posted allocations not loaded',
                        description: c.options.containsKey('posted')
                            ? 'Create an allocation after recording eligible receipts and freight expense. Posted allocations for this scope will appear here.'
                            : 'Select Refresh posted allocations to review this scope. Create a new allocation after recording eligible receipts and freight expense.',
                      ),
                    ),
                  ),
                for (final row in c.options['posted'] ?? [])
                  ListTile(
                    title: Text('${row['reference']}'),
                    subtitle: Text(
                      'Total ${row['currency_code']} ${row['total_amount']} · Increment ${row['amount']}',
                    ),
                    trailing: TextButton(
                      onPressed: c.busy || !c.online
                          ? null
                          : () => c.openPosted(row),
                      child: const Text('View'),
                    ),
                  ),
                if (c.cursors['posted'] != null)
                  TextButton(
                    onPressed: c.busy || !c.online
                        ? null
                        : () => c.refresh('posted', more: true),
                    child: const Text('More posted allocations'),
                  ),
              ],
              if (f != null) ...[
                if (c.correcting)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Linked correction. Receipt identities, accounts and allocation weights remain frozen. Enter the corrected total charge.',
                    ),
                  ),
                field('reference', 'Reference'),
                field('reason', 'Reason'),
                field('document_date', 'Posting date (YYYY-MM-DD)'),
                field(
                  'total_amount',
                  c.correcting
                      ? 'Corrected total amount'
                      : 'Total landed charge',
                ),
                if (!c.correcting) ...[
                  DropdownButtonFormField<String>(
                    initialValue: f['basis_mode'] as String?,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Allocation basis',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'quantity',
                        child: Text('Original received quantity'),
                      ),
                      DropdownMenuItem(
                        value: 'original_value',
                        child: Text('Original receipt value'),
                      ),
                      DropdownMenuItem(
                        value: 'manual',
                        child: Text('Manual exact positive weights'),
                      ),
                    ],
                    onChanged: c.locked
                        ? null
                        : (value) {
                            if (value != null) c.update('basis_mode', value);
                          },
                  ),
                  account(
                    'offset_account_id',
                    'Recorded freight expense account',
                  ),
                  account(
                    'variance_account_id',
                    'Consumed inventory variance account',
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text('Choose up to 50 eligible receipt lines'),
                  ),
                  for (final row in c.options['receipts'] ?? [])
                    Builder(
                      builder: (context) {
                        final selected = (f['receipts'] as List)
                            .where(
                              (line) => line['receipt_line_id'] == row['id'],
                            )
                            .firstOrNull;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${row['document_number']} · ${row['product_name']}',
                              ),
                              subtitle: Text(
                                'Received ${row['received_quantity']} · ${row['warehouse_name']}',
                              ),
                              value: selected != null,
                              onChanged: c.locked
                                  ? null
                                  : (value) =>
                                        c.selectReceipt(row, value ?? false),
                            ),
                            if (selected != null && f['basis_mode'] == 'manual')
                              TextFormField(
                                key: ValueKey('${f['id']}-${row['id']}-weight'),
                                initialValue: selected['weight'] as String?,
                                enabled: !c.locked,
                                decoration: const InputDecoration(
                                  labelText: 'Exact positive weight',
                                ),
                                onChanged: (value) =>
                                    c.weight(row['id'] as String, value),
                              ),
                          ],
                        );
                      },
                    ),
                  if (c.cursors['receipts'] != null)
                    TextButton(
                      onPressed: c.busy || !c.online
                          ? null
                          : () => c.refresh('receipts', more: true),
                      child: const Text('More receipt lines'),
                    ),
                ],
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: c.locked ? null : c.save,
                      child: const Text('Save inputs'),
                    ),
                    FilledButton(
                      onPressed: c.locked || !c.online ? null : c.calculate,
                      child: const Text('Preview exact allocation'),
                    ),
                    FilledButton(
                      onPressed:
                          c.busy ||
                              !c.online ||
                              (p == null && c.local?.pending == null)
                          ? null
                          : () => confirm(context),
                      child: Text(
                        c.local?.pending != null
                            ? 'Retry saved posting'
                            : 'Review and post',
                      ),
                    ),
                  ],
                ),
              ],
              if (p != null) ...[
                const Divider(),
                Text(
                  'Exact ${p['currency_code']} allocation',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  'Total charge ${p['total_amount']} · Increment ${p['amount']}',
                ),
                Text(
                  'Held inventory ${p['inventory_amount']} · In transit ${p['transit_amount']} · Consumed variance ${p['variance_amount']}',
                ),
                for (final row in p['receipts'] as List)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Receipt ${row['receipt_line_id']}\nWeight ${row['weight']} · Increment ${row['incremental_amount']}\n'
                      'Received ${row['received_quantity']} · Held ${row['held_quantity']} · In transit ${row['transit_quantity']} · Consumed ${row['consumed_quantity']}',
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Receipt quantities provide attribution. Allocation weights do not establish original carrying-cost provenance.',
                  ),
                ),
              ],
              if (c.posted != null && c.online)
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (canReadOperational('landed_extension', capabilities))
                      OperationalLink(
                        scope: c.scope,
                        kind: 'landed_extension',
                        id: c.posted!['id'] as String,
                      ),
                    if (capabilities.contains('finance.view'))
                      for (final journal
                          in c.posted!['journal_ids'] as List? ?? [])
                        PostedJournalLink(
                          scope: c.scope,
                          journalId: journal as String,
                        ),
                  ],
                ),
              if (c.posted != null && c.posted!['has_correction'] != true)
                TextButton(
                  onPressed: c.busy || !c.online ? null : c.correction,
                  child: const Text('Prepare linked correction'),
                ),
              if (f != null || c.posted != null)
                TextButton(
                  onPressed: c.busy || c.local?.pending != null
                      ? null
                      : c.close,
                  child: const Text('Close allocation'),
                ),
            ],
          ),
        ),
      );
    },
  );
}

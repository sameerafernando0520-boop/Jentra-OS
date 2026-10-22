import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import '../../app_providers.dart';
import '../operations/operational_read_access.dart';
import 'landed_value_controller.dart';

class LandedValueScreen extends ConsumerWidget {
  const LandedValueScreen({super.key});
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
    final c = ref.watch(landedValueControllerProvider);
    return c == null
        ? const Center(
            child: Text(
              'Choose a scope with valuation and inventory cost access.',
            ),
          )
        : LandedValueWorkspace(key: ValueKey(c), controller: c);
  }
}

class LandedValueWorkspace extends StatelessWidget {
  const LandedValueWorkspace({required this.controller, super.key});
  final LandedValueController controller;
  Future<void> confirm(BuildContext context) async {
    if (controller.local?.pending != null) {
      await controller.post();
      return;
    }
    final reverse = controller.form?['reverse_of'] != null;
    final accepted = await showOperationalReadDialog<bool>(
      context,
      controller,
      (context) => AlertDialog(
        title: Text(
          reverse ? 'Reverse this landed value?' : 'Post this landed value?',
        ),
        content: SingleChildScrollView(
          child: Text(
            '${reverse ? 'Original allocation: ${controller.form?['reverse_of']}' : '${controller.preview?['currency_code']} ${controller.preview?['amount']}'}\n${controller.form?['reference']}\n${controller.form?['reason']}\n\n${reverse ? 'This creates a linked correction.' : 'This reclassifies recorded freight expense and changes inventory carrying value.'}',
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
    if (accepted == true) await controller.post();
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
      Widget field(String key, String label, {int max = 140}) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextFormField(
          key: ValueKey('${f?['id']}-$key'),
          initialValue: f?[key] as String? ?? '',
          decoration: InputDecoration(labelText: label),
          enabled: !c.locked,
          maxLength: max,
          onChanged: (v) => c.update(key, v),
        ),
      );
      Widget picker(String key, String label, String resource) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey('${f?['id']}-$key-${f?[key]}'),
            initialValue:
                (c.options[resource] ?? []).any((r) => r['id'] == f?[key])
                ? (f?[key] as String?)
                : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: label),
            items: [
              for (final r in c.options[resource] ?? [])
                DropdownMenuItem(
                  value: r['id'] as String,
                  child: Text(
                    resource == 'receipts'
                        ? '${r['document_number']} · ${r['product_name']}'
                        : '${r['code']} · ${r['name']}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: c.locked
                ? null
                : (v) {
                    if (v != null) c.update(key, v);
                  },
          ),
          if (f?[key] != null &&
              !(c.options[resource] ?? []).any((r) => r['id'] == f?[key]))
            Text('Saved selection ${f?[key]} — load references to review.'),
          if (c.cursors[resource] != null)
            TextButton(
              onPressed: c.busy || !c.online
                  ? null
                  : () => c.refresh(resource, more: true),
              child: Text('More $resource'),
            ),
        ],
      );
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Landed value',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Allocate previously recorded freight expense to remaining inventory and consumed-stock variance.',
          ),
          if (c.busy) const LinearProgressIndicator(),
          if (!c.online)
            const Text(
              'Offline — save locally and connect before preview or posting.',
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
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: c.busy ? null : c.create,
                  child: const Text('New landed adjustment'),
                ),
                OutlinedButton(
                  onPressed: c.busy || !c.online
                      ? null
                      : () => c.refresh('posted'),
                  child: const Text('Refresh posted'),
                ),
              ],
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
                        ? 'No posted landed adjustments'
                        : 'Posted adjustments not loaded',
                    description: c.options.containsKey('posted')
                        ? 'Create a landed adjustment after recording the receipt and freight expense. Posted adjustments for this scope will appear here.'
                        : 'Select Refresh posted to review landed adjustments for this scope. Create a new adjustment after recording the receipt and freight expense.',
                  ),
                ),
              ),
            for (final r in c.options['posted'] ?? [])
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${r['reference']} · ${r['receipt_number']}'),
                      Text(
                        '${r['document_date']} · ${r['currency_code']} ${r['amount']}',
                      ),
                      Text(
                        r['reversed'] == true
                            ? 'Reversed'
                            : r['reverse_of'] != null
                            ? 'Linked reversal'
                            : 'Posted',
                      ),
                      TextButton(
                        onPressed: c.busy ? null : () => c.openPosted(r),
                        child: const Text('Review posting'),
                      ),
                    ],
                  ),
                ),
              ),
            if (c.cursors['posted'] != null)
              TextButton(
                onPressed: c.busy || !c.online
                    ? null
                    : () => c.refresh('posted', more: true),
                child: const Text('More postings'),
              ),
          ] else ...[
            Text(
              f['status'] == 'posted'
                  ? 'Posted evidence'
                  : f['reverse_of'] != null
                  ? 'Linked reversal'
                  : 'Local adjustment',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (f['status'] != 'posted' && f['reverse_of'] == null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: c.busy || !c.online ? null : c.references,
                  child: const Text('Refresh receipt and account choices'),
                ),
              ),
              const SizedBox(height: 16),
              picker('receipt_line_id', 'Receipt line', 'receipts'),
              field('amount', 'Exact amount in entity base currency'),
              const SizedBox(height: 12),
              picker(
                'offset_account_id',
                'Recorded freight expense account',
                'accounts',
              ),
              const SizedBox(height: 16),
              picker(
                'variance_account_id',
                'Consumed-stock expense account',
                'accounts',
              ),
            ],
            field('document_date', 'Posting date (YYYY-MM-DD)', max: 10),
            field('reference', 'Reference'),
            field('reason', 'Reason', max: 1000),
            if (p != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p['receipt_number']} · ${p['product_name']}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Received ${p['received_quantity']} · Held ${p['held_quantity']} · Consumed ${p['consumed_quantity']}',
                      ),
                      Text(
                        'Inventory: ${p['currency_code']} ${p['inventory_amount']}',
                      ),
                      Text(
                        'Consumed variance: ${p['currency_code']} ${p['variance_amount']}',
                      ),
                      for (final l in p['legs'] as List? ?? [])
                        Text('${l['warehouse_name']}: ${l['value']}'),
                      if (p['journal_ids'] != null)
                        SelectableText(
                          'Journals: ${(p['journal_ids'] as List).join(', ')}',
                        ),
                    ],
                  ),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: c.busy ? null : c.save,
                  child: const Text('Save locally'),
                ),
                if (f['status'] != 'posted' && f['reverse_of'] == null)
                  OutlinedButton(
                    onPressed: c.locked || !c.online ? null : c.calculate,
                    child: const Text('Preview exact allocation'),
                  ),
                if (f['status'] != 'posted')
                  FilledButton(
                    onPressed:
                        c.busy ||
                            !c.online ||
                            (c.local?.pending == null &&
                                f['reverse_of'] == null &&
                                p == null)
                        ? null
                        : () => confirm(context),
                    child: Text(
                      c.local?.pending != null
                          ? 'Retry saved posting'
                          : 'Post adjustment',
                    ),
                  ),
                if (f['status'] == 'posted' &&
                    f['reverse_of'] == null &&
                    f['reversed'] != true)
                  OutlinedButton(
                    onPressed: c.busy || !c.online ? null : c.reverse,
                    child: const Text('Prepare reversal'),
                  ),
                TextButton(
                  onPressed: c.busy || c.local?.pending != null
                      ? null
                      : c.close,
                  child: const Text('Close editor'),
                ),
              ],
            ),
          ],
        ],
      );
    },
  );
}

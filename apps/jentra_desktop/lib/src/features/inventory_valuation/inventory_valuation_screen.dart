import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_providers.dart';
import 'inventory_valuation_controller.dart';

class InventoryValuationScreen extends ConsumerWidget {
  const InventoryValuationScreen({super.key});
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
    final c = ref.watch(inventoryValuationControllerProvider);
    return c == null
        ? const Center(
            child: Text('Choose a scope with stock, cost and finance access.'),
          )
        : InventoryValuationWorkspace(key: ValueKey(c), controller: c);
  }
}

class InventoryValuationWorkspace extends StatelessWidget {
  const InventoryValuationWorkspace({required this.controller, super.key});
  final InventoryValuationController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller, s = c.summary;
      if (c.accessDenied) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Access changed. Report data has been cleared.'),
              TextButton(
                onPressed: c.busy || !c.online ? null : c.initialize,
                child: const Text('Recheck access'),
              ),
            ],
          ),
        );
      }
      Widget more(String title, VoidCallback action) => TextButton(
        onPressed: c.busy || !c.online ? null : action,
        child: Text(title),
      );
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Inventory valuation',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Saved reports cover the whole legal entity, including stock in transit. Select the inventory control accounts to reconcile.',
          ),
          if (c.busy) const LinearProgressIndicator(),
          if (!c.online)
            const Text(
              'Offline — saved inputs remain available. Connect to generate or read report evidence.',
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: c.busy || c.local?.pending != null
                    ? null
                    : c.newReport,
                child: const Text('New report'),
              ),
              OutlinedButton(
                onPressed: c.busy ? null : c.save,
                child: const Text('Save inputs locally'),
              ),
              more('Refresh saved reports', () => c.refresh('reports')),
            ],
          ),
          if (c.form['status'] != 'generated') ...[
            const SizedBox(height: 16),
            TextFormField(
              key: ValueKey(c.form['id']),
              initialValue: c.form['as_of'] as String? ?? '',
              enabled: !c.locked,
              decoration: const InputDecoration(
                labelText: 'As-of posting date (YYYY-MM-DD)',
              ),
              onChanged: c.date,
            ),
            const SizedBox(height: 12),
            Text(
              'Inventory control accounts (${c.selectedAccounts.length} selected)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (c.accounts.isEmpty && !c.busy)
              const Text(
                'No account choices loaded. Refresh account choices to retry.',
              ),
            more('Refresh account choices', () => c.refresh('accounts')),
            for (final a in c.accounts)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${a['code']} · ${a['name']}'),
                subtitle: a['status'] == 'active'
                    ? null
                    : Text('Historical account · ${a['status']}'),
                value: c.selectedAccounts.contains(a['id']),
                onChanged: c.locked
                    ? null
                    : (v) => c.account(a['id'] as String, v ?? false),
              ),
            if (c.accountCursor != null)
              more('More accounts', () => c.refresh('accounts', more: true)),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: c.busy || !c.online ? null : c.generate,
                child: Text(
                  c.local?.pending == null
                      ? 'Generate saved report'
                      : 'Retry saved generation',
                ),
              ),
            ),
          ],
          if (s.isNotEmpty) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${s['entity_name']} · ${s['as_of']}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      'Generated ${s['generated_at']} · ${s['currency_code']}',
                    ),
                    SelectableText('Report ${s['id']}'),
                    Text(
                      'Warehouses ${s['warehouse_value']} · In transit ${s['transit_value']}',
                    ),
                    Text(
                      'Inventory ${s['inventory_value']} · General ledger ${s['gl_value']}',
                    ),
                    Text(
                      'Difference ${s['difference']} · ${s['difference_count']} source differences',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'Control basis: ${(s['accounts'] as List).map((a) => '${a['code']} ${a['name']}').join(', ')}',
                    ),
                  ],
                ),
              ),
            ),
            if (c.evidenceKey != null) ...[
              SelectableText('Source ${c.evidenceKey}'),
              more('Clear source filter', () => c.sources(null)),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final pair in const {
                  'stock': 'Stock',
                  'lots': 'Lots',
                  'transit': 'In transit',
                  'differences': 'Differences',
                  'movements': 'Movements',
                  'journals': 'Journal lines',
                }.entries)
                  ChoiceChip(
                    label: Text(pair.value),
                    selected: c.section == pair.key,
                    onSelected: c.busy || !c.online
                        ? null
                        : (_) => c.selectSection(pair.key),
                  ),
              ],
            ),
            if (c.section == 'lots')
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Lot values allocate pooled product average cost; they are not separate lot costing.',
                ),
              ),
            more('Refresh this saved section', () => c.refreshPage()),
            if (c.rows.isEmpty && !c.busy)
              const Text('No rows in this saved section.'),
            for (final r in c.rows)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (c.section == 'differences') ...[
                        SelectableText('${r['id']}'),
                        Text(
                          'Inventory ${r['inventory_value']} · GL ${r['gl_value']} · Difference ${r['difference']}',
                        ),
                        more(
                          'View source lines',
                          () => c.sources(r['id'] as String),
                        ),
                      ] else if (c.section == 'journals') ...[
                        Text(
                          '${r['document_number']} · ${r['account_code']} · ${r['posting_date']}',
                        ),
                        Text('Control value ${r['value']}'),
                        SelectableText(
                          '${r['source_type']} · ${r['source_id']}\nJournal ${r['journal_id']} · Line ${r['source_line_id']}',
                        ),
                      ] else if (c.section == 'movements') ...[
                        Text(
                          '${r['product_name']} · ${r['warehouse_name']} · ${r['posting_date']}',
                        ),
                        Text('Quantity ${r['quantity']} · Value ${r['value']}'),
                        SelectableText(
                          '${r['source_type']} · ${r['source_id']}\nMovement ${r['stock_movement_id']} · Line ${r['source_line_id']}',
                        ),
                      ] else ...[
                        Text(
                          '${r['product_name']} · ${r['warehouse_name'] ?? r['reference']}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (c.section == 'transit')
                          Text(
                            '${r['source_warehouse_name']} → ${r['destination_warehouse_name']}',
                          ),
                        if (c.section == 'lots')
                          Text('Lot ${r['lot_code'] ?? 'Untracked / no lot'}'),
                        Text(
                          'Quantity ${r['quantity']} · Value ${r['value'] ?? 'Unallocated'}',
                        ),
                        if (c.section == 'stock')
                          Text(
                            'Average cost (rounded to 12 decimals) ${r['average_cost'] ?? 'Not defined'}',
                          ),
                        if (r['exception'] != null)
                          Text('Review required: ${r['exception']}'),
                      ],
                    ],
                  ),
                ),
              ),
            if (c.cursor != null)
              more('More rows', () => c.refreshPage(more: true)),
          ],
          const SizedBox(height: 24),
          Text('Saved reports', style: Theme.of(context).textTheme.titleLarge),
          if (c.reports.isEmpty && !c.busy)
            const Text('No saved reports loaded.'),
          for (final r in c.reports)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${r['as_of']} · ${r['entity_name']}'),
              subtitle: Text(
                'Generated ${r['generated_at']} · Difference ${r['difference']}',
              ),
              trailing: TextButton(
                onPressed: c.busy || !c.online || c.local?.pending != null
                    ? null
                    : () => c.open(r),
                child: const Text('Open'),
              ),
            ),
          if (c.reportCursor != null)
            more('More saved reports', () => c.refresh('reports', more: true)),
        ],
      );
    },
  );
}

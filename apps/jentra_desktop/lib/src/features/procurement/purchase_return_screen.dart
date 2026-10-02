import 'package:flutter/material.dart';

import '../operations/access_changed.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_providers.dart';
import 'purchase_return_controller.dart';

class PurchaseReturnScreen extends ConsumerWidget {
  const PurchaseReturnScreen({super.key});
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
    final c = ref.watch(purchaseReturnControllerProvider);
    if (c == null) {
      return const Center(
        child: Text('Choose a business scope with purchase return permission.'),
      );
    }
    return PurchaseReturnWorkspace(key: ValueKey(c), controller: c);
  }
}

class PurchaseReturnWorkspace extends StatelessWidget {
  const PurchaseReturnWorkspace({super.key, required this.controller});
  final PurchaseReturnController controller;
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
              'Purchase returns',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Return received goods or record a supplier debit note against an original bill.',
            ),
            const SizedBox(height: 16),
            if (c.busy) const LinearProgressIndicator(),
            if (!c.online)
              const Text(
                'Offline · save your draft on this device. Posting requires a connection.',
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
                  FilledButton(
                    onPressed: c.busy || !c.online
                        ? null
                        : () => c.findSources('bill'),
                    child: const Text('Return against bill'),
                  ),
                  OutlinedButton(
                    onPressed: c.busy || !c.online
                        ? null
                        : () => c.findSources('receipt'),
                    child: const Text('Return unbilled receipt'),
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
              if (c.sourceKind != null) ...[
                const SizedBox(height: 24),
                Text(
                  c.sourceKind == 'bill'
                      ? 'Choose an eligible bill'
                      : 'Choose an unbilled receipt',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: ValueKey(c.sourceKind),
                  initialValue: c.sourceSearch,
                  enabled: !c.busy && c.online,
                  decoration: const InputDecoration(
                    labelText: 'Search supplier or document number',
                    helperText: 'Press Enter to search',
                  ),
                  maxLength: 100,
                  onFieldSubmitted: (text) =>
                      c.findSources(c.sourceKind!, search: text),
                ),
                if (c.sources.isEmpty && !c.busy)
                  const Text('No eligible sources match this search.'),
                for (final row in c.sources)
                  Card(
                    child: ListTile(
                      title: Text(
                        '${row['document_number']} · ${row['supplier_name']}',
                      ),
                      subtitle: Text(
                        '${row['document_date']} · ${row['currency_code']}',
                      ),
                      onTap: c.busy || !c.online
                          ? null
                          : () => c.create(c.sourceKind!, row['id'] as String),
                    ),
                  ),
                if (c.sourceCursor != null)
                  TextButton(
                    onPressed: c.busy || !c.online
                        ? null
                        : () => c.findSources(c.sourceKind!, more: true),
                    child: const Text('Load more sources'),
                  ),
              ],
              const SizedBox(height: 24),
              Text(
                'Posted returns',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (c.page.items.isEmpty && !c.busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('No posted returns loaded.'),
                ),
              for (final row in c.page.items)
                Card(
                  child: ListTile(
                    title: Text('${row['document_number']} · posted'),
                    subtitle: Text(
                      '${row['document_date']} · ${row['currency_code']} ${row['total']}\n${row['reference']}',
                    ),
                    selected: c.selected?['id'] == row['id'],
                    onTap: c.busy
                        ? null
                        : () {
                            c.selected = row;
                            c.emit();
                          },
                  ),
                ),
              if (c.page.nextCursor != null)
                TextButton(
                  onPressed: c.busy || !c.online
                      ? null
                      : () => c.refresh(more: true),
                  child: const Text('Load more returns'),
                ),
              if (c.selected case final selected?) ...[
                const Divider(height: 32),
                Text(
                  'Return ${selected['document_number'] ?? ''}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text('${selected['reference']} · ${selected['document_date']}'),
                Text('${selected['reason']}'),
                Text(
                  'Original ${selected['source_kind'] == 'bill' ? 'bill' : 'receipt'}: ${(selected['source_snapshot'] as Map?)?['document_number'] ?? ''}',
                ),
                Text(
                  '${selected['currency_code']} ${selected['total']} · tax ${selected['tax_total']}',
                ),
                if (selected['source_kind'] == 'bill')
                  const Text(
                    'Supplier credit is available for allocation in Supplier payments.',
                  ),
                for (final raw in selected['lines'] as List? ?? [])
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '${(raw as Map)['description']} · quantity ${raw['quantity']}\nNet ${raw['net_amount']} · tax ${raw['tax_amount']}',
                    ),
                  ),
                ExpansionTile(
                  title: const Text('Posting evidence'),
                  children: [
                    SelectableText(
                      'Journal: ${selected['journal_entry_id'] ?? 'No value posting'}\nStock movement: ${selected['stock_movement_id'] ?? 'Nonstock'}\nPayable item: ${selected['open_item_id'] ?? 'Unbilled receipt return'}',
                    ),
                  ],
                ),
              ],
            ] else ...[
              Text(
                f['source_kind'] == 'bill'
                    ? 'Supplier debit note'
                    : 'Unbilled receipt return',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                '${f['_source_number']} · ${f['_supplier_name']} · ${f['currency_code']}',
              ),
              const SizedBox(height: 16),
              for (final entry in [
                ('document_date', 'Posting date (YYYY-MM-DD)'),
                ('reference', 'Supplier return reference'),
                ('reason', 'Reason for return'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextFormField(
                    key: ValueKey('${f['id']}:${entry.$1}'),
                    initialValue: f[entry.$1] as String?,
                    enabled: !c.locked,
                    maxLength: entry.$1 == 'reason'
                        ? 1000
                        : entry.$1 == 'reference'
                        ? 140
                        : 10,
                    decoration: InputDecoration(
                      labelText: entry.$2,
                      counterText: '',
                    ),
                    onChanged: (v) => c.update(entry.$1, v),
                  ),
                ),
              for (var i = 0; i < (f['lines'] as List).length; i++)
                _ReturnLine(controller: c, index: i),
              const SizedBox(height: 16),
              const Text(
                'Amounts use the original source prices and tax. Eligible quantities and current stock cost are checked again when posted.',
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  try {
                    final amounts = c.preview;
                    return Text(
                      'Expected ${f['source_kind'] == 'bill' ? 'supplier credit' : 'accrual reduction'}: ${f['currency_code']} ${amounts.total} · tax ${amounts.tax}',
                      style: Theme.of(context).textTheme.titleMedium,
                    );
                  } on FormatException catch (e) {
                    return Text(
                      e.message,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 16),
              if (c.local?.pending != null)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'A posting result is uncertain. Retry the saved command to reconcile it safely.',
                  ),
                ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton(
                    onPressed: c.busy || !c.online ? null : c.post,
                    child: Text(
                      c.local?.pending != null
                          ? 'Retry saved posting'
                          : 'Post purchase return',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: c.locked ? null : c.saveLocal,
                    child: const Text('Save on this device'),
                  ),
                  TextButton(
                    onPressed: c.locked ? null : c.discard,
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
}

class _ReturnLine extends StatelessWidget {
  const _ReturnLine({required this.controller, required this.index});
  final PurchaseReturnController controller;
  final int index;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final l = (c.form!['lines'] as List)[index] as Map;
    final serials = (l['serial_ids'] as List).cast<String>();
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
            Text(
              'Eligible: ${l['eligible_quantity']} · base units ${l['conversion_numerator']}/${l['conversion_denominator']}',
            ),
            if (l['lot_code'] != null) Text('Original lot: ${l['lot_code']}'),
            const SizedBox(height: 12),
            TextFormField(
              key: ValueKey('${l['line_id']}:quantity'),
              enabled: !c.locked,
              initialValue: l['quantity'] as String?,
              decoration: const InputDecoration(
                labelText: 'Return quantity',
                helperText: 'Leave at zero to keep this line',
              ),
              onChanged: (v) => c.line(index, 'quantity', v),
            ),
            for (final raw in l['serial_options'] as List)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${(raw as Map)['code']}'),
                subtitle: raw['available'] == true
                    ? null
                    : const Text('Unavailable at original warehouse'),
                value: serials.contains(raw['id']),
                onChanged: c.locked || raw['available'] != true
                    ? null
                    : (value) {
                        c.line(
                          index,
                          'serial_ids',
                          value == true
                              ? [...serials, raw['id']]
                              : serials.where((id) => id != raw['id']).toList(),
                        );
                      },
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import 'receipt_trace_controller.dart';

class ReceiptTraceScreen extends ConsumerWidget {
  const ReceiptTraceScreen({super.key});
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
    final c = ref.watch(receiptTraceControllerProvider);
    if (c == null) {
      return const Center(
        child: Text('Choose a scope with valuation and inventory cost access.'),
      );
    }
    return ReceiptTraceWorkspace(key: ValueKey(c), controller: c);
  }
}

class ReceiptTraceWorkspace extends StatelessWidget {
  const ReceiptTraceWorkspace({required this.controller, super.key});
  final ReceiptTraceController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller, d = c.detail;
      final enabled = c.online && !c.busy;
      Widget panel(List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      );
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Receipt quantity trace',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Follow received quantities through issues, returns and warehouse transfers.',
          ),
          const SizedBox(height: 16),
          if (c.busy) const LinearProgressIndicator(),
          if (!c.online)
            const Text(
              'Offline — displayed quantities may be out of date. Connect to refresh.',
            ),
          if (c.error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                c.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (c.selected == null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: enabled ? c.refresh : null,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh receipts'),
              ),
            ),
            if (c.rows.isEmpty && !c.busy)
              const Text('No receipts in this scope.'),
            for (final row in c.rows)
              panel([
                Text(
                  '${row['document_number']} · ${row['product_name']}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('${row['warehouse_name']} · ${row['posting_date']}'),
                Text('Received ${row['received_quantity']} base units'),
                Text(
                  row['covered'] == true
                      ? 'Receipt attribution available'
                      : 'Historical receipt — attribution unavailable',
                ),
                TextButton(
                  onPressed: enabled ? () => c.open(row) : null,
                  child: const Text('Trace receipt'),
                ),
              ]),
            if (c.cursor != null)
              TextButton(
                onPressed: enabled ? () => c.refresh(more: true) : null,
                child: const Text('More receipts'),
              ),
          ] else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: c.busy ? null : c.close,
                  child: const Text('Back to receipts'),
                ),
                OutlinedButton.icon(
                  onPressed: enabled ? c.refreshDetail : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh trace'),
                ),
              ],
            ),
            Text(
              '${c.selected!['document_number']} · ${c.selected!['product_name']}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (d != null) ...[
              const SizedBox(height: 12),
              if (d['covered'] != true)
                panel([
                  const Text(
                    'Receipt attribution is unavailable for this historical stock. Current warehouse stock cannot establish how much of this receipt remains.',
                  ),
                ])
              else ...[
                panel([
                  Text('Received: ${d['received_quantity']} base units'),
                  Text('In warehouses: ${d['held_quantity']}'),
                  Text('In transit: ${d['in_transit_quantity']}'),
                  Text('Net issued: ${d['net_issued_quantity']}'),
                  const SizedBox(height: 8),
                  const Text(
                    'Net issued includes supplier returns and count shortages. It is not a landed-cost expense allocation.',
                  ),
                  Text('Observed ${d['observed_at']}'),
                ]),
                const SizedBox(height: 8),
                Text(
                  'Current holdings',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if ((d['holdings'] as List).isEmpty)
                  const Text('No attributed warehouse holdings.'),
                for (final h in d['holdings'] as List)
                  Text('${h['warehouse_name']}: ${h['quantity']} base units'),
                const SizedBox(height: 16),
                Text(
                  'Movement history',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text(
                  'Each page reads current committed history. Refresh restarts the view.',
                ),
                for (final e in c.history)
                  panel([
                    Text(
                      '${e['posting_date']} · ${e['source_type']} · ${e['quantity']} base units',
                    ),
                    Text('${e['warehouse_name']} · event ${e['sequence']}'),
                    if (e['lot_code'] != null) Text('Lot ${e['lot_code']}'),
                    if (e['serial_code'] != null)
                      Text('Serial ${e['serial_code']}'),
                    if (e['restores_sequence'] != null)
                      Text('Restores event ${e['restores_sequence']}'),
                    SelectableText('Source ${e['source_id']}'),
                  ]),
                if (c.historyCursor != null)
                  TextButton(
                    onPressed: enabled
                        ? () => c.refreshDetail(more: true)
                        : null,
                    child: const Text('More movements'),
                  ),
              ],
              const SizedBox(height: 16),
              Text(d['attribution_rule'] as String? ?? ''),
            ],
          ],
        ],
      );
    },
  );
}

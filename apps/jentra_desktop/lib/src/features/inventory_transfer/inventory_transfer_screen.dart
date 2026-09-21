import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_providers.dart';
import 'inventory_transfer_controller.dart';

class InventoryTransferScreen extends ConsumerWidget {
  const InventoryTransferScreen({super.key});
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
    final c = ref.watch(inventoryTransferControllerProvider);
    if (c == null) {
      return const Center(
        child: Text('Select an entity and branch with transfer permission.'),
      );
    }
    return InventoryTransferWorkspace(key: ValueKey(c), controller: c);
  }
}

class InventoryTransferWorkspace extends StatelessWidget {
  const InventoryTransferWorkspace({required this.controller, super.key});
  final InventoryTransferController controller;
  Future<void> pick(
    BuildContext context,
    String resource,
    void Function(Map<String, Object?>) selected, {
    String? product,
    bool source = false,
  }) async {
    final c = controller;
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _ReferencePicker(
        controller: c,
        resource: resource,
        product: product,
        source: source,
      ),
    );
    if (result != null && !c.locked) selected(result);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller, f = c.form;
      final dispatch =
          f != null && ['dispatch', 'immediate'].contains(f['operation']);
      Widget field(String key, String label, {int? max}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          key: ValueKey('${f?['id']}-$key'),
          initialValue: f?[key]?.toString() ?? '',
          enabled: !c.locked,
          maxLength: max,
          decoration: InputDecoration(labelText: label),
          onChanged: (value) => c.update(key, value),
        ),
      );
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Warehouse transfers',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Dispatch stock, receive shipments and retain a traceable reversal history.',
          ),
          const SizedBox(height: 16),
          if (c.busy) const LinearProgressIndicator(),
          if (!c.online)
            const Text(
              'Offline — local drafts are available. Posting requires a connection.',
            ),
          if (c.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                c.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (c.message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(c.message!),
            ),
          ExpansionTile(
            title: const Text('Dated stock in transit'),
            children: [
              TextFormField(
                initialValue: c.holdingsDate,
                decoration: const InputDecoration(
                  labelText: 'As of posting date (YYYY-MM-DD)',
                ),
                enabled: !c.busy,
                onChanged: (value) => c.holdingsDate = value,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: c.busy || !c.online ? null : c.loadHoldings,
                  child: const Text('View holdings'),
                ),
              ),
              if (c.loadedHoldingsDate != null)
                Text(
                  'Outstanding shipments at ${c.loadedHoldingsDate} (end of UTC posting date).',
                ),
              if (c.loadedHoldingsDate != null && c.holdings.isEmpty)
                const Text('No outstanding shipments on this date.'),
              for (final h in c.holdings)
                ListTile(
                  title: Text(
                    '${h['reference']} · ${h['source_warehouse_name']} → ${h['destination_warehouse_name']}',
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final raw in h['lines'] as List)
                        Text(
                          '${(raw as Map)['product_name']}: ${raw['base_quantity']} base units${raw['carrying_value'] == null ? '' : ' · ${h['currency_code']} ${raw['carrying_value']}'}',
                        ),
                    ],
                  ),
                ),
              if (c.holdingsCursor != null)
                OutlinedButton(
                  onPressed: c.busy || !c.online
                      ? null
                      : () => c.loadHoldings(more: true),
                  child: const Text('Load more holdings'),
                ),
            ],
          ),
          if (f == null) ...[
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: c.busy ? null : c.create,
                  child: const Text('New transfer'),
                ),
                OutlinedButton(
                  onPressed: c.busy || !c.online ? null : c.refresh,
                  child: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (c.items.isEmpty && !c.busy)
              const Text('No transfers in this branch.'),
            for (final item in c.items)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item['reference']} · ${item['status']}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Dispatch date ${item['document_date']} · Version ${item['version']}',
                      ),
                      Text(
                        '${item['source_warehouse_name']} → ${item['destination_warehouse_name']}',
                      ),
                      for (final raw in item['lines'] as List)
                        Text(
                          '${(raw as Map)['product_name']} · ${raw['base_quantity']} base units',
                        ),
                      ExpansionTile(
                        title: const Text('Movement history'),
                        children: [
                          for (final raw in item['events'] as List)
                            ListTile(
                              title: Text(
                                '${(raw as Map)['operation']} · ${raw['posting_date']}',
                              ),
                              subtitle: Text(
                                '${raw['reason']}\nRequest ${raw['request_id']}',
                              ),
                            ),
                        ],
                      ),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          if (item['status'] == 'in_transit')
                            FilledButton(
                              onPressed: c.busy || !c.online
                                  ? null
                                  : () => c.prepare(item, 'receive'),
                              child: const Text('Receive shipment'),
                            ),
                          if (item['status'] != 'reversed')
                            OutlinedButton(
                              onPressed: c.busy || !c.online
                                  ? null
                                  : () => c.prepare(item, 'reverse'),
                              child: const Text('Prepare reversal'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (c.cursor != null)
              OutlinedButton(
                onPressed: c.busy || !c.online
                    ? null
                    : () => c.refresh(more: true),
                child: const Text('Load more transfers'),
              ),
          ] else ...[
            const SizedBox(height: 16),
            Text(
              '${f['operation']} transfer',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (c.local?.pending != null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'A saved command is awaiting confirmation. Retry sends the identical request.',
                ),
              ),
            const SizedBox(height: 16),
            field('reference', 'Transfer reference', max: 140),
            field('document_date', 'Posting date (YYYY-MM-DD)'),
            field('reason', 'Reason', max: 1000),
            if (dispatch) ...[
              DropdownButtonFormField<String>(
                initialValue: f['operation'] as String,
                decoration: const InputDecoration(labelText: 'Transfer method'),
                items: const [
                  DropdownMenuItem(
                    value: 'dispatch',
                    child: Text('Dispatch into transit'),
                  ),
                  DropdownMenuItem(
                    value: 'immediate',
                    child: Text('Immediate warehouse transfer'),
                  ),
                ],
                onChanged: c.locked
                    ? null
                    : (value) => c.update('operation', value),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed:
                        c.locked || !c.online || (f['lines'] as List).isNotEmpty
                        ? null
                        : () => pick(context, 'warehouses', (w) {
                            c.update('source_warehouse_id', w['id']);
                            c.update('_source_name', w['name']);
                          }, source: true),
                    child: Text(
                      'From: ${f['_source_name'] ?? 'Select warehouse'}',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: c.locked || !c.online
                        ? null
                        : () => pick(context, 'warehouses', (w) {
                            c.update('destination_warehouse_id', w['id']);
                            c.update('_destination_name', w['name']);
                          }),
                    child: Text(
                      'To: ${f['_destination_name'] ?? 'Select warehouse'}',
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            for (var i = 0; i < (f['lines'] as List).length; i++)
              _line(context, i, (f['lines'] as List)[i] as Map, dispatch),
            if (dispatch)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed:
                      c.locked || !c.online || f['source_warehouse_id'] == null
                      ? null
                      : () => pick(context, 'products', c.addProduct),
                  icon: const Icon(Icons.add),
                  label: const Text('Add product'),
                ),
              ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: c.busy || !c.online ? null : c.submit,
                  child: Text(
                    c.local?.pending != null
                        ? 'Retry saved action'
                        : switch (f['operation']) {
                            'receive' => 'Confirm receipt',
                            'reverse' => 'Post reasoned reversal',
                            'immediate' => 'Post immediate transfer',
                            _ => 'Dispatch shipment',
                          },
                  ),
                ),
                OutlinedButton(
                  onPressed: c.locked ? null : c.save,
                  child: const Text('Save local draft'),
                ),
                TextButton(
                  onPressed: c.locked ? null : c.discard,
                  child: const Text('Discard draft'),
                ),
              ],
            ),
          ],
        ],
      );
    },
  );
  Widget _line(BuildContext context, int i, Map line, bool editable) {
    final c = controller;
    final units = (line['units'] as List? ?? []).cast<Map>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${line['product_name']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (editable) ...[
              TextFormField(
                key: ValueKey('${line['line_id']}-quantity'),
                initialValue: line['quantity'] as String,
                enabled: !c.locked,
                decoration: const InputDecoration(labelText: 'Quantity'),
                onChanged: (v) => c.updateLine(i, 'quantity', v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: line['unit_id'] as String,
                decoration: const InputDecoration(
                  labelText: 'Transaction unit',
                ),
                items: [
                  for (final u in units)
                    DropdownMenuItem(
                      value: u['id'] as String,
                      child: Text(
                        '${u['name']} (${u['numerator']}/${u['denominator']})',
                      ),
                    ),
                ],
                onChanged: c.locked
                    ? null
                    : (value) {
                        final u = units.firstWhere((u) => u['id'] == value);
                        c.updateLine(i, 'unit_id', value);
                        c.updateLine(i, 'conversion_numerator', u['numerator']);
                        c.updateLine(
                          i,
                          'conversion_denominator',
                          u['denominator'],
                        );
                      },
              ),
              if (line['tracking_mode'] == 'lot')
                OutlinedButton(
                  onPressed: c.locked || !c.online
                      ? null
                      : () => pick(context, 'lots', (lot) {
                          c.updateLine(i, 'lot_id', lot['id']);
                          c.updateLine(i, '_lot_code', lot['code']);
                        }, product: line['product_id'] as String),
                  child: Text('Lot: ${line['_lot_code'] ?? 'Select lot'}'),
                ),
              if (line['tracking_mode'] == 'serial') ...[
                Text('${(line['serial_ids'] as List).length} serials selected'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final id in line['serial_ids'] as List)
                      InputChip(
                        label: Text(
                          '${(line['_serial_names'] as Map?)?[id] ?? id}',
                        ),
                        onDeleted: c.locked
                            ? null
                            : () => c.updateLine(
                                i,
                                'serial_ids',
                                [...line['serial_ids'] as List]..remove(id),
                              ),
                      ),
                  ],
                ),
                OutlinedButton(
                  onPressed: c.locked || !c.online
                      ? null
                      : () => pick(context, 'serials', (serial) {
                          c.updateLine(
                            i,
                            'serial_ids',
                            {
                              ...line['serial_ids'] as List,
                              serial['id'],
                            }.toList(),
                          );
                          c.updateLine(i, '_serial_names', {
                            ...line['_serial_names'] as Map? ?? {},
                            serial['id']: serial['code'],
                          });
                        }, product: line['product_id'] as String),
                  child: const Text('Select serial'),
                ),
              ],
              TextButton(
                onPressed: c.locked
                    ? null
                    : () => c.update(
                        'lines',
                        [...c.form!['lines'] as List]..removeAt(i),
                      ),
                child: const Text('Remove line'),
              ),
            ] else
              Text(
                '${line['base_quantity']} base units · ${line['quantity']} transaction units',
              ),
          ],
        ),
      ),
    );
  }
}

class _ReferencePicker extends StatefulWidget {
  const _ReferencePicker({
    required this.controller,
    required this.resource,
    this.product,
    this.source = false,
  });
  final InventoryTransferController controller;
  final String resource;
  final String? product;
  final bool source;
  @override
  State<_ReferencePicker> createState() => _ReferencePickerState();
}

class _ReferencePickerState extends State<_ReferencePicker> {
  List<Map<String, Object?>> rows = [];
  String? cursor, error;
  String search = '';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool more = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final c = widget.controller;
      final r = await c.gateway.options(
        c.scope,
        widget.resource,
        warehouse: c.form?['source_warehouse_id'] as String?,
        product: widget.product,
        after: more ? cursor : null,
        search: search,
      );
      if (!mounted) return;
      setState(() {
        rows = [
          if (more) ...rows,
          for (final raw in r['items'] as List)
            (raw as Map).cast<String, Object?>(),
        ];
        cursor = r['next_cursor'] as String?;
      });
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Unable to load choices. Retry when connected.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Select ${widget.resource}'),
    content: SizedBox(
      width: 540,
      height: 440,
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(labelText: 'Search'),
            maxLength: 100,
            onChanged: (v) => search = v,
            onSubmitted: (_) => load(),
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          Expanded(
            child: ListView(
              children: [
                for (final row in rows)
                  if (!widget.source ||
                      row['branch_id'] == widget.controller.scope.branchId)
                    ListTile(
                      title: Text('${row['name'] ?? row['code']}'),
                      subtitle: Text(
                        '${row['available_quantity'] ?? row['on_hand_quantity'] ?? row['code'] ?? ''}',
                      ),
                      onTap: () => Navigator.pop(context, row),
                    ),
                if (rows.isEmpty && !busy) const Text('No eligible choices.'),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: busy ? null : () => load(),
                child: const Text('Search / retry'),
              ),
              if (cursor != null)
                TextButton(
                  onPressed: busy ? null : () => load(more: true),
                  child: const Text('Load more'),
                ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app_providers.dart';
import 'sourcing_controller.dart';
import 'procurement_picker.dart';

class SourcingScreen extends ConsumerWidget {
  const SourcingScreen({super.key});
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
    final c = ref.watch(sourcingControllerProvider);
    if (c == null) {
      return const Center(
        child: Text(
          'Choose an online business scope with sourcing permission.',
        ),
      );
    }
    return SourcingWorkspace(
      key: ValueKey(c),
      controller: c,
      canOrder: caps.value?.contains('procurement.orders.manage') ?? false,
    );
  }
}

class SourcingWorkspace extends StatelessWidget {
  const SourcingWorkspace({
    super.key,
    required this.controller,
    this.canOrder = false,
  });
  final SourcingController controller;
  final bool canOrder;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Supplier sourcing',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Approved requirements, comparable responses and accountable supplier selection',
            ),
            const SizedBox(height: 16),
            if (c.busy) const LinearProgressIndicator(),
            if (!c.online)
              const Text(
                'Offline · authoritative sourcing actions require a connection.',
              ),
            if (c.error != null)
              Text(
                c.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (c.message != null) Text(c.message!),
            const SizedBox(height: 16),
            if (c.form == null) ...[
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: c.locked || !c.online
                        ? null
                        : () async {
                            final source = await pickSourcingReference(
                              context,
                              c.gateway,
                              c.scope,
                              'requisitions',
                            );
                            if (source != null && !c.locked) {
                              await c.issue(
                                (source['detail'] as Map)
                                    .cast<String, Object?>(),
                              );
                            }
                          },
                    icon: const Icon(Icons.add),
                    label: const Text('Issue RFQ from requisition'),
                  ),
                  OutlinedButton(
                    onPressed: c.busy || !c.online ? null : c.refresh,
                    child: const Text('Refresh'),
                  ),
                  TextButton(
                    onPressed: () => context.go('/procurement'),
                    child: const Text('Requisitions'),
                  ),
                  if (canOrder)
                    TextButton(
                      onPressed: () => context.go('/procurement/orders'),
                      child: const Text('Purchase orders'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (c.page.items.isEmpty && !c.busy)
                const Text('No requests for quote loaded.'),
              for (final rfq in c.page.items)
                Card(
                  child: ListTile(
                    title: Text('${rfq['document_number']} · ${rfq['title']}'),
                    subtitle: Text(
                      '${rfq['status']} · Responses ${(rfq['quotes'] as List).length} · Close ${rfq['close_date']}',
                    ),
                    onTap: c.busy ? null : () => c.select(rfq),
                  ),
                ),
              if (c.page.nextCursor != null)
                TextButton(
                  onPressed: c.busy ? null : () => c.refresh(more: true),
                  child: const Text('Load more'),
                ),
              if (c.selected != null) _RfqDetail(controller: c),
            ] else
              _SourcingEditor(
                key: ValueKey((
                  c.form!['id'],
                  c.form!['operation'],
                  c.form!['quote_id'],
                )),
                controller: c,
              ),
          ],
        ),
      );
    },
  );
}

class _RfqDetail extends StatelessWidget {
  const _RfqDetail({required this.controller});
  final SourcingController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller, r = c.selected!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${r['document_number']} · ${r['status']}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const Text('Invited suppliers'),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final supplier in (r['invited_suppliers'] as List? ?? []))
                  OutlinedButton(
                    onPressed: c.busy || !c.online || r['status'] != 'issued'
                        ? null
                        : () => c.quote(
                            (supplier as Map).cast<String, Object?>(),
                          ),
                    child: Text(
                      'Record response · ${(supplier as Map)['name']}',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Compare responses',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text(
              'Base-currency totals include the recorded rate. Incomplete or expired responses cannot be selected.',
            ),
            for (final raw in (r['quotes'] as List? ?? []))
              Builder(
                builder: (context) {
                  final quote = (raw as Map).cast<String, Object?>();
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${quote['supplier_name']} · ${quote['complete'] == true ? 'Complete response' : 'Incomplete response'}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '${quote['currency_code']} ${quote['total']} · Base ${c.baseCurrency ?? ''} ${quote['base_total']}',
                          ),
                          Text(
                            'Valid until ${quote['valid_until']} · Rate ${quote['exchange_rate']}',
                          ),
                          Text(
                            'Payment: ${quote['payment_terms']} · Delivery: ${quote['delivery_terms']}',
                          ),
                          for (final line in (quote['lines'] as List))
                            Text(
                              '${(line as Map)['description']} · ${line['quantity']} × ${line['unit_price']} · Total ${line['line_total']}',
                            ),
                          if (r['status'] == 'issued')
                            TextButton(
                              onPressed:
                                  c.busy ||
                                      !c.online ||
                                      quote['complete'] != true
                                  ? null
                                  : () async {
                                      final reason = await sourcingReason(
                                        context,
                                        'Why select ${quote['supplier_name']}?',
                                      );
                                      if (reason != null && reason.isNotEmpty) {
                                        await c.choose(quote, reason);
                                      }
                                    },
                              child: const Text('Select supplier with reason'),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            if (r['selection_reason'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text('Selection rationale: ${r['selection_reason']}'),
              ),
          ],
        ),
      ),
    );
  }
}

Future<String?> sourcingReason(BuildContext context, String title) async {
  final input = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: input,
        autofocus: true,
        maxLength: 1000,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Reason'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, input.text.trim()),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) => input.dispose());
  return result;
}

class _SourcingEditor extends StatelessWidget {
  const _SourcingEditor({super.key, required this.controller});
  final SourcingController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller, f = c.form!;
    Widget field(String key, String label, {int maxLines = 1}) => TextFormField(
      initialValue: '${f[key] ?? ''}',
      enabled: !c.locked,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
      onChanged: (v) => c.update(key, v),
    );
    final operation = f['operation'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          operation == 'issue'
              ? 'Issue request for quote'
              : operation == 'select'
              ? 'Confirm supplier selection'
              : 'Record supplier quotation',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 20),
        if (operation == 'issue') ...[
          Text(
            'Source requisition ${f['_source_number']} · approved version ${f['requisition_version']}',
          ),
          const SizedBox(height: 16),
          field('title', 'Sourcing title'),
          const SizedBox(height: 16),
          const Text('Requested lines to source'),
          for (final raw in (f['_source_lines'] as List? ?? []))
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${raw['description']} · ${raw['quantity']}'),
              value: (f['source_line_ids'] as List).contains(raw['line_id']),
              onChanged: c.locked
                  ? null
                  : (checked) {
                      final ids = List<Object?>.from(
                        c.form!['source_line_ids'] as List,
                      );
                      if (checked == true) {
                        ids.add(raw['line_id']);
                      } else {
                        ids.remove(raw['line_id']);
                      }
                      c.update('source_line_ids', ids);
                    },
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(width: 250, child: field('document_date', 'RFQ date')),
              SizedBox(width: 250, child: field('close_date', 'Close date')),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final supplier in (f['_supplier_labels'] as List? ?? []))
                InputChip(
                  label: Text('${(supplier as Map)['name']}'),
                  onDeleted: c.locked
                      ? null
                      : () {
                          c.update(
                            'invited_supplier_ids',
                            (f['invited_supplier_ids'] as List)
                                .where((id) => id != supplier['id'])
                                .toList(),
                          );
                          c.update(
                            '_supplier_labels',
                            (f['_supplier_labels'] as List)
                                .where(
                                  (s) => (s as Map)['id'] != supplier['id'],
                                )
                                .toList(),
                          );
                        },
                ),
              OutlinedButton(
                onPressed: c.locked || !c.online
                    ? null
                    : () async {
                        final supplier = await pickSourcingReference(
                          context,
                          c.gateway,
                          c.scope,
                          'suppliers',
                        );
                        if (supplier == null || c.locked) return;
                        final ids = List<Object?>.from(
                          c.form!['invited_supplier_ids'] as List,
                        );
                        if (ids.contains(supplier['id'])) return;
                        c.update('invited_supplier_ids', [
                          ...ids,
                          supplier['id'],
                        ]);
                        c.update('_supplier_labels', [
                          ...c.form!['_supplier_labels'] as List,
                          supplier,
                        ]);
                      },
                child: const Text('Add invited supplier'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Invitations are recorded here. External email delivery is separate.',
          ),
        ] else if (operation == 'record_quote') ...[
          Text('${f['_supplier_name']}'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(
                width: 250,
                child: field('quote_date', 'Quotation date'),
              ),
              SizedBox(width: 250, child: field('valid_until', 'Valid until')),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Currency ${f['currency_code']} · rate ${f['exchange_rate']} · ${f['rate_date']}',
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton(
                onPressed: c.locked || !c.online
                    ? null
                    : () async {
                        final rate = await pickSourcingReference(
                          context,
                          c.gateway,
                          c.scope,
                          'rates',
                        );
                        if (rate == null || c.locked) return;
                        for (final key in [
                          'currency_code',
                          'exchange_rate',
                          'rate_date',
                        ]) {
                          c.update(key, rate[key]);
                        }
                        c.update('exchange_rate_id', rate['id']);
                      },
                child: const Text('Choose governed FX rate'),
              ),
              TextButton(
                onPressed: c.locked || c.baseCurrency == null
                    ? null
                    : () {
                        c.update('currency_code', c.baseCurrency);
                        c.update('exchange_rate', '1');
                        c.update('exchange_rate_id', null);
                      },
                child: const Text('Use base currency'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          field('payment_terms', 'Payment terms'),
          const SizedBox(height: 16),
          field('delivery_terms', 'Delivery terms'),
          const SizedBox(height: 20),
          for (var i = 0; i < (f['lines'] as List).length; i++)
            Builder(
              builder: (context) {
                final lines = (f['lines'] as List)
                    .map((x) => (x as Map).cast<String, Object?>())
                    .toList();
                final line = lines[i];
                void change(String k, Object? v) {
                  lines[i] = {...lines[i], k: v};
                  c.update('lines', lines);
                }

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${line['description']}'),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            for (final entry in const {
                              'quantity': 'Quantity',
                              'unit_price': 'Unit price',
                              'discount_percent': 'Discount %',
                            }.entries)
                              SizedBox(
                                width: 230,
                                child: TextFormField(
                                  initialValue: '${line[entry.key] ?? ''}',
                                  enabled: !c.locked,
                                  decoration: InputDecoration(
                                    labelText: entry.value,
                                  ),
                                  onChanged: (v) => change(entry.key, v),
                                ),
                              ),
                            OutlinedButton(
                              onPressed: c.locked || !c.online
                                  ? null
                                  : () async {
                                      final tax = await pickSourcingReference(
                                        context,
                                        c.gateway,
                                        c.scope,
                                        'taxes',
                                      );
                                      if (tax == null || c.locked) return;
                                      change('tax_definition_id', tax['id']);
                                      change('_tax_label', tax['name']);
                                    },
                              child: Text(
                                '${line['_tax_label'] ?? (line['tax_definition_id'] == null ? 'Choose input tax' : 'Selected input tax')}',
                              ),
                            ),
                            if (line['tax_definition_id'] != null)
                              TextButton(
                                onPressed: c.locked
                                    ? null
                                    : () {
                                        change('tax_definition_id', null);
                                        change('_tax_label', null);
                                      },
                                child: const Text('No tax'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ] else ...[
          Text('Supplier: ${f['_supplier_name']}'),
          field('selection_reason', 'Selection rationale', maxLines: 3),
        ],
        const SizedBox(height: 24),
        if (c.local?.errorCode == 'VERSION_CONFLICT')
          const Text(
            'The RFQ changed. Retain your notes, discard this local edit and refresh before preparing a new command.',
          ),
        if (c.local?.pending != null)
          const Text(
            'A saved command needs confirmation. Retry keeps its original IDs and exact inputs.',
          ),
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
                    : operation == 'issue'
                    ? 'Issue RFQ'
                    : 'Save to server',
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
                      final result = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Discard local sourcing draft?'),
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
                      if (result == true) await c.discard();
                    },
              child: const Text('Discard local draft'),
            ),
          ],
        ),
      ],
    );
  }
}

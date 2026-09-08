import 'dart:async';
import 'package:flutter/material.dart';
import 'package:jentra_domain/jentra_receivables.dart';
import 'package:uuid/uuid.dart';
import 'receivables_controller.dart';
import 'receivable_picker.dart';

class ReceivableEditor extends StatefulWidget {
  const ReceivableEditor({super.key, required this.controller});
  final ReceivablesController controller;
  @override
  State<ReceivableEditor> createState() => _ReceivableEditorState();
}

class _ReceivableEditorState extends State<ReceivableEditor> {
  late Map<String, Object?> form;
  ReceivablesController get c => widget.controller;
  bool direct(Map<String, Object?> line) =>
      c.kind == ReceivableKind.invoice &&
      line['sales_order_line_id'] == null &&
      line['delivery_line_id'] == null;
  @override
  void initState() {
    super.initState();
    form = receivableMap(c.form);
  }

  List<Map<String, Object?>> get lines =>
      (form['lines'] as List? ?? []).map(receivableMap).toList();
  void update(String field, Object? value) {
    setState(() {
      if (value == '' && field == 'due_date') {
        form.remove(field);
      } else {
        form[field] = value;
      }
    });
    unawaited(c.saveLocal(form));
  }

  void updateLine(int i, String field, Object? value) {
    final values = lines;
    if (value == '' && field == 'discount_amount') {
      values[i].remove(field);
    } else {
      values[i][field] = value;
    }
    if (field == 'base_quantity' && values[i]['product_id'] != null) {
      values[i]['quantity'] = value;
    }
    update('lines', values);
  }

  Widget field(String key, String label, {int? line, int maxLines = 1}) =>
      SizedBox(
        width: MediaQuery.textScalerOf(context).scale(1) > 1.4 ? 400 : 270,
        child: TextFormField(
          key: ValueKey('$key:$line'),
          initialValue:
              '${line == null ? form[key] ?? '' : lines[line][key] ?? ''}',
          enabled: c.canEdit,
          maxLines: maxLines,
          decoration: InputDecoration(labelText: label),
          onChanged: (v) =>
              line == null ? update(key, v) : updateLine(line, key, v),
        ),
      );
  Widget pick(
    String key,
    String label,
    String resource, {
    void Function(Map<String, Object?>)? selected,
  }) => SizedBox(
    width: MediaQuery.textScalerOf(context).scale(1) > 1.4 ? 400 : 270,
    child: OutlinedButton.icon(
      onPressed: c.canEdit && c.online
          ? () async {
              final row = await pickReceivableReference(
                context,
                c,
                resource,
                label,
                customerId: form['customer_id'] as String?,
              );
              if (row == null || !mounted) return;
              if (selected != null) {
                selected(row);
              } else {
                form['_${key}_label'] = referenceLabel(row);
                update(key, row['id']);
              }
            }
          : null,
      icon: const Icon(Icons.search, size: 18),
      label: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Text(
          '${form['_${key}_label'] ?? (key == 'customer_id' ? form['customer_name'] : null) ?? label}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ),
  );
  Future<void> addSource(String resource) async {
    final source = await pickReceivableReference(
      context,
      c,
      resource,
      'Choose a source document',
      customerId: form['customer_id'] as String?,
    );
    if (source == null || !mounted) return;
    final line = await pickReceivableLine(context, source, c);
    if (line == null || !mounted) return;
    if (c.kind == ReceivableKind.delivery &&
        form['sales_order_id'] != null &&
        form['sales_order_id'] != source['id']) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('One delivery must use a single sales order.'),
        ),
      );
      return;
    }
    if (lines.isNotEmpty &&
        (form['customer_id'] != source['customer_id'] ||
            form['currency_code'] != source['currency_code'])) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All lines must use the same customer and currency.'),
        ),
      );
      return;
    }
    form['customer_id'] = source['customer_id'];
    form['_customer_id_label'] =
        source['customer_name'] ?? source['customer_id'];
    form['currency_code'] = source['currency_code'];
    form['exchange_rate_id'] = source['exchange_rate_id'];
    if (c.kind == ReceivableKind.delivery) {
      form['sales_order_id'] = source['id'];
      form['warehouse_id'] = source['warehouse_id'];
    }
    final sourceKey = resource == 'sales_order_details'
        ? 'sales_order_line_id'
        : resource == 'deliveries'
        ? 'delivery_line_id'
        : 'sales_invoice_line_id';
    if (lines.any((l) => l[sourceKey] == line['id'])) return;
    update('lines', [
      ...lines,
      {
        'line_id': const Uuid().v4(),
        sourceKey: line['id'],
        'description': line['description'],
        'base_quantity': '1',
        '_source_number': source['document_number'],
        '_tracking_mode':
            line['tracking_mode'] ??
            receivableMap(line['snapshot'] ?? {})['tracking_mode'],
        if (c.kind == ReceivableKind.credit) 'disposition': 'saleable',
      },
    ]);
  }

  Future<void> addService() async {
    final product = await pickReceivableReference(
      context,
      c,
      'products',
      'Choose a service or non-stocked product',
    );
    if (product == null || !mounted) return;
    update('lines', [
      ...lines,
      {
        'line_id': const Uuid().v4(),
        'product_id': product['id'],
        'description': product['name'],
        'unit_id': product['base_unit_id'],
        'quantity': '1',
        'base_quantity': '1',
        'conversion_numerator': '1',
        'conversion_denominator': '1',
        'unit_price': '0',
      },
    ]);
  }

  Future<void> tracking(int i, bool serial) async {
    final row = await pickReceivableReference(
      context,
      c,
      serial ? 'serials' : 'lots',
      serial ? 'Choose serial' : 'Choose lot',
    );
    if (row == null || !mounted) return;
    final old = receivableMap(lines[i]['tracking'] ?? {});
    if (serial) {
      final ids = List<String>.from(old['serial_ids'] as List? ?? []);
      if (!ids.contains(row['id'])) ids.add(row['id']! as String);
      old['serial_ids'] = ids;
    } else {
      old['lot_id'] = row['id'];
    }
    updateLine(i, 'tracking', old);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Draft · ${c.kind.label}',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          pick(
            'customer_id',
            'Choose customer',
            'parties',
            selected: (r) {
              if (lines.isNotEmpty) return;
              form['_customer_id_label'] = referenceLabel(r);
              update('customer_id', r['id']);
            },
          ),
          field('document_date', 'Document date · YYYY-MM-DD'),
          field('due_date', 'Due date · YYYY-MM-DD'),
          pick(
            'currency_code',
            'Currency · ${form['currency_code']}',
            'currencies',
            selected: (r) {
              if (lines.isNotEmpty) return;
              form['_currency_code_label'] = referenceLabel(r);
              form.remove('exchange_rate_id');
              update('currency_code', r['code']);
            },
          ),
          pick(
            'exchange_rate_id',
            'FX rate · foreign currency only',
            'exchange_rates',
          ),
          TextButton(
            onPressed: c.canEdit
                ? () => update('exchange_rate_id', null)
                : null,
            child: const Text('Use entity base currency rate'),
          ),
          if (c.kind == ReceivableKind.receipt) ...[
            pick(
              'cash_bank_account_id',
              'Choose cash / bank account',
              'cash_bank_accounts',
            ),
            field('amount', 'Receipt amount'),
          ],
          field('external_reference', 'External reference'),
          field('notes', 'Notes'),
          field('terms', 'Payment terms'),
          if (c.kind == ReceivableKind.receipt)
            SizedBox(
              width: 270,
              child: DropdownButtonFormField<String>(
                initialValue:
                    receivableMap(form['tender_metadata'] ?? {})['method']
                        as String?,
                decoration: const InputDecoration(labelText: 'Tender method'),
                items: [
                  for (final m in ['bank_transfer', 'cash', 'cheque', 'card'])
                    DropdownMenuItem(
                      value: m,
                      child: Text(m.replaceAll('_', ' ')),
                    ),
                ],
                onChanged: c.canEdit
                    ? (v) => update('tender_metadata', {'method': v})
                    : null,
              ),
            ),
          if (c.kind == ReceivableKind.credit)
            field('reason', 'Return / credit reason'),
        ],
      ),
      if (c.kind == ReceivableKind.delivery)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Order and warehouse are taken from the selected source. Base-unit quantities consume active reservations.',
          ),
        ),
      if (c.kind != ReceivableKind.receipt) ...[
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (c.kind == ReceivableKind.delivery ||
                c.kind == ReceivableKind.invoice)
              OutlinedButton.icon(
                onPressed: c.canEdit && c.online
                    ? () => addSource('sales_order_details')
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('From order'),
              ),
            if (c.kind != ReceivableKind.delivery)
              OutlinedButton.icon(
                onPressed: c.canEdit && c.online
                    ? () => addSource('deliveries')
                    : null,
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('From delivery'),
              ),
            if (c.kind == ReceivableKind.credit)
              OutlinedButton.icon(
                onPressed: c.canEdit && c.online
                    ? () => addSource('sales_invoices')
                    : null,
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('From invoice'),
              ),
            if (c.kind == ReceivableKind.invoice)
              OutlinedButton.icon(
                onPressed: c.canEdit && c.online ? addService : null,
                icon: const Icon(Icons.add),
                label: const Text('Direct service line'),
              ),
          ],
        ),
        for (var i = 0; i < lines.length; i++)
          Card(
            margin: const EdgeInsets.only(top: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${i + 1}. ${lines[i]['description'] ?? 'Source line'}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove line ${i + 1}',
                        onPressed: c.canEdit
                            ? () {
                                final next = lines..removeAt(i);
                                update('lines', next);
                              }
                            : null,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  if (lines[i]['_source_number'] != null)
                    Text('Source ${lines[i]['_source_number']}'),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      field('base_quantity', 'Base quantity', line: i),
                      if (direct(lines[i])) ...[
                        field('quantity', 'Transaction quantity', line: i),
                        field('unit_price', 'Unit price', line: i),
                        field(
                          'discount_amount',
                          'Line discount amount',
                          line: i,
                        ),
                        TextButton(
                          onPressed: c.canEdit && c.online
                              ? () async {
                                  final tax = await pickReceivableReference(
                                    context,
                                    c,
                                    'tax_definitions',
                                    'Choose tax',
                                  );
                                  if (tax != null && mounted) {
                                    updateLine(
                                      i,
                                      'tax_definition_id',
                                      tax['id'],
                                    );
                                  }
                                }
                              : null,
                          child: Text(
                            lines[i]['tax_definition_id'] == null
                                ? 'Choose tax'
                                : 'Tax selected',
                          ),
                        ),
                        TextButton(
                          onPressed: c.canEdit
                              ? () => updateLine(i, 'tax_definition_id', null)
                              : null,
                          child: const Text('Clear tax'),
                        ),
                      ],
                      if (c.kind == ReceivableKind.credit)
                        SizedBox(
                          width: 270,
                          child: DropdownButtonFormField<String>(
                            initialValue: lines[i]['disposition'] as String?,
                            decoration: const InputDecoration(
                              labelText: 'Disposition',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'saleable',
                                child: Text('Return to saleable stock'),
                              ),
                              DropdownMenuItem(
                                value: 'no_restock',
                                child: Text('Credit only · no restock'),
                              ),
                            ],
                            onChanged: c.canEdit
                                ? (v) => updateLine(i, 'disposition', v)
                                : null,
                          ),
                        ),
                    ],
                  ),
                  if (c.kind == ReceivableKind.delivery ||
                      c.kind == ReceivableKind.credit)
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: c.canEdit && c.online
                              ? () => tracking(i, false)
                              : null,
                          child: const Text('Choose lot'),
                        ),
                        TextButton(
                          onPressed: c.canEdit && c.online
                              ? () => tracking(i, true)
                              : null,
                          child: const Text('Add serial'),
                        ),
                        TextButton(
                          onPressed: c.canEdit
                              ? () => updateLine(
                                  i,
                                  'tracking',
                                  <String, Object?>{},
                                )
                              : null,
                          child: const Text('Clear tracking'),
                        ),
                        Text(
                          'Serials: ${(receivableMap(lines[i]['tracking'] ?? {})['serial_ids'] as List? ?? []).length}',
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
      const SizedBox(height: 16),
      const Text(
        'Totals are calculated and validated by the server when saved. Local drafts do not post stock or accounting entries.',
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        children: [
          FilledButton.icon(
            onPressed: c.canEdit && c.online ? c.saveServer : null,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Save & calculate'),
          ),
          OutlinedButton(
            onPressed: !c.busy && !c.pending ? c.closeEditor : null,
            child: const Text('Close · keep local draft'),
          ),
          Text(
            c.saving
                ? 'Saving encrypted draft…'
                : c.localSaveFailed
                ? 'Local save failed · keep this editor open'
                : 'Draft saved locally',
          ),
        ],
      ),
    ],
  );
}

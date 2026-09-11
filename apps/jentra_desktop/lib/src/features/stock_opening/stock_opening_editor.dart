import 'dart:async';
import 'package:flutter/material.dart';
import 'package:jentra_domain/jentra_stock_opening.dart';
import 'package:uuid/uuid.dart';
import 'stock_opening_controller.dart';
import 'stock_opening_picker.dart';

class StockOpeningEditor extends StatefulWidget {
  const StockOpeningEditor({super.key, required this.controller});
  final StockOpeningController controller;
  @override
  State<StockOpeningEditor> createState() => _EditorState();
}

class _EditorState extends State<StockOpeningEditor> {
  late Map<String, Object?> form;
  StockOpeningController get c => widget.controller;
  List<Map<String, Object?>> get lines =>
      (form['lines'] as List? ?? []).map(openingMap).toList();
  @override
  void initState() {
    super.initState();
    form = openingMap(c.form);
  }

  void update(String key, Object? value) {
    if (!c.canEdit) return;
    setState(() => form[key] = value);
    unawaited(c.saveLocal(form));
  }

  void lineUpdate(int index, String key, Object? value) {
    final next = lines;
    if (value == '' && {'expiry_date', 'manufacture_date'}.contains(key)) {
      next[index].remove(key);
    } else {
      next[index][key] = value;
    }
    update('lines', next);
  }

  Widget field(
    String key,
    String label,
    double width, {
    int? line,
    int maxLines = 1,
    String? helper,
  }) {
    final data = line == null ? form : lines[line];
    final value = key == 'serial_codes'
        ? (data[key] as List? ?? []).join('\n')
        : '${data[key] ?? ''}';
    return SizedBox(
      width: width,
      child: TextFormField(
        key: ValueKey('${data['line_id'] ?? 'header'}:$key'),
        initialValue: value,
        enabled: c.canEdit,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
        ),
        onChanged: (text) {
          if (line == null) {
            update(key, text);
          } else {
            lineUpdate(
              line,
              key,
              key == 'serial_codes'
                  ? text
                        .split('\n')
                        .map((s) => s.trim())
                        .where((s) => s.isNotEmpty)
                        .toList()
                  : text,
            );
          }
        },
      ),
    );
  }

  Widget choose(String key, String label, String resource, double width) =>
      SizedBox(
        width: width,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.search),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '${form['_${key}_label'] ?? c.labels[form[key]] ?? label}',
            ),
          ),
          onPressed: c.canEdit && c.online
              ? () async {
                  final row = await pickStockOpeningReference(
                    context,
                    c,
                    resource,
                    label,
                  );
                  if (!mounted || !c.canEdit || row == null) return;
                  form['_${key}_label'] = openingReferenceLabel(row);
                  update(key, row['id']);
                }
              : null,
        ),
      );
  Future<void> addProduct() async {
    final row = await pickStockOpeningReference(
      context,
      c,
      'products',
      'Choose a stocked product',
    );
    if (!mounted || !c.canEdit || row == null) return;
    var unitLabel = 'Base units';
    try {
      final units = await c.repository.references(
        c.scope,
        'units',
        id: row['base_unit_id'] as String?,
      );
      if (units.items.isNotEmpty) {
        unitLabel =
            '${units.items.first['name']} (${units.items.first['symbol']})';
      }
    } catch (_) {
      /* The server still validates the active base unit. */
    }
    if (!mounted || !c.canEdit) return;
    update('lines', [
      ...lines,
      {
        'line_id': const Uuid().v4(),
        'product_id': row['id'],
        'product_name': row['name'],
        'sku': row['sku'],
        'base_unit_id': row['base_unit_id'],
        'tracking_mode': row['tracking_mode'],
        '_unit_label': unitLabel,
        'base_quantity': '',
        'base_value': '',
        'serial_codes': <String>[],
      },
    ]);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth < 600
          ? constraints.maxWidth
          : MediaQuery.textScalerOf(context).scale(1) > 1.4
          ? constraints.maxWidth
          : (constraints.maxWidth - 32) / 3;
      String total;
      try {
        total = StockOpeningDraft(form).total.toDecimalString();
      } on FormatException {
        total = 'Enter line values';
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Count details', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              choose('warehouse_id', 'Choose warehouse', 'warehouses', width),
              field(
                'document_date',
                'Opening date',
                width,
                helper: 'YYYY-MM-DD',
              ),
              choose(
                'offset_account_id',
                'Choose opening equity account',
                'accounts',
                width,
              ),
            ],
          ),
          const SizedBox(height: 16),
          field(
            'reason',
            'Reason for opening',
            constraints.maxWidth,
            maxLines: 2,
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Counted products',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text('${lines.length} / 100 lines'),
              OutlinedButton.icon(
                onPressed: c.canEdit && c.online && lines.length < 100
                    ? addProduct
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('Add product'),
              ),
            ],
          ),
          if (lines.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Add the products counted in this warehouse. Enter their total opening value in the entity currency.',
              ),
            ),
          for (var i = 0; i < lines.length; i++)
            Padding(
              key: ValueKey(lines[i]['line_id']),
              padding: const EdgeInsets.only(top: 16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final fieldWidth =
                          box.maxWidth < 600 ||
                              MediaQuery.textScalerOf(context).scale(1) > 1.4
                          ? box.maxWidth
                          : (box.maxWidth - 32) / 3;
                      final line = lines[i],
                          tracking = line['tracking_mode'] ?? 'none';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${line['product_name'] ?? 'Stocked product'}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    Text(
                                      '${line['sku'] ?? ''} · ${line['_unit_label'] ?? 'Base units'} · ${tracking == 'none' ? 'Untracked' : '$tracking tracking'}',
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remove product ${i + 1}',
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
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              field(
                                'base_quantity',
                                'Counted quantity',
                                fieldWidth,
                                line: i,
                              ),
                              field(
                                'base_value',
                                'Total opening value',
                                fieldWidth,
                                line: i,
                                helper:
                                    form['_currency_code'] as String? ??
                                    c.document?.currency ??
                                    'Entity base currency',
                              ),
                              if (tracking == 'lot')
                                field(
                                  'lot_code',
                                  'Lot code',
                                  fieldWidth,
                                  line: i,
                                ),
                            ],
                          ),
                          if (tracking == 'lot') ...[
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              children: [
                                field(
                                  'manufacture_date',
                                  'Manufactured · optional',
                                  fieldWidth,
                                  line: i,
                                  helper: 'YYYY-MM-DD',
                                ),
                                field(
                                  'expiry_date',
                                  'Expires · optional',
                                  fieldWidth,
                                  line: i,
                                  helper: 'YYYY-MM-DD',
                                ),
                              ],
                            ),
                          ],
                          if (tracking == 'serial') ...[
                            const SizedBox(height: 16),
                            field(
                              'serial_codes',
                              'Serial codes · one per line',
                              box.maxWidth,
                              line: i,
                              maxLines: 3,
                              helper:
                                  '${(line['serial_codes'] as List? ?? []).length} entered. Counted quantity must match.',
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            'Opening value preview · $total',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Saving validates the count and account mappings. Posting follows independent approval and creates the stock and journal entries together.',
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: c.canEdit && c.online ? c.saveServer : null,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Save opening'),
              ),
              if (c.localSaveFailed)
                OutlinedButton(
                  onPressed: c.canEdit && !c.saving
                      ? () => c.saveLocal(form)
                      : null,
                  child: const Text('Retry local save'),
                ),
              OutlinedButton(
                onPressed: !c.busy && !c.pending ? c.closeEditor : null,
                child: const Text('Close · keep local draft'),
              ),
              Text(
                c.saving
                    ? 'Saving locally…'
                    : c.localSaveFailed
                    ? 'Local save failed · keep this editor open'
                    : 'Encrypted draft saved locally',
              ),
            ],
          ),
        ],
      );
    },
  );
}

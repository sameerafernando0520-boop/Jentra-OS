import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:uuid/uuid.dart';

import 'quotation_reference_picker.dart';
import 'quotation_reference_label.dart';
import 'quotation_scope_guard.dart';

class QuotationEditor extends StatefulWidget {
  const QuotationEditor({
    required this.form,
    required this.onChanged,
    required this.enabled,
    required this.online,
    required this.baseCurrency,
    this.orderMode = false,
    super.key,
  });
  final Map<String, Object?> form;
  final Future<void> Function(Map<String, Object?>) onChanged;
  final bool enabled, online;
  final bool orderMode;
  final String baseCurrency;
  @override
  State<QuotationEditor> createState() => _QuotationEditorState();
}

class _QuotationEditorState extends State<QuotationEditor> {
  late Map<String, Object?> _form;
  final _controllers = <String, TextEditingController>{};
  final _discountModes = <String, bool>{};
  final _referenceDialogs = <QuotationDialogAccess>{};
  @override
  void initState() {
    super.initState();
    _form = (jsonDecode(jsonEncode(widget.form)) as Map)
        .cast<String, Object?>();
  }

  @override
  void dispose() {
    for (final access in _referenceDialogs) {
      access.denyReadAccess();
    }
    _referenceDialogs.clear();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<Map<String, Object?>> get _lines => (_form['lines']! as List)
      .map((line) => (line as Map).cast<String, Object?>())
      .toList();
  Map<String, Object?> get _labels =>
      (_form['_labels'] as Map? ?? {}).cast<String, Object?>();
  void _changed() {
    widget.onChanged(_form);
  }

  void _label(String field, String label) {
    _form['_labels'] = {..._labels, field: label};
  }

  void _lineSet(int index, String field, Object? value) {
    final lines = _lines;
    if (value == null) {
      lines[index].remove(field);
    } else {
      lines[index][field] = value;
    }
    _form['lines'] = lines;
    _controllers['${lines[index]['line_id']}:$field']?.text =
        value?.toString() ?? '';
  }

  void _quantity(int index) {
    final line = _lines[index];
    try {
      final raw = line['quantity']! as String;
      if (!RegExp(r'^[0-9]+(?:\.[0-9]{1,6})?$').hasMatch(raw)) {
        throw const FormatException();
      }
      final quantity = ExactDecimal.parse(raw, scale: 6).scaledValue;
      final numerator = BigInt.parse(line['conversion_numerator']! as String),
          denominator = BigInt.parse(line['conversion_denominator']! as String);
      if (numerator <= BigInt.zero ||
          denominator <= BigInt.zero ||
          (quantity * numerator) % denominator != BigInt.zero) {
        throw const FormatException();
      }
      _lineSet(
        index,
        'base_quantity',
        ExactDecimal.fromScaledValue(
          quantity * numerator ~/ denominator,
          scale: 6,
        ).toDecimalString(),
      );
    } on Object {
      _lineSet(index, 'base_quantity', '');
    }
  }

  Widget _field(
    String field,
    String label, {
    String? hint,
    bool readOnly = false,
    bool integer = false,
    int? line,
    int maxLines = 1,
  }) {
    final values = line == null ? _form : _lines[line];
    final key = line == null ? field : '${values['line_id']}:$field';
    final controller = _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: values[field]?.toString() ?? ''),
    );
    return TextField(
      key: Key('quote-$key'),
      controller: controller,
      enabled: widget.enabled,
      readOnly: readOnly,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        helperText: hint,
        helperMaxLines: 3,
        alignLabelWithHint: true,
      ),
      onChanged: readOnly
          ? null
          : (text) {
              final value = integer ? (int.tryParse(text) ?? text) : text;
              if (line == null) {
                if (text.isEmpty &&
                    {
                      'header_discount_amount',
                      'header_discount_percent',
                    }.contains(field)) {
                  _form.remove(field);
                } else {
                  _form[field] = value;
                }
              } else {
                final lines = _lines;
                if (text.isEmpty &&
                    {'discount_amount', 'discount_percent'}.contains(field)) {
                  lines[line].remove(field);
                } else {
                  lines[line][field] = value;
                }
                _form['lines'] = lines;
                if ({
                  'quantity',
                  'conversion_numerator',
                  'conversion_denominator',
                }.contains(field)) {
                  _quantity(line);
                }
              }
              _changed();
            },
    );
  }

  Widget _reference(
    String field,
    String label,
    QuotationReferenceKind kind, {
    int? line,
    bool optional = false,
  }) {
    final values = line == null ? _form : _lines[line];
    final identity = values[field]?.toString();
    final labelKey = line == null ? field : '$field:$identity';
    final display = _labels[labelKey]?.toString() ?? identity;
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              key: Key(
                'pick-${line == null ? field : '${values['line_id']}:$field'}',
              ),
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: EdgeInsets.zero,
              ),
              onPressed:
                  !widget.enabled ||
                      !widget.online ||
                      (kind == QuotationReferenceKind.contact &&
                          (_form['customer_id'] as String? ?? '').isEmpty)
                  ? null
                  : () async {
                      final access = QuotationDialogAccess(context);
                      final accessEpoch = access.readAccessEpoch;
                      _referenceDialogs.add(access);
                      try {
                        final item = await showQuotationReferencePicker(
                          context,
                          originAccess: access,
                          title: label,
                          permission: widget.orderMode
                              ? 'sales.orders.manage'
                              : 'sales.quotations.manage',
                          kind: kind,
                          customerId: _form['customer_id'] as String?,
                          fromCurrency:
                              kind == QuotationReferenceKind.exchangeRate
                              ? _form['currency_code'] as String?
                              : null,
                          toCurrency:
                              kind == QuotationReferenceKind.exchangeRate
                              ? widget.baseCurrency
                              : null,
                        );
                        if (!mounted ||
                            !widget.enabled ||
                            !access.currentRead(accessEpoch) ||
                            item == null) {
                          return;
                        }
                        setState(() {
                          if (line == null) {
                            _form[field] = item.id;
                            _label(field, item.label);
                          } else {
                            _lineSet(line, field, item.id);
                            _label('$field:${item.id}', item.label);
                          }
                          if (kind == QuotationReferenceKind.customer) {
                            _form.remove('contact_id');
                            _form.remove('opportunity_id');
                            _form['_labels'] = {..._labels}
                              ..remove('contact_id')
                              ..remove('opportunity_id');
                            final days = item.values['payment_terms_days'];
                            if (days is int) {
                              _form['payment_terms_days'] = days;
                              _controllers['payment_terms_days']?.text = days
                                  .toString();
                            }
                          }
                          if (kind == QuotationReferenceKind.currency) {
                            _form.remove('exchange_rate_id');
                            _form['_labels'] = {..._labels}
                              ..remove('exchange_rate_id');
                            _form['exchange_rate'] =
                                item.id == widget.baseCurrency
                                ? '1.0000000000'
                                : '';
                            _controllers['exchange_rate']?.text =
                                _form['exchange_rate']! as String;
                          }
                          if (kind == QuotationReferenceKind.exchangeRate) {
                            _form['exchange_rate'] = item.values['rate'];
                            _form['rate_date'] = item.values['effective_date'];
                            _controllers['exchange_rate']?.text =
                                item.values['rate']! as String;
                            _controllers['rate_date']?.text =
                                item.values['effective_date']! as String;
                          }
                          if (kind == QuotationReferenceKind.product &&
                              line != null) {
                            _lineSet(
                              line,
                              'description',
                              item.values['description'] ?? item.values['name'],
                            );
                            _lineSet(
                              line,
                              'unit_id',
                              item.values['base_unit_id'],
                            );
                            _lineSet(
                              line,
                              'tax_definition_id',
                              item.values['tax_definition_id'],
                            );
                            _lineSet(line, 'conversion_numerator', '1');
                            _lineSet(line, 'conversion_denominator', '1');
                            _quantity(line);
                          }
                        });
                        _changed();
                      } finally {
                        _referenceDialogs.remove(access);
                        access.dispose();
                      }
                    },
              child: display == null || display.isEmpty
                  ? Text('Choose ${label.toLowerCase()}')
                  : QuotationReferenceLabel(
                      orderMode: widget.orderMode,
                      kind: kind,
                      id: identity!,
                      customerId: _form['customer_id'] as String?,
                      savedLabel: _labels[labelKey] as String?,
                      resolveCurrentName: line == null || line < 25,
                    ),
            ),
          ),
          if (optional && identity != null && identity.isNotEmpty)
            IconButton(
              tooltip: 'Clear $label',
              onPressed: widget.enabled
                  ? () {
                      setState(() {
                        if (line == null) {
                          _form.remove(field);
                        } else {
                          _lineSet(line, field, null);
                        }
                      });
                      _changed();
                    }
                  : null,
              icon: const Icon(Icons.close, size: 18),
            )
          else
            const Icon(Icons.expand_more, size: 18),
        ],
      ),
    );
  }

  Widget _grid(List<Widget> children) => LayoutBuilder(
    builder: (context, constraints) {
      final scaled = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
      final columns = scaled || constraints.maxWidth < 540
          ? 1
          : constraints.maxWidth > 950
          ? 3
          : 2;
      final width = (constraints.maxWidth - 16 * (columns - 1)) / columns;
      return Wrap(
        spacing: 16,
        runSpacing: 20,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: JentraPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _section('Customer & terms', [
        _grid([
          _reference(
            'customer_id',
            'Customer',
            QuotationReferenceKind.customer,
          ),
          _reference(
            'contact_id',
            'Contact',
            QuotationReferenceKind.contact,
            optional: true,
          ),
          if (!widget.orderMode)
            _reference(
              'opportunity_id',
              'Opportunity',
              QuotationReferenceKind.opportunity,
              optional: true,
            ),
          _field(
            widget.orderMode ? 'order_date' : 'quotation_date',
            widget.orderMode ? 'Order date' : 'Quotation date',
            hint: 'YYYY-MM-DD',
          ),
          if (!widget.orderMode)
            _field('valid_until', 'Valid through', hint: 'YYYY-MM-DD'),
          _field('payment_terms_days', 'Payment terms · days', integer: true),
          if (!widget.orderMode)
            _field(
              'salesperson_id',
              'Salesperson',
              readOnly: true,
              hint: 'Assigned member; new quotations use your signed-in identity.',
            ),
          _field('delivery_terms', 'Delivery terms'),
        ]),
      ]),
      _section('Currency & discounts', [
        _grid([
          _reference(
            'currency_code',
            'Currency',
            QuotationReferenceKind.currency,
          ),
          if (_form['currency_code'] != widget.baseCurrency)
            _reference(
              'exchange_rate_id',
              'Exchange rate',
              QuotationReferenceKind.exchangeRate,
            ),
          _field(
            'exchange_rate',
            'Exchange rate to ${widget.baseCurrency}',
            readOnly: true,
            hint: 'Governed rate · up to 10 decimal places',
          ),
          _field(
            'rate_date',
            'Rate date',
            readOnly: _form['currency_code'] != widget.baseCurrency,
            hint: 'YYYY-MM-DD',
          ),
          _discount(null),
        ]),
      ]),
      _section('Products & services', [
        Text(
          'Amounts use ${_form['currency_code']}. Save to calculate governed tax and totals.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        for (var i = 0; i < _lines.length; i++) _line(i),
        OutlinedButton.icon(
          key: const Key('quote-add-line'),
          onPressed: widget.enabled && _lines.length < 500
              ? () {
                  setState(() {
                    _form['lines'] = [
                      ..._lines,
                      {
                        'line_id': const Uuid().v4(),
                        'description': '',
                        'quantity': '1.000000',
                        'unit_id': '',
                        'base_quantity': '1.000000',
                        'conversion_numerator': '1',
                        'conversion_denominator': '1',
                        'unit_price': '0.000000',
                      },
                    ];
                  });
                  _changed();
                }
              : null,
          icon: const Icon(Icons.add),
          label: const Text('Add item'),
        ),
      ]),
      _section('Notes', [
        _field('notes', 'Customer-facing notes', maxLines: 3),
        if (_form['create_revision'] == true) ...[
          const SizedBox(height: 16),
          _field('revision_reason', 'Revision reason'),
        ],
      ]),
    ],
  );
  Widget _discount(int? line) {
    final values = line == null ? _form : _lines[line];
    final prefix = line == null ? 'header_discount' : 'discount';
    final modeKey = line == null ? 'header' : values['line_id']! as String;
    final percent = _discountModes.putIfAbsent(
      modeKey,
      () => values['${prefix}_percent'] != null,
    );
    return Column(
      children: [
        DropdownButtonFormField<bool>(
          initialValue: percent,
          decoration: const InputDecoration(labelText: 'Discount type'),
          items: const [
            DropdownMenuItem(value: false, child: Text('Amount')),
            DropdownMenuItem(value: true, child: Text('Percentage')),
          ],
          onChanged: widget.enabled
              ? (value) {
                  setState(() {
                    _discountModes[modeKey] = value == true;
                    if (line == null) {
                      _form.remove('${prefix}_amount');
                      _form.remove('${prefix}_percent');
                      _form[value == true
                              ? '${prefix}_percent'
                              : '${prefix}_amount'] =
                          '0';
                    } else {
                      _lineSet(line, '${prefix}_amount', null);
                      _lineSet(line, '${prefix}_percent', null);
                      _lineSet(
                        line,
                        value == true
                            ? '${prefix}_percent'
                            : '${prefix}_amount',
                        '0',
                      );
                    }
                  });
                  _changed();
                }
              : null,
        ),
        const SizedBox(height: 12),
        _field(
          '${prefix}_${percent ? 'percent' : 'amount'}',
          percent ? 'Discount · %' : 'Discount · ${_form['currency_code']}',
          line: line,
        ),
      ],
    );
  }

  Widget _line(int index) {
    final line = _lines[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: JentraPanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Item ${index + 1}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove item ${index + 1}',
                  onPressed: widget.enabled
                      ? () {
                          setState(() {
                            final lines = _lines;
                            lines.removeAt(index);
                            _form['lines'] = lines;
                          });
                          _changed();
                        }
                      : null,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _grid([
              _reference(
                'product_id',
                'Product or service',
                QuotationReferenceKind.product,
                line: index,
                optional: true,
              ),
              _field('description', 'Description', line: index),
              _reference(
                'unit_id',
                'Unit',
                QuotationReferenceKind.unit,
                line: index,
              ),
              _field('quantity', 'Quantity', line: index),
              _field(
                'unit_price',
                'Unit price · ${_form['currency_code']}',
                line: index,
              ),
              _discount(index),
              _reference(
                'tax_definition_id',
                'Tax',
                QuotationReferenceKind.tax,
                line: index,
                optional: true,
              ),
            ]),
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.symmetric(vertical: 12),
              title: const Text('Unit conversion'),
              children: [
                _grid([
                  _field(
                    'conversion_numerator',
                    'Base units · numerator',
                    line: index,
                  ),
                  _field(
                    'conversion_denominator',
                    'Sold units · denominator',
                    line: index,
                  ),
                  _field(
                    'base_quantity',
                    'Exact base quantity',
                    line: index,
                    readOnly: true,
                    hint: 'Conversion must be exact within 6 decimal places.',
                  ),
                ]),
              ],
            ),
            if (line['tax_definition_id'] != null)
              Text(
                'The selected tax definition determines inclusive or exclusive tax at save.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

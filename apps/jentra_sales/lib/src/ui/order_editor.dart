import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../sales_controller.dart';
import 'components.dart';

Future<void> openOrderEditor(
  BuildContext context,
  SalesController c, {
  SalesCustomer? customer,
  SalesOrder? draft,
  SalesProduct? product,
}) => salesDialog<void>(
  context,
  OrderEditor(c, customer: customer, draft: draft, product: product),
);

class OrderEditor extends StatefulWidget {
  const OrderEditor(
    this.c, {
    this.customer,
    this.draft,
    this.product,
    super.key,
  });
  final SalesController c;
  final SalesCustomer? customer;
  final SalesOrder? draft;
  final SalesProduct? product;
  @override
  State<OrderEditor> createState() => _OrderEditorState();
}

class _OrderEditorState extends State<OrderEditor> {
  final _form = GlobalKey<FormState>();
  final _reference = TextEditingController(),
      _notes = TextEditingController(),
      _reason = TextEditingController(),
      _discount = TextEditingController(text: '0');
  final _quantities = <String, TextEditingController>{};
  final _products = <SalesProduct>[];
  late final String _id, _commandId;
  String? _customer, _error;
  String _requestedDate = '';
  bool _review = false, _saving = false, _allowClose = false, _closing = false;
  late final String _initialSignature;
  String get _signature => jsonEncode([
    _customer,
    _reference.text,
    _notes.text,
    _reason.text,
    _discount.text,
    _requestedDate,
    _products.map((p) => [p.id, _quantities[p.id]!.text]).toList(),
  ]);
  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    _id = draft?.id ?? widget.c.newId();
    _commandId = draft?.commandId ?? widget.c.newId();
    _customer = draft?.customerId ?? widget.customer?.id;
    _reference.text = draft?.reference ?? '';
    _notes.text = draft?.notes ?? '';
    _reason.text = draft?.discountReason ?? '';
    _discount.text = draft?.discount ?? '0';
    _requestedDate = draft?.requestedDate ?? '';
    if (draft != null) {
      for (final line in draft.lines) {
        _products.add(line.product);
        _quantities[line.product.id] = TextEditingController(
          text: line.quantity,
        );
      }
    }
    if (widget.product != null) {
      _products.add(widget.product!);
      _quantities[widget.product!.id] = TextEditingController(text: '1');
    }
    _initialSignature = _signature;
  }

  Future<void> _close() async {
    if (_saving || _closing) return;
    _closing = true;
    if (_signature != _initialSignature) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Discard unsaved changes?'),
          content: const Text(
            'Keep editing to review and save your draft. Discarding removes the changes from this editor.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard changes'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (discard != true) {
        _closing = false;
        return;
      }
    }
    if (!mounted) return;
    setState(() => _allowClose = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    for (final t in [
      _reference,
      _notes,
      _reason,
      _discount,
      ..._quantities.values,
    ]) {
      t.dispose();
    }
    super.dispose();
  }

  List<SalesLine> get _lines =>
      _products.map((p) => SalesLine(p, _quantities[p.id]!.text)).toList();
  SalesOrder _order() => SalesOrder(
    id: _id,
    customerId: _customer!,
    date: widget.c.now(),
    lines: List.unmodifiable(_lines),
    customerState: 'Not requested',
    companyState: 'Not submitted',
    deliveryState: 'Not scheduled',
    local: true,
    reference: _reference.text.trim(),
    notes: _notes.text.trim(),
    discount: _discount.text,
    discountReason: _reason.text.trim(),
    commandId: _commandId,
    requestedDate: _requestedDate,
  );
  void _next() {
    if (!_form.currentState!.validate()) return;
    if (_products.isEmpty) {
      setState(() => _error = 'Add at least one product before review.');
      return;
    }
    setState(() {
      _error = null;
      _review = true;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.c.saveDraft(_order());
      if (!mounted) return;
      setState(() => _allowClose = true);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      Navigator.pop(context);
      salesToast(
        context,
        'Preview draft saved on this device. No order was submitted.',
      );
    } on SalesFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _saving = false;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'The draft could not be saved. Keep this editor open and try again.';
          _saving = false;
        });
      }
    }
  }

  Future<void> _add() async {
    if (_products.length >= 100) {
      setState(() => _error = 'Keep this order within 100 product lines.');
      return;
    }
    final result = await salesDialog<SalesProduct>(
      context,
      _ProductPicker(
        widget.c.products,
        excluded: _products.map((p) => p.id).toSet(),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _products.add(result);
      _quantities[result.id] = TextEditingController(text: '1');
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowClose,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 12, 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _review
                          ? 'Review your order'
                          : widget.draft == null
                          ? 'New order'
                          : 'Continue your draft',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _review
                          ? '02 / Review & save locally'
                          : '01 / Customer, products & terms',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close order editor',
                onPressed: _saving ? null : _close,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _review
                ? _reviewContent(context)
                : Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionTitle('Start with your customer'),
                        DropdownButtonFormField<String>(
                          initialValue: _customer,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Customer',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          items: widget.c.customers
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(
                                    c.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => _customer = v),
                          validator: (v) =>
                              v == null ? 'Choose a customer.' : null,
                        ),
                        const SizedBox(height: 28),
                        SectionTitle(
                          'Build the order',
                          action: TextButton.icon(
                            onPressed: _add,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add product'),
                          ),
                        ),
                        if (_products.isEmpty)
                          SalesPanel(
                            child: SalesEmpty(
                              'Make room for a great order.',
                              'Choose products from your sample catalogue.',
                              action: OutlinedButton.icon(
                                onPressed: _add,
                                icon: const Icon(Icons.add),
                                label: const Text('Browse products'),
                              ),
                            ),
                          ),
                        for (final product in _products)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: SalesPanel(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ProductIcon(product, size: 44),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              product.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${product.code} · ${money(product.price)} / ${product.unit}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Remove ${product.name}',
                                        onPressed: () {
                                          setState(() {
                                            _products.remove(product);
                                            _quantities
                                                .remove(product.id)
                                                ?.dispose();
                                          });
                                        },
                                        icon: const Icon(Icons.close, size: 18),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    key: ValueKey(product.id),
                                    controller: _quantities[product.id],
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: InputDecoration(
                                      labelText: 'Quantity · ${product.unit}',
                                      helperText: 'Up to 3 decimal places. Example: 12.5',
                                    ),
                                    validator: (v) {
                                      try {
                                        parseQuantity(v ?? '');
                                        return null;
                                      } on FormatException catch (e) {
                                        return e.message;
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        const SectionTitle('Delivery & reference'),
                        TextFormField(
                          controller: _reference,
                          maxLength: 120,
                          decoration: const InputDecoration(
                            labelText: 'Customer reference (optional)',
                            hintText: 'PO number or visit reference',
                          ),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: widget.c.now(),
                              firstDate: DateUtils.dateOnly(widget.c.now()),
                              lastDate: widget.c.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (date != null && mounted) {
                              setState(
                                () =>
                                    _requestedDate = DateFormat('yyyy-MM-dd')
                                        .format(date),
                              );
                            }
                          },
                          icon: const Icon(
                            Icons.calendar_today_outlined,
                            size: 18,
                          ),
                          label: Text(
                            _requestedDate.isEmpty
                                ? 'Choose requested delivery date'
                                : 'Requested delivery: $_requestedDate',
                          ),
                        ),
                        const SizedBox(height: 28),
                        const SectionTitle('Request a discount'),
                        const Text(
                          'A discount request needs company approval. Your requested percentage does not change the current price.',
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _discount,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Requested discount (%)',
                          ),
                          validator: (v) {
                            try {
                              parseDiscount(v ?? '');
                              return null;
                            } on FormatException catch (e) {
                              return e.message;
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _reason,
                          maxLength: 500,
                          decoration: const InputDecoration(
                            labelText: 'Discount reason',
                          ),
                          validator: (v) {
                            try {
                              if (parseDiscount(_discount.text).isPositive &&
                                  (v == null || v.trim().isEmpty)) {
                                return 'Add a reason for your discount request.';
                              }
                            } on Object {
                              return null;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _notes,
                          minLines: 2,
                          maxLines: 4,
                          maxLength: 2000,
                          decoration: const InputDecoration(
                            labelText: 'Order notes (optional)',
                          ),
                        ),
                        const SizedBox(height: 20),
                        const SalesNotice(
                          'Preview prices and availability are illustrative. Online review must confirm current prices, tax, credit and stock before a real order can be submitted.',
                        ),
                      ],
                    ),
                  ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: SalesNotice(_error!, icon: Icons.error_outline),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () {
                          if (_review) {
                            setState(() => _review = false);
                          } else {
                            _close();
                          }
                        },
                  child: Text(_review ? 'Back to edit' : 'Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving
                      ? null
                      : _review
                      ? _save
                      : _next,
                  icon: Icon(
                    _review ? Icons.save_outlined : Icons.arrow_forward,
                    size: 18,
                  ),
                  label: Text(
                    _saving
                        ? 'Saving…'
                        : _review
                        ? 'Save local draft'
                        : 'Review order',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _reviewContent(BuildContext context) {
    final order = _order();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SalesNotice(
          'Preview review · Not saved yet. Save on this device for up to 24 hours. No real order will be submitted.',
        ),
        const SizedBox(height: 24),
        Text(
          widget.c.customer(_customer!).name,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(widget.c.customer(_customer!).address),
        const SizedBox(height: 8),
        Text(widget.c.customer(_customer!).terms),
        const SizedBox(height: 24),
        const SectionTitle('Your order'),
        for (final line in order.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.product.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '${line.quantity} ${line.product.unit} × ${money(line.product.price)}',
                ),
                const SizedBox(height: 6),
                Text(
                  money(line.total.toDecimalString()),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        const Divider(),
        const SizedBox(height: 16),
        Text(
          'Subtotal  ${money(order.subtotal.toDecimalString())}',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        const Text('Tax & final total: available after online review.'),
        const SizedBox(height: 12),
        Text(
          'Discount request: ${order.discount}% · ${order.discountReason.isEmpty ? 'No discount requested' : order.discountReason}',
        ),
        const SizedBox(height: 12),
        Text(
          'Requested delivery: ${order.requestedDate.isEmpty ? 'Not selected' : order.requestedDate}',
        ),
        if (order.reference.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Reference: ${order.reference}'),
        ],
        if (order.notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Notes: ${order.notes}'),
        ],
        const SizedBox(height: 24),
        const SalesNotice(
          'Customer response: not requested. Company approval: not submitted. Delivery: not scheduled. These remain separate facts.',
        ),
      ],
    );
  }
}

class _ProductPicker extends StatefulWidget {
  const _ProductPicker(this.products, {required this.excluded});
  final List<SalesProduct> products;
  final Set<String> excluded;
  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final products = widget.products
        .where(
          (p) =>
              !widget.excluded.contains(p.id) &&
              '${p.name} ${p.code}'.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 12, 16),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Add a product',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Close products',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Search products',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => query = v),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (products.isEmpty)
                const SalesEmpty(
                  'No more matching products',
                  'Try another search or change the quantity of an existing line.',
                ),
              for (final p in products)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  leading: ProductIcon(p, size: 44),
                  title: Text(p.name),
                  subtitle: Text('${p.code} · ${money(p.price)} / ${p.unit}'),
                  trailing: const Icon(Icons.add_circle_outline),
                  onTap: () => Navigator.pop(context, p),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

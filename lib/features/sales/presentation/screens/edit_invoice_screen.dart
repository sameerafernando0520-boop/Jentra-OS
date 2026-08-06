import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../company/application/company_state.dart';
import '../../../company/presentation/widgets/company_context_gate.dart';
import '../../../inventory/application/product_models.dart';
import '../../../inventory/application/product_state.dart';
import '../../application/invoice_failure.dart';
import '../../application/invoice_models.dart';
import '../../application/invoice_state.dart';
import '../../application/invoice_validators.dart';
import '../../domain/invoice_calculation_service.dart';

final class EditInvoiceScreen extends ConsumerWidget {
  const EditInvoiceScreen({required this.invoiceId, super.key});

  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(selectedCompanyProvider);
    if (company == null) {
      return const CompanyRouteRedirect(location: '/company/select');
    }

    final invoiceAsync = ref.watch(invoiceDetailProvider(invoiceId));

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Draft Invoice')),
      body: invoiceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  error is InvoiceFailure ? error.message : error.toString(),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.invalidate(invoiceDetailProvider(invoiceId)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (invoice) {
          if (!invoice.isDraft) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text('Only draft invoices can be edited.'),
              ),
            );
          }
          return _EditInvoiceForm(invoice: invoice);
        },
      ),
    );
  }
}

final class _EditInvoiceForm extends ConsumerStatefulWidget {
  const _EditInvoiceForm({required this.invoice});

  final Invoice invoice;

  @override
  ConsumerState<_EditInvoiceForm> createState() => _EditInvoiceFormState();
}

final class _EditInvoiceFormState extends ConsumerState<_EditInvoiceForm> {
  final _formKey = GlobalKey<FormState>();

  late String? _selectedCustomerId;
  late final TextEditingController _documentNumberController;
  late final TextEditingController _notesController;
  late DateTime _issueDate;
  late DateTime? _dueDate;

  final List<_InvoiceLineItemRow> _items = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selectedCustomerId = widget.invoice.customerId;
    _documentNumberController =
        TextEditingController(text: widget.invoice.documentNumber);
    _notesController = TextEditingController(text: widget.invoice.notes ?? '');
    _issueDate = widget.invoice.issueDate;
    _dueDate = widget.invoice.dueDate;

    for (final item in widget.invoice.items) {
      _items.add(
        _InvoiceLineItemRow(
          productId: item.productId,
          descriptionController:
              TextEditingController(text: item.description),
          quantityController:
              TextEditingController(text: item.quantity.toString()),
          unitPriceController:
              TextEditingController(text: item.unitPrice.toString()),
          discountController:
              TextEditingController(text: item.discountAmount.toString()),
          taxRateController:
              TextEditingController(text: item.taxRate.toString()),
        ),
      );
    }

    if (_items.isEmpty) {
      _addItemRow();
    }
  }

  void _addItemRow({Product? selectedProduct}) {
    setState(() {
      _items.add(
        _InvoiceLineItemRow(
          productId: selectedProduct?.id,
          descriptionController: TextEditingController(
            text: selectedProduct?.name ?? '',
          ),
          quantityController: TextEditingController(text: '1'),
          unitPriceController: TextEditingController(
            text: selectedProduct != null
                ? selectedProduct.unitPrice.toString()
                : '0.00',
          ),
          discountController: TextEditingController(text: '0.00'),
          taxRateController: TextEditingController(text: '0.00'),
        ),
      );
    });
  }

  void _removeItemRow(int index) {
    if (_items.length <= 1) return;
    setState(() {
      final removed = _items.removeAt(index);
      removed.dispose();
    });
  }

  @override
  void dispose() {
    _documentNumberController.dispose();
    _notesController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  InvoiceCalculatedTotals _computeTotals() {
    final inputItems = _items.map((row) => row.toInput()).toList();
    return InvoiceCalculationService.calculateDocumentTotals(inputItems);
  }

  Future<void> _submit(String targetStatus) async {
    if (!_formKey.currentState!.validate()) return;
    final itemInputs = _items.map((row) => row.toInput()).toList();
    final itemsValidation = InvoiceValidators.validateItems(itemInputs);
    if (itemsValidation != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(itemsValidation), backgroundColor: Colors.red),
      );
      return;
    }

    if (_selectedCustomerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a customer'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final input = InvoiceInput(
        customerId: _selectedCustomerId!,
        documentNumber: _documentNumberController.text,
        status: targetStatus,
        issueDate: _issueDate,
        dueDate: _dueDate,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        items: itemInputs,
      );

      await ref
          .read(invoiceMutationControllerProvider.notifier)
          .updateInvoice(widget.invoice.id, input);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice updated successfully')),
        );
        context.pop();
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _submitting = false);
        final message =
            error is InvoiceFailure ? error.message : error.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(invoiceCustomerListProvider);
    final productsStateAsync = ref.watch(productControllerProvider);
    final products = productsStateAsync.value?.products ?? const <Product>[];
    final totals = _computeTotals();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            customersAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Text('Error loading customers: $err'),
              data: (customers) => DropdownButtonFormField<String>(
                initialValue: _selectedCustomerId,
                decoration: const InputDecoration(
                  labelText: 'Select Customer *',
                  border: OutlineInputBorder(),
                ),
                items: customers
                    .map(
                      (cust) => DropdownMenuItem<String>(
                        value: cust.id,
                        child: Text(cust.title),
                      ),
                    )
                    .toList(),
                onChanged: (val) => setState(() => _selectedCustomerId = val),
                validator: InvoiceValidators.validateCustomer,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _documentNumberController,
              decoration: const InputDecoration(
                labelText: 'Invoice Number',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Invoice Items', style: Theme.of(context).textTheme.titleMedium),
                PopupMenuButton<Product>(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add Product Item',
                  onSelected: (prod) => _addItemRow(selectedProduct: prod),
                  itemBuilder: (context) => [
                    const PopupMenuItem<Product>(
                      value: null,
                      child: Text('+ Custom Line Item'),
                    ),
                    ...products.map(
                      (p) => PopupMenuItem<Product>(
                        value: p,
                        child: Text('${p.name} (\$${p.unitPrice.toStringAsFixed(2)})'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._items.asMap().entries.map((entry) {
              final idx = entry.key;
              final row = entry.value;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: row.descriptionController,
                              decoration: const InputDecoration(
                                labelText: 'Item Description *',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Required'
                                  : null,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: _items.length > 1
                                ? () => _removeItemRow(idx)
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: row.quantityController,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Qty *',
                                border: OutlineInputBorder(),
                              ),
                              validator: InvoiceValidators.validateQuantity,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: row.unitPriceController,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Price *',
                                prefixText: '\$',
                                border: OutlineInputBorder(),
                              ),
                              validator: InvoiceValidators.validateUnitPrice,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: row.discountController,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Discount',
                                prefixText: '\$',
                                border: OutlineInputBorder(),
                              ),
                              validator: InvoiceValidators.validateDiscount,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: row.taxRateController,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Tax %',
                                border: OutlineInputBorder(),
                              ),
                              validator: InvoiceValidators.validateTaxRate,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            OutlinedButton.icon(
              onPressed: () => _addItemRow(),
              icon: const Icon(Icons.add),
              label: const Text('Add Custom Item'),
            ),
            const SizedBox(height: 24),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Subtotal:'),
                        Text('\$${totals.subtotal.toStringAsFixed(2)}'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Discount:'),
                        Text('-\$${totals.totalDiscount.toStringAsFixed(2)}'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Tax:'),
                        Text('\$${totals.totalTax.toStringAsFixed(2)}'),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Grand Total:',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '\$${totals.grandTotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting ? null : () => _submit('draft'),
                    child: const Text('Save Draft'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _submitting ? null : () => _submit('issued'),
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: const Text('Save & Issue'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class _InvoiceLineItemRow {
  _InvoiceLineItemRow({
    this.productId,
    required this.descriptionController,
    required this.quantityController,
    required this.unitPriceController,
    required this.discountController,
    required this.taxRateController,
  });

  String? productId;
  final TextEditingController descriptionController;
  final TextEditingController quantityController;
  final TextEditingController unitPriceController;
  final TextEditingController discountController;
  final TextEditingController taxRateController;

  InvoiceItemInput toInput() {
    return InvoiceItemInput(
      productId: productId,
      description: descriptionController.text.trim(),
      quantity: double.tryParse(quantityController.text.trim()) ?? 1.0,
      unitPrice: double.tryParse(unitPriceController.text.trim()) ?? 0.0,
      discountAmount: double.tryParse(discountController.text.trim()) ?? 0.0,
      taxRate: double.tryParse(taxRateController.text.trim()) ?? 0.0,
    );
  }

  void dispose() {
    descriptionController.dispose();
    quantityController.dispose();
    unitPriceController.dispose();
    discountController.dispose();
    taxRateController.dispose();
  }
}

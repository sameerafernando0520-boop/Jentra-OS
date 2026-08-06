import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../company/application/company_state.dart';
import '../../../company/presentation/widgets/company_context_gate.dart';
import '../../application/inventory_failure.dart';
import '../../application/product_models.dart';
import '../../application/product_state.dart';
import '../../application/product_validators.dart';

final class EditProductScreen extends ConsumerWidget {
  const EditProductScreen({required this.productId, super.key});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(selectedCompanyProvider);
    if (company == null) {
      return const CompanyRouteRedirect(location: '/company/select');
    }

    final productAsync = ref.watch(productDetailProvider(productId));

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Product')),
      body: productAsync.when(
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
                  error is InventoryFailure ? error.message : error.toString(),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () =>
                      ref.invalidate(productDetailProvider(productId)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (product) => _EditProductForm(product: product),
      ),
    );
  }
}

final class _EditProductForm extends ConsumerStatefulWidget {
  const _EditProductForm({required this.product});

  final Product product;

  @override
  ConsumerState<_EditProductForm> createState() => _EditProductFormState();
}

final class _EditProductFormState extends ConsumerState<_EditProductForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _skuController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _unitPriceController;
  late final TextEditingController _costPriceController;
  late final TextEditingController _unitController;

  String? _selectedCategoryId;
  late bool _trackInventory;
  late bool _isActive;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product.name);
    _skuController = TextEditingController(text: widget.product.sku ?? '');
    _barcodeController =
        TextEditingController(text: widget.product.barcode ?? '');
    _descriptionController =
        TextEditingController(text: widget.product.description ?? '');
    _unitPriceController =
        TextEditingController(text: widget.product.unitPrice.toString());
    _costPriceController =
        TextEditingController(text: widget.product.costPrice.toString());
    _unitController = TextEditingController(text: widget.product.unit);

    _selectedCategoryId = widget.product.categoryId;
    _trackInventory = widget.product.trackInventory;
    _isActive = widget.product.isActive;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _barcodeController.dispose();
    _descriptionController.dispose();
    _unitPriceController.dispose();
    _costPriceController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      final input = ProductInput(
        name: _nameController.text,
        categoryId: _selectedCategoryId,
        sku: _skuController.text,
        barcode: _barcodeController.text,
        description: _descriptionController.text,
        unit: _unitController.text,
        unitPrice: double.parse(_unitPriceController.text.trim()),
        costPrice: double.tryParse(_costPriceController.text.trim()) ?? 0.0,
        trackInventory: _trackInventory,
        isActive: _isActive,
      );

      await ref
          .read(productMutationProvider.notifier)
          .updateProduct(widget.product.id, input);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product updated successfully')),
        );
        context.pop();
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _submitting = false);
        final message =
            error is InventoryFailure ? error.message : error.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoryListProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Product Name *',
                border: OutlineInputBorder(),
              ),
              validator: ProductValidators.validateName,
            ),
            const SizedBox(height: 16),
            categoriesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const SizedBox.shrink(),
              data: (categories) => DropdownButtonFormField<String>(
                initialValue: _selectedCategoryId,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('No Category'),
                  ),
                  ...categories.map(
                    (cat) => DropdownMenuItem<String>(
                      value: cat.id,
                      child: Text(cat.name),
                    ),
                  ),
                ],
                onChanged: (val) => setState(() => _selectedCategoryId = val),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _unitPriceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Selling Price *',
                      prefixText: '\$ ',
                      border: OutlineInputBorder(),
                    ),
                    validator: ProductValidators.validateUnitPrice,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _costPriceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Cost Price',
                      prefixText: '\$ ',
                      border: OutlineInputBorder(),
                    ),
                    validator: ProductValidators.validateCostPrice,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _skuController,
                    decoration: const InputDecoration(
                      labelText: 'SKU',
                      border: OutlineInputBorder(),
                    ),
                    validator: ProductValidators.validateSku,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _barcodeController,
                    decoration: const InputDecoration(
                      labelText: 'Barcode / EAN',
                      border: OutlineInputBorder(),
                    ),
                    validator: ProductValidators.validateBarcode,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _unitController,
              decoration: const InputDecoration(
                labelText: 'Unit of Measure',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Track Inventory'),
              value: _trackInventory,
              onChanged: (val) => setState(() => _trackInventory = val),
            ),
            SwitchListTile(
              title: const Text('Active Product'),
              value: _isActive,
              onChanged: (val) => setState(() => _isActive = val),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_submitting ? 'Saving...' : 'Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

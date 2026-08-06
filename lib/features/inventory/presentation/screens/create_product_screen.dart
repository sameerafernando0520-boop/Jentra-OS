import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../company/application/company_state.dart';
import '../../../company/presentation/widgets/company_context_gate.dart';
import '../../application/inventory_failure.dart';
import '../../application/product_models.dart';
import '../../application/product_state.dart';
import '../../application/product_validators.dart';

final class CreateProductScreen extends ConsumerStatefulWidget {
  const CreateProductScreen({super.key});

  @override
  ConsumerState<CreateProductScreen> createState() =>
      _CreateProductScreenState();
}

final class _CreateProductScreenState
    extends ConsumerState<CreateProductScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _skuController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _unitPriceController = TextEditingController(text: '0.00');
  final _costPriceController = TextEditingController(text: '0.00');
  final _unitController = TextEditingController(text: 'pcs');

  String? _selectedCategoryId;
  bool _trackInventory = true;
  bool _isActive = true;
  bool _submitting = false;

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

      final created = await ref
          .read(productMutationProvider.notifier)
          .createProduct(input);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Product "${created.name}" created successfully')),
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
    final company = ref.watch(selectedCompanyProvider);
    if (company == null) {
      return const CompanyRouteRedirect(location: '/company/select');
    }

    final categoriesAsync = ref.watch(categoryListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Product'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Product Details for ${company.name}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              // Name
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Product Name *',
                  hintText: 'e.g. Wireless Mouse',
                  border: OutlineInputBorder(),
                ),
                validator: ProductValidators.validateName,
              ),
              const SizedBox(height: 16),
              // Category
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
              // Selling Price & Cost Price
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
              // SKU & Barcode
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _skuController,
                      decoration: const InputDecoration(
                        labelText: 'SKU',
                        hintText: 'e.g. WM-100',
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
                        hintText: 'e.g. 890123456',
                        border: OutlineInputBorder(),
                      ),
                      validator: ProductValidators.validateBarcode,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Unit of measure
              TextFormField(
                controller: _unitController,
                decoration: const InputDecoration(
                  labelText: 'Unit of Measure',
                  hintText: 'pcs, kg, box, hrs, etc.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              // Description
              TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              // Toggles
              SwitchListTile(
                title: const Text('Track Inventory'),
                subtitle: const Text('Enable stock movement & balance tracking'),
                value: _trackInventory,
                onChanged: (val) => setState(() => _trackInventory = val),
              ),
              SwitchListTile(
                title: const Text('Active Product'),
                subtitle: const Text('Available for sales documents and invoices'),
                value: _isActive,
                onChanged: (val) => setState(() => _isActive = val),
              ),
              const SizedBox(height: 24),
              // Actions
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
                      : const Icon(Icons.check),
                  label: Text(_submitting ? 'Creating...' : 'Create Product'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

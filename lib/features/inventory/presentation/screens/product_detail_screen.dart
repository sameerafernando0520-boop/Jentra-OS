import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../company/application/company_state.dart';
import '../../../company/presentation/widgets/company_context_gate.dart';
import '../../application/inventory_failure.dart';
import '../../application/product_models.dart';
import '../../application/product_state.dart';

final class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({required this.productId, super.key});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(selectedCompanyProvider);
    if (company == null) {
      return const CompanyRouteRedirect(location: '/company/select');
    }

    final productAsync = ref.watch(productDetailProvider(productId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Product',
            onPressed: () =>
                context.push('/inventory/products/$productId/edit'),
          ),
        ],
      ),
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
                  onPressed: () => ref.invalidate(productDetailProvider(productId)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (product) => _ProductDetailContent(product: product),
      ),
    );
  }
}

final class _ProductDetailContent extends StatelessWidget {
  const _ProductDetailContent({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: product.isActive
                        ? theme.colorScheme.primaryContainer
                        : Colors.grey.shade300,
                    child: Icon(
                      Icons.inventory_2,
                      size: 32,
                      color: product.isActive
                          ? theme.colorScheme.onPrimaryContainer
                          : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (product.categoryName != null) ...[
                          const SizedBox(height: 4),
                          Chip(
                            label: Text(product.categoryName!),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: product.isActive
                          ? Colors.green.shade100
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      product.isActive ? 'Active' : 'Inactive',
                      style: TextStyle(
                        color: product.isActive
                            ? Colors.green.shade900
                            : Colors.grey.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Master Data Grid
          Text('Master Data', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _DetailRow(
                    label: 'Selling Price',
                    value: '\$${product.unitPrice.toStringAsFixed(2)} / ${product.unit}',
                  ),
                  const Divider(),
                  _DetailRow(
                    label: 'Cost Price',
                    value: '\$${product.costPrice.toStringAsFixed(2)}',
                  ),
                  const Divider(),
                  _DetailRow(
                    label: 'SKU',
                    value: product.sku ?? 'Not set',
                  ),
                  const Divider(),
                  _DetailRow(
                    label: 'Barcode',
                    value: product.barcode ?? 'Not set',
                  ),
                  const Divider(),
                  _DetailRow(
                    label: 'Unit of Measure',
                    value: product.unit,
                  ),
                  const Divider(),
                  _DetailRow(
                    label: 'Track Inventory',
                    value: product.trackInventory ? 'Yes' : 'No',
                  ),
                  if (product.description != null &&
                      product.description!.isNotEmpty) ...[
                    const Divider(),
                    _DetailRow(
                      label: 'Description',
                      value: product.description!,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Stock Overview section
          Text('Stock Overview', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StockSummaryItem(
                        label: 'On Hand',
                        quantity: product.totalOnHand,
                        unit: product.unit,
                      ),
                      _StockSummaryItem(
                        label: 'Allocated',
                        quantity: product.totalAllocated,
                        unit: product.unit,
                      ),
                      _StockSummaryItem(
                        label: 'Available',
                        quantity: product.totalAvailable,
                        unit: product.unit,
                        color: Colors.green,
                      ),
                    ],
                  ),
                  if (product.stockBalances.isNotEmpty) ...[
                    const Divider(height: 24),
                    Text(
                      'Warehouse Breakdown',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    ...product.stockBalances.map(
                      (balance) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.warehouse_outlined),
                        title: Text(balance.warehouseName ?? 'Warehouse'),
                        trailing: Text(
                          '${balance.quantityAvailable} ${product.unit}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ] else ...[
                    const Divider(height: 24),
                    const Text(
                      'No stock movement data recorded yet across warehouses.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

final class _StockSummaryItem extends StatelessWidget {
  const _StockSummaryItem({
    required this.label,
    required this.quantity,
    required this.unit,
    this.color,
  });

  final String label;
  final double quantity;
  final String unit;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          quantity.toStringAsFixed(quantity.truncateToDouble() == quantity ? 0 : 2),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text('$label ($unit)', style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

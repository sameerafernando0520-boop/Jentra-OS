import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../company/application/company_state.dart';
import '../../../company/presentation/widgets/company_context_gate.dart';
import '../../application/inventory_failure.dart';
import '../../application/product_models.dart';
import '../../application/product_state.dart';

final class ProductListScreen extends ConsumerStatefulWidget {
  const ProductListScreen({super.key});

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

final class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _scheduleSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(productControllerProvider.notifier).updateSearch(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(selectedCompanyProvider);
    if (company == null) {
      return const CompanyRouteRedirect(location: '/company/select');
    }

    final productsAsync = ref.watch(productControllerProvider);
    final categoriesAsync = ref.watch(categoryListProvider);

    return productsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ProductListError(
        message: error is InventoryFailure ? error.message : error.toString(),
        onRetry: () =>
            ref.read(productControllerProvider.notifier).refreshProducts(),
      ),
      data: (state) => _ProductListContent(
        key: ValueKey('product-list-company-${company.id}'),
        companyName: company.name,
        state: state,
        categories: categoriesAsync.value ?? const [],
        searchController: _searchController,
        onSearchChanged: _scheduleSearch,
        onClearSearch: () {
          _searchController.clear();
          _scheduleSearch('');
        },
        onCategorySelected: (catId) => ref
            .read(productControllerProvider.notifier)
            .selectCategory(catId),
        onIncludeInactiveChanged: (value) => ref
            .read(productControllerProvider.notifier)
            .setIncludeInactive(value),
        onRefresh: () =>
            ref.read(productControllerProvider.notifier).refreshProducts(),
        onLoadMore: () =>
            ref.read(productControllerProvider.notifier).loadMore(),
      ),
    );
  }
}

final class _ProductListContent extends StatelessWidget {
  const _ProductListContent({
    required this.companyName,
    required this.state,
    required this.categories,
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onCategorySelected,
    required this.onIncludeInactiveChanged,
    required this.onRefresh,
    required this.onLoadMore,
    super.key,
  });

  final String companyName;
  final ProductState state;
  final List<ProductCategory> categories;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<String?> onCategorySelected;
  final ValueChanged<bool> onIncludeInactiveChanged;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Products - $companyName'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Product',
            onPressed: () => context.push('/inventory/products/new'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/inventory/products/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
      ),
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Search box
                    TextField(
                      controller: searchController,
                      onChanged: onSearchChanged,
                      decoration: InputDecoration(
                        hintText: 'Search products by name, SKU, or barcode...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: onClearSearch,
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Categories chips
                    if (categories.isNotEmpty) ...[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            FilterChip(
                              label: const Text('All Categories'),
                              selected: state.selectedCategoryId == null,
                              onSelected: (_) => onCategorySelected(null),
                            ),
                            const SizedBox(width: 8),
                            ...categories.map(
                              (cat) => Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: FilterChip(
                                  label: Text(cat.name),
                                  selected: state.selectedCategoryId == cat.id,
                                  onSelected: (_) => onCategorySelected(cat.id),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    // Show inactive toggle
                    Row(
                      children: [
                        Checkbox(
                          value: state.includeInactive,
                          onChanged: (val) =>
                              onIncludeInactiveChanged(val ?? false),
                        ),
                        const Text('Include inactive products'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (state.products.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 64,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          state.search.isNotEmpty ||
                                  state.selectedCategoryId != null
                              ? 'No products match your filters'
                              : 'No products created yet',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add products to manage inventory and create invoices.',
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => context.push('/inventory/products/new'),
                          icon: const Icon(Icons.add),
                          label: const Text('Create Product'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= state.products.length) {
                      if (state.canLoadMore) {
                        onLoadMore();
                        return const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      return const SizedBox.shrink();
                    }

                    final product = state.products[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: product.isActive
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Colors.grey.shade300,
                          child: Icon(
                            Icons.inventory_2,
                            color: product.isActive
                                ? Theme.of(context).colorScheme.onPrimaryContainer
                                : Colors.grey,
                          ),
                        ),
                        title: Text(
                          product.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            decoration: product.isActive
                                ? null
                                : TextDecoration.lineThrough,
                          ),
                        ),
                        subtitle: Text(
                          '${product.sku != null ? "SKU: ${product.sku} • " : ""}'
                          '${product.categoryName != null ? "${product.categoryName} • " : ""}'
                          'Price: \$${product.unitPrice.toStringAsFixed(2)} / ${product.unit}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!product.isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Inactive',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () =>
                            context.push('/inventory/products/${product.id}'),
                      ),
                    );
                  },
                  childCount: state.products.length + (state.canLoadMore ? 1 : 0),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final class _ProductListError extends StatelessWidget {
  const _ProductListError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

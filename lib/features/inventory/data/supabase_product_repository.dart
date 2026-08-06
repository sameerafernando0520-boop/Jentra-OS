import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/inventory_failure.dart';
import '../application/inventory_models.dart';
import '../application/product_models.dart';
import '../application/product_repository.dart';
import 'inventory_service.dart';
import 'product_service.dart';

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return SupabaseProductRepository(
    ref.watch(productServiceProvider),
    ref.watch(inventoryServiceProvider),
  );
});

final class SupabaseProductRepository implements ProductRepository {
  const SupabaseProductRepository(this._productService, this._inventoryService);

  final ProductService _productService;
  final InventoryService _inventoryService;

  @override
  Future<ProductPage> listProducts({
    required String companyId,
    required String search,
    String? categoryId,
    required bool includeInactive,
    ProductCursor? cursor,
    int pageSize = 30,
  }) async {
    final rows = await _productService.fetchProducts(
      companyId: companyId,
      search: search,
      categoryId: categoryId,
      includeInactive: includeInactive,
      cursor: cursor,
      limit: pageSize,
    );

    final products = rows.map((row) => _mapProduct(row, companyId)).toList();
    ProductCursor? nextCursor;
    if (products.length >= pageSize) {
      final last = products.last;
      nextCursor = ProductCursor(sortName: last.name.toLowerCase(), id: last.id);
    }

    return ProductPage(products: products, nextCursor: nextCursor);
  }

  @override
  Future<Product> getProduct({
    required String companyId,
    required String productId,
  }) async {
    final row = await _productService.fetchProduct(
      companyId: companyId,
      productId: productId,
    );

    if (row == null) {
      throw const InventoryFailure('Product not found.');
    }

    // Fetch stock balances for this product
    final balanceRows = await _inventoryService.fetchStockBalances(
      companyId: companyId,
      productId: productId,
    );

    final balances = balanceRows.map(_mapStockBalance).toList();
    return _mapProduct(row, companyId, balances: balances);
  }

  @override
  Future<Product> createProduct({
    required String companyId,
    required ProductInput input,
  }) async {
    final row = await _productService.insertProduct(
      companyId: companyId,
      input: input,
    );
    return _mapProduct(row, companyId);
  }

  @override
  Future<Product> updateProduct({
    required String companyId,
    required String productId,
    required ProductInput input,
  }) async {
    final row = await _productService.updateProduct(
      companyId: companyId,
      productId: productId,
      input: input,
    );

    if (row == null) {
      throw const InventoryFailure('Product update failed or product not found.');
    }
    return _mapProduct(row, companyId);
  }

  @override
  Future<Product> setProductActive({
    required String companyId,
    required String productId,
    required bool isActive,
  }) async {
    final row = await _productService.updateProductActive(
      companyId: companyId,
      productId: productId,
      isActive: isActive,
    );

    if (row == null) {
      throw const InventoryFailure('Product update failed or product not found.');
    }
    return _mapProduct(row, companyId);
  }

  @override
  Future<List<ProductCategory>> listCategories({
    required String companyId,
  }) async {
    final rows = await _productService.fetchCategories(companyId: companyId);
    return rows.map(_mapCategory).toList();
  }

  @override
  Future<ProductCategory> createCategory({
    required String companyId,
    required ProductCategoryInput input,
  }) async {
    final row = await _productService.insertCategory(
      companyId: companyId,
      input: input,
    );
    return _mapCategory(row);
  }

  Product _mapProduct(
    Map<String, dynamic> row,
    String companyId, {
    List<StockBalance> balances = const [],
  }) {
    final catMap = row['product_categories'] as Map<String, dynamic>?;
    return Product(
      id: row['id'] as String,
      companyId: row['company_id'] as String? ?? companyId,
      categoryId: row['category_id'] as String?,
      categoryName: catMap?['name'] as String?,
      name: row['name'] as String,
      sku: row['sku'] as String?,
      barcode: row['barcode'] as String?,
      description: row['description'] as String?,
      unit: row['unit'] as String? ?? 'pcs',
      unitPrice: (row['unit_price'] as num?)?.toDouble() ?? 0.0,
      costPrice: (row['cost_price'] as num?)?.toDouble() ?? 0.0,
      trackInventory: row['track_inventory'] as bool? ?? true,
      isActive: row['is_active'] as bool? ?? true,
      stockBalances: balances,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  ProductCategory _mapCategory(Map<String, dynamic> row) {
    return ProductCategory(
      id: row['id'] as String,
      companyId: row['company_id'] as String,
      name: row['name'] as String,
      code: row['code'] as String?,
      description: row['description'] as String?,
      isActive: row['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  StockBalance _mapStockBalance(Map<String, dynamic> row) {
    final whMap = row['warehouses'] as Map<String, dynamic>?;
    return StockBalance(
      id: row['id'] as String,
      companyId: row['company_id'] as String,
      productId: row['product_id'] as String,
      warehouseId: row['warehouse_id'] as String,
      warehouseName: whMap?['name'] as String?,
      quantityOnHand: (row['quantity_on_hand'] as num?)?.toDouble() ?? 0.0,
      quantityAllocated: (row['quantity_allocated'] as num?)?.toDouble() ?? 0.0,
      quantityAvailable: (row['quantity_available'] as num?)?.toDouble() ?? 0.0,
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}

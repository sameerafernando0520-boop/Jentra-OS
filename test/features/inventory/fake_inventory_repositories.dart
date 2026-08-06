import 'package:jentra_os/features/inventory/application/inventory_models.dart';
import 'package:jentra_os/features/inventory/application/inventory_repository.dart';
import 'package:jentra_os/features/inventory/application/product_models.dart';
import 'package:jentra_os/features/inventory/application/product_repository.dart';

final class FakeProductRepository implements ProductRepository {
  FakeProductRepository({
    List<Product> products = const <Product>[],
    List<ProductCategory> categories = const <ProductCategory>[],
  })  : products = List<Product>.of(products),
        categories = List<ProductCategory>.of(categories);

  final List<Product> products;
  final List<ProductCategory> categories;
  final List<String> listCompanyIds = <String>[];
  final List<String> createCompanyIds = <String>[];

  @override
  Future<ProductPage> listProducts({
    required String companyId,
    required String search,
    String? categoryId,
    required bool includeInactive,
    ProductCursor? cursor,
    int pageSize = 30,
  }) async {
    listCompanyIds.add(companyId);
    final query = search.toLowerCase();
    final matches = products.where((p) {
      if (p.companyId != companyId) return false;
      if (!includeInactive && !p.isActive) return false;
      if (categoryId != null && p.categoryId != categoryId) return false;
      if (query.isEmpty) return true;
      return p.name.toLowerCase().contains(query) ||
          (p.sku?.toLowerCase().contains(query) ?? false) ||
          (p.barcode?.toLowerCase().contains(query) ?? false);
    }).toList();

    return ProductPage(products: matches, nextCursor: null);
  }

  @override
  Future<Product> getProduct({
    required String companyId,
    required String productId,
  }) async {
    return products.firstWhere(
      (p) => p.id == productId && p.companyId == companyId,
    );
  }

  @override
  Future<Product> createProduct({
    required String companyId,
    required ProductInput input,
  }) async {
    createCompanyIds.add(companyId);
    final now = DateTime.now();
    final product = Product(
      id: 'created-prod-${products.length + 1}',
      companyId: companyId,
      categoryId: input.categoryId,
      categoryName: categories
          .where((c) => c.id == input.categoryId)
          .map((c) => c.name)
          .firstOrNull,
      name: input.name,
      sku: input.sku,
      barcode: input.barcode,
      description: input.description,
      unit: input.unit,
      unitPrice: input.unitPrice,
      costPrice: input.costPrice,
      trackInventory: input.trackInventory,
      isActive: input.isActive,
      createdAt: now,
      updatedAt: now,
    );
    products.add(product);
    return product;
  }

  @override
  Future<Product> updateProduct({
    required String companyId,
    required String productId,
    required ProductInput input,
  }) async {
    final index = products.indexWhere((p) => p.id == productId);
    final existing = products[index];
    final updated = Product(
      id: productId,
      companyId: companyId,
      categoryId: input.categoryId,
      categoryName: categories
          .where((c) => c.id == input.categoryId)
          .map((c) => c.name)
          .firstOrNull,
      name: input.name,
      sku: input.sku,
      barcode: input.barcode,
      description: input.description,
      unit: input.unit,
      unitPrice: input.unitPrice,
      costPrice: input.costPrice,
      trackInventory: input.trackInventory,
      isActive: input.isActive,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
    );
    products[index] = updated;
    return updated;
  }

  @override
  Future<Product> setProductActive({
    required String companyId,
    required String productId,
    required bool isActive,
  }) async {
    final index = products.indexWhere((p) => p.id == productId);
    final existing = products[index];
    final updated = Product(
      id: productId,
      companyId: companyId,
      categoryId: existing.categoryId,
      categoryName: existing.categoryName,
      name: existing.name,
      sku: existing.sku,
      barcode: existing.barcode,
      description: existing.description,
      unit: existing.unit,
      unitPrice: existing.unitPrice,
      costPrice: existing.costPrice,
      trackInventory: existing.trackInventory,
      isActive: isActive,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
    );
    products[index] = updated;
    return updated;
  }

  @override
  Future<List<ProductCategory>> listCategories({
    required String companyId,
  }) async {
    return categories.where((c) => c.companyId == companyId).toList();
  }

  @override
  Future<ProductCategory> createCategory({
    required String companyId,
    required ProductCategoryInput input,
  }) async {
    final now = DateTime.now();
    final cat = ProductCategory(
      id: 'cat-${categories.length + 1}',
      companyId: companyId,
      name: input.name,
      code: input.code,
      description: input.description,
      isActive: input.isActive,
      createdAt: now,
      updatedAt: now,
    );
    categories.add(cat);
    return cat;
  }
}

final class FakeInventoryRepository implements InventoryRepository {
  FakeInventoryRepository({
    List<Warehouse> warehouses = const <Warehouse>[],
    List<StockOverviewItem> stockOverview = const <StockOverviewItem>[],
  })  : warehouses = List<Warehouse>.of(warehouses),
        stockOverview = List<StockOverviewItem>.of(stockOverview);

  final List<Warehouse> warehouses;
  final List<StockOverviewItem> stockOverview;
  final List<String> movementRequests = <String>[];

  @override
  Future<List<Warehouse>> listWarehouses({
    required String companyId,
  }) async {
    return warehouses.where((w) => w.companyId == companyId).toList();
  }

  @override
  Future<Warehouse> createWarehouse({
    required String companyId,
    required WarehouseInput input,
  }) async {
    final now = DateTime.now();
    final wh = Warehouse(
      id: 'wh-${warehouses.length + 1}',
      companyId: companyId,
      name: input.name,
      code: input.code,
      address: input.address,
      isDefault: input.isDefault,
      isActive: input.isActive,
      createdAt: now,
      updatedAt: now,
    );
    warehouses.add(wh);
    return wh;
  }

  @override
  Future<Warehouse> updateWarehouse({
    required String companyId,
    required String warehouseId,
    required WarehouseInput input,
  }) async {
    final index = warehouses.indexWhere((w) => w.id == warehouseId);
    final existing = warehouses[index];
    final updated = Warehouse(
      id: warehouseId,
      companyId: companyId,
      name: input.name,
      code: input.code,
      address: input.address,
      isDefault: input.isDefault,
      isActive: input.isActive,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
    );
    warehouses[index] = updated;
    return updated;
  }

  @override
  Future<List<StockOverviewItem>> listStockOverview({
    required String companyId,
    String? search,
    String? warehouseId,
  }) async {
    return stockOverview.where((item) {
      if (warehouseId != null && item.warehouseId != warehouseId) return false;
      if (search != null && search.isNotEmpty) {
        return item.productName.toLowerCase().contains(search.toLowerCase());
      }
      return true;
    }).toList();
  }

  @override
  Future<void> recordStockMovement({
    required String companyId,
    required String productId,
    required String warehouseId,
    required String movementType,
    required double quantity,
    double? unitCost,
    String? referenceType,
    String? referenceId,
    String? notes,
  }) async {
    movementRequests.add('$companyId:$productId:$warehouseId:$movementType:$quantity');
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/inventory_failure.dart';
import '../application/inventory_models.dart';
import '../application/inventory_repository.dart';
import 'inventory_service.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return SupabaseInventoryRepository(ref.watch(inventoryServiceProvider));
});

final class SupabaseInventoryRepository implements InventoryRepository {
  const SupabaseInventoryRepository(this._inventoryService);

  final InventoryService _inventoryService;

  @override
  Future<List<Warehouse>> listWarehouses({
    required String companyId,
  }) async {
    final rows = await _inventoryService.fetchWarehouses(companyId: companyId);
    return rows.map(_mapWarehouse).toList();
  }

  @override
  Future<Warehouse> createWarehouse({
    required String companyId,
    required WarehouseInput input,
  }) async {
    final row = await _inventoryService.insertWarehouse(
      companyId: companyId,
      input: input,
    );
    return _mapWarehouse(row);
  }

  @override
  Future<Warehouse> updateWarehouse({
    required String companyId,
    required String warehouseId,
    required WarehouseInput input,
  }) async {
    final row = await _inventoryService.updateWarehouse(
      companyId: companyId,
      warehouseId: warehouseId,
      input: input,
    );

    if (row == null) {
      throw const InventoryFailure('Warehouse update failed or not found.');
    }
    return _mapWarehouse(row);
  }

  @override
  Future<List<StockOverviewItem>> listStockOverview({
    required String companyId,
    String? search,
    String? warehouseId,
  }) async {
    final rows = await _inventoryService.fetchStockOverview(
      companyId: companyId,
      search: search,
      warehouseId: warehouseId,
    );
    return rows.map(_mapStockOverviewItem).toList();
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
    await _inventoryService.recordStockMovement(
      companyId: companyId,
      productId: productId,
      warehouseId: warehouseId,
      movementType: movementType,
      quantity: quantity,
      unitCost: unitCost,
      referenceType: referenceType,
      referenceId: referenceId,
      notes: notes,
    );
  }

  Warehouse _mapWarehouse(Map<String, dynamic> row) {
    return Warehouse(
      id: row['id'] as String,
      companyId: row['company_id'] as String,
      name: row['name'] as String,
      code: row['code'] as String?,
      address: row['address'] as String?,
      isDefault: row['is_default'] as bool? ?? false,
      isActive: row['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  StockOverviewItem _mapStockOverviewItem(Map<String, dynamic> row) {
    final prodMap = row['products'] as Map<String, dynamic>? ?? {};
    final whMap = row['warehouses'] as Map<String, dynamic>? ?? {};
    final catMap = prodMap['product_categories'] as Map<String, dynamic>?;

    return StockOverviewItem(
      productId: row['product_id'] as String,
      productName: prodMap['name'] as String? ?? 'Unknown Product',
      sku: prodMap['sku'] as String?,
      barcode: prodMap['barcode'] as String?,
      categoryName: catMap?['name'] as String?,
      unit: prodMap['unit'] as String? ?? 'pcs',
      warehouseId: row['warehouse_id'] as String,
      warehouseName: whMap['name'] as String? ?? 'Main Warehouse',
      quantityOnHand: (row['quantity_on_hand'] as num?)?.toDouble() ?? 0.0,
      quantityAllocated: (row['quantity_allocated'] as num?)?.toDouble() ?? 0.0,
      quantityAvailable: (row['quantity_available'] as num?)?.toDouble() ?? 0.0,
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}

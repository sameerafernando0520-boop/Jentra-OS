import 'inventory_models.dart';

abstract class InventoryRepository {
  Future<List<Warehouse>> listWarehouses({
    required String companyId,
  });

  Future<Warehouse> createWarehouse({
    required String companyId,
    required WarehouseInput input,
  });

  Future<Warehouse> updateWarehouse({
    required String companyId,
    required String warehouseId,
    required WarehouseInput input,
  });

  Future<List<StockOverviewItem>> listStockOverview({
    required String companyId,
    String? search,
    String? warehouseId,
  });

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
  });
}

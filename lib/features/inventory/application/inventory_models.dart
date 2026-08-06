final class Warehouse {
  const Warehouse({
    required this.id,
    required this.companyId,
    required this.name,
    this.code,
    this.address,
    this.isDefault = false,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final String name;
  final String? code;
  final String? address;
  final bool isDefault;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class WarehouseInput {
  const WarehouseInput({
    required this.name,
    this.code,
    this.address,
    this.isDefault = false,
    this.isActive = true,
  });

  final String name;
  final String? code;
  final String? address;
  final bool isDefault;
  final bool isActive;
}

final class StockBalance {
  const StockBalance({
    required this.id,
    required this.companyId,
    required this.productId,
    required this.warehouseId,
    this.warehouseName,
    required this.quantityOnHand,
    required this.quantityAllocated,
    required this.quantityAvailable,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final String productId;
  final String warehouseId;
  final String? warehouseName;
  final double quantityOnHand;
  final double quantityAllocated;
  final double quantityAvailable;
  final DateTime updatedAt;
}

final class StockMovement {
  const StockMovement({
    required this.id,
    required this.companyId,
    required this.productId,
    required this.warehouseId,
    required this.movementType,
    required this.quantity,
    this.unitCost,
    this.referenceType,
    this.referenceId,
    this.notes,
    this.createdBy,
    required this.createdAt,
  });

  final String id;
  final String companyId;
  final String productId;
  final String warehouseId;
  final String movementType; // 'in', 'out', 'adjustment', 'transfer', 'opening'
  final double quantity;
  final double? unitCost;
  final String? referenceType;
  final String? referenceId;
  final String? notes;
  final String? createdBy;
  final DateTime createdAt;
}

final class StockOverviewItem {
  const StockOverviewItem({
    required this.productId,
    required this.productName,
    this.sku,
    this.barcode,
    this.categoryName,
    required this.unit,
    required this.warehouseId,
    required this.warehouseName,
    required this.quantityOnHand,
    required this.quantityAllocated,
    required this.quantityAvailable,
    required this.updatedAt,
  });

  final String productId;
  final String productName;
  final String? sku;
  final String? barcode;
  final String? categoryName;
  final String unit;
  final String warehouseId;
  final String warehouseName;
  final double quantityOnHand;
  final double quantityAllocated;
  final double quantityAvailable;
  final DateTime updatedAt;
}

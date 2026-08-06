final class StockTransferItem {
  const StockTransferItem({
    required this.id,
    required this.companyId,
    required this.transferId,
    required this.productId,
    required this.quantity,
  });

  final String id;
  final String companyId;
  final String transferId;
  final String productId;
  final double quantity;
}

final class StockTransfer {
  const StockTransfer({
    required this.id,
    required this.companyId,
    required this.transferNumber,
    required this.fromWarehouseId,
    required this.toWarehouseId,
    required this.status,
    this.notes,
    this.items = const [],
    required this.createdAt,
  });

  final String id;
  final String companyId;
  final String transferNumber;
  final String fromWarehouseId;
  final String toWarehouseId;
  final String status;
  final String? notes;
  final List<StockTransferItem> items;
  final DateTime createdAt;
}

import 'inventory_models.dart';

final class ProductCategory {
  const ProductCategory({
    required this.id,
    required this.companyId,
    required this.name,
    this.code,
    this.description,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final String name;
  final String? code;
  final String? description;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class ProductCategoryInput {
  const ProductCategoryInput({
    required this.name,
    this.code,
    this.description,
    this.isActive = true,
  });

  final String name;
  final String? code;
  final String? description;
  final bool isActive;
}

final class Product {
  const Product({
    required this.id,
    required this.companyId,
    this.categoryId,
    this.categoryName,
    required this.name,
    this.sku,
    this.barcode,
    this.description,
    this.unit = 'pcs',
    required this.unitPrice,
    required this.costPrice,
    this.trackInventory = true,
    this.isActive = true,
    this.stockBalances = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final String? categoryId;
  final String? categoryName;
  final String name;
  final String? sku;
  final String? barcode;
  final String? description;
  final String unit;
  final double unitPrice;
  final double costPrice;
  final bool trackInventory;
  final bool isActive;
  final List<StockBalance> stockBalances;
  final DateTime createdAt;
  final DateTime updatedAt;

  double get totalOnHand =>
      stockBalances.fold(0.0, (sum, item) => sum + item.quantityOnHand);

  double get totalAllocated =>
      stockBalances.fold(0.0, (sum, item) => sum + item.quantityAllocated);

  double get totalAvailable =>
      stockBalances.fold(0.0, (sum, item) => sum + item.quantityAvailable);
}

final class ProductInput {
  const ProductInput({
    required this.name,
    this.categoryId,
    this.sku,
    this.barcode,
    this.description,
    this.unit = 'pcs',
    required this.unitPrice,
    required this.costPrice,
    this.trackInventory = true,
    this.isActive = true,
  });

  final String name;
  final String? categoryId;
  final String? sku;
  final String? barcode;
  final String? description;
  final String unit;
  final double unitPrice;
  final double costPrice;
  final bool trackInventory;
  final bool isActive;
}

final class ProductCursor {
  const ProductCursor({required this.sortName, required this.id});

  final String sortName;
  final String id;
}

final class ProductPage {
  const ProductPage({required this.products, required this.nextCursor});

  final List<Product> products;
  final ProductCursor? nextCursor;
}

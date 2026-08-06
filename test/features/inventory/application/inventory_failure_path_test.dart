import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_os/features/company/application/company_state.dart';
import 'package:jentra_os/features/inventory/application/inventory_failure.dart';
import 'package:jentra_os/features/inventory/application/product_models.dart';
import 'package:jentra_os/features/inventory/application/product_repository.dart';
import 'package:jentra_os/features/inventory/application/product_state.dart';
import 'package:jentra_os/features/inventory/data/supabase_product_repository.dart';

final class ThrowingProductRepository implements ProductRepository {
  ThrowingProductRepository({this.errorMessage = 'Product repository error'});

  final String errorMessage;

  @override
  Future<Product> createProduct({
    required String companyId,
    required ProductInput input,
  }) async {
    throw InventoryFailure(errorMessage);
  }

  @override
  Future<ProductPage> listProducts({
    required String companyId,
    required String search,
    String? categoryId,
    required bool includeInactive,
    ProductCursor? cursor,
    int pageSize = 30,
  }) async {
    throw InventoryFailure(errorMessage);
  }

  @override
  Future<Product> getProduct({
    required String companyId,
    required String productId,
  }) async {
    throw InventoryFailure(errorMessage);
  }

  @override
  Future<Product> updateProduct({
    required String companyId,
    required String productId,
    required ProductInput input,
  }) async {
    throw InventoryFailure(errorMessage);
  }

  @override
  Future<Product> setProductActive({
    required String companyId,
    required String productId,
    required bool isActive,
  }) async {
    throw InventoryFailure(errorMessage);
  }

  @override
  Future<List<ProductCategory>> listCategories({
    required String companyId,
  }) async {
    throw InventoryFailure(errorMessage);
  }

  @override
  Future<ProductCategory> createCategory({
    required String companyId,
    required ProductCategoryInput input,
  }) async {
    throw InventoryFailure(errorMessage);
  }
}

void main() {
  group('Inventory & Product Failure Paths & Error Handling', () {
    test('productController handles repository exception gracefully', () async {
      final throwingRepo = ThrowingProductRepository(errorMessage: 'Permission denied to list products.');
      final container = ProviderContainer(
        overrides: [
          productRepositoryProvider.overrideWithValue(throwingRepo),
          selectedCompanyIdProvider.overrideWith((ref) => 'comp-1'),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(productControllerProvider.future),
        throwsA(isA<InventoryFailure>().having((f) => f.message, 'message', contains('Permission denied'))),
      );
    });

    test('createProduct handles repository error and throws InventoryFailure', () async {
      final throwingRepo = ThrowingProductRepository(errorMessage: 'Duplicate SKU code');
      final container = ProviderContainer(
        overrides: [
          productRepositoryProvider.overrideWithValue(throwingRepo),
          selectedCompanyIdProvider.overrideWith((ref) => 'comp-1'),
        ],
      );
      addTearDown(container.dispose);

      const input = ProductInput(
        name: 'New Product',
        unit: 'pcs',
        unitPrice: 100.0,
        costPrice: 50.0,
      );

      expect(
        () => container.read(productMutationProvider.notifier).createProduct(input),
        throwsA(isA<InventoryFailure>().having((f) => f.message, 'message', contains('Duplicate SKU'))),
      );
    });
  });
}

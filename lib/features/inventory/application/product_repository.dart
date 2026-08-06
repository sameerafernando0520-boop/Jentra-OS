import 'product_models.dart';

abstract class ProductRepository {
  Future<ProductPage> listProducts({
    required String companyId,
    required String search,
    String? categoryId,
    required bool includeInactive,
    ProductCursor? cursor,
    int pageSize = 30,
  });

  Future<Product> getProduct({
    required String companyId,
    required String productId,
  });

  Future<Product> createProduct({
    required String companyId,
    required ProductInput input,
  });

  Future<Product> updateProduct({
    required String companyId,
    required String productId,
    required ProductInput input,
  });

  Future<Product> setProductActive({
    required String companyId,
    required String productId,
    required bool isActive,
  });

  Future<List<ProductCategory>> listCategories({
    required String companyId,
  });

  Future<ProductCategory> createCategory({
    required String companyId,
    required ProductCategoryInput input,
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../company/application/company_state.dart';
import '../data/supabase_product_repository.dart';
import 'inventory_failure.dart';
import 'product_models.dart';

final productControllerProvider =
    AsyncNotifierProvider<ProductController, ProductState>(
      ProductController.new,
      retry: (_, _) => null,
    );

final productMutationProvider =
    AsyncNotifierProvider<ProductMutationController, Product?>(
      ProductMutationController.new,
      retry: (_, _) => null,
    );

final productDetailProvider = FutureProvider.autoDispose
    .family<Product, String>((ref, productId) async {
      final companyId = ref.watch(selectedCompanyIdProvider);
      if (companyId == null || companyId.trim().isEmpty) {
        throw const InventoryFailure(
          'Select a company before loading a product.',
        );
      }
      return ref
          .watch(productRepositoryProvider)
          .getProduct(companyId: companyId, productId: productId);
    }, retry: (_, _) => null);

final categoryListProvider = FutureProvider.autoDispose<List<ProductCategory>>((
  ref,
) async {
  final companyId = ref.watch(selectedCompanyIdProvider);
  if (companyId == null || companyId.trim().isEmpty) {
    return const [];
  }
  return ref
      .watch(productRepositoryProvider)
      .listCategories(companyId: companyId);
}, retry: (_, _) => null);

final class ProductState {
  const ProductState({
    required this.companyId,
    required this.products,
    required this.search,
    this.selectedCategoryId,
    required this.includeInactive,
    required this.nextCursor,
    this.isRefreshing = false,
    this.isLoadingMore = false,
  });

  final String companyId;
  final List<Product> products;
  final String search;
  final String? selectedCategoryId;
  final bool includeInactive;
  final ProductCursor? nextCursor;
  final bool isRefreshing;
  final bool isLoadingMore;

  bool get canLoadMore => nextCursor != null && !isLoadingMore;

  ProductState copyWith({
    List<Product>? products,
    String? search,
    String? selectedCategoryId,
    bool clearCategory = false,
    bool? includeInactive,
    ProductCursor? nextCursor,
    bool clearCursor = false,
    bool? isRefreshing,
    bool? isLoadingMore,
  }) {
    return ProductState(
      companyId: companyId,
      products: products ?? this.products,
      search: search ?? this.search,
      selectedCategoryId: clearCategory
          ? null
          : selectedCategoryId ?? this.selectedCategoryId,
      includeInactive: includeInactive ?? this.includeInactive,
      nextCursor: clearCursor ? null : nextCursor ?? this.nextCursor,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

final class ProductController extends AsyncNotifier<ProductState> {
  static const _pageSize = 30;

  String _search = '';
  String? _selectedCategoryId;
  bool _includeInactive = false;
  int _requestVersion = 0;

  @override
  Future<ProductState> build() async {
    final companyId = ref.watch(selectedCompanyIdProvider);
    if (companyId == null || companyId.trim().isEmpty) {
      throw const InventoryFailure('Select a company before loading products.');
    }

    _search = '';
    _selectedCategoryId = null;
    _includeInactive = false;
    _requestVersion += 1;

    final page = await ref
        .watch(productRepositoryProvider)
        .listProducts(
          companyId: companyId,
          search: _search,
          categoryId: _selectedCategoryId,
          includeInactive: _includeInactive,
          pageSize: _pageSize,
        );

    _ensureCompany(companyId);
    _ensureProductsCompany(page.products, companyId);

    return ProductState(
      companyId: companyId,
      products: page.products,
      search: _search,
      selectedCategoryId: _selectedCategoryId,
      includeInactive: _includeInactive,
      nextCursor: page.nextCursor,
    );
  }

  Future<void> updateSearch(String value) async {
    final normalized = value.trim();
    if (_search == normalized) return;
    _search = normalized;
    await _loadFirstPage();
  }

  Future<void> selectCategory(String? categoryId) async {
    if (_selectedCategoryId == categoryId) return;
    _selectedCategoryId = categoryId;
    await _loadFirstPage();
  }

  Future<void> setIncludeInactive(bool value) async {
    if (_includeInactive == value) return;
    _includeInactive = value;
    await _loadFirstPage();
  }

  Future<void> refreshProducts() => _loadFirstPage();

  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null || !current.canLoadMore) return;
    final cursor = current.nextCursor;
    if (cursor == null) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final page = await ref
          .read(productRepositoryProvider)
          .listProducts(
            companyId: current.companyId,
            search: _search,
            categoryId: _selectedCategoryId,
            includeInactive: _includeInactive,
            cursor: cursor,
            pageSize: _pageSize,
          );

      _ensureCompany(current.companyId);
      _ensureProductsCompany(page.products, current.companyId);

      final existingIds = current.products.map((item) => item.id).toSet();
      final combined = <Product>[
        ...current.products,
        ...page.products.where((item) => existingIds.add(item.id)),
      ];

      state = AsyncData(
        current.copyWith(
          products: List<Product>.unmodifiable(combined),
          nextCursor: page.nextCursor,
          clearCursor: page.nextCursor == null,
          isLoadingMore: false,
        ),
      );
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> _loadFirstPage() async {
    final current = state.asData?.value;
    final companyId = ref.read(selectedCompanyIdProvider);
    if (companyId == null || companyId.trim().isEmpty) {
      state = AsyncError(
        const InventoryFailure('Select a company before loading products.'),
        StackTrace.current,
      );
      return;
    }

    final requestVersion = ++_requestVersion;
    if (current != null) {
      state = AsyncData(
        current.copyWith(
          search: _search,
          selectedCategoryId: _selectedCategoryId,
          includeInactive: _includeInactive,
          isRefreshing: true,
        ),
      );
    } else {
      state = const AsyncLoading();
    }

    try {
      final page = await ref
          .read(productRepositoryProvider)
          .listProducts(
            companyId: companyId,
            search: _search,
            categoryId: _selectedCategoryId,
            includeInactive: _includeInactive,
            pageSize: _pageSize,
          );

      if (requestVersion != _requestVersion) return;
      _ensureCompany(companyId);
      _ensureProductsCompany(page.products, companyId);

      state = AsyncData(
        ProductState(
          companyId: companyId,
          products: page.products,
          search: _search,
          selectedCategoryId: _selectedCategoryId,
          includeInactive: _includeInactive,
          nextCursor: page.nextCursor,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (requestVersion == _requestVersion) {
        state = AsyncError(error, stackTrace);
      }
    }
  }

  void _ensureCompany(String companyId) {
    if (ref.read(selectedCompanyIdProvider) != companyId) {
      throw const InventoryFailure(
        'The selected company changed while loading products.',
      );
    }
  }
}

final class ProductMutationController extends AsyncNotifier<Product?> {
  @override
  Future<Product?> build() async => null;

  Future<Product> createProduct(ProductInput input) async {
    final companyId = _requireCompanyId();
    state = const AsyncLoading();
    try {
      final created = await ref
          .read(productRepositoryProvider)
          .createProduct(companyId: companyId, input: input);

      _ensureCompany(companyId);
      _ensureProductsCompany([created], companyId);

      state = AsyncData(created);
      ref.invalidate(productControllerProvider);
      return created;
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<Product> updateProduct(String productId, ProductInput input) async {
    final companyId = _requireCompanyId();
    state = const AsyncLoading();
    try {
      final updated = await ref
          .read(productRepositoryProvider)
          .updateProduct(
            companyId: companyId,
            productId: productId,
            input: input,
          );

      _ensureCompany(companyId);
      _ensureProductsCompany([updated], companyId);

      state = AsyncData(updated);
      ref.invalidate(productDetailProvider(productId));
      ref.invalidate(productControllerProvider);
      return updated;
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<Product> setProductActive(String productId, bool isActive) async {
    final companyId = _requireCompanyId();
    state = const AsyncLoading();
    try {
      final updated = await ref
          .read(productRepositoryProvider)
          .setProductActive(
            companyId: companyId,
            productId: productId,
            isActive: isActive,
          );

      _ensureCompany(companyId);
      _ensureProductsCompany([updated], companyId);

      state = AsyncData(updated);
      ref.invalidate(productDetailProvider(productId));
      ref.invalidate(productControllerProvider);
      return updated;
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<ProductCategory> createCategory(ProductCategoryInput input) async {
    final companyId = _requireCompanyId();
    try {
      final created = await ref
          .read(productRepositoryProvider)
          .createCategory(companyId: companyId, input: input);
      ref.invalidate(categoryListProvider);
      return created;
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  String _requireCompanyId() {
    final companyId = ref.read(selectedCompanyIdProvider);
    if (companyId == null || companyId.trim().isEmpty) {
      throw const InventoryFailure(
        'Select a company before managing products.',
      );
    }
    return companyId;
  }

  void _ensureCompany(String companyId) {
    if (ref.read(selectedCompanyIdProvider) != companyId) {
      throw const InventoryFailure(
        'The selected company changed during the product action.',
      );
    }
  }
}

void _ensureProductsCompany(List<Product> products, String companyId) {
  if (products.any((p) => p.companyId != companyId)) {
    throw const InventoryFailure(
      'A product response did not match the selected company.',
    );
  }
}

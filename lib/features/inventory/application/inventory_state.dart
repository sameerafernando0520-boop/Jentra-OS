import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../company/application/company_state.dart';
import '../data/supabase_inventory_repository.dart';
import 'inventory_failure.dart';
import 'inventory_models.dart';

final warehouseControllerProvider =
    AsyncNotifierProvider<WarehouseController, List<Warehouse>>(
      WarehouseController.new,
      retry: (_, _) => null,
    );

final stockOverviewControllerProvider = AsyncNotifierProvider<
  StockOverviewController,
  StockOverviewState
>(StockOverviewController.new, retry: (_, _) => null);

final inventoryMutationControllerProvider =
    AsyncNotifierProvider<InventoryMutationController, void>(
      InventoryMutationController.new,
      retry: (_, _) => null,
    );

final class WarehouseController extends AsyncNotifier<List<Warehouse>> {
  @override
  Future<List<Warehouse>> build() async {
    final companyId = ref.watch(selectedCompanyIdProvider);
    if (companyId == null || companyId.trim().isEmpty) {
      return const [];
    }
    return ref
        .watch(inventoryRepositoryProvider)
        .listWarehouses(companyId: companyId);
  }

  Future<Warehouse> createWarehouse(WarehouseInput input) async {
    final companyId = _requireCompanyId();
    final created = await ref
        .read(inventoryRepositoryProvider)
        .createWarehouse(companyId: companyId, input: input);
    ref.invalidateSelf();
    return created;
  }

  Future<Warehouse> updateWarehouse(
    String warehouseId,
    WarehouseInput input,
  ) async {
    final companyId = _requireCompanyId();
    final updated = await ref
        .read(inventoryRepositoryProvider)
        .updateWarehouse(
          companyId: companyId,
          warehouseId: warehouseId,
          input: input,
        );
    ref.invalidateSelf();
    return updated;
  }

  String _requireCompanyId() {
    final companyId = ref.read(selectedCompanyIdProvider);
    if (companyId == null || companyId.trim().isEmpty) {
      throw const InventoryFailure(
        'Select a company before managing warehouses.',
      );
    }
    return companyId;
  }
}

final class StockOverviewState {
  const StockOverviewState({
    required this.companyId,
    required this.items,
    required this.search,
    this.selectedWarehouseId,
  });

  final String companyId;
  final List<StockOverviewItem> items;
  final String search;
  final String? selectedWarehouseId;

  StockOverviewState copyWith({
    List<StockOverviewItem>? items,
    String? search,
    String? selectedWarehouseId,
    bool clearWarehouse = false,
  }) {
    return StockOverviewState(
      companyId: companyId,
      items: items ?? this.items,
      search: search ?? this.search,
      selectedWarehouseId: clearWarehouse
          ? null
          : selectedWarehouseId ?? this.selectedWarehouseId,
    );
  }
}

final class StockOverviewController
    extends AsyncNotifier<StockOverviewState> {
  String _search = '';
  String? _selectedWarehouseId;

  @override
  Future<StockOverviewState> build() async {
    final companyId = ref.watch(selectedCompanyIdProvider);
    if (companyId == null || companyId.trim().isEmpty) {
      throw const InventoryFailure('Select a company before loading stock.');
    }

    _search = '';
    _selectedWarehouseId = null;

    final items = await ref
        .watch(inventoryRepositoryProvider)
        .listStockOverview(
          companyId: companyId,
          search: _search,
          warehouseId: _selectedWarehouseId,
        );

    return StockOverviewState(
      companyId: companyId,
      items: items,
      search: _search,
      selectedWarehouseId: _selectedWarehouseId,
    );
  }

  Future<void> updateSearch(String search) async {
    _search = search;
    await refresh();
  }

  Future<void> filterByWarehouse(String? warehouseId) async {
    _selectedWarehouseId = warehouseId;
    await refresh();
  }

  Future<void> refresh() async {
    final companyId = ref.read(selectedCompanyIdProvider);
    if (companyId == null || companyId.trim().isEmpty) return;

    state = const AsyncLoading();
    try {
      final items = await ref
          .read(inventoryRepositoryProvider)
          .listStockOverview(
            companyId: companyId,
            search: _search,
            warehouseId: _selectedWarehouseId,
          );
      state = AsyncData(
        StockOverviewState(
          companyId: companyId,
          items: items,
          search: _search,
          selectedWarehouseId: _selectedWarehouseId,
        ),
      );
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }
}

final class InventoryMutationController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> recordStockMovement({
    required String productId,
    required String warehouseId,
    required String movementType,
    required double quantity,
    double? unitCost,
    String? referenceType,
    String? referenceId,
    String? notes,
  }) async {
    final companyId = ref.read(selectedCompanyIdProvider);
    if (companyId == null || companyId.trim().isEmpty) {
      throw const InventoryFailure(
        'Select a company before recording stock movements.',
      );
    }

    state = const AsyncLoading();
    try {
      await ref
          .read(inventoryRepositoryProvider)
          .recordStockMovement(
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
      state = const AsyncData(null);
      ref.invalidate(stockOverviewControllerProvider);
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

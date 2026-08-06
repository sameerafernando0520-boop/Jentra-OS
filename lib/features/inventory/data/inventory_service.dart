import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_providers.dart';
import '../application/inventory_failure.dart';
import '../application/inventory_models.dart';

final inventoryServiceProvider = Provider<InventoryService>((ref) {
  return InventoryService(ref.watch(supabaseServiceProvider).client);
});

/// Low-level Data API adapter for warehouses, stock balances, and stock movements.
/// Enforces company_id scoping across all queries. Stock operations are handled via StockService logic.
final class InventoryService {
  const InventoryService(this._client);

  final SupabaseClient _client;

  void requireSession() {
    if (_client.auth.currentUser == null) {
      throw const InventoryFailure('Please sign in to manage inventory.');
    }
  }

  // Warehouses
  Future<List<Map<String, dynamic>>> fetchWarehouses({
    required String companyId,
  }) async {
    requireSession();
    final response = await _client
        .from('warehouses')
        .select()
        .eq('company_id', companyId)
        .order('is_default', ascending: false)
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> insertWarehouse({
    required String companyId,
    required WarehouseInput input,
  }) async {
    requireSession();
    return _client
        .from('warehouses')
        .insert({
          'company_id': companyId,
          'name': input.name.trim(),
          'code': _optional(input.code),
          'address': _optional(input.address),
          'is_default': input.isDefault,
          'is_active': input.isActive,
        })
        .select()
        .single();
  }

  Future<Map<String, dynamic>?> updateWarehouse({
    required String companyId,
    required String warehouseId,
    required WarehouseInput input,
  }) async {
    requireSession();
    return _client
        .from('warehouses')
        .update({
          'name': input.name.trim(),
          'code': _optional(input.code),
          'address': _optional(input.address),
          'is_default': input.isDefault,
          'is_active': input.isActive,
        })
        .eq('company_id', companyId)
        .eq('id', warehouseId)
        .select()
        .maybeSingle();
  }

  // Stock Balances
  Future<List<Map<String, dynamic>>> fetchStockBalances({
    required String companyId,
    String? productId,
    String? warehouseId,
  }) async {
    requireSession();
    var query = _client
        .from('stock_balances')
        .select('''
          id,
          company_id,
          product_id,
          warehouse_id,
          quantity_on_hand,
          quantity_allocated,
          quantity_available,
          updated_at,
          warehouses(name)
        ''')
        .eq('company_id', companyId);

    if (productId != null) {
      query = query.eq('product_id', productId);
    }
    if (warehouseId != null) {
      query = query.eq('warehouse_id', warehouseId);
    }

    final response = await query;
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> fetchStockOverview({
    required String companyId,
    String? search,
    String? warehouseId,
  }) async {
    requireSession();
    var query = _client
        .from('stock_balances')
        .select('''
          id,
          company_id,
          product_id,
          warehouse_id,
          quantity_on_hand,
          quantity_allocated,
          quantity_available,
          updated_at,
          products!inner(name, sku, barcode, unit, product_categories(name)),
          warehouses!inner(name)
        ''')
        .eq('company_id', companyId);

    if (warehouseId != null && warehouseId.trim().isNotEmpty) {
      query = query.eq('warehouse_id', warehouseId);
    }

    final response = await query;
    var rows = List<Map<String, dynamic>>.from(response);

    final querySearch = search?.trim().toLowerCase();
    if (querySearch != null && querySearch.isNotEmpty) {
      rows = rows.where((row) {
        final prod = row['products'] as Map<String, dynamic>? ?? {};
        final name = (prod['name'] as String? ?? '').toLowerCase();
        final sku = (prod['sku'] as String? ?? '').toLowerCase();
        final barcode = (prod['barcode'] as String? ?? '').toLowerCase();
        return name.contains(querySearch) ||
            sku.contains(querySearch) ||
            barcode.contains(querySearch);
      }).toList();
    }

    return rows;
  }

  // Stock movements posting (StockService logic)
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
    requireSession();
    // 1. Create movement record
    await _client.from('stock_movements').insert({
      'company_id': companyId,
      'product_id': productId,
      'warehouse_id': warehouseId,
      'movement_type': movementType,
      'quantity': quantity,
      'unit_cost': unitCost,
      'reference_type': referenceType,
      'reference_id': referenceId,
      'notes': notes,
    });

    // 2. Fetch current balance row
    final existingBalance = await _client
        .from('stock_balances')
        .select('id, quantity_on_hand')
        .eq('company_id', companyId)
        .eq('product_id', productId)
        .eq('warehouse_id', warehouseId)
        .maybeSingle();

    final delta = (movementType == 'out') ? -quantity.abs() : quantity;

    if (existingBalance == null) {
      await _client.from('stock_balances').insert({
        'company_id': companyId,
        'product_id': productId,
        'warehouse_id': warehouseId,
        'quantity_on_hand': delta,
        'quantity_allocated': 0,
      });
    } else {
      final currentQty =
          (existingBalance['quantity_on_hand'] as num?)?.toDouble() ?? 0.0;
      final newQty = currentQty + delta;
      await _client
          .from('stock_balances')
          .update({'quantity_on_hand': newQty})
          .eq('id', existingBalance['id']);
    }
  }

  String? _optional(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_providers.dart';
import '../application/inventory_failure.dart';
import '../application/product_models.dart';

final productServiceProvider = Provider<ProductService>((ref) {
  return ProductService(ref.watch(supabaseServiceProvider).client);
});

/// Low-level Data API adapter for products & categories.
/// Every query carries explicit company_id filtering; DB RLS acts as security perimeter.
final class ProductService {
  const ProductService(this._client);

  final SupabaseClient _client;

  static const productFields = '''
    id,
    company_id,
    category_id,
    name,
    sku,
    barcode,
    description,
    unit,
    unit_price,
    cost_price,
    track_inventory,
    is_active,
    created_by,
    created_at,
    updated_at,
    product_categories(name)
  ''';

  void requireSession() {
    if (_client.auth.currentUser == null) {
      throw const InventoryFailure('Please sign in to manage products.');
    }
  }

  Future<List<Map<String, dynamic>>> fetchProducts({
    required String companyId,
    required String search,
    String? categoryId,
    required bool includeInactive,
    required ProductCursor? cursor,
    required int limit,
  }) async {
    requireSession();
    final response = await _client.rpc(
      'search_products',
      params: {
        'p_company_id': companyId,
        'p_search': search.trim().isEmpty ? null : search.trim(),
        'p_category_id': categoryId,
        'p_include_inactive': includeInactive,
        'p_after_sort_name': cursor?.sortName,
        'p_after_id': cursor?.id,
        'p_limit': limit,
      },
    );

    if (response is! List) {
      throw const InventoryFailure(
        'The product list returned an unexpected response.',
      );
    }
    return response
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>?> fetchProduct({
    required String companyId,
    required String productId,
  }) async {
    requireSession();
    return _client
        .from('products')
        .select(productFields)
        .eq('company_id', companyId)
        .eq('id', productId)
        .maybeSingle();
  }

  Future<Map<String, dynamic>> insertProduct({
    required String companyId,
    required ProductInput input,
  }) async {
    requireSession();
    return _client
        .from('products')
        .insert({
          'company_id': companyId,
          ..._inputValues(input),
        })
        .select(productFields)
        .single();
  }

  Future<Map<String, dynamic>?> updateProduct({
    required String companyId,
    required String productId,
    required ProductInput input,
  }) async {
    requireSession();
    return _client
        .from('products')
        .update(_inputValues(input))
        .eq('company_id', companyId)
        .eq('id', productId)
        .select(productFields)
        .maybeSingle();
  }

  Future<Map<String, dynamic>?> updateProductActive({
    required String companyId,
    required String productId,
    required bool isActive,
  }) async {
    requireSession();
    return _client
        .from('products')
        .update({'is_active': isActive})
        .eq('company_id', companyId)
        .eq('id', productId)
        .select(productFields)
        .maybeSingle();
  }

  // Categories
  Future<List<Map<String, dynamic>>> fetchCategories({
    required String companyId,
  }) async {
    requireSession();
    final response = await _client
        .from('product_categories')
        .select()
        .eq('company_id', companyId)
        .eq('is_active', true)
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> insertCategory({
    required String companyId,
    required ProductCategoryInput input,
  }) async {
    requireSession();
    return _client
        .from('product_categories')
        .insert({
          'company_id': companyId,
          'name': input.name.trim(),
          'code': _optional(input.code),
          'description': _optional(input.description),
          'is_active': input.isActive,
        })
        .select()
        .single();
  }

  Map<String, Object?> _inputValues(ProductInput input) {
    return {
      'name': input.name.trim(),
      'category_id': input.categoryId,
      'sku': _optional(input.sku),
      'barcode': _optional(input.barcode),
      'description': _optional(input.description),
      'unit': input.unit.trim().isEmpty ? 'pcs' : input.unit.trim(),
      'unit_price': input.unitPrice,
      'cost_price': input.costPrice,
      'track_inventory': input.trackInventory,
      'is_active': input.isActive,
    };
  }

  String? _optional(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

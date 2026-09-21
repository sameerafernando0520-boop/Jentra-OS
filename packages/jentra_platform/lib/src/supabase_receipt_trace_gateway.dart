import 'package:jentra_domain/jentra_inventory.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class ReceiptTraceGateway {
  Future<Map<String, Object?>> page(TenantContext scope, {String? after});
  Future<Map<String, Object?>> detail(
    TenantContext scope,
    String id, {
    String? after,
  });
}

final class SupabaseReceiptTraceGateway implements ReceiptTraceGateway {
  SupabaseReceiptTraceGateway(this.client);
  final SupabaseClient client;

  Future<Map<String, Object?>> read(
    String name,
    TenantContext scope,
    Map<String, Object?> parameters,
  ) async {
    if (!scope.hasOperationalScope ||
        client.auth.currentUser?.id != scope.actorId) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Select your current authenticated entity and branch.',
      );
    }
    try {
      final response = await client
          .schema('api')
          .rpc(
            name,
            params: {
              'p_tenant_id': scope.tenantId,
              'p_legal_entity_id': scope.legalEntityId,
              'p_branch_id': scope.branchId,
              ...parameters,
            },
          );
      if (response is! Map ||
          response['items'] is! List ||
          (response['items'] as List).length > 50 ||
          (response['next_cursor'] != null &&
              response['next_cursor'] is! String)) {
        throw const FormatException('Invalid receipt trace response.');
      }
      final result = response.cast<String, Object?>();
      void quantity(Object? value) {
        if (value is! String ||
            !RegExp(r'^-?\d+(\.\d{1,6})?$').hasMatch(value)) {
          throw const FormatException(
            'Receipt quantities must be exact decimal strings.',
          );
        }
      }

      for (final item in result['items'] as List) {
        if (item is! Map) {
          throw const FormatException('Invalid receipt trace row.');
        }
        quantity(
          item[name == 'receipt_trace_page' ? 'received_quantity' : 'quantity'],
        );
        if (name == 'receipt_trace_page') {
          if (item['id'] is! String || item['covered'] is! bool) {
            throw const FormatException('Invalid receipt identity.');
          }
        } else if (item['sequence'] is! String ||
            !RegExp(r'^[1-9]\d*$').hasMatch(item['sequence'] as String)) {
          throw const FormatException('Invalid receipt history sequence.');
        }
      }
      if (name == 'receipt_trace_detail') {
        if (result['id'] != parameters['p_id'] ||
            result['covered'] is! bool ||
            result['holdings'] is! List) {
          throw const FormatException('Invalid receipt detail identity.');
        }
        quantity(result['received_quantity']);
        for (final key in [
          'held_quantity',
          'in_transit_quantity',
          'net_issued_quantity',
        ]) {
          if (result['covered'] == true) {
            quantity(result[key]);
          } else if (result[key] != null) {
            throw const FormatException(
              'Unknown coverage cannot report an attributed quantity.',
            );
          }
        }
        for (final holding in result['holdings'] as List) {
          if (holding is! Map) {
            throw const FormatException('Invalid receipt holding.');
          }
          quantity(holding['quantity']);
        }
      }
      return result;
    } on PostgrestException catch (e) {
      throw DomainError(
        code: e.code == '42501' ? 'PERMISSION_DENIED' : 'READ_FAILED',
        message: e.code == '42501'
            ? 'Receipt trace requires valuation and cost access in every affected branch.'
            : 'Receipt trace could not be loaded. Refresh to try again.',
      );
    }
  }

  @override
  Future<Map<String, Object?>> page(TenantContext scope, {String? after}) =>
      read('receipt_trace_page', scope, {'p_after': after});
  @override
  Future<Map<String, Object?>> detail(
    TenantContext scope,
    String id, {
    String? after,
  }) => read('receipt_trace_detail', scope, {'p_id': id, 'p_after': after});
}

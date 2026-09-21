import 'package:jentra_domain/jentra_inventory.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class InventoryValuationGateway {
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? after,
  });
  Future<Map<String, Object?>> generate(
    CommandEnvelope<Map<String, Object?>> command,
  );
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String id,
    String section, {
    String? after,
    String? evidenceKey,
  });
}

final class SupabaseInventoryValuationGateway
    implements InventoryValuationGateway {
  SupabaseInventoryValuationGateway(this.client);
  final SupabaseClient client;
  Future<Map<String, Object?>> call(
    String name,
    TenantContext scope,
    Map<String, Object?> params,
  ) async {
    if (!scope.hasOperationalScope ||
        client.auth.currentUser?.id != scope.actorId) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Select your authenticated entity and branch.',
      );
    }
    try {
      final r = await client
          .schema('api')
          .rpc(
            name,
            params: {
              'p_tenant_id': scope.tenantId,
              'p_legal_entity_id': scope.legalEntityId,
              'p_branch_id': scope.branchId,
              ...params,
            },
          );
      if (r is! Map) {
        throw const DomainError(
          code: 'UNCERTAIN_RESULT',
          message:
              'Report response could not be verified. Retry the saved request.',
        );
      }
      return r.cast<String, Object?>();
    } on PostgrestException catch (e) {
      final code = e.code == '42501'
          ? 'PERMISSION_DENIED'
          : e.code == '40001'
          ? 'VERSION_CONFLICT'
          : RegExp(r'^(22|23|54|55|P0)').hasMatch(e.code ?? '')
          ? 'VALIDATION_ERROR'
          : 'UNCERTAIN_RESULT';
      throw DomainError(
        code: code,
        message: code == 'PERMISSION_DENIED'
            ? 'Stock, cost and finance access are required in every entity branch.'
            : e.code == '54000'
            ? 'This report exceeds the supported size. No partial report was saved.'
            : code == 'UNCERTAIN_RESULT'
            ? 'Report outcome is uncertain. Retry the identical saved request.'
            : 'Check the date and selected inventory control accounts.',
      );
    }
  }

  void decimal(Object? value, {int scale = 6, bool nullable = false}) {
    if (value == null && nullable) return;
    if (value is! String ||
        !RegExp('^-?\\d+(\\.\\d{1,$scale})?\$').hasMatch(value)) {
      throw const FormatException(
        'Report values must be exact decimal strings.',
      );
    }
  }

  void summary(Map<String, Object?> r) {
    for (final k in [
      'id',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'as_of',
      'generated_at',
      'currency_code',
      'entity_name',
    ]) {
      if (r[k] is! String) {
        throw const FormatException('Report identity is incomplete.');
      }
    }
    for (final k in [
      'warehouse_value',
      'transit_value',
      'inventory_value',
      'gl_value',
      'difference',
    ]) {
      decimal(r[k]);
    }
    ExactDecimal d(String k) => ExactDecimal.parse(r[k] as String, scale: 6);
    if (d('warehouse_value') + d('transit_value') != d('inventory_value') ||
        d('inventory_value') - d('gl_value') != d('difference')) {
      throw const FormatException('Report totals do not reconcile.');
    }
    if (r['accounts'] is! List ||
        (r['accounts'] as List).isEmpty ||
        (r['accounts'] as List).length > 50 ||
        (r['accounts'] as List).any(
          (a) =>
              a is! Map ||
              a['id'] is! String ||
              a['code'] is! String ||
              a['name'] is! String,
        )) {
      throw const FormatException('Missing report account basis.');
    }
    if (r['status'] != 'generated' ||
        r['version'] != 1 ||
        r['stock_count'] is! int ||
        (r['stock_count'] as int) < 0 ||
        (r['stock_count'] as int) > 2000 ||
        r['difference_count'] is! int ||
        (r['difference_count'] as int) < 0 ||
        (r['difference_count'] as int) > 30000) {
      throw const FormatException(
        'Report counts or state could not be verified.',
      );
    }
  }

  void scopeIdentity(Map<String, Object?> r, TenantContext scope) {
    if (r['tenant_id'] != scope.tenantId ||
        r['legal_entity_id'] != scope.legalEntityId ||
        r['branch_id'] != scope.branchId) {
      throw const FormatException('Report scope does not match.');
    }
  }

  void rows(Map<String, Object?> r) {
    if (r['items'] is! List ||
        (r['items'] as List).length > 50 ||
        (r['items'] as List).any((x) => x is! Map || x['id'] is! String) ||
        (r['next_cursor'] != null && r['next_cursor'] is! String)) {
      throw const FormatException('Invalid bounded report page.');
    }
  }

  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? after,
  }) async {
    final r = await call('inventory_valuation_reports', scope, {
      'p_resource': resource,
      'p_after': after,
    });
    rows(r);
    if (resource == 'reports') {
      for (final x in r['items'] as List) {
        final s = (x as Map).cast<String, Object?>();
        summary(s);
        scopeIdentity(s, scope);
      }
    }
    return r;
  }

  @override
  Future<Map<String, Object?>> generate(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    final r =
        await call('generate_inventory_valuation_report', command.context, {
          'p_command_id': command.commandId,
          'p_idempotency_key': command.idempotencyKey,
          'p_client_timestamp': command.clientTimestamp.toIso8601String(),
          'p_expected_entity_version': command.expectedEntityVersion,
          'p_payload': command.payload,
        });
    try {
      if (r['command_id'] != command.commandId ||
          r['request_id'] is! String ||
          r['entity'] is! Map) {
        throw const FormatException();
      }
      final s = (r['entity'] as Map).cast<String, Object?>();
      summary(s);
      scopeIdentity(s, command.context);
      final ids = (s['accounts'] as List).map((x) => (x as Map)['id']).toSet();
      final expected = (command.payload['account_ids'] as List).toSet();
      if (s['id'] != command.payload['id'] ||
          s['as_of'] != command.payload['as_of'] ||
          s['status'] != 'generated' ||
          s['version'] != 1 ||
          ids.length != expected.length ||
          !ids.containsAll(expected)) {
        throw const FormatException();
      }
      return s;
    } on FormatException {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'Report confirmation could not be verified. Retry the saved request.',
      );
    }
  }

  @override
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String id,
    String section, {
    String? after,
    String? evidenceKey,
  }) async {
    final cursor = after == null ? 0 : int.tryParse(after);
    if (cursor == null || cursor < 0 || cursor > 30000) {
      throw const FormatException('Invalid report cursor.');
    }
    final r = await call('inventory_valuation_report_page', scope, {
      'p_id': id,
      'p_section': section,
      'p_after': cursor,
      'p_evidence_key': evidenceKey,
    });
    rows(r);
    if (r['summary'] is! Map ||
        r['section'] != section ||
        r['evidence_key'] != evidenceKey) {
      throw const FormatException('Report page identity does not match.');
    }
    final s = (r['summary'] as Map).cast<String, Object?>();
    summary(s);
    scopeIdentity(s, scope);
    if (s['id'] != id) {
      throw const FormatException('Report identity does not match.');
    }
    for (final x in r['items'] as List) {
      if (section == 'differences') {
        for (final k in ['inventory_value', 'gl_value', 'difference']) {
          decimal(x[k]);
        }
      } else {
        decimal(x['value'], nullable: section == 'lots');
        if (section != 'journals') decimal(x['quantity']);
      }
      if (section == 'stock') {
        decimal(x['average_cost'], scale: 12, nullable: true);
      }
    }
    return r;
  }
}

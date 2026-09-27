import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_control_reconciliation_gateway.dart';

abstract interface class FinancialDimensionGateway {
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String kind, {
    String? after,
    String search = '',
    bool activeOnly = true,
  });
  Future<Map<String, Object?>> save(
    CommandEnvelope<Map<String, Object?>> command,
  );
}

abstract final class FinancialDimensionEvidence {
  static void validate(
    Map row,
    TenantContext? scope, {
    bool entityOnly = false,
  }) {
    final snapshot = row['dimension_snapshot'];
    for (final kind in ['cost_centre', 'project']) {
      final id = row['${kind}_id'];
      if (id == null) {
        if (snapshot is Map && snapshot[kind] != null) {
          throw const FormatException(
            'Unassigned dimension contains a hidden basis.',
          );
        }
        continue;
      }
      final basis = snapshot is Map ? snapshot[kind] : null;
      if (id is! String ||
          id.isEmpty ||
          basis is! Map ||
          basis['id'] != id ||
          basis['kind'] != kind ||
          basis['version'] is! int ||
          (basis['version'] as int) < 1 ||
          basis['code'] is! String ||
          basis['name'] is! String ||
          scope != null &&
              (basis['tenant_id'] != scope.tenantId ||
                  basis['legal_entity_id'] != scope.legalEntityId ||
                  basis['branch_id'] != null &&
                      basis['branch_id'] != scope.branchId) ||
          entityOnly && basis['branch_id'] != null) {
        throw const FormatException(
          'Invalid frozen financial dimension basis.',
        );
      }
    }
  }

  static bool same(Object? a, Object? b) => a is Map && b is Map
      ? a.length == b.length &&
            a.keys.every((k) => b.containsKey(k) && same(a[k], b[k]))
      : a == b;
}

final class SupabaseFinancialDimensionGateway
    implements FinancialDimensionGateway {
  SupabaseFinancialDimensionGateway(SupabaseClient client)
    : transport = SupabaseControlReconciliationGateway(client);
  final SupabaseControlReconciliationGateway transport;
  static const kinds = {'cost_centre', 'project'};

  static void validate(Map row, TenantContext s, String kind) {
    if (row['id'] is! String ||
        row['tenant_id'] != s.tenantId ||
        row['legal_entity_id'] != s.legalEntityId ||
        row['kind'] != kind ||
        row['dimension_branch_id'] != null &&
            row['dimension_branch_id'] != s.branchId ||
        row['code'] is! String ||
        !RegExp(
          r'^[A-Z0-9][A-Z0-9._-]{0,39}$',
        ).hasMatch(row['code'] as String) ||
        row['name'] is! String ||
        (row['name'] as String).trim().length < 2 ||
        (row['name'] as String).length > 160 ||
        row['version'] is! int ||
        (row['version'] as int) < 1 ||
        !{'active', 'retired'}.contains(row['status'])) {
      throw const FormatException('Invalid scoped financial dimension.');
    }
  }

  @override
  Future<Map<String, Object?>> page(
    TenantContext s,
    String kind, {
    String? after,
    String search = '',
    bool activeOnly = true,
  }) async {
    if (!kinds.contains(kind) || search.length > 100) {
      throw const FormatException('Invalid dimension query.');
    }
    final r = await transport.call('financial_dimensions', s, {
      'p_kind': kind,
      'p_after': after,
      'p_search': search,
      'p_active_only': activeOnly,
    });
    if (r['tenant_id'] != s.tenantId ||
        r['legal_entity_id'] != s.legalEntityId ||
        r['branch_id'] != s.branchId ||
        r['kind'] != kind) {
      throw const FormatException('Dimension query scope mismatch.');
    }
    transport.rows(r);
    final ids = <String>{};
    for (final raw in r['items'] as List) {
      if (raw is! Map) throw const FormatException('Invalid dimension row.');
      validate(raw, s, kind);
      if (after != null && (raw['id'] as String).compareTo(after) <= 0) {
        throw const FormatException('Dimension page did not advance.');
      }
      if (!ids.add(raw['id'] as String) ||
          activeOnly && raw['status'] != 'active') {
        throw const FormatException('Duplicate or retired dimension choice.');
      }
    }
    if (r['next_cursor'] != null &&
        ((r['items'] as List).length != 50 ||
            (r['items'] as List).last['id'] != r['next_cursor'])) {
      throw const FormatException('Invalid dimension continuation.');
    }
    return r;
  }

  @override
  Future<Map<String, Object?>> save(CommandEnvelope<Map<String, Object?>> c) =>
      transport.command('financial_dimension_command', c, (r) {
        validate(r, c.context, c.payload['kind'] as String);
        if (r['branch_id'] != c.context.branchId ||
            r['id'] != c.payload['id'] ||
            r['dimension_branch_id'] != c.payload['dimension_branch_id'] ||
            r['version'] != (c.expectedEntityVersion ?? 0) + 1 ||
            r['code'] != c.payload['code'] ||
            r['name'] != (c.payload['name'] as String).trim() ||
            r['status'] != c.payload['status'] ||
            r['reason'] != (c.payload['reason'] as String).trim()) {
          throw const FormatException(
            'Dimension confirmation changed the sealed request.',
          );
        }
      });
}

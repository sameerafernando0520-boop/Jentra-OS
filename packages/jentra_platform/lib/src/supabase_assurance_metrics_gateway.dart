import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_assurance_gateway.dart';

/// Process metrics for a period (A11 candidate API `api.assurance_metrics`).
abstract interface class AssuranceMetricsGateway {
  Future<AssuranceMetrics> metrics(
    TenantContext scope,
    DateTime from,
    DateTime to,
  );
}

final class SupabaseAssuranceMetricsGateway implements AssuranceMetricsGateway {
  SupabaseAssuranceMetricsGateway(this.client);
  final SupabaseClient client;

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Future<AssuranceMetrics> metrics(
    TenantContext s,
    DateTime from,
    DateTime to,
  ) async {
    final start = DateTime.utc(from.year, from.month, from.day);
    final end = DateTime.utc(to.year, to.month, to.day);
    if (end.isBefore(start) || end.difference(start).inDays > 366) {
      throw const FormatException('Choose a period of at most a year.');
    }
    if (!s.hasOperationalScope || client.auth.currentUser?.id != s.actorId) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Select your authenticated entity and branch.',
      );
    }
    final Object? r;
    try {
      r = await client
          .schema('api')
          .rpc(
            'assurance_metrics',
            params: {
              'p_tenant_id': s.tenantId,
              'p_legal_entity_id': s.legalEntityId,
              'p_branch_id': s.branchId,
              'p_from': _day(start),
              'p_to': _day(end),
            },
          );
    } on PostgrestException catch (e) {
      throw SupabaseAssuranceGateway.assuranceDenial(e);
    }
    if (r is! Map) throw const FormatException('Invalid metrics response.');
    final m = AssuranceMetrics.fromJson(r.cast<String, Object?>());
    if (m.from != start || m.to != end) {
      throw const FormatException('Metrics are for a different period.');
    }
    return m;
  }
}

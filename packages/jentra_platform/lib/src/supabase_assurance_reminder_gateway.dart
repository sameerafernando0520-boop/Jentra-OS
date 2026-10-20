import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_assurance_gateway.dart';

/// Reminder delivery (A10 candidate API): one page of the scope's due work
/// becomes in-app notices; repeating a scan is harmless.
abstract interface class AssuranceReminderGateway {
  Future<ReminderScan> scan(
    TenantContext scope,
    String idempotencyKey, {
    String? after,
  });
}

final class SupabaseAssuranceReminderGateway
    implements AssuranceReminderGateway {
  SupabaseAssuranceReminderGateway(this.client);
  final SupabaseClient client;

  @override
  Future<ReminderScan> scan(
    TenantContext s,
    String idempotencyKey, {
    String? after,
  }) async {
    if (!s.hasOperationalScope || client.auth.currentUser?.id != s.actorId) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Select your authenticated entity and branch.',
      );
    }
    assuranceId(idempotencyKey);
    if (after != null) assuranceId(after);
    try {
      final r = await client
          .schema('api')
          .rpc(
            'assurance_scan_reminders',
            params: {
              'p_tenant_id': s.tenantId,
              'p_legal_entity_id': s.legalEntityId,
              'p_branch_id': s.branchId,
              'p_idempotency_key': idempotencyKey,
              'p_payload': {'after_id': after},
            },
          );
      if (r is! Map) throw const FormatException('Invalid scan response.');
      return assuranceReminderScanFromJson(r.cast<String, Object?>());
    } on PostgrestException catch (e) {
      throw SupabaseAssuranceGateway.assuranceDenial(e);
    }
  }
}

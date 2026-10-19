import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_assurance_gateway.dart';

/// Who holds which assurance role, and the grant/revoke command.
abstract interface class AssuranceAccessGateway {
  /// One page of members (`api.assurance_access`, candidate API).
  Future<AssuranceAccess> access(TenantContext scope, {String? after});

  /// One `api.assurance_set_role`, versioned against the membership; the
  /// receipt must confirm the same change one version later.
  Future<Map<String, Object?>> setRole(
    CommandEnvelope<Map<String, Object?>> command,
  );
}

final class SupabaseAssuranceAccessGateway implements AssuranceAccessGateway {
  SupabaseAssuranceAccessGateway(this.client);
  final SupabaseClient client;

  Future<Object?> _call(
    String rpc,
    TenantContext s,
    Map<String, Object?> p,
  ) async {
    if (!s.hasOperationalScope || client.auth.currentUser?.id != s.actorId) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Select your authenticated entity and branch.',
      );
    }
    try {
      return await client
          .schema('api')
          .rpc(
            rpc,
            params: {
              'p_tenant_id': s.tenantId,
              'p_legal_entity_id': s.legalEntityId,
              'p_branch_id': s.branchId,
              ...p,
            },
          );
    } on PostgrestException catch (e) {
      throw SupabaseAssuranceGateway.assuranceDenial(e);
    }
  }

  @override
  Future<AssuranceAccess> access(TenantContext s, {String? after}) async {
    if (after != null) assuranceId(after);
    final r = await _call('assurance_access', s, {'p_after': after});
    if (r is! Map) throw const FormatException('Invalid access response.');
    return AssuranceAccess.fromJson(r.cast<String, Object?>());
  }

  @override
  Future<Map<String, Object?>> setRole(
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    final p = c.payload, version = c.expectedEntityVersion;
    if (version == null) {
      throw const FormatException('Access changes are versioned.');
    }
    AssuranceAccessCommands.validate(p);
    final r = await _call('assurance_set_role', c.context, {
      'p_idempotency_key': c.idempotencyKey,
      'p_payload': p,
      'p_expected_version': version,
    });
    if (r is! Map || !assuranceAccessReceiptConfirms(r.cast(), p, version)) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Confirmation could not be verified. Retry the saved request.',
      );
    }
    return r.cast<String, Object?>();
  }
}

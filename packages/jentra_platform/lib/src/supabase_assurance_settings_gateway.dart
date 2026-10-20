import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_assurance_gateway.dart';

/// Tenant assurance settings (A9 candidate APIs).
abstract interface class AssuranceSettingsGateway {
  Future<AssuranceSettingsPage> settings(TenantContext scope);

  /// One `api.assurance_settings_command`, versioned against the row at the
  /// payload's level (0 creates it); the receipt must confirm one version on.
  Future<Map<String, Object?>> saveSettings(
    CommandEnvelope<Map<String, Object?>> command,
  );
}

final class SupabaseAssuranceSettingsGateway
    implements AssuranceSettingsGateway {
  SupabaseAssuranceSettingsGateway(this.client);
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
  Future<AssuranceSettingsPage> settings(TenantContext s) async {
    final r = await _call('assurance_settings', s, const {});
    if (r is! Map) throw const FormatException('Invalid settings response.');
    return AssuranceSettingsPage.fromJson(r.cast<String, Object?>());
  }

  @override
  Future<Map<String, Object?>> saveSettings(
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    final p = c.payload, version = c.expectedEntityVersion;
    if (version == null) {
      throw const FormatException('Settings changes are versioned.');
    }
    AssuranceSettingsCommands.validate(p);
    final r = await _call('assurance_settings_command', c.context, {
      'p_idempotency_key': c.idempotencyKey,
      'p_payload': p,
      'p_expected_version': version,
    });
    if (r is! Map ||
        !assuranceSettingsReceiptConfirms(
          r.cast(),
          p['level']! as String,
          version,
        )) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Confirmation could not be verified. Retry the saved request.',
      );
    }
    return r.cast<String, Object?>();
  }
}

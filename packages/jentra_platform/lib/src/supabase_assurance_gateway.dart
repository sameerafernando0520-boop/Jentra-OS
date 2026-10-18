import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'assurance_pack_verifier.dart';

/// Governance & Audit workspace reads, the finding-owner response and the
/// auditor commands offered on an engagement.
abstract interface class AssuranceGateway {
  Future<AssuranceOverview> overview(TenantContext scope);
  Future<AssuranceEngagementPage> engagements(
    TenantContext scope, {
    String? after,
  });

  /// Raw detail validated by [EngagementDetail]; titles are read from it.
  Future<Map<String, Object?>> engagement(TenantContext scope, String id);
  Future<Map<String, Object?>> respond(
    CommandEnvelope<Map<String, Object?>> command,
  );

  /// One [AuditorAction], versioned against the engagement; the receipt must
  /// confirm the same aggregate one version later.
  Future<Map<String, Object?>> auditorCommand(
    CommandEnvelope<Map<String, Object?>> command,
  );

  /// Reads an export and hashes the exact manifest bytes.
  Future<AuditPackVerification> auditPack(TenantContext scope, String exportId);
}

final class SupabaseAssuranceGateway implements AssuranceGateway {
  SupabaseAssuranceGateway(this.client);
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
      throw assuranceDenial(e);
    }
  }

  /// Maps server error codes to the client contract. Only codes the server
  /// raises before committing are reported as definite.
  static DomainError assuranceDenial(PostgrestException e) {
    final message = e.message;
    final code = switch (e.code) {
      '42501' when message.contains('MFA') => 'MFA_REQUIRED',
      // Independence and team rules refuse one action, not workspace access.
      '42501' when _segregation.containsKey(message) =>
        'SEGREGATION_OF_DUTIES_VIOLATION',
      '42501' => 'PERMISSION_DENIED',
      '40001' => 'VERSION_CONFLICT',
      'P0002' => 'NOT_FOUND',
      '22023' || '23505' || '55000' => 'VALIDATION_ERROR',
      _ => 'UNCERTAIN_RESULT',
    };
    return DomainError(
      code: code,
      message: switch (code) {
        'MFA_REQUIRED' =>
          'Complete recent MFA in account security, then retry the saved request.',
        'SEGREGATION_OF_DUTIES_VIOLATION' => _segregation[message]!,
        'PERMISSION_DENIED' =>
          'Audit access is required in this entity and branch.',
        'VERSION_CONFLICT' =>
          'The engagement changed. Refresh it before responding again.',
        'NOT_FOUND' => 'The engagement or finding is no longer available here.',
        'VALIDATION_ERROR' => _validation(message),
        _ => 'The outcome is uncertain. Retry the identical saved request.',
      },
    );
  }

  static const _segregation = {
    'ASSURANCE_INDEPENDENT_REVIEW_REQUIRED':
        'Someone other than the person who recorded this exception must decide it.',
    'ASSURANCE_SELF_REVIEW_FORBIDDEN':
        'Someone other than the collector must review this evidence.',
    'ASSURANCE_INDEPENDENCE_REQUIRED':
        'The owner must be independent of the audit team.',
    'ASSURANCE_TEAM_MEMBER_REQUIRED':
        'Only this engagement\'s audit team can do this.',
    'ASSURANCE_EXTERNAL_READ_ONLY': 'External reviewers have read-only access.',
  };

  static String _validation(String m) => switch (m) {
    'ASSURANCE_TRANSITION_INVALID' =>
      'This item has changed state. Refresh the engagement.',
    'ASSURANCE_ENGAGEMENT_CLOSED' => 'The engagement is closed.',
    'ASSURANCE_EVIDENCE_FROZEN' =>
      'Evidence is frozen or the engagement is not in fieldwork.',
    'ASSURANCE_REPORT_NOT_ISSUED' => 'No issued report can be exported yet.',
    'ASSURANCE_REPORT_SUPERSEDED' =>
      'A newer report version exists. Refresh and export that one.',
    'ASSURANCE_MEMBER_REQUIRED' =>
      'The owner must be an active member of this organisation.',
    'IDEMPOTENCY_MISMATCH' =>
      'A different request already used this key. Start a new request.',
    _ => 'Check the entered details and try again.',
  };

  Map<String, Object?> _map(Object? r, String what) => r is Map
      ? r.cast<String, Object?>()
      : throw FormatException('Invalid $what response.');

  @override
  Future<AssuranceOverview> overview(TenantContext s) async =>
      AssuranceOverview.fromJson(
        _map(await _call('assurance_overview', s, const {}), 'work queue'),
        s.actorId,
      );

  @override
  Future<AssuranceEngagementPage> engagements(
    TenantContext s, {
    String? after,
  }) async {
    if (after != null) assuranceId(after);
    return AssuranceEngagementPage.fromJson(
      _map(
        await _call('assurance_engagements', s, {'p_after': after}),
        'engagement register',
      ),
    );
  }

  @override
  Future<Map<String, Object?>> engagement(TenantContext s, String id) async {
    assuranceId(id);
    final r = _map(
      await _call('assurance_engagement', s, {'p_engagement_id': id}),
      'engagement',
    );
    if (EngagementDetail.fromJson(r).id != id) {
      throw const FormatException('Engagement identity does not match.');
    }
    return r;
  }

  @override
  Future<Map<String, Object?>> respond(
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    final p = c.payload;
    if (p['action'] != 'respond' || c.expectedEntityVersion == null) {
      throw const FormatException('Only a versioned response is supported.');
    }
    AssuranceCommands.validate(
      'respond',
      p,
      now: c.clientTimestamp,
      tenantId: c.context.tenantId,
    );
    final r = await _call('assurance_command', c.context, {
      'p_idempotency_key': c.idempotencyKey,
      'p_payload': p,
      'p_expected_version': c.expectedEntityVersion,
    });
    if (r is! Map ||
        r['action'] != 'respond' ||
        r['engagement_id'] != p['engagement_id'] ||
        r['aggregate_type'] != 'finding' ||
        r['aggregate_id'] != p['finding_id'] ||
        r['version'] != c.expectedEntityVersion! + 1 ||
        r['to_status'] !=
            ((p['accept_risk'] as bool) ? 'risk_pending' : 'remediating')) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Confirmation could not be verified. Retry the saved request.',
      );
    }
    return r.cast<String, Object?>();
  }

  @override
  Future<Map<String, Object?>> auditorCommand(
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    final p = c.payload, version = c.expectedEntityVersion;
    final action = AuditorAction.of(p['action'] as String? ?? '');
    if (version == null) {
      throw const FormatException('Auditor commands are versioned.');
    }
    action.validate(p, now: c.clientTimestamp, tenantId: c.context.tenantId);
    final r = await _call(action.rpc.function, c.context, {
      'p_idempotency_key': c.idempotencyKey,
      'p_payload': p,
      'p_expected_version': version,
    });
    if (r is! Map || !action.confirms(r.cast(), p, version)) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Confirmation could not be verified. Retry the saved request.',
      );
    }
    return r.cast<String, Object?>();
  }

  @override
  Future<AuditPackVerification> auditPack(
    TenantContext s,
    String exportId,
  ) async {
    assuranceId(exportId);
    final v = await AssurancePackVerifier.verify(
      _map(
        await _call('assurance_export_manifest', s, {'p_export_id': exportId}),
        'audit pack',
      ),
    );
    if (v.pack.exportId != exportId) {
      throw const FormatException('Audit pack identity does not match.');
    }
    return v;
  }
}

import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Governance & Audit workspace reads and the finding-owner response command.
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

  static String _validation(String m) => switch (m) {
    'ASSURANCE_TRANSITION_INVALID' =>
      'This finding no longer accepts a response.',
    'ASSURANCE_ENGAGEMENT_CLOSED' => 'The engagement is closed.',
    'IDEMPOTENCY_MISMATCH' =>
      'A different request already used this key. Start a new response.',
    _ => 'Check the response, due date and risk acceptance choice.',
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
}

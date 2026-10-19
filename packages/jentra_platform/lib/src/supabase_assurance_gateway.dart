import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
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

  /// Test procedures and runs for an engagement (`api.assurance_tests`).
  Future<List<Object?>> tests(TenantContext scope, String engagementId);
  Future<Map<String, Object?>> respond(
    CommandEnvelope<Map<String, Object?>> command,
  );

  /// One [AuditorAction], versioned against the engagement; the receipt must
  /// confirm the same aggregate one version later.
  Future<Map<String, Object?>> auditorCommand(
    CommandEnvelope<Map<String, Object?>> command,
  );

  /// The audit universe and templates in scope (`api.assurance_universe`).
  Future<AssuranceUniverse> universe(TenantContext scope);

  /// The audit plan register (`api.assurance_plans`, candidate API).
  Future<AssurancePlanPage> plans(TenantContext scope, {String? after});
  Future<AssurancePlanDetail> plan(TenantContext scope, String planId);

  /// One `api.assurance_plan_command`, versioned against its aggregate (0 for
  /// creation); the receipt must confirm the same aggregate one version later.
  Future<Map<String, Object?>> planCommand(
    CommandEnvelope<Map<String, Object?>> command,
  );

  /// Reads an export and hashes the exact manifest bytes.
  Future<AuditPackVerification> auditPack(TenantContext scope, String exportId);

  /// The request owner's manual evidence: records the sealed `submit_evidence`
  /// command, uploads [bytes] to its generated path and asks the server to
  /// hash what was stored. Every step is safe to retry with the same command
  /// and file.
  Future<StoredEvidenceVerification> submitManualEvidence(
    CommandEnvelope<Map<String, Object?>> command,
    Uint8List bytes,
    String mime,
  );

  /// Asks the server to hash the stored object (owner or audit team).
  Future<StoredEvidenceVerification> verifyEvidence(
    TenantContext scope,
    String engagementId,
    String evidenceId,
  );

  /// Whether an evidence item needs bytes, has them and is verified.
  Future<EvidenceVerificationStatus> evidenceVerification(
    TenantContext scope,
    String engagementId,
    String evidenceId,
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
        'NOT_FOUND' when message == 'ASSURANCE_ASSIGNMENT_NOT_FOUND' =>
          'That role is no longer assigned. Refresh access.',
        'NOT_FOUND' when message == 'ASSURANCE_MEMBER_NOT_FOUND' =>
          'That person is no longer an active member. Refresh access.',
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
    'ASSURANCE_INDEPENDENT_APPROVAL_REQUIRED':
        'Someone other than the maker or submitter must decide this.',
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
    'ASSURANCE_EVIDENCE_UNVERIFIED' =>
      'The stored file has not been verified against its digest. Verify it, or reject the submission.',
    'ASSURANCE_MEMBER_REQUIRED' =>
      'The owner must be an active member of this organisation.',
    'ASSURANCE_RISK_ASSESSMENT_REQUIRED' =>
      'Assess the area\'s risk before planning it.',
    'ASSURANCE_PLAN_EMPTY' => 'Add at least one area before submitting.',
    'ASSURANCE_PLAN_NOT_APPROVED' =>
      'Engagements come only from approved plans.',
    'ASSURANCE_ITEM_IN_OPEN_PLAN' =>
      'This area is in an open plan and cannot be retired yet.',
    'ASSURANCE_ITEM_RETIRED' => 'This area has been retired.',
    'ASSURANCE_PLAN_ITEM_EXISTS' => 'This area is already in the plan.',
    'ASSURANCE_OCCURRENCE_EXISTS' =>
      'That occurrence already has an engagement. Refresh the plan.',
    'ASSURANCE_ROLE_UNKNOWN' => 'Only assurance roles can be given here.',
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
  Future<List<Object?>> tests(TenantContext s, String engagementId) async {
    assuranceId(engagementId);
    final r = await _call('assurance_tests', s, {
      'p_engagement_id': engagementId,
    });
    return r is List
        ? r
        : throw const FormatException('Invalid tests response.');
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
  Future<AssuranceUniverse> universe(TenantContext s) async =>
      AssuranceUniverse.fromJson(
        _map(await _call('assurance_universe', s, const {}), 'universe'),
      );

  @override
  Future<AssurancePlanPage> plans(TenantContext s, {String? after}) async {
    if (after != null) assuranceId(after);
    return AssurancePlanPage.fromJson(
      _map(
        await _call('assurance_plans', s, {'p_after': after}),
        'plan register',
      ),
    );
  }

  @override
  Future<AssurancePlanDetail> plan(TenantContext s, String planId) async {
    assuranceId(planId);
    final d = AssurancePlanDetail.fromJson(
      _map(await _call('assurance_plan', s, {'p_plan_id': planId}), 'plan'),
    );
    if (d.id != planId) {
      throw const FormatException('Plan identity does not match.');
    }
    return d;
  }

  @override
  Future<Map<String, Object?>> planCommand(
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    final p = c.payload, version = c.expectedEntityVersion;
    final action = p['action'] as String? ?? '';
    if (version == null) {
      throw const FormatException('Plan commands are versioned.');
    }
    AssurancePlanCommands.validate(action, p);
    if (AssurancePlanCommands.creates(action) != (version == 0)) {
      throw const FormatException('Creation uses version 0, changes do not.');
    }
    final r = await _call('assurance_plan_command', c.context, {
      'p_idempotency_key': c.idempotencyKey,
      'p_payload': p,
      'p_expected_version': version,
    });
    if (r is! Map || !assurancePlanReceiptConfirms(r.cast(), p, version)) {
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

  static String _hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  @override
  Future<StoredEvidenceVerification> submitManualEvidence(
    CommandEnvelope<Map<String, Object?>> c,
    Uint8List bytes,
    String mime,
  ) async {
    final p = c.payload, version = c.expectedEntityVersion;
    if (p['action'] != 'submit_evidence' ||
        p['collection_method'] != 'manual' ||
        version == null ||
        !assuranceEvidenceMimeTypes.containsValue(mime)) {
      throw const FormatException('Only versioned manual evidence uploads.');
    }
    final m = EvidenceMetadata.fromCommand(
      p,
      tenantId: c.context.tenantId,
      engagementId: assuranceId(p['engagement_id']),
      now: c.clientTimestamp,
    );
    final frozen = Uint8List.fromList(bytes);
    if (frozen.length != m.byteSize ||
        _hex((await Sha256().hash(frozen)).bytes) != m.sha256) {
      throw const FormatException(
        'Choose the exact file this saved submission was prepared for.',
      );
    }
    // A replay of the same key returns the original receipt, so a retry after
    // a lost response or a failed upload continues from here.
    final r = await _call('assurance_command', c.context, {
      'p_idempotency_key': c.idempotencyKey,
      'p_payload': p,
      'p_expected_version': version,
    });
    if (r is! Map ||
        r['action'] != 'submit_evidence' ||
        r['engagement_id'] != p['engagement_id'] ||
        r['aggregate_type'] != 'evidence_request' ||
        r['aggregate_id'] != p['request_id'] ||
        r['version'] != version + 1 ||
        r['to_status'] != 'submitted') {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Confirmation could not be verified. Retry the saved request.',
      );
    }
    try {
      await client.storage
          .from(assuranceEvidenceBucket)
          .uploadBinary(
            m.storageRef,
            frozen,
            fileOptions: FileOptions(upsert: false, contentType: mime),
          );
    } on StorageException catch (e) {
      // Only an existing object permits continuing; the server then hashes
      // whatever is stored, so a different earlier upload is a mismatch.
      if (!{'409', 'Duplicate'}.contains(e.statusCode) &&
          !{'Duplicate', 'ResourceAlreadyExists'}.contains(e.error)) {
        final denied = e.statusCode == '403';
        throw DomainError(
          code: denied ? 'PERMISSION_DENIED' : 'UNCERTAIN_RESULT',
          message: denied
              ? 'Only the request owner can upload while the evidence is open.'
              : 'The file did not finish uploading. Retry the saved submission.',
        );
      }
    }
    final v = await verifyEvidence(
      c.context,
      p['engagement_id']! as String,
      m.id,
    );
    if (v.verified && !v.confirms(sha256: m.sha256, byteSize: m.byteSize)) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'Verification could not be confirmed. Retry the saved request.',
      );
    }
    return v;
  }

  @override
  Future<StoredEvidenceVerification> verifyEvidence(
    TenantContext s,
    String engagementId,
    String evidenceId,
  ) async {
    assuranceId(engagementId);
    assuranceId(evidenceId);
    if (!s.hasOperationalScope || client.auth.currentUser?.id != s.actorId) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Select your authenticated entity and branch.',
      );
    }
    final Object? data;
    try {
      data = (await client.functions.invoke(
        assuranceEvidenceVerifyFunction,
        body: {
          'tenant_id': s.tenantId,
          'legal_entity_id': s.legalEntityId,
          'branch_id': s.branchId,
          'engagement_id': engagementId,
          'evidence_id': evidenceId,
        },
      )).data;
    } on FunctionException catch (e) {
      final safe = e.details is Map ? (e.details as Map)['code'] : null;
      throw switch ((e.status, safe)) {
        (401 || 403, _) => const DomainError(
          code: 'PERMISSION_DENIED',
          message:
              'Only the request owner or the audit team can verify this file.',
        ),
        (409, 'ASSURANCE_EVIDENCE_OBJECT_MISSING') => const DomainError(
          code: 'VALIDATION_ERROR',
          message: 'No file is stored for this evidence yet. Upload it first.',
        ),
        (404, _) => const DomainError(
          code: 'NOT_FOUND',
          message: 'The evidence is no longer available here.',
        ),
        _ => const DomainError(
          code: 'UNCERTAIN_RESULT',
          message: 'Verification did not complete. Retry it.',
        ),
      };
    }
    return StoredEvidenceVerification.fromJson(
      _map(data, 'evidence verification'),
      evidenceId: evidenceId,
    );
  }

  @override
  Future<EvidenceVerificationStatus> evidenceVerification(
    TenantContext s,
    String engagementId,
    String evidenceId,
  ) async {
    assuranceId(engagementId);
    assuranceId(evidenceId);
    final v = EvidenceVerificationStatus.fromJson(
      _map(
        await _call('assurance_evidence_verification', s, {
          'p_engagement_id': engagementId,
          'p_evidence_id': evidenceId,
        }),
        'evidence verification',
      ),
    );
    if (v.engagementId != engagementId || v.evidenceId != evidenceId) {
      throw const FormatException('Evidence verification identity mismatch.');
    }
    return v;
  }
}

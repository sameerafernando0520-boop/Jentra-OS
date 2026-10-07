import 'dart:convert';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/intelligence_control.dart';
import 'package:jentra_domain/jentra_domain.dart' show DomainError;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'process_metric_gateway.dart';
import 'process_metric_hasher.dart';

final class VerifiedHumanProposal {
  const VerifiedHumanProposal(this.revision, this.state);
  final AiProposalRevision revision;
  final String state;
  static Future<VerifiedHumanProposal> verify(
    Map<String, Object?> raw,
    ProcessMetricScope scope,
  ) async {
    const fields = {
      'id',
      'revision',
      'state',
      'parametersHash',
      'canonicalText',
      'explanationCode',
      'resourceBudget',
      'origin',
      'modelProvider',
    };
    if (raw.length != fields.length ||
        !raw.keys.toSet().containsAll(fields) ||
        raw['revision'] != '1' ||
        raw['origin'] != 'human' ||
        raw['modelProvider'] != 'unavailable' ||
        raw['explanationCode'] != 'freeze_current_pipeline_for_review' ||
        !{
          'proposed',
          'approved',
          'rejected',
          'expired',
          'executed',
        }.contains(raw['state']) ||
        raw['canonicalText'] is! String ||
        raw['parametersHash'] is! String ||
        raw['resourceBudget'] is! Map<String, Object?>) {
      throw const FormatException('Invalid proposal projection.');
    }
    final bytes = utf8.encode(raw['canonicalText'] as String),
        hasher = ProcessMetricSha256Hasher();
    if (bytes.length > 8388608 ||
        await hasher.sha256(bytes) != raw['parametersHash']) {
      throw const FormatException('Proposal digest mismatch.');
    }
    final c = jsonDecode(raw['canonicalText'] as String);
    if (c is! Map<String, Object?> ||
        c['policyVersion'] != 1 ||
        c['revision'] != 1 ||
        c['commandCode'] != AiProposalRevision.commandCode ||
        c['scope'] is! Map<String, Object?> ||
        c['targets'] is! Map<String, Object?> ||
        c['estimatedUnits'] != '0') {
      throw const FormatException('Unsupported proposal policy.');
    }
    final s = c['scope'] as Map<String, Object?>;
    if (s.length != 3 ||
        s['tenantId'] != scope.tenantId ||
        s['legalEntityId'] != scope.legalEntityId ||
        s['branchId'] != scope.branchId ||
        c['id'] != raw['id']) {
      throw const FormatException('Proposal scope mismatch.');
    }
    final targets = (c['targets'] as Map<String, Object?>).map((k, v) {
      if (v is! String) throw const FormatException('Invalid source revision.');
      return MapEntry(k, v);
    });
    final p = AiProposalRevision(
      id: c['id'] as String,
      proposerId: c['proposerId'] as String,
      commandId: c['commandId'] as String,
      evidence: RedactedForecastEvidence(
        scope: scope,
        sourceId: c['sourceId'] as String,
        sourceHash: c['sourceHash'] as String,
        targetVersions: targets,
      ),
      createdAt: c['createdAt'] as String,
      expiresAt: c['expiresAt'] as String,
      horizonStart: c['horizonStart'] as String,
      horizonEnd: c['horizonEnd'] as String,
      estimatedUnits: BigInt.zero,
      parametersHash: raw['parametersHash'] as String,
      revision: 1,
    );
    await p.verifyHash(
      hasher,
    ); // Independently reconstruct the published canonical bytes.
    final budget = raw['resourceBudget'] as Map<String, Object?>;
    if (budget.length != 3 ||
        budget['modelUnits'] != '0' ||
        budget['commands'] != '1' ||
        budget['sourceRows'] != targets.length.toString()) {
      throw const FormatException('Proposal resource budget mismatch.');
    }
    return VerifiedHumanProposal(p, raw['state'] as String);
  }
}

abstract interface class Wave5ControlRepository {
  Future<void> authorizeProposalRecovery(
    ProcessMetricScope scope,
    String actor,
  );
  Future<VerifiedHumanProposal> proposal(ProcessMetricScope scope, String id);
  Future<String> command(
    ProcessMetricScope scope,
    Map<String, Object?> envelope,
  );
  Future<Map<String, Object?>> usage(
    String tenant,
    String metric,
    String periodStart,
  );
  Future<Map<String, Object?>> health({String? tenant, String? grant});
  Future<void> authorizeSubscriptionRecovery(
    ProcessMetricScope scope,
    String actor,
  );
  Future<Map<String, Object?>> subscription(String tenant);
  Future<String> scheduleSubscription(
    ProcessMetricScope scope,
    Map<String, Object?> envelope,
  );
}

final class SupabaseWave5ControlGateway implements Wave5ControlRepository {
  SupabaseWave5ControlGateway(SupabaseClient client)
    : rpc = ((name, params) => client.schema('api').rpc(name, params: params));
  SupabaseWave5ControlGateway.injected(this.rpc);
  final ProcessMetricRpc rpc;
  Map<String, Object?> _scope(ProcessMetricScope s) => {
    'p_tenant_id': s.tenantId,
    'p_legal_entity_id': s.legalEntityId,
    'p_branch_id': s.branchId,
  };
  Future<Object?> _call(String name, Map<String, Object?> p) async {
    try {
      return await rpc(name, p);
    } on PostgrestException catch (e) {
      final code = e.code == '42501'
          ? 'PERMISSION_DENIED'
          : e.code == '40001'
          ? 'CONFLICT'
          : 'PROVIDER_UNAVAILABLE';
      throw DomainError(
        code: code,
        message: switch (code) {
          'PERMISSION_DENIED' =>
            'Current permissions, MFA or entitlement do not permit this control action.',
          'CONFLICT' =>
            'The source or decision changed. Read the current revision before continuing.',
          _ =>
            'The control provider is unavailable. The original request can be reviewed and retried.',
        },
        retryable: code == 'PROVIDER_UNAVAILABLE',
      );
    } catch (_) {
      throw const DomainError(
        code: 'OUTCOME_UNKNOWN',
        message:
            'The control request could not be confirmed. Review its original identity before retrying.',
        retryable: true,
      );
    }
  }

  @override
  Future<void> authorizeProposalRecovery(
    ProcessMetricScope scope,
    String actor,
  ) async {
    if (await _call('wave5_proposal_authorize', _scope(scope)) != actor) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Saved control requests belong to another signed-in actor.',
      );
    }
  }

  @override
  Future<VerifiedHumanProposal> proposal(
    ProcessMetricScope scope,
    String id,
  ) async {
    final raw = await _call('get_wave5_proposal', {
      ..._scope(scope),
      'p_proposal_id': id,
    });
    if (raw is! Map<String, Object?>) {
      throw const FormatException('Invalid proposal response.');
    }
    return VerifiedHumanProposal.verify(raw, scope);
  }

  @override
  Future<String> command(
    ProcessMetricScope scope,
    Map<String, Object?> e,
  ) async {
    final raw = await _call('wave5_proposal_command', {
      ..._scope(scope),
      'p_command_id': e['commandId'],
      'p_idempotency_key': e['idempotencyKey'],
      'p_client_timestamp': e['clientTimestamp'],
      'p_action': e['action'],
      'p_payload': e['payload'],
    });
    if (raw is! Map<String, Object?> ||
        raw['entity'] is! Map<String, Object?>) {
      throw const FormatException('Invalid control receipt.');
    }
    final entity = raw['entity'] as Map<String, Object?>;
    if (entity['id'] is! String || entity['version'] != '1') {
      throw const FormatException('Invalid proposal receipt identity.');
    }
    final id = entity['id'] as String;
    ProcessMetricScope(tenantId: id, legalEntityId: id);
    return id;
  }

  @override
  Future<Map<String, Object?>> usage(
    String tenant,
    String metric,
    String periodStart,
  ) async {
    if (!{'ai.tokens', 'webhook.deliveries'}.contains(metric)) {
      throw const FormatException('Unsupported usage metric.');
    }
    parseProcessMetricUtc(periodStart);
    final raw = await _call('get_wave5_usage_allowance', {
      'p_tenant_id': tenant,
      'p_metric_code': metric,
      'p_period_start': periodStart,
    });
    if (raw is! Map<String, Object?>) {
      throw const FormatException('Invalid allowance projection.');
    }
    if (raw['state'] == 'unavailable' &&
        raw.length == 3 &&
        raw['reason'] == 'PERIOD_NOT_RESERVED' &&
        raw['limit'] is String &&
        RegExp(r'^(0|[1-9][0-9]{0,19})$').hasMatch(raw['limit'] as String)) {
      return Map.unmodifiable(raw);
    }
    const fields = {
      'state',
      'tenantId',
      'metricCode',
      'periodStart',
      'periodEnd',
      'limit',
      'settled',
      'reserved',
      'remaining',
      'generatedAt',
    };
    if (raw.length != fields.length ||
        !raw.keys.toSet().containsAll(fields) ||
        raw['state'] != 'available' ||
        raw['tenantId'] != tenant ||
        raw['metricCode'] != metric ||
        ['limit', 'settled', 'reserved', 'remaining'].any(
          (k) =>
              raw[k] is! String ||
              !RegExp(r'^(0|[1-9][0-9]{0,19})$').hasMatch(raw[k] as String),
        )) {
      throw const FormatException('Invalid exact usage projection.');
    }
    if (parseProcessMetricUtc(raw['periodStart'] as String) !=
        parseProcessMetricUtc(periodStart)) {
      throw const FormatException('Usage period mismatch.');
    }
    parseProcessMetricUtc(raw['periodEnd'] as String);
    parseProcessMetricUtc(raw['generatedAt'] as String);
    final expected =
        BigInt.parse(raw['limit'] as String) -
        BigInt.parse(raw['settled'] as String) -
        BigInt.parse(raw['reserved'] as String);
    if (BigInt.parse(raw['remaining'] as String) !=
        (expected.isNegative ? BigInt.zero : expected)) {
      throw const FormatException('Allowance arithmetic mismatch.');
    }
    return Map.unmodifiable(raw);
  }

  @override
  Future<Map<String, Object?>> health({String? tenant, String? grant}) async {
    if ((tenant == null) != (grant == null)) {
      throw const FormatException('Exact tenant access grant required.');
    }
    final raw = await _call(
      tenant == null ? 'get_operator_health' : 'get_operator_tenant_health',
      tenant == null ? {} : {'p_tenant_id': tenant, 'p_grant_id': grant},
    );
    if (raw is! Map<String, Object?> ||
        raw.length != 3 ||
        raw['contractRevision'] != 1 ||
        raw['generatedAt'] is! String ||
        raw['probes'] is! List ||
        (raw['probes'] as List).length != 4) {
      throw const FormatException('Invalid operator projection.');
    }
    final generated = parseProcessMetricUtc(raw['generatedAt'] as String),
        codes = <String>{};
    final probes = <Map<String, Object?>>[];
    for (final p in raw['probes'] as List) {
      if (p is! Map<String, Object?> ||
          p.length != 4 ||
          !p.keys.toSet().containsAll({
            'code',
            'state',
            'exactValue',
            'observedAt',
          }) ||
          p['code'] is! String ||
          !codes.add(p['code'] as String) ||
          !{
            'worker_lag_seconds',
            'retry_count',
            'dead_letter_count',
            'quota_remaining',
          }.contains(p['code']) ||
          !{'observed', 'unknown'}.contains(p['state'])) {
        throw const FormatException('Invalid health probe.');
      }
      if (p['state'] == 'observed') {
        if (p['exactValue'] is! String ||
            p['observedAt'] is! String ||
            !RegExp(
              r'^(0|[1-9][0-9]{0,19})$',
            ).hasMatch(p['exactValue'] as String) ||
            HealthProbe(
                  code: p['code'] as String,
                  observedAt: p['observedAt'] as String,
                  value: BigInt.parse(p['exactValue'] as String),
                  contractRevision: 1,
                ).stateAt(generated) !=
                'observed') {
          throw const FormatException('Stale probe cannot imply health.');
        }
      } else if (p['exactValue'] != null) {
        throw const FormatException('Unknown probe cannot imply a value.');
      }
      if (p['observedAt'] != null) {
        parseProcessMetricUtc(p['observedAt'] as String);
      }
      probes.add(Map.unmodifiable(p));
    }
    return Map.unmodifiable({...raw, 'probes': List.unmodifiable(probes)});
  }

  @override
  Future<void> authorizeSubscriptionRecovery(
    ProcessMetricScope scope,
    String actor,
  ) async {
    if (await _call('wave5_subscription_authorize', {
          'p_tenant_id': scope.tenantId,
        }) !=
        actor) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message:
            'Saved subscription requests require the original privileged MFA actor.',
      );
    }
  }

  @override
  Future<Map<String, Object?>> subscription(String tenant) async {
    final raw = await _call('get_wave5_subscription', {'p_tenant_id': tenant});
    const fields = {
      'contractRevision',
      'tenantId',
      'id',
      'version',
      'plan',
      'status',
      'seats',
      'trialStart',
      'trialEnd',
      'syntheticTarget',
    };
    if (raw is! Map<String, Object?> ||
        raw.length != fields.length ||
        !raw.keys.toSet().containsAll(fields) ||
        raw['contractRevision'] != 1 ||
        raw['tenantId'] != tenant ||
        raw['id'] is! String ||
        raw['version'] is! String ||
        !RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(raw['version'] as String) ||
        BigInt.parse(raw['version'] as String) >
            BigInt.parse('9223372036854775807') ||
        raw['plan'] is! String ||
        !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(raw['plan'] as String) ||
        !{
          'active',
          'trialing',
          'past_due',
          'canceled',
          'paused',
        }.contains(raw['status']) ||
        raw['seats'] is! int ||
        (raw['seats'] as int) < 1 ||
        (raw['seats'] as int) > 10000 ||
        raw['syntheticTarget'] is! bool ||
        raw['trialStart'] is! String ||
        (raw['trialEnd'] != null && raw['trialEnd'] is! String)) {
      throw const FormatException('Invalid subscription projection.');
    }
    ProcessMetricScope(
      tenantId: raw['id'] as String,
      legalEntityId: raw['id'] as String,
    );
    final start = parseProcessMetricUtc(raw['trialStart'] as String);
    if (raw['trialEnd'] != null &&
        !parseProcessMetricUtc(raw['trialEnd'] as String).isAfter(start)) {
      throw const FormatException('Invalid explicit trial period.');
    }
    return Map.unmodifiable(raw);
  }

  @override
  Future<String> scheduleSubscription(
    ProcessMetricScope scope,
    Map<String, Object?> envelope,
  ) async {
    final p = envelope['payload'] as Map<String, Object?>;
    final raw = await _call('schedule_synthetic_subscription', {
      'p_tenant_id': scope.tenantId,
      'p_command_id': envelope['commandId'],
      'p_idempotency_key': envelope['idempotencyKey'],
      'p_client_timestamp': envelope['clientTimestamp'],
      'p_expected_version': p['expectedVersion'],
      'p_plan_code': p['plan'],
      'p_seats': int.parse(p['seats'] as String),
      'p_trial_starts_at': p['trialStart'],
      'p_trial_ends_at': p['trialEnd'],
    });
    if (raw is! Map<String, Object?> || raw['entity'] is! Map<String, Object?>) {
      throw const FormatException('Invalid subscription receipt.');
    }
    final e = raw['entity'] as Map<String, Object?>;
    if (e['id'] is! String ||
        e['version'] != '1' ||
        e['state'] != 'scheduled' ||
        e['explanationCode'] != 'synthetic_trial_review') {
      throw const FormatException('Invalid scheduling decision.');
    }
    ProcessMetricScope(
      tenantId: e['id'] as String,
      legalEntityId: e['id'] as String,
    );
    return e['id'] as String;
  }
}

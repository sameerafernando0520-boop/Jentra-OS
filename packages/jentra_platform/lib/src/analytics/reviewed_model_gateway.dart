import 'dart:convert';

import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart' show DomainError;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'process_metric_gateway.dart';

/// Stable invocation and usage identities; no prompts, output, tokens or keys.
final class ReviewedModelRequest {
  static void validateEnvelope(Map<String, Object?> e) {
    const fields = {
      'commandId',
      'idempotencyKey',
      'clientTimestamp',
      'action',
      'payload',
    };
    if (e.length != fields.length ||
        !e.keys.toSet().containsAll(fields) ||
        e['action'] != 'suggest' ||
        e['commandId'] is! String ||
        e['idempotencyKey'] is! String ||
        e['clientTimestamp'] is! String ||
        e['payload'] is! Map<String, Object?> ||
        utf8.encode(jsonEncode(e)).length > 8192) {
      throw const FormatException('Invalid model invocation request.');
    }
    ProcessMetricScope(
      tenantId: e['commandId'] as String,
      legalEntityId: e['idempotencyKey'] as String,
    );
    parseProcessMetricUtc(e['clientTimestamp'] as String);
    final p = e['payload'] as Map<String, Object?>;
    const parameters = {'sourceId', 'maxTokens', 'periodStart', 'periodEnd'};
    if (p.length != parameters.length ||
        !p.keys.toSet().containsAll(parameters) ||
        p.values.any((v) => v is! String) ||
        !RegExp(r'^[1-9][0-9]{0,3}$').hasMatch(p['maxTokens'] as String) ||
        int.parse(p['maxTokens'] as String) > 2000) {
      throw const FormatException(
        'Use a reviewed forecast, quota period and a token reservation from 1 to 2000.',
      );
    }
    ProcessMetricScope(
      tenantId: p['sourceId'] as String,
      legalEntityId: p['sourceId'] as String,
    );
    final start = parseProcessMetricUtc(p['periodStart'] as String),
        end = parseProcessMetricUtc(p['periodEnd'] as String);
    if (!end.isAfter(start) ||
        end.difference(start) > const Duration(days: 366)) {
      throw const FormatException('Invalid model quota period.');
    }
  }

  static Map<String, Object?> wire(
    ProcessMetricScope scope,
    Map<String, Object?> e,
  ) {
    validateEnvelope(e);
    return {
      ...e['payload'] as Map<String, Object?>,
      'scope': {
        'tenantId': scope.tenantId,
        'legalEntityId': scope.legalEntityId,
        'branchId': scope.branchId,
      },
      'invocationId': e['commandId'],
      'usageEventId': e['idempotencyKey'],
    };
  }
}

/// A suggestion is data. Only the separate human proposal can be approved.
final class VerifiedModelSuggestion {
  const VerifiedModelSuggestion._(
    this.sourceId,
    this.sourceHash,
    this.horizonStart,
    this.horizonEnd,
  );
  final String sourceId, sourceHash, horizonStart, horizonEnd;

  static VerifiedModelSuggestion verify(
    Object? raw,
    Map<String, Object?> evidence,
  ) {
    const fields = {
      'commandCode',
      'sourceId',
      'sourceHash',
      'horizonStart',
      'horizonEnd',
    };
    if (raw is! Map<String, Object?> ||
        raw.length != fields.length ||
        !raw.keys.toSet().containsAll(fields) ||
        raw['commandCode'] != 'analytics.freeze_pipeline.v1' ||
        fields
            .where((f) => f != 'commandCode')
            .any((f) => raw[f] != evidence[f])) {
      throw const FormatException(
        'The model suggestion does not match the authorized forecast.',
      );
    }
    return VerifiedModelSuggestion._(
      raw['sourceId'] as String,
      raw['sourceHash'] as String,
      raw['horizonStart'] as String,
      raw['horizonEnd'] as String,
    );
  }
}

abstract interface class ReviewedModelRepository {
  Future<void> authorizeRecovery(ProcessMetricScope scope, String actor);
  Future<VerifiedModelSuggestion> suggestion(
    ProcessMetricScope scope,
    String actor,
    Map<String, Object?> envelope,
  );
}

typedef ReviewedModelInvoke =
    Future<Object?> Function(Map<String, Object?> request, String actor);

final class SupabaseReviewedModelGateway implements ReviewedModelRepository {
  SupabaseReviewedModelGateway(SupabaseClient client)
    : rpc = ((name, p) => client.schema('api').rpc(name, params: p)),
      invoke = ((request, actor) async {
        final session = client.auth.currentSession;
        if (session == null || session.user.id != actor) {
          throw _failure('AUTH_REQUIRED');
        }
        return (await client.functions.invoke(
          'wave5-runtime/model/suggestion',
          body: request,
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
          abortSignal: Future<void>.delayed(const Duration(seconds: 70)),
        )).data;
      });
  SupabaseReviewedModelGateway.injected(this.rpc, this.invoke);
  final ProcessMetricRpc rpc;
  final ReviewedModelInvoke invoke;
  Map<String, Object?> _scope(ProcessMetricScope s) => {
    'p_tenant_id': s.tenantId,
    'p_legal_entity_id': s.legalEntityId,
    'p_branch_id': s.branchId,
  };

  static DomainError _failure(String code) => DomainError(
    code: code,
    retryable: true,
    message: switch (code) {
      'AUTH_REQUIRED' ||
      'PERMISSION_DENIED' ||
      'WORKER_ACCESS_DENIED' ||
      'SOURCE_AUTHORITY_CHANGED' =>
        'Current source access or sign-in does not permit this model request. Protected evidence has been cleared.',
      'QUOTA_EXCEEDED' ||
      'THROTTLED' => 'The reviewed model allowance cannot admit this request.',
      'MODEL_PROVIDER_UNAVAILABLE' || 'WORKER_PROVIDER_UNAVAILABLE' =>
        'The reviewed model worker is unavailable. The original invocation is saved; no suggestion was invented.',
      'MODEL_OUTCOME_REQUIRES_REVIEW' ||
      'MODEL_OUTCOME_UNKNOWN' ||
      'OUTCOME_UNKNOWN' =>
        'The model outcome is unconfirmed. Keep this original invocation; a pending or unknown reservation requires review before another call.',
      _ =>
        'The model response could not be verified. Keep the original invocation for review.',
    },
  );

  Future<Object?> _call(String name, Map<String, Object?> p) async {
    try {
      return await rpc(name, p);
    } on PostgrestException catch (e) {
      throw _failure(
        e.code == '42501' ? 'PERMISSION_DENIED' : 'WORKER_PROVIDER_UNAVAILABLE',
      );
    }
  }

  @override
  Future<void> authorizeRecovery(ProcessMetricScope scope, String actor) async {
    if (await _call('wave5_proposal_authorize', _scope(scope)) != actor) {
      throw _failure('PERMISSION_DENIED');
    }
  }

  Future<Map<String, Object?>> _evidence(
    ProcessMetricScope s,
    String source,
  ) async {
    final raw = await _call('get_ai_forecast_evidence', {
      ..._scope(s),
      'p_forecast_id': source,
    });
    const fields = {
      'contractRevision',
      'modelProvider',
      'sourceId',
      'sourceHash',
      'scope',
      'currencies',
      'horizonStart',
      'horizonEnd',
    };
    if (raw is! Map<String, Object?> ||
        raw.length != fields.length ||
        !raw.keys.toSet().containsAll(fields) ||
        raw['contractRevision'] != 1 ||
        raw['sourceId'] != source ||
        raw['modelProvider'] != 'unavailable' ||
        raw['sourceHash'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['sourceHash'] as String) ||
        raw['scope'] is! Map<String, Object?> ||
        raw['currencies'] is! List ||
        utf8.encode(jsonEncode(raw)).length > 65536) {
      throw const FormatException('Invalid authorized model evidence.');
    }
    final scope = raw['scope'] as Map<String, Object?>;
    if (scope.length != 3 ||
        scope['tenantId'] != s.tenantId ||
        scope['legalEntityId'] != s.legalEntityId ||
        scope['branchId'] != s.branchId) {
      throw const FormatException('Model evidence belongs to another scope.');
    }
    final start = raw['horizonStart'], end = raw['horizonEnd'];
    if (start is! String ||
        end is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(start) ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(end)) {
      throw const FormatException('Invalid model horizon.');
    }
    final a = parseProcessMetricUtc('${start}T00:00:00Z'),
        b = parseProcessMetricUtc('${end}T00:00:00Z');
    if (!b.isAfter(a) || b.difference(a) > const Duration(days: 366)) {
      throw const FormatException('Invalid model horizon.');
    }
    return raw;
  }

  @override
  Future<VerifiedModelSuggestion> suggestion(
    ProcessMetricScope scope,
    String actor,
    Map<String, Object?> envelope,
  ) async {
    final request = ReviewedModelRequest.wire(scope, envelope);
    await authorizeRecovery(scope, actor);
    final before = await _evidence(scope, request['sourceId'] as String);
    Object? raw;
    try {
      raw = await invoke(request, actor);
    } on DomainError {
      rethrow;
    } on FunctionException catch (e) {
      const codes = {
        'AUTH_REQUIRED',
        'WORKER_ACCESS_DENIED',
        'SOURCE_AUTHORITY_CHANGED',
        'QUOTA_EXCEEDED',
        'THROTTLED',
        'MODEL_PROVIDER_UNAVAILABLE',
        'WORKER_PROVIDER_UNAVAILABLE',
        'MODEL_OUTCOME_REQUIRES_REVIEW',
        'MODEL_OUTCOME_UNKNOWN',
      };
      final data = e.details;
      throw _failure(
        data is Map && codes.contains(data['code'])
            ? data['code'] as String
            : 'OUTCOME_UNKNOWN',
      );
    } catch (_) {
      throw _failure('OUTCOME_UNKNOWN');
    }
    await authorizeRecovery(scope, actor);
    final after = await _evidence(scope, request['sourceId'] as String);
    if (before['sourceHash'] != after['sourceHash']) {
      throw _failure('SOURCE_AUTHORITY_CHANGED');
    }
    return VerifiedModelSuggestion.verify(raw, after);
  }
}

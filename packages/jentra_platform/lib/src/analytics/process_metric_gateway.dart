import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart' show DomainError;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'process_metric_hasher.dart';

typedef ProcessMetricRpc =
    Future<Object?> Function(String name, Map<String, Object?> parameters);

final class SupabaseProcessMetricGateway implements ProcessMetricRepository {
  SupabaseProcessMetricGateway(SupabaseClient client)
    : rpc = ((name, params) => client.schema('api').rpc(name, params: params));
  SupabaseProcessMetricGateway.injected(this.rpc);
  final ProcessMetricRpc rpc;
  Map<String, Object?> _scope(ProcessMetricScope s) => {
    'p_tenant_id': s.tenantId,
    'p_legal_entity_id': s.legalEntityId,
    'p_branch_id': s.branchId,
  };
  Future<Object?> _call(String name, Map<String, Object?> params) async {
    try {
      return await rpc(name, params);
    } on PostgrestException catch (e) {
      final known = {
        'AUTH_REQUIRED',
        'PERMISSION_DENIED',
        'ENTITLEMENT_REQUIRED',
        'LIMIT_EXCEEDED',
        'CONTRACT_MISMATCH',
        'VALIDATION_ERROR',
      };
      final code = known.contains(e.message)
          ? e.message
          : e.code == '42501'
          ? 'PERMISSION_DENIED'
          : e.code == 'PGRST202'
          ? 'PROVIDER_UNAVAILABLE'
          : 'PROVIDER_UNAVAILABLE';
      throw DomainError(
        code: code,
        message: switch (code) {
          'AUTH_REQUIRED' => 'Sign in again to read process evidence.',
          'PERMISSION_DENIED' =>
            'Current source permissions do not permit this read.',
          'ENTITLEMENT_REQUIRED' => 'The analytics entitlement is unavailable.',
          'LIMIT_EXCEEDED' =>
            'Narrow the cohort; the complete source exceeds a limit.',
          'VALIDATION_ERROR' => 'Check the UTC cohort and cutoff order.',
          'CONTRACT_MISMATCH' => 'The process provider contract has changed.',
          _ => 'The process provider is unavailable. Retry when ready.',
        },
        retryable: code == 'PROVIDER_UNAVAILABLE',
      );
    } on DomainError {
      rethrow;
    } catch (_) {
      throw const DomainError(
        code: 'PROVIDER_UNAVAILABLE',
        message: 'Process evidence is unavailable.',
        retryable: true,
      );
    }
  }

  @override
  Future<void> authorize(ProcessMetricScope scope) async {
    await _call('analytics_process_authorize', _scope(scope));
  }

  @override
  Future<void> authorizeRecovery(
    ProcessMetricScope scope,
    String actorId,
  ) async {
    final current = await _call('analytics_process_authorize', _scope(scope));
    if (current != actorId) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Saved filters belong to another signed-in actor.',
      );
    }
  }

  @override
  Future<ProcessMetricSnapshot> snapshot(
    ProcessMetricScope scope,
    ProcessMetricFilter filter,
  ) async {
    final raw = await _call('analytics_process_snapshot', {
      ..._scope(scope),
      'p_window_start': filter.windowStart.toIso8601String(),
      'p_window_end': filter.windowEnd.toIso8601String(),
      'p_as_of': filter.asOf.toIso8601String(),
      'p_recorded_through': filter.recordedThrough.toIso8601String(),
    });
    if (raw is! Map<String, Object?>) {
      throw const DomainError(
        code: 'CONTRACT_MISMATCH',
        message: 'Invalid process response.',
      );
    }
    final parsed = ParsedProcessMetricSnapshot.fromJson(
      raw,
      expectedScope: scope,
    );
    if (parsed.source.windowStart != filter.windowStart ||
        parsed.source.windowEnd != filter.windowEnd ||
        parsed.source.asOf != filter.asOf ||
        parsed.source.recordedThrough != filter.recordedThrough) {
      throw const DomainError(
        code: 'CONTRACT_MISMATCH',
        message: 'The process response uses different cutoffs.',
      );
    }
    return parsed.verify(ProcessMetricSha256Hasher());
  }

  @override
  Future<Map<String, Object?>> event(
    ProcessMetricScope scope,
    String eventId,
  ) async {
    if (!RegExp(
      r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$',
    ).hasMatch(eventId)) {
      throw const FormatException('Invalid event identity.');
    }
    final raw = await _call('analytics_process_event', {
      ..._scope(scope),
      'p_event_id': eventId,
    });
    if (raw is! Map<String, Object?> ||
        raw.length != 6 ||
        !raw.keys.toSet().containsAll({
          'eventId',
          'tenantId',
          'legalEntityId',
          'branchId',
          'documentType',
          'documentId',
        }) ||
        raw['eventId'] != eventId ||
        raw['tenantId'] != scope.tenantId ||
        raw['legalEntityId'] != scope.legalEntityId ||
        (scope.branchId != null && raw['branchId'] != scope.branchId) ||
        raw['documentType'] != 'crm_opportunity' ||
        raw['documentId'] is! String ||
        !RegExp(
          r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$',
        ).hasMatch(raw['documentId'] as String) ||
        (raw['branchId'] != null &&
            (raw['branchId'] is! String ||
                !RegExp(
                  r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$',
                ).hasMatch(raw['branchId'] as String)))) {
      throw const DomainError(
        code: 'CONTRACT_MISMATCH',
        message: 'Invalid process drill-through response.',
      );
    }
    return Map.unmodifiable(raw);
  }
}

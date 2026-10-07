import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart' show DomainError;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'process_metric_gateway.dart';
import 'process_metric_hasher.dart';

final class SupabasePipelineForecastGateway
    implements PipelineForecastRepository {
  SupabasePipelineForecastGateway(SupabaseClient client)
    : rpc = ((name, params) => client.schema('api').rpc(name, params: params));
  SupabasePipelineForecastGateway.injected(this.rpc);
  final ProcessMetricRpc rpc;
  @override
  Future<void> authorizeRecovery(
    ProcessMetricScope scope,
    String actorId,
  ) async {
    final current = await _call('analytics_pipeline_authorize', _scope(scope));
    if (current != actorId) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Saved requests belong to another signed-in actor.',
      );
    }
  }

  Map<String, Object?> _scope(ProcessMetricScope s) => {
    'p_tenant_id': s.tenantId,
    'p_legal_entity_id': s.legalEntityId,
    'p_branch_id': s.branchId,
  };
  Future<Object?> _call(String name, Map<String, Object?> parameters) async {
    try {
      return await rpc(name, parameters);
    } on PostgrestException catch (e) {
      final denied = e.code == '42501';
      throw DomainError(
        code: denied ? 'PERMISSION_DENIED' : 'PROVIDER_UNAVAILABLE',
        message: denied
            ? 'Current source access or entitlement does not permit forecasts.'
            : 'The forecast provider is unavailable.',
        retryable: !denied,
      );
    } on DomainError {
      rethrow;
    } catch (_) {
      throw const DomainError(
        code: 'OUTCOME_UNKNOWN',
        message:
            'The forecast request could not be confirmed. Retry with its original command identity.',
        retryable: true,
      );
    }
  }

  @override
  Future<void> authorize(ProcessMetricScope scope) async {
    await _call('analytics_pipeline_authorize', _scope(scope));
  }

  @override
  Future<String> freeze(
    ProcessMetricScope scope, {
    required String commandId,
    required String idempotencyKey,
    required String clientTimestamp,
    required String horizonStart,
    required String horizonEnd,
  }) async {
    final raw = await _call('freeze_pipeline_forecast', {
      ..._scope(scope),
      'p_command_id': commandId,
      'p_idempotency_key': idempotencyKey,
      'p_client_timestamp': clientTimestamp,
      'p_horizon_start': horizonStart,
      'p_horizon_end': horizonEnd,
    });
    if (raw is! Map<String, Object?> ||
        raw['entity'] is! Map<String, Object?>) {
      throw const FormatException('Invalid forecast receipt.');
    }
    final entity = raw['entity'] as Map<String, Object?>;
    if (entity['id'] is! String || entity['version'] != '1') {
      throw const FormatException('Invalid frozen identity.');
    }
    final id = entity['id'] as String;
    ProcessMetricScope(tenantId: id, legalEntityId: id);
    return id;
  }

  @override
  Future<FrozenPipelineForecast> get(
    ProcessMetricScope scope,
    String id,
  ) async {
    final raw = await _call('get_pipeline_forecast', {
      ..._scope(scope),
      'p_forecast_id': id,
    });
    if (raw is! Map<String, Object?>) {
      throw const FormatException('Invalid forecast response.');
    }
    return FrozenPipelineForecast.verify(
      raw,
      scope,
      id,
      ProcessMetricSha256Hasher(),
    );
  }
}

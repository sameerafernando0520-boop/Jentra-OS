import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_tax_lk.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sri Lanka tax schedule candidate API. Server permissions, MFA and the
/// separate-approver rule decide every write; this adapter only maps outcomes.
final class SupabaseLkTaxGateway implements LkTaxRepository {
  SupabaseLkTaxGateway(this.client);
  final SupabaseClient client;

  Future<Object?> _rpc(
    String name,
    TenantContext scope, [
    Map<String, Object?> args = const {},
  ]) async {
    if (!scope.hasOperationalScope ||
        client.auth.currentUser?.id != scope.actorId) {
      throw const DomainError(
        code: 'AUTHENTICATION_REQUIRED',
        message: 'Select a signed-in entity and branch.',
      );
    }
    try {
      return await client
          .schema('api')
          .rpc(
            name,
            params: {
              'p_tenant_id': scope.tenantId,
              'p_legal_entity_id': scope.legalEntityId,
              'p_branch_id': scope.branchId,
              ...args,
            },
          );
    } on PostgrestException catch (cause) {
      final code = switch ((cause.code, cause.message)) {
        ('PGRST202' || '42P01', _) => 'FEATURE_NOT_INSTALLED',
        ('42501', 'TAX_SEPARATE_APPROVER_REQUIRED') =>
          'SEPARATE_APPROVER_REQUIRED',
        ('42501', _) => 'PERMISSION_DENIED',
        ('55000', _) => 'STATE_CONFLICT',
        ('23505' || '23P01', _) => 'IDENTITY_EXISTS',
        ('22023', 'TAX_VAT_PERIOD_INVALID') => 'PERIOD_INVALID',
        ('22023', 'TAX_VAT_MAPPING_INVALID') => 'MAPPING_INVALID',
        ('22023' || '22007' || '22008' || '22P02' || '23503' || '23514', _) =>
          'VALIDATION_ERROR',
        _ => 'UNCERTAIN_RESULT',
      };
      throw DomainError(
        code: code,
        message: switch (code) {
          'FEATURE_NOT_INSTALLED' =>
            'Sri Lanka tax schedules require their reviewed development update.',
          'SEPARATE_APPROVER_REQUIRED' =>
            'Another approver must approve mappings you proposed.',
          'PERMISSION_DENIED' =>
            'Tax permission for this entity and a verified authenticator session are required.',
          'STATE_CONFLICT' =>
            'This mapping changed. Reload and review its current status.',
          'IDENTITY_EXISTS' =>
            'An approved mapping already exists for this code. Reload first.',
          'PERIOD_INVALID' => 'Choose one calendar month or one quarter.',
          'MAPPING_INVALID' =>
            'That VAT line does not suit this tax code\'s kind and rate.',
          'VALIDATION_ERROR' => 'Check the period, line and reason.',
          _ => 'The result is uncertain. Reload before trying again.',
        },
        retryable: code == 'UNCERTAIN_RESULT',
      );
    }
  }

  Map<String, Object?> _map(Object? raw) =>
      Map<String, Object?>.from(raw! as Map);

  @override
  Future<List<LkVatMappingRow>> vatMappings(TenantContext scope) async => [
    for (final row
        in (await _rpc('lk_vat_mappings', scope) as List<Object?>? ?? const []))
      LkVatMappingRow.fromJson(_map(row)),
  ];

  @override
  Future<LkVatMapping> proposeVatMapping(
    TenantContext scope, {
    required String id,
    required String taxDefinitionId,
    required LkVatLine line,
    required String reason,
  }) async => LkVatMapping.fromJson(
    _map(
      await _rpc('lk_vat_mapping_propose', scope, {
        'p_id': id,
        'p_tax_definition_id': taxDefinitionId,
        'p_vat_line': line.wire,
        'p_reason': reason,
      }),
    ),
  );

  @override
  Future<LkVatMapping> decideVatMapping(
    TenantContext scope,
    String id,
    String action,
  ) async => LkVatMapping.fromJson(
    _map(
      await _rpc('lk_vat_mapping_decide', scope, {
        'p_id': id,
        'p_action': action,
      }),
    ),
  );

  @override
  Future<LkVatReturn> vatReturn(
    TenantContext scope, {
    required String from,
    required String toExclusive,
  }) async => LkVatReturn.fromJson(
    _map(
      await _rpc('lk_vat_return', scope, {
        'p_from': from,
        'p_to_exclusive': toExclusive,
      }),
    ),
  );
}

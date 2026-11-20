import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_payroll.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sri Lanka statutory payroll candidate API. Server permissions, MFA and the
/// separate-approver rule decide every write; this adapter only maps outcomes.
final class SupabaseLkStatutoryPayrollGateway
    implements LkStatutoryPayrollRepository {
  SupabaseLkStatutoryPayrollGateway(this.client);
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
        ('42501', 'PAYROLL_MFA_REQUIRED') => 'MFA_REQUIRED',
        ('42501', 'PAYROLL_STATUTORY_SEPARATE_APPROVER_REQUIRED') =>
          'SEPARATE_APPROVER_REQUIRED',
        ('42501', _) => 'PERMISSION_DENIED',
        ('55000', 'PAYROLL_STATUTORY_OVERLAP') => 'STATUTORY_OVERLAP',
        ('55000', _) => 'STATE_CONFLICT',
        ('23505' || '23P01', _) => 'IDENTITY_EXISTS',
        ('22023' || '22007' || '22008' || '22P02' || '23503' || '23514', _) =>
          'VALIDATION_ERROR',
        _ => 'UNCERTAIN_RESULT',
      };
      throw DomainError(
        code: code,
        message: switch (code) {
          'FEATURE_NOT_INSTALLED' =>
            'Statutory payroll requires its reviewed development update.',
          'MFA_REQUIRED' =>
            'Verify with your authenticator before changing statutory payroll.',
          'SEPARATE_APPROVER_REQUIRED' =>
            'Another payroll approver must approve rates you proposed.',
          // The shared access check refuses missing permission and missing
          // MFA with one message, so name both.
          'PERMISSION_DENIED' =>
            'Payroll permission for this scope and a verified authenticator session are required.',
          'STATUTORY_OVERLAP' =>
            'Approved rates already cover part of this period. Retire them first.',
          'STATE_CONFLICT' =>
            'This rate set changed. Reload and review its current status.',
          'IDENTITY_EXISTS' =>
            'This record already exists. Reload before saving again.',
          'VALIDATION_ERROR' =>
            'Check the NIC, registration numbers, period and reason.',
          _ => 'The result is uncertain. Reload before trying again.',
        },
        retryable: code == 'UNCERTAIN_RESULT',
      );
    }
  }

  List<Map<String, Object?>> _list(Object? raw) => [
    for (final row in (raw as List<Object?>? ?? const []))
      Map<String, Object?>.from(row! as Map),
  ];

  Map<String, Object?>? _map(Object? raw) =>
      raw == null ? null : Map<String, Object?>.from(raw as Map);

  @override
  Future<LkStatutoryReturn> statutoryReturn(
    TenantContext scope, {
    required String month,
    required LkStatutoryReturnKind kind,
  }) async => LkStatutoryReturn.fromJson(
    _map(
      await _rpc('people_payroll_statutory_return', scope, {
        'p_month': month,
        'p_kind': kind.name,
      }),
    )!,
  );

  @override
  Future<List<LkStatutoryRuleSetRecord>> ruleSets(TenantContext scope) async =>
      [
        for (final row in _list(
          await _rpc('people_payroll_statutory_rule_sets', scope),
        ))
          LkStatutoryRuleSetRecord.fromJson(row),
      ];

  @override
  Future<LkStatutoryRuleSetRecord> proposeLk(
    TenantContext scope, {
    required String id,
    required String effectiveFrom,
    required String effectiveToExclusive,
  }) async => LkStatutoryRuleSetRecord.fromJson(
    _map(
      await _rpc('people_payroll_statutory_propose_lk', scope, {
        'p_id': id,
        'p_effective_from': effectiveFrom,
        'p_effective_to_exclusive': effectiveToExclusive,
      }),
    )!,
  );

  @override
  Future<LkStatutoryRuleSetRecord> decide(
    TenantContext scope,
    String id,
    String action,
  ) async => LkStatutoryRuleSetRecord.fromJson(
    _map(
      await _rpc('people_payroll_statutory_decide', scope, {
        'p_id': id,
        'p_action': action,
      }),
    )!,
  );

  @override
  Future<List<LkComponentStatutoryRecord>> classifications(
    TenantContext scope,
  ) async => [
    for (final row in _list(
      await _rpc('people_payroll_component_statutory', scope),
    ))
      LkComponentStatutoryRecord.fromJson(row),
  ];

  @override
  Future<void> classify(
    TenantContext scope, {
    required String id,
    required String componentId,
    required bool epfLiable,
    required bool etfLiable,
    required bool apitRegularProfit,
    required String reason,
  }) => _rpc('people_payroll_component_statutory_set', scope, {
    'p_id': id,
    'p_component_id': componentId,
    'p_epf_liable': epfLiable,
    'p_etf_liable': etfLiable,
    'p_apit_regular_profit': apitRegularProfit,
    'p_reason': reason,
  });

  @override
  Future<LkEmployeeStatutoryDetails?> employee(
    TenantContext scope,
    String employeeId,
  ) async {
    final row = _map(
      await _rpc('people_payroll_employee_statutory', scope, {
        'p_employee_id': employeeId,
      }),
    );
    return row == null ? null : LkEmployeeStatutoryDetails.fromJson(row);
  }

  @override
  Future<void> saveEmployee(
    TenantContext scope, {
    required String id,
    required String employeeId,
    required LkEmployeeStatutoryDetails details,
    required String reason,
  }) => _rpc('people_payroll_employee_statutory_set', scope, {
    'p_id': id,
    'p_employee_id': employeeId,
    'p_payload': details.toPayload(reason),
  });

  @override
  Future<LkEmployerRegistration?> employer(TenantContext scope) async {
    final row = _map(await _rpc('people_payroll_employer_registration', scope));
    return row == null ? null : LkEmployerRegistration.fromJson(row);
  }

  @override
  Future<void> saveEmployer(
    TenantContext scope, {
    required String id,
    required String epfEmployerNumber,
    required String etfEmployerNumber,
    required String reason,
  }) => _rpc('people_payroll_employer_registration_set', scope, {
    'p_id': id,
    'p_epf_employer_number': epfEmployerNumber,
    'p_etf_employer_number': etfEmployerNumber,
    'p_reason': reason,
  });
}

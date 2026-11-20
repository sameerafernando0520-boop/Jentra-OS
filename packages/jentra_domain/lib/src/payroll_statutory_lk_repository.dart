import 'payroll_statutory_lk.dart';
import 'tenant_context.dart';

/// Plain-language explanation of a `PAYROLL_STATUTORY_BLOCKED` reason code.
String lkStatutoryBlockerMessage(String reason) => switch (reason) {
  'STATUTORY_LKR_REQUIRED' =>
    'Statutory payroll runs in Sri Lankan rupees only.',
  'STATUTORY_INPUTS_MISSING' =>
    'Statutory inputs are missing. Prepare the run again.',
  LkStatutoryBlocker.approvedRuleSetRequired =>
    'No approved statutory rates cover this pay period. Approve a rate set first.',
  LkStatutoryBlocker.employeeDetailsRequired =>
    "Record the employee's statutory details: NIC, EPF member number and APIT facts.",
  LkStatutoryBlocker.nicRequired => "Record the employee's NIC.",
  LkStatutoryBlocker.coverageReviewRequired =>
    'The employee is marked exempt from EPF and ETF. Exemptions need separate review.',
  LkStatutoryBlocker.epfMemberNumberRequired =>
    "Record the employee's EPF member number.",
  LkStatutoryBlocker.apitOtherTableRequired =>
    'This payment needs an APIT table other than Table 01.',
  LkStatutoryBlocker.apitNonresidentReviewRequired =>
    'Nonresident, noncitizen employees need separate APIT treatment.',
  LkStatutoryBlocker.apitPrimaryDeclarationRequired =>
    'Confirm the primary employment declaration before using APIT Table 01.',
  LkStatutoryBlocker.apitTable05Required =>
    'This employee needs APIT Table 05: they joined or left this year, or a low month follows high year-to-date pay.',
  LkStatutoryBlocker.apitMonthlyPeriodRequired =>
    'APIT Table 01 needs a pay period of one full calendar month.',
  LkStatutoryBlocker.earningsRequired =>
    'Statutory payroll needs at least one earning.',
  LkStatutoryBlocker.earningsUnclassified =>
    'Classify every earning for EPF, ETF and APIT before preparing the run.',
  _ => 'Statutory payroll is blocked. Review the employee and rate details.',
};

String _text(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw FormatException('Statutory payroll field $field is missing.');
  }
  return value;
}

bool _bool(Object? value, String field) => value is bool
    ? value
    : throw FormatException('Statutory payroll field $field is missing.');

final class LkStatutoryRuleSetRecord {
  LkStatutoryRuleSetRecord.fromJson(Map<String, Object?> json)
    : id = _text(json['id'], 'id'),
      status = switch (json['status']) {
        'pending' || 'approved' || 'retired' => json['status']! as String,
        _ => throw const FormatException('Unknown statutory rule set status.'),
      },
      ruleSet = LkStatutoryRuleSet.fromJson(json),
      sources = Map.unmodifiable({
        for (final MapEntry(:key, :value)
            in (json['sources']! as Map<String, Object?>).entries)
          key: '$value',
      }),
      proposedBy = _text(json['proposed_by'], 'proposed_by'),
      approvedBy = json['approved_by'] as String?;

  final String id, status, proposedBy;
  final String? approvedBy;
  final LkStatutoryRuleSet ruleSet;
  final Map<String, String> sources;
}

final class LkComponentStatutoryRecord {
  LkComponentStatutoryRecord.fromJson(Map<String, Object?> json)
    : componentId = _text(json['component_id'], 'component_id'),
      code = _text(json['code'], 'code'),
      epfLiable = _bool(json['epf_liable'], 'epf_liable'),
      etfLiable = _bool(json['etf_liable'], 'etf_liable'),
      apitRegularProfit = _bool(
        json['apit_regular_profit'],
        'apit_regular_profit',
      );

  final String componentId, code;
  final bool epfLiable, etfLiable, apitRegularProfit;
}

/// Employee statutory details. Only payroll configurers can read the identifiers.
final class LkEmployeeStatutoryDetails {
  const LkEmployeeStatutoryDetails({
    this.nic,
    this.epfMemberNumber,
    this.coverage = 'standard',
    this.apitCase = 'regular_primary',
    this.residentOrCitizen = true,
    this.primaryEmploymentDeclared = false,
    this.joinedOrLeftInYear = false,
  });

  factory LkEmployeeStatutoryDetails.fromJson(Map<String, Object?> json) =>
      LkEmployeeStatutoryDetails(
        nic: json['nic'] as String?,
        epfMemberNumber: json['epf_member_number'] as String?,
        coverage: _text(json['coverage'], 'coverage'),
        apitCase: _text(json['apit_case'], 'apit_case'),
        residentOrCitizen: _bool(
          json['resident_or_citizen'],
          'resident_or_citizen',
        ),
        primaryEmploymentDeclared: _bool(
          json['primary_employment_declared'],
          'primary_employment_declared',
        ),
        joinedOrLeftInYear: _bool(
          json['joined_or_left_in_year'],
          'joined_or_left_in_year',
        ),
      );

  static const coverages = ['standard', 'exempt'];
  static const apitCases = [
    'regular_primary',
    'lump_sum_or_arrears',
    'terminal_benefit',
    'secondary_employment',
    'employer_paid_tax',
    'foreign_employer',
  ];

  /// Old (9 digits + V/X) or new (12 digits) NIC.
  static bool validNic(String value) => RegExp(
    r'^([0-9]{9}[VX]|[0-9]{12})$',
  ).hasMatch(value.trim().toUpperCase());

  final String? nic, epfMemberNumber;
  final String coverage, apitCase;
  final bool residentOrCitizen, primaryEmploymentDeclared, joinedOrLeftInYear;

  Map<String, Object?> toPayload(String reason) => {
    'nic': nic,
    'epf_member_number': epfMemberNumber,
    'coverage': coverage,
    'apit_case': apitCase,
    'resident_or_citizen': residentOrCitizen,
    'primary_employment_declared': primaryEmploymentDeclared,
    'joined_or_left_in_year': joinedOrLeftInYear,
    'reason': reason,
  };
}

final class LkEmployerRegistration {
  LkEmployerRegistration.fromJson(Map<String, Object?> json)
    : epfEmployerNumber = _text(
        json['epf_employer_number'],
        'epf_employer_number',
      ),
      etfEmployerNumber = _text(
        json['etf_employer_number'],
        'etf_employer_number',
      );

  final String epfEmployerNumber, etfEmployerNumber;
}

/// Server API for the Sri Lanka statutory payroll candidate
/// (supabase/candidates/20261120090000_lk_statutory_payroll.sql).
abstract interface class LkStatutoryPayrollRepository {
  Future<List<LkStatutoryRuleSetRecord>> ruleSets(TenantContext scope);
  Future<LkStatutoryRuleSetRecord> proposeLk(
    TenantContext scope, {
    required String id,
    required String effectiveFrom,
    required String effectiveToExclusive,
  });

  /// [action] is `approve` or `retire`. Approval needs a second person with MFA.
  Future<LkStatutoryRuleSetRecord> decide(
    TenantContext scope,
    String id,
    String action,
  );
  Future<List<LkComponentStatutoryRecord>> classifications(TenantContext scope);
  Future<void> classify(
    TenantContext scope, {
    required String id,
    required String componentId,
    required bool epfLiable,
    required bool etfLiable,
    required bool apitRegularProfit,
    required String reason,
  });
  Future<LkEmployeeStatutoryDetails?> employee(
    TenantContext scope,
    String employeeId,
  );
  Future<void> saveEmployee(
    TenantContext scope, {
    required String id,
    required String employeeId,
    required LkEmployeeStatutoryDetails details,
    required String reason,
  });
  Future<LkEmployerRegistration?> employer(TenantContext scope);
  Future<void> saveEmployer(
    TenantContext scope, {
    required String id,
    required String epfEmployerNumber,
    required String etfEmployerNumber,
    required String reason,
  });
}

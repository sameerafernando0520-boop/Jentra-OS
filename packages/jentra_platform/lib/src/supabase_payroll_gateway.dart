import 'dart:convert';

import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_domain/jentra_payroll.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Payroll never uses generic table reads. Every response is scoped and allowlisted.
final class SupabasePayrollGateway implements PayrollRepository {
  SupabasePayrollGateway(this.client);
  final SupabaseClient client;
  void _require(TenantContext scope) {
    if (!scope.hasOperationalScope ||
        client.auth.currentUser?.id != scope.actorId) {
      throw const DomainError(
        code: 'AUTHENTICATION_REQUIRED',
        message: 'Select a signed-in entity and branch.',
      );
    }
  }

  Future<Object?> _rpc(
    String name,
    TenantContext scope,
    Map<String, Object?> args, {
    bool command = false,
  }) async {
    _require(scope);
    try {
      final result = await client
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
      if (client.auth.currentUser?.id != scope.actorId) {
        throw DomainError(
          code: command ? 'UNCERTAIN_RESULT' : 'AUTHENTICATION_REQUIRED',
          message: command
              ? 'The account changed. Keep the exact saved request.'
              : 'The account changed. Select the current scope.',
          retryable: command,
        );
      }
      return result;
    } on PostgrestException catch (cause) {
      final code = switch ((cause.code, cause.message)) {
        ('PGRST202' || '42P01', _) => 'FEATURE_NOT_INSTALLED',
        ('42501', 'PEOPLE_ENTITLEMENT_REQUIRED') => 'FEATURE_NOT_ENTITLED',
        ('42501', _) => 'PERMISSION_DENIED',
        ('40001', 'PAYROLL_INPUTS_CHANGED') => 'PAYROLL_INPUTS_CHANGED',
        ('40001', _) => 'VERSION_CONFLICT',
        ('P0002', _) => 'RESOURCE_NOT_FOUND',
        ('55000', 'PERIOD_CLOSED') => 'PERIOD_CLOSED',
        ('55000', 'PAYROLL_NEGATIVE_NET') => 'PAYROLL_NEGATIVE_NET',
        ('55000', 'PAYROLL_ACTIVE_SETTLEMENT_BLOCKS_REVERSAL') =>
          'PAYROLL_ACTIVE_SETTLEMENT',
        ('55000', 'PAYROLL_SETTLEMENT_EXCEEDS_DUE') =>
          'PAYROLL_SETTLEMENT_EXCEEDS_DUE',
        ('55000', 'PAYROLL_SEPARATE_CONTROL_REQUIRED') =>
          'PAYROLL_SEPARATE_CONTROL_REQUIRED',
        (
          '55000',
          'PAYROLL_APPROVED_SOURCE_PROVIDER_REQUIRED' ||
              'PAYROLL_BANK_PROVIDER_REQUIRED' ||
              'PAYROLL_BASE_CURRENCY_PROVIDER_REQUIRED',
        ) =>
          'PROVIDER_UNAVAILABLE',
        (
          '55000',
          'PAYROLL_SOURCE_ALREADY_CONSUMED' ||
              'PAYROLL_PERIOD_ALREADY_CONSUMED',
        ) =>
          'PAYROLL_SOURCE_CONSUMED',
        ('22023', 'IDEMPOTENCY_MISMATCH') => 'IDEMPOTENCY_MISMATCH',
        ('23505' || '23P01', _) => 'IDENTITY_EXISTS',
        ('22023' || '22007' || '22008' || '22P02' || '23503' || '23514', _) =>
          'VALIDATION_ERROR',
        ('55000', _) => 'STATE_CONFLICT',
        _ => 'UNCERTAIN_RESULT',
      };
      throw DomainError(
        code: code,
        message: switch (code) {
          'FEATURE_NOT_INSTALLED' =>
            'Payroll requires its reviewed development update.',
          'FEATURE_NOT_ENTITLED' =>
            'People is not enabled on this business plan.',
          'PERMISSION_DENIED' =>
            'Current payroll permission, scope and MFA are required.',
          'PAYROLL_INPUTS_CHANGED' =>
            'Approved inputs changed. Prepare a new revision and obtain independent approval.',
          'VERSION_CONFLICT' =>
            'The record changed. Compare the current revision before replacing this request.',
          'RESOURCE_NOT_FOUND' =>
            'This payroll record is unavailable in the selected scope.',
          'PERIOD_CLOSED' => 'The posting period is closed.',
          'PAYROLL_NEGATIVE_NET' =>
            'Configured deductions exceed earned pay. Resolve the rule basis.',
          'PAYROLL_ACTIVE_SETTLEMENT' =>
            'Reverse the active recorded settlement before reversing the run.',
          'PAYROLL_SETTLEMENT_EXCEEDS_DUE' =>
            'The allocation exceeds the outstanding payroll obligation.',
          'PAYROLL_SEPARATE_CONTROL_REQUIRED' =>
            'Payroll requires a liability account distinct from supplier and customer controls.',
          'PROVIDER_UNAVAILABLE' =>
            'The required payroll source, base currency or bank mapping is unavailable.',
          'PAYROLL_SOURCE_CONSUMED' =>
            'This period or source is already consumed. Use a linked payroll correction.',
          'IDEMPOTENCY_MISMATCH' =>
            'This key belongs to different content. Keep the exact original request.',
          'IDENTITY_EXISTS' =>
            'This dated rule, source or evidence reference already exists.',
          'VALIDATION_ERROR' =>
            'Check exact amounts, dated coverage, rule basis and selected sources.',
          'STATE_CONFLICT' =>
            'This payroll transition is unavailable. Review the current evidence and history.',
          _ => 'The result is uncertain. Retry the exact encrypted request.',
        },
        retryable: code == 'UNCERTAIN_RESULT',
      );
    }
  }

  Future<Map<String, Object?>> _call(
    String name,
    TenantContext scope,
    Map<String, Object?> args, {
    bool command = false,
  }) async => workforceMap(await _rpc(name, scope, args, command: command));
  Map<String, Object?> _copy(Map<String, Object?> row) =>
      workforceMap(jsonDecode(jsonEncode(row)));
  WorkforcePage<T> _page<T>(
    Map<String, Object?> row,
    TenantContext scope,
    String? after,
    T Function(Map<String, Object?>) parse, {
    Map<String, Object?> extra = const {},
  }) {
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'items',
      'next_cursor',
      ...extra.keys,
    });
    assertPayrollScope(row, scope);
    for (final key in extra.keys) {
      if (row[key] != extra[key]) {
        throw const FormatException('Payroll page identity changed.');
      }
    }
    final raw = row['items'];
    if (raw is! List || raw.length > 50) {
      throw const FormatException('Payroll page exceeds its bound.');
    }
    var previous = after;
    final values = <T>[];
    for (final item in raw) {
      final wire = workforceMap(item), id = calendarUuid(wire['id']);
      if (previous != null && id.compareTo(previous) <= 0) {
        throw const FormatException('Payroll cursor order changed.');
      }
      previous = id;
      values.add(parse(wire));
    }
    final cursor = row['next_cursor'] == null
        ? null
        : calendarUuid(row['next_cursor']);
    if (cursor != null && (raw.length != 50 || cursor != previous)) {
      throw const FormatException('Payroll cursor is invalid.');
    }
    return WorkforcePage(List.unmodifiable(values), cursor);
  }

  @override
  Future<void> authorize(TenantContext scope, String capability) async {
    if (!payrollCapabilities.contains(capability)) {
      throw const FormatException('Payroll capability is invalid.');
    }
    final row = await _call('people_payroll_authorize', scope, {
      'p_capability': capability,
    });
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'actor_id',
      'capability',
      'authorized',
    });
    assertPayrollScope(row, scope);
    if (row['actor_id'] != scope.actorId ||
        row['capability'] != capability ||
        row['authorized'] != true) {
      throw const FormatException('Payroll authorization changed.');
    }
  }

  Future<Map<String, Object?>> _rules(TenantContext scope, String? after) =>
      _call('people_payroll_rules', scope, {'p_after': after});
  @override
  Future<WorkforcePage<Map<String, Object?>>> assignments(
    TenantContext scope,
    String employeeId, {
    String? after,
  }) async {
    calendarUuid(employeeId);
    final row = await _call('people_payroll_assignments', scope, {
      'p_employee_id': employeeId,
      'p_after': after,
    });
    return _page(row, scope, after, (wire) {
      calendarFields(wire, {
        'id',
        'employee_id',
        'component_id',
        'component_code',
        'component_name',
        'start_date',
        'end_date_exclusive',
        'reason',
        'recorded_by',
        'recorded_at',
      });
      calendarUuid(wire['id']);
      calendarUuid(wire['component_id']);
      calendarUuid(wire['recorded_by']);
      if (wire['employee_id'] != employeeId) {
        throw const FormatException('Payroll assignment employee changed.');
      }
      workforceText(wire['component_code'], 32);
      workforceText(wire['component_name'], 160);
      workforceText(wire['reason'], 1000);
      workforceRecorded(wire['recorded_at']);
      final days = CivilDate.parse(wire['end_date_exclusive'] as String).utc
          .difference(CivilDate.parse(wire['start_date'] as String).utc)
          .inDays;
      if (days < 1 || days > 1830) {
        throw const FormatException('Payroll assignment coverage changed.');
      }
      return _copy(wire);
    }, extra: {'employee_id': employeeId});
  }

  @override
  Future<Map<String, Object?>> snapshot(
    TenantContext scope,
    String calculationId,
    String section, {
    int after = 0,
  }) async {
    calendarUuid(calculationId);
    if (!{'rules', 'planned_slots'}.contains(section) ||
        after < 0 ||
        after > 2000) {
      throw const FormatException('Payroll frozen snapshot cursor is invalid.');
    }
    final row = await _call('people_payroll_snapshot', scope, {
      'p_calculation_id': calculationId,
      'p_section': section,
      'p_after': after,
    });
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'id',
      'run_id',
      'revision_id',
      'employee_id',
      'input_digest',
      'section',
      'items',
      'next_position',
    });
    assertPayrollScope(row, scope);
    if (row['id'] != calculationId || row['section'] != section) {
      throw const FormatException('Payroll frozen snapshot identity changed.');
    }
    for (final k in ['run_id', 'revision_id', 'employee_id']) {
      calendarUuid(row[k]);
    }
    payrollDigest(row['input_digest']);
    final items = row['items'];
    if (items is! List || items.length > 50) {
      throw const FormatException('Payroll frozen snapshot bound changed.');
    }
    var position = after;
    for (final v in items) {
      final item = workforceMap(v);
      calendarFields(item, {'position', 'value'});
      if (item['position'] != ++position ||
          position > (section == 'rules' ? 100 : 2000)) {
        throw const FormatException(
          'Payroll frozen snapshot ordering changed.',
        );
      }
      final value = workforceMap(item['value']);
      if (section == 'rules') {
        calendarUuid(value['assignment_id']);
        PayrollRuleVersion.fromJson({...value}..remove('assignment_id'));
      } else {
        calendarFields(value, {
          'date',
          'start_local',
          'end_local',
          'start_utc',
          'end_utc',
          'seconds',
        });
        final date = CivilDate.parse(value['date'] as String),
            start = workforceLocalTime(value['start_local']),
            end = workforceLocalTime(value['end_local']);
        final span = WorkSpan(
          workforceInstant(value['start_utc']),
          workforceInstant(value['end_utc']),
        );
        if (DateTime.utc(start.year, start.month, start.day) != date.utc ||
            !end.isAfter(start) ||
            value['seconds'] != span.seconds) {
          throw const FormatException('Payroll planned slot evidence changed.');
        }
      }
    }
    if (row['next_position'] != null &&
        (items.length != 50 || row['next_position'] != position)) {
      throw const FormatException(
        'Payroll frozen snapshot next position changed.',
      );
    }
    return _copy(row);
  }

  Map<String, Object?>? _settings(Object? raw) {
    if (raw == null) {
      return null;
    }
    final row = workforceMap(raw);
    calendarFields(row, {'id', 'version', 'net_account_id'});
    calendarUuid(row['id']);
    calendarUuid(row['net_account_id']);
    workforceInteger(row['version'], positive: true);
    return _copy(row);
  }

  @override
  Future<Map<String, Object?>?> settings(TenantContext scope) async {
    final row = await _rules(scope, null);
    assertPayrollScope(row, scope);
    _page(
      {...row}..remove('settings'),
      scope,
      null,
      PayrollRuleVersion.fromJson,
    );
    return _settings(row['settings']);
  }

  @override
  Future<WorkforcePage<PayrollRuleVersion>> rules(
    TenantContext scope, {
    String? after,
  }) async {
    if (after != null) {
      calendarUuid(after);
    }
    final row = await _rules(scope, after);
    _settings(row['settings']);
    final result = _page(
      {...row}..remove('settings'),
      scope,
      after,
      PayrollRuleVersion.fromJson,
    );
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'items',
      'next_cursor',
      'settings',
    });
    return result;
  }

  @override
  Future<WorkforcePage<PayrollRun>> runs(
    TenantContext scope, {
    String? after,
  }) async {
    final row = await _call('people_payroll_runs', scope, {'p_after': after});
    return _page(row, scope, after, (wire) {
      final run = PayrollRun.fromJson(wire);
      run.assertScope(scope);
      return run;
    });
  }

  @override
  Future<PayrollRunDetail> detail(
    TenantContext scope,
    String runId, {
    String? after,
  }) async {
    calendarUuid(runId);
    final row = await _call('people_payroll_run_detail', scope, {
      'p_run_id': runId,
      'p_after': after,
    });
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'run',
      'employee_ids',
      'calculations',
      'next_cursor',
    });
    assertPayrollScope(row, scope);
    final run = PayrollRun.fromJson(workforceMap(row['run']));
    run.assertScope(scope);
    if (run.id != runId) {
      throw const FormatException('Payroll run identity changed.');
    }
    final rawEmployees = row['employee_ids'];
    if (rawEmployees is! List ||
        rawEmployees.isEmpty ||
        rawEmployees.length > 200) {
      throw const FormatException('Payroll employee selection is invalid.');
    }
    final employees = rawEmployees.map(calendarUuid).toList();
    if (employees.toSet().length != employees.length ||
        run.employeeCount != null && run.employeeCount != employees.length) {
      throw const FormatException('Payroll employee selection changed.');
    }
    final page = _page(
      {
        'tenant_id': scope.tenantId,
        'legal_entity_id': scope.legalEntityId,
        'branch_id': scope.branchId,
        'items': row['calculations'],
        'next_cursor': row['next_cursor'],
      },
      scope,
      after,
      (wire) {
        final calc = PayrollEmployeeCalculation.fromJson(wire, run.currency);
        if (!employees.contains(calc.employeeId)) {
          throw const FormatException('Payroll employee calculation changed.');
        }
        return calc;
      },
    );
    return PayrollRunDetail(run, List.unmodifiable(employees), page);
  }

  List<PayrollExplainedLine> _lines(
    Object? raw,
    String currency,
    String? after,
    String? cursor,
  ) {
    if (raw is! List || raw.length > 50) {
      throw const FormatException('Payroll explanation page is invalid.');
    }
    var last = after;
    final ids = <String>{}, lines = <PayrollExplainedLine>[];
    for (final value in raw) {
      final line = PayrollExplainedLine.fromJson(workforceMap(value), currency);
      if (last != null && line.code.compareTo(last) <= 0 ||
          !ids.add(line.ruleId)) {
        throw const FormatException('Payroll explanation ordering changed.');
      }
      last = line.code;
      lines.add(line);
    }
    if (cursor != null && (raw.length != 50 || last != cursor)) {
      throw const FormatException('Payroll explanation cursor changed.');
    }
    return lines;
  }

  @override
  Future<Map<String, Object?>> calculation(
    TenantContext scope,
    String calculationId,
    String currency, {
    String? afterCode,
    String? sourceAfter,
  }) async {
    calendarUuid(calculationId);
    final row = await _call('people_payroll_calculation', scope, {
      'p_calculation_id': calculationId,
      'p_after_code': afterCode,
      'p_source_after': sourceAfter,
    });
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'id',
      'run_id',
      'revision_id',
      'employee_id',
      'input_digest',
      'input',
      'gross',
      'deductions',
      'employer_cost',
      'net',
      'lines',
      'sources',
      'next_code',
      'next_source',
    });
    assertPayrollScope(row, scope);
    if (row['id'] != calculationId) {
      throw const FormatException('Payroll calculation identity changed.');
    }
    for (final k in ['run_id', 'revision_id', 'employee_id']) {
      calendarUuid(row[k]);
    }
    payrollDigest(row['input_digest']);
    PayrollAmounts.fromJson(row, currency);
    _lines(row['lines'], currency, afterCode, row['next_code'] as String?);
    final input = workforceMap(row['input']);
    calendarFields(input, {
      'employee_id',
      'employee_version',
      'employee_code',
      'employee_name',
      'employment_assignment',
      'organization_assignment_id',
      'calendar_version_id',
      'timezone',
      'start_date',
      'end_date_exclusive',
      'eligible_start',
      'eligible_end_exclusive',
      'period_days',
      'eligible_days',
      'paid_seconds',
      'planned_seconds',
    });
    if (input['employee_id'] != row['employee_id']) {
      throw const FormatException('Payroll input employee changed.');
    }
    workforceInteger(input['employee_version'], positive: true);
    workforceText(input['employee_code'], 32);
    workforceText(input['employee_name'], 160);
    calendarUuid(input['organization_assignment_id']);
    calendarUuid(input['calendar_version_id']);
    workforceText(input['timezone'], 100);
    PayrollCalculationInput(
      employeeId: input['employee_id'] as String,
      start: CivilDate.parse(input['start_date'] as String),
      endExclusive: CivilDate.parse(input['end_date_exclusive'] as String),
      periodDays: workforceInteger(input['period_days'], positive: true),
      eligibleDays: workforceInteger(input['eligible_days'], positive: true),
      paidSeconds: workforceInteger(input['paid_seconds']),
      plannedSeconds: workforceInteger(input['planned_seconds']),
    );
    final assignment = workforceMap(input['employment_assignment']);
    calendarFields(assignment, {
      'id',
      'spell_id',
      'start_date',
      'end_date_exclusive',
      'type',
      'job_title',
    });
    calendarUuid(assignment['id']);
    calendarUuid(assignment['spell_id']);
    EmploymentInterval(
      assignment['start_date'] as String,
      assignment['end_date_exclusive'] as String?,
    );
    workforceText(assignment['job_title'], 160);
    if (!{
      'permanent',
      'fixed_term',
      'casual',
      'contractor',
    }.contains(assignment['type'])) {
      throw const FormatException('Payroll employment type changed.');
    }
    final start = CivilDate.parse(input['eligible_start'] as String),
        end = CivilDate.parse(input['eligible_end_exclusive'] as String);
    if (end.utc.difference(start.utc).inDays != input['eligible_days']) {
      throw const FormatException('Payroll eligible coverage changed.');
    }
    final raw = row['sources'];
    if (raw is! List || raw.length > 50) {
      throw const FormatException('Payroll source page is invalid.');
    }
    var last = sourceAfter;
    for (final v in raw) {
      final source = workforceMap(v);
      calendarFields(source, {
        'claim_id',
        'source_kind',
        'source_id',
        'source_version',
        'calendar_version_id',
        'start_utc',
        'end_utc',
        'gross_seconds',
        'break_seconds',
        'paid_seconds',
        'leave_policy_version_id',
        'leave_charge_seconds',
        'unpaid_seconds',
        'leave_effects',
      });
      final id = calendarUuid(source['claim_id']);
      if (last != null && id.compareTo(last) <= 0) {
        throw const FormatException('Payroll source order changed.');
      }
      last = id;
      calendarUuid(source['source_id']);
      calendarUuid(source['calendar_version_id']);
      workforceInteger(source['source_version'], positive: true);
      final span = WorkSpan(
        workforceInstant(source['start_utc']),
        workforceInstant(source['end_utc']),
      );
      final gross = workforceInteger(source['gross_seconds'], positive: true),
          breaks = workforceInteger(source['break_seconds']),
          paid = workforceInteger(source['paid_seconds']);
      if (span.seconds != gross ||
          breaks >= gross ||
          !{'attendance', 'leave'}.contains(source['source_kind'])) {
        throw const FormatException('Payroll source arithmetic changed.');
      }
      if (source['source_kind'] == 'attendance') {
        if (paid != gross - breaks ||
            source['leave_policy_version_id'] != null ||
            source['leave_effects'] != null ||
            source['unpaid_seconds'] != null ||
            source['leave_charge_seconds'] != null) {
          throw const FormatException('Payroll work source changed.');
        }
      } else {
        calendarUuid(source['leave_policy_version_id']);
        final charge = workforceInteger(
              source['leave_charge_seconds'],
              positive: true,
            ),
            unpaid = workforceInteger(source['unpaid_seconds']);
        if (paid != charge - unpaid || breaks != 0) {
          throw const FormatException('Payroll leave source changed.');
        }
        final effects = source['leave_effects'];
        if (effects is! List || effects.length > 2000) {
          throw const FormatException('Payroll leave effect bound changed.');
        }
        for (final value in effects) {
          final effect = workforceMap(value);
          calendarFields(effect, {'id', 'grant_id', 'seconds', 'reversal_of'});
          calendarUuid(effect['id']);
          calendarUuid(effect['grant_id']);
          final seconds = effect['seconds'];
          if (seconds is! int ||
              seconds == 0 ||
              seconds.abs() > maxExactWorkInteger) {
            throw const FormatException('Payroll leave effect is invalid.');
          }
          if (effect['reversal_of'] != null) {
            calendarUuid(effect['reversal_of']);
          }
        }
      }
    }
    if (row['next_source'] != null &&
        (raw.length != 50 || row['next_source'] != last)) {
      throw const FormatException('Payroll source cursor changed.');
    }
    return _copy(row);
  }

  @override
  Future<WorkforcePage<Map<String, Object?>>> accounts(
    TenantContext scope,
    String kind, {
    String? after,
  }) async {
    if (!{'expense', 'liability', 'bank'}.contains(kind)) {
      throw const FormatException('Payroll account kind is invalid.');
    }
    final row = await _call('people_payroll_accounts', scope, {
      'p_kind': kind,
      'p_after': after,
    });
    return _page(row, scope, after, (wire) {
      calendarFields(wire, {
        'id',
        'code',
        'name',
        'currency_code',
        'version',
        if (kind == 'bank') 'account_id',
      });
      workforceText(wire['code'], 64);
      workforceText(wire['name'], 160);
      workforceInteger(wire['version'], positive: true);
      if (wire['currency_code'] != null) {
        Money.zero(wire['currency_code'] as String);
      }
      if (kind == 'bank') {
        calendarUuid(wire['account_id']);
      }
      return _copy(wire);
    }, extra: {'kind': kind});
  }

  @override
  Future<WorkforcePage<Map<String, Object?>>> obligations(
    TenantContext scope,
    String runId, {
    String? after,
  }) async {
    calendarUuid(runId);
    final row = await _call('people_payroll_obligations', scope, {
      'p_run_id': runId,
      'p_after': after,
    });
    return _page(row, scope, after, (wire) {
      calendarFields(wire, {
        'id',
        'run_id',
        'employee_id',
        'kind',
        'currency_code',
        'amount',
        'account_id',
        'outstanding',
      });
      if (wire['run_id'] != runId ||
          !{'net', 'deduction', 'employer_cost'}.contains(wire['kind'])) {
        throw const FormatException('Payroll obligation changed.');
      }
      calendarUuid(wire['employee_id']);
      calendarUuid(wire['account_id']);
      final currency = wire['currency_code'] as String,
          amount = payrollAmount(wire['amount'] as String, currency),
          due = payrollAmount(wire['outstanding'] as String, currency);
      if (amount.minorUnits <= BigInt.zero || due.compareTo(amount) > 0) {
        throw const FormatException('Payroll obligation balance changed.');
      }
      return _copy(wire);
    }, extra: {'run_id': runId});
  }

  @override
  Future<WorkforcePage<Map<String, Object?>>> settlements(
    TenantContext scope,
    String runId, {
    String? after,
  }) async {
    final row = await _call('people_payroll_settlements', scope, {
      'p_run_id': runId,
      'p_after': after,
    });
    return _page(row, scope, after, (wire) {
      calendarFields(wire, {
        'id',
        'run_id',
        'posting_date',
        'bank_id',
        'currency_code',
        'evidence_reference',
        'version',
        'status',
        'journal_id',
        'reversal_journal_id',
        'recorded_by',
        'recorded_at',
        'amount',
      });
      if (wire['run_id'] != runId ||
          !{'recorded', 'reversed'}.contains(wire['status'])) {
        throw const FormatException('Payroll settlement state changed.');
      }
      CivilDate.parse(wire['posting_date'] as String);
      calendarUuid(wire['bank_id']);
      calendarUuid(wire['journal_id']);
      calendarUuid(wire['recorded_by']);
      workforceRecorded(wire['recorded_at']);
      workforceInteger(wire['version'], positive: true);
      workforceText(wire['evidence_reference'], 160);
      payrollAmount(wire['amount'] as String, wire['currency_code'] as String);
      if (wire['reversal_journal_id'] != null) {
        calendarUuid(wire['reversal_journal_id']);
      }
      if ((wire['status'] == 'reversed') !=
          (wire['reversal_journal_id'] != null)) {
        throw const FormatException('Payroll settlement reversal changed.');
      }
      return _copy(wire);
    }, extra: {'run_id': runId});
  }

  @override
  Future<WorkforcePage<Map<String, Object?>>> history(
    TenantContext scope,
    String runId, {
    String? after,
  }) async {
    final row = await _call('people_payroll_history', scope, {
      'p_run_id': runId,
      'p_after': after,
    });
    return _page(row, scope, after, (wire) {
      calendarFields(wire, {
        'id',
        'revision_id',
        'action',
        'version',
        'reason',
        'actor_id',
        'recorded_at',
      });
      if (wire['revision_id'] != null) {
        calendarUuid(wire['revision_id']);
      }
      workforceInteger(wire['version'], positive: true);
      workforceText(wire['reason'], 1000);
      calendarUuid(wire['actor_id']);
      workforceRecorded(wire['recorded_at']);
      if (!{
        'create',
        'prepare',
        'submit',
        'approve',
        'cancel',
        'post',
        'reverse',
      }.contains(wire['action'])) {
        throw const FormatException('Payroll history action changed.');
      }
      return _copy(wire);
    }, extra: {'run_id': runId});
  }

  void _payslip(Map<String, Object?> wire, {bool full = false}) {
    calendarFields(wire, {
      'id',
      'run_id',
      'employee_id',
      'revision_digest',
      'issued_at',
      'currency_code',
      'start_date',
      'end_date_exclusive',
      'employee_code',
      'employee_name',
      'input_digest',
      'calculation_id',
      'gross',
      'deductions',
      'employer_cost',
      'net',
      if (full) 'lines',
    });
    for (final k in ['id', 'run_id', 'employee_id', 'calculation_id']) {
      calendarUuid(wire[k]);
    }
    payrollDigest(wire['revision_digest']);
    payrollDigest(wire['input_digest']);
    workforceRecorded(wire['issued_at']);
    workforceText(wire['employee_code'], 32);
    workforceText(wire['employee_name'], 160);
    final from = CivilDate.parse(wire['start_date'] as String),
        until = CivilDate.parse(wire['end_date_exclusive'] as String),
        currency = wire['currency_code'] as String;
    if (until.utc.difference(from.utc).inDays < 1 ||
        until.utc.difference(from.utc).inDays > 366) {
      throw const FormatException('Payroll payslip period changed.');
    }
    final amounts = PayrollAmounts.fromJson(wire, currency);
    if (full) {
      final raw = wire['lines'];
      if (raw is! List || raw.isEmpty || raw.length > 100) {
        throw const FormatException('Payroll export line bound changed.');
      }
      var gross = Money.zero(currency),
          deductions = Money.zero(currency),
          cost = Money.zero(currency);
      final ids = <String>{}, codes = <String>{};
      for (final v in raw) {
        final line = PayrollExplainedLine.fromJson(workforceMap(v), currency);
        if (!ids.add(line.ruleId) || !codes.add(line.code)) {
          throw const FormatException('Payroll export line duplicated.');
        }
        if (line.classification == 'earning') {
          gross += line.amount;
        } else if (line.classification == 'deduction') {
          deductions += line.amount;
        } else {
          cost += line.amount;
        }
      }
      if (amounts.gross != gross ||
          amounts.deductions != deductions ||
          amounts.employerCost != cost) {
        throw const FormatException(
          'Payroll export totals do not reconcile to lines.',
        );
      }
    }
  }

  @override
  Future<WorkforcePage<Map<String, Object?>>> payslips(
    TenantContext scope,
    String employeeId, {
    String? after,
  }) async {
    calendarUuid(employeeId);
    final row = await _call('people_payroll_payslips', scope, {
      'p_employee_id': employeeId,
      'p_after': after,
    });
    return _page(row, scope, after, (wire) {
      _payslip(wire);
      if (wire['employee_id'] != employeeId) {
        throw const FormatException('Payslip employee changed.');
      }
      return _copy(wire);
    }, extra: {'employee_id': employeeId});
  }

  @override
  Future<WorkforcePage<Map<String, Object?>>> selfPayslips(
    TenantContext scope, {
    String? after,
  }) async {
    final row = await _call('people_payroll_self_payslips', scope, {
      'p_after': after,
    });
    final employeeId = calendarUuid(row['employee_id']);
    return _page(row, scope, after, (wire) {
      _payslip(wire);
      if (wire['employee_id'] != employeeId) {
        throw const FormatException('Self payslip employee changed.');
      }
      return _copy(wire);
    }, extra: {'employee_id': employeeId});
  }

  @override
  Future<Map<String, Object?>> payslip(
    TenantContext scope,
    String payslipId, {
    String? afterCode,
  }) async {
    final row = await _call('people_payroll_payslip', scope, {
      'p_payslip_id': payslipId,
      'p_after_code': afterCode,
    });
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'payslip',
      'lines',
      'next_code',
    });
    assertPayrollScope(row, scope);
    final slip = workforceMap(row['payslip']);
    _payslip(slip);
    if (slip['id'] != payslipId) {
      throw const FormatException('Payslip identity changed.');
    }
    _lines(
      row['lines'],
      slip['currency_code'] as String,
      afterCode,
      row['next_code'] as String?,
    );
    return _copy(row);
  }

  @override
  Future<Map<String, Object?>> exportContent(
    TenantContext scope,
    String exportId,
  ) async {
    final row = await _call('people_payroll_export_content', scope, {
      'p_export_id': exportId,
    });
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'id',
      'content_digest',
      'synthetic',
      'payslip',
    });
    assertPayrollScope(row, scope);
    if (row['id'] != exportId || row['synthetic'] != true) {
      throw const FormatException('Payroll export identity changed.');
    }
    payrollDigest(row['content_digest']);
    _payslip(workforceMap(row['payslip']), full: true);
    return _copy(row);
  }

  void _receipt(
    Map<String, Object?> row,
    TenantContext scope,
    String commandId,
  ) {
    calendarFields(row, {
      'request_id',
      'command_id',
      'correlation_id',
      'entity',
      'warnings',
    });
    calendarUuid(row['request_id']);
    calendarUuid(row['correlation_id']);
    if (row['command_id'] != commandId ||
        row['warnings'] is! List ||
        (row['warnings'] as List).isNotEmpty) {
      throw const FormatException('Payroll receipt envelope changed.');
    }
    final entity = workforceMap(row['entity']);
    assertPayrollScope(entity, scope);
    calendarUuid(entity['id']);
    workforceInteger(entity['version'], positive: true);
    const allowed = {
      'id',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'version',
      'kind',
      'component_id',
      'status',
      'name',
      'start_date',
      'end_date_exclusive',
      'posting_date',
      'currency_code',
      'current_revision_id',
      'digest',
      'employee_count',
      'prepared_by',
      'submitted_by',
      'approved_by',
      'posted_journal_id',
      'reversal_journal_id',
      'created_by',
      'run_id',
      'journal_id',
      'payslip_id',
      'content_digest',
    };
    if (entity.keys.any((k) => !allowed.contains(k)) ||
        entity.containsKey('name')) {
      throw const FormatException('Payroll receipt contains private content.');
    }
  }

  @override
  Future<Map<String, Object?>?> ownReceipt(
    TenantContext scope,
    String commandId,
    String capability,
  ) async {
    calendarUuid(commandId);
    if (!payrollCapabilities.contains(capability)) {
      throw const FormatException('Payroll capability is invalid.');
    }
    final raw = await _rpc('people_payroll_own_receipt', scope, {
      'p_command_id': commandId,
      'p_capability': capability,
    });
    if (raw == null) {
      return null;
    }
    final row = workforceMap(raw);
    _receipt(row, scope, commandId);
    final entity = workforceMap(row['entity']);
    const identity = {
      'id',
      'version',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
    };
    if (capability == 'people.payroll.configure') {
      final kind = entity['kind'];
      if (!{'settings', 'assignment', 'rule'}.contains(kind)) {
        throw const FormatException(
          'Payroll receipt configuration kind changed.',
        );
      }
      calendarFields(entity, {
        ...identity,
        'kind',
        if (kind == 'rule') 'component_id',
      });
      if (kind == 'rule') calendarUuid(entity['component_id']);
    } else if (capability == 'people.payroll.settle') {
      final status = entity['status'];
      if (!{'recorded', 'reversed'}.contains(status)) {
        throw const FormatException(
          'Payroll receipt settlement state changed.',
        );
      }
      calendarFields(entity, {
        ...identity,
        'run_id',
        'status',
        if (status == 'recorded') 'journal_id' else 'reversal_journal_id',
      });
      calendarUuid(entity['run_id']);
      calendarUuid(
        entity[status == 'recorded' ? 'journal_id' : 'reversal_journal_id'],
      );
    } else if (capability == 'people.payroll.export') {
      calendarFields(entity, {...identity, 'payslip_id', 'content_digest'});
      calendarUuid(entity['payslip_id']);
      payrollDigest(entity['content_digest']);
    } else if ({
      'people.payroll.prepare',
      'people.payroll.approve',
      'people.payroll.post',
      'people.payroll.reverse',
    }.contains(capability)) {
      final run = PayrollRun.fromJson({...entity, 'name': 'Confirmed payroll'});
      run.assertScope(scope);
      final allowed = switch (capability) {
        'people.payroll.approve' => {'approved'},
        'people.payroll.post' => {'posted'},
        'people.payroll.reverse' => {'reversed'},
        _ => {'draft', 'prepared', 'submitted', 'cancelled'},
      };
      if (!allowed.contains(run.status)) {
        throw const FormatException('Payroll receipt run state changed.');
      }
    } else {
      throw const FormatException(
        'Payroll receipt needs its original write capability.',
      );
    }
    return _copy(row);
  }

  @override
  Future<Map<String, Object?>> execute(
    PayrollCommandKind kind,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    // Snapshot before the first await. A caller cannot mutate an uncertain request.
    final payload = _copy(command.payload),
        version = command.expectedEntityVersion;
    if (version == null) {
      throw const FormatException('Payroll expected version is required.');
    }
    PayrollCommands.validate(kind, payload, version);
    calendarUuid(command.commandId);
    calendarUuid(command.idempotencyKey);
    final action = payload['action'] as String;
    final name = switch (kind) {
      PayrollCommandKind.configuration => 'people_payroll_configure',
      PayrollCommandKind.run => 'people_payroll_command',
      PayrollCommandKind.settlement => 'people_payroll_settlement',
      PayrollCommandKind.export => 'people_payroll_export',
    };
    try {
      final row = await _call(name, command.context, {
        'p_command_id': command.commandId,
        'p_idempotency_key': command.idempotencyKey,
        'p_client_timestamp': command.clientTimestamp.toIso8601String(),
        'p_payload': payload,
        'p_expected_version': version,
      }, command: true);
      _receipt(row, command.context, command.commandId);
      final entity = workforceMap(row['entity']);
      if (entity['id'] != payload['id'] || entity['version'] != version + 1) {
        throw const FormatException(
          'Payroll confirmation identity/version changed.',
        );
      }
      switch (kind) {
        case PayrollCommandKind.run:
          final status = switch (action) {
            'create' => 'draft',
            'prepare' => 'prepared',
            'submit' => 'submitted',
            'approve' => 'approved',
            'post' => 'posted',
            'reverse' => 'reversed',
            _ => 'cancelled',
          };
          final run = PayrollRun.fromJson({
            ...entity,
            'name': payload['name'] ?? 'Confirmed payroll',
          });
          run.assertScope(command.context);
          if (run.status != status ||
              action == 'create' &&
                  (run.createdBy != command.context.actorId ||
                      run.start.value != payload['start_date'] ||
                      run.endExclusive.value != payload['end_date_exclusive'] ||
                      run.postingDate.value != payload['posting_date']) ||
              {'submit', 'approve', 'post', 'reverse'}.contains(action) &&
                  (run.revisionId != payload['revision_id'] ||
                      run.digest != payload['digest']) ||
              action == 'approve' &&
                  run.approvedBy != command.context.actorId ||
              action == 'prepare' &&
                  run.preparedBy != command.context.actorId ||
              action == 'submit' &&
                  run.submittedBy != command.context.actorId) {
            throw const FormatException(
              'Payroll revision confirmation changed.',
            );
          }
        case PayrollCommandKind.configuration:
          final kindName = switch (action) {
            'publish' => 'rule',
            'assign' => 'assignment',
            _ => 'settings',
          };
          calendarFields(entity, {
            'id',
            'version',
            'kind',
            'tenant_id',
            'legal_entity_id',
            'branch_id',
            if (action == 'publish') 'component_id',
          });
          if (entity['kind'] != kindName ||
              action == 'publish' &&
                  entity['component_id'] != payload['component_id']) {
            throw const FormatException(
              'Payroll configuration confirmation changed.',
            );
          }
        case PayrollCommandKind.settlement:
          calendarFields(entity, {
            'id',
            'run_id',
            'version',
            'status',
            'tenant_id',
            'legal_entity_id',
            'branch_id',
            if (action == 'record') 'journal_id' else 'reversal_journal_id',
          });
          if (entity['run_id'] != payload['run_id'] ||
              entity['status'] !=
                  (action == 'record' ? 'recorded' : 'reversed')) {
            throw const FormatException(
              'Payroll settlement confirmation changed.',
            );
          }
          calendarUuid(
            entity[action == 'record' ? 'journal_id' : 'reversal_journal_id'],
          );
        case PayrollCommandKind.export:
          calendarFields(entity, {
            'id',
            'payslip_id',
            'content_digest',
            'tenant_id',
            'legal_entity_id',
            'branch_id',
            'version',
          });
          if (entity['payslip_id'] != payload['payslip_id']) {
            throw const FormatException('Payroll export confirmation changed.');
          }
          payrollDigest(entity['content_digest']);
      }
      return _copy(row);
    } on DomainError {
      rethrow;
    } catch (_) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'Payroll confirmation could not be verified. Keep the exact encrypted request.',
        retryable: true,
      );
    }
  }
}

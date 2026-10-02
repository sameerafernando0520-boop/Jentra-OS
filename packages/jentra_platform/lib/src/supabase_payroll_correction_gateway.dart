import 'dart:convert';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_domain/jentra_payroll.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class SupabasePayrollCorrectionGateway
    implements PayrollCorrectionRepository {
  SupabasePayrollCorrectionGateway(this.client);
  final SupabaseClient client;
  @override
  Future<WorkforcePage<Map<String, Object?>>> correctionCredits(
    TenantContext scope,
    String sourceRevisionId, {
    String? after,
  }) async {
    final response = workforceMap(
      await _rpc('projects_payroll_credit_choices', scope, {
        'p_source_revision_id': calendarUuid(sourceRevisionId),
        'p_after': after,
      }),
    );
    calendarFields(response, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'source_revision_id',
      'kind',
      'rows',
      'next_after',
    });
    if (response['source_revision_id'] != sourceRevisionId ||
        response['kind'] != 'billing_credits') {
      throw const FormatException('Credit source lineage changed.');
    }
    final page = _page(
      {...response}
        ..remove('source_revision_id')
        ..remove('kind')
        ..remove('rows')
        ..remove('next_after')
        ..addAll({
          'items': response['rows'],
          'next_cursor': response['next_after'],
        }),
      scope,
      after,
    );
    for (final row in page.items) {
      calendarFields(row, {
        'id',
        'name',
        'code',
        'version',
        'amount',
        'currency_code',
        'invoice_line_id',
        'credit_document_id',
      });
      calendarUuid(row['invoice_line_id']);
      calendarUuid(row['credit_document_id']);
      workforceInteger(row['version'], positive: true);
      workforceText(row['name'], 160);
      payrollAmount(row['amount'] as String, row['currency_code'] as String);
    }
    return page;
  }

  static const capabilities = {
    'people.payroll.view',
    'people.payroll.correction.prepare',
    'people.payroll.correction.approve',
    'people.payroll.post',
    'people.payroll.reverse',
    'people.payroll.settle',
    'people.payroll.payslip.view',
  };
  Future<Object?> _rpc(
    String name,
    TenantContext scope,
    Map<String, Object?> args, {
    bool command = false,
  }) async {
    if (!scope.hasOperationalScope ||
        client.auth.currentUser?.id != scope.actorId) {
      throw const DomainError(
        code: 'AUTHENTICATION_REQUIRED',
        message: 'Choose a signed-in entity and branch.',
      );
    }
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
          message: 'The account changed. Keep the saved request.',
          retryable: command,
        );
      }
      return result;
    } on PostgrestException catch (e) {
      final code = switch (e.code) {
        'PGRST202' || '42P01' => 'FEATURE_NOT_INSTALLED',
        '42501' => 'PERMISSION_DENIED',
        '40001' => 'VERSION_CONFLICT',
        'P0002' => 'RESOURCE_NOT_FOUND',
        '22023' || '22007' || '22008' || '22P02' || '23503' || '23514' =>
          e.message == 'IDEMPOTENCY_MISMATCH'
              ? 'IDEMPOTENCY_MISMATCH'
              : 'VALIDATION_ERROR',
        '23505' || '23P01' => 'IDENTITY_EXISTS',
        '55000' =>
          e.message.contains('PROVIDER_REQUIRED') ||
                  e.message.contains('IMPACT_REQUIRED')
              ? 'PROVIDER_UNAVAILABLE'
              : e.message == 'PERIOD_CLOSED'
              ? 'PERIOD_CLOSED'
              : 'STATE_CONFLICT',
        _ => 'UNCERTAIN_RESULT',
      };
      throw DomainError(
        code: code,
        message: switch (code) {
          'PERMISSION_DENIED' =>
            'Current correction permission, source authority and MFA are required.',
          'VERSION_CONFLICT' =>
            'The source or correction changed. Compare its current facts before replacing the request.',
          'FEATURE_NOT_INSTALLED' =>
            'Payroll corrections require the reviewed development update.',
          'PROVIDER_UNAVAILABLE' =>
            'Complete the linked source and billing impacts before applying this correction.',
          'PERIOD_CLOSED' => 'The posting period is closed.',
          'UNCERTAIN_RESULT' =>
            'Confirmation is uncertain. Retain and retry the exact saved request.',
          _ =>
            'The correction could not be applied. Review its source, state and amounts.',
        },
        retryable: code == 'UNCERTAIN_RESULT',
      );
    }
  }

  @override
  Future<void> authorize(TenantContext scope, String capability) async {
    if (!capabilities.contains(capability)) {
      throw const FormatException('Correction capability is invalid.');
    }
    final row = workforceMap(
      await _rpc('people_payroll_correction_authorize', scope, {
        'p_capability': capability,
      }),
    );
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
      throw const FormatException('Correction authorization changed.');
    }
  }

  WorkforcePage<Map<String, Object?>> _page(
    Map<String, Object?> row,
    TenantContext scope,
    String? after, {
    Set<String> extra = const {},
  }) {
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'items',
      'next_cursor',
      ...extra,
    });
    assertPayrollScope(row, scope);
    final raw = row['items'];
    if (raw is! List || raw.length > 50) {
      throw const FormatException('Correction page exceeds its bound.');
    }
    final rows = <Map<String, Object?>>[];
    String? previous = after;
    for (final value in raw) {
      final item = workforceMap(value), id = calendarUuid(item['id']);
      if (previous != null && id.compareTo(previous) <= 0) {
        throw const FormatException('Correction cursor order changed.');
      }
      for (final key in ['tenant_id', 'legal_entity_id', 'branch_id']) {
        if (item.containsKey(key) && item[key] != scope.toJson()[key]) {
          throw const FormatException('Correction row scope changed.');
        }
      }
      rows.add(Map.unmodifiable(item));
      previous = id;
    }
    final cursor = row['next_cursor'] == null
        ? null
        : calendarUuid(row['next_cursor']);
    if (cursor != null && (raw.length != 50 || cursor != previous)) {
      throw const FormatException('Correction cursor changed.');
    }
    return WorkforcePage(List.unmodifiable(rows), cursor);
  }

  @override
  Future<WorkforcePage<Map<String, Object?>>> correctionOriginals(
    TenantContext scope, {
    String? after,
  }) async => _page(
    workforceMap(
      await _rpc('people_payroll_correction_originals', scope, {
        'p_after': after,
      }),
    ),
    scope,
    after,
  );
  @override
  Future<WorkforcePage<Map<String, Object?>>> correctionSources(
    TenantContext scope,
    String calculationId, {
    String? after,
  }) async {
    final row = workforceMap(
      await _rpc('people_payroll_correction_sources', scope, {
        'p_calculation_id': calendarUuid(calculationId),
        'p_after': after,
      }),
    );
    if (row['calculation_id'] != calculationId) {
      throw const FormatException('Correction source calculation changed.');
    }
    return _page(row, scope, after, extra: {'calculation_id'});
  }

  @override
  Future<WorkforcePage<Map<String, Object?>>> corrections(
    TenantContext scope, {
    String? after,
  }) async => _page(
    workforceMap(
      await _rpc('people_payroll_corrections', scope, {'p_after': after}),
    ),
    scope,
    after,
  );
  @override
  Future<Map<String, Object?>> correctionDetail(
    TenantContext scope,
    String id,
    String section, {
    String? after,
  }) async {
    if (!{
      'calculation',
      'sources',
      'balances',
      'settlements',
      'history',
      'payslip',
    }.contains(section)) {
      throw const FormatException('Correction section is invalid.');
    }
    final row = workforceMap(
      await _rpc('people_payroll_correction_detail', scope, {
        'p_correction_id': calendarUuid(id),
        'p_section': section,
        'p_after': after,
      }),
    );
    final correction = workforceMap(row['correction']);
    assertPayrollScope(correction, scope);
    if (correction['id'] != id || row['section'] != section) {
      throw const FormatException('Correction detail changed identity.');
    }
    _page(row, scope, after, extra: {'correction', 'section'});
    return row;
  }

  Map<String, Object?> _confirmation(
    Object? value,
    TenantContext scope,
    String commandId, {
    String? id,
    int? version,
  }) {
    final row = workforceMap(value);
    calendarFields(row, {
      'request_id',
      'correlation_id',
      'command_id',
      'entity',
      'warnings',
    });
    final entity = workforceMap(row['entity']);
    final entityFields = <String>{
      'id',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'original_calculation_id',
      'employee_id',
      'original_run_id',
      'predecessor_id',
      'chain_version',
      'posting_date',
      'currency_code',
      'status',
      'version',
      'digest',
      'prepared_by',
      'approved_by',
      'posted_journal_id',
      'reversal_journal_id',
      'correction_id',
      'journal_id',
    };
    calendarFields(entity, entityFields.intersection(entity.keys.toSet()));
    assertPayrollScope(entity, scope);
    calendarUuid(entity['id']);
    workforceInteger(entity['version'], positive: true);
    calendarUuid(row['request_id']);
    calendarUuid(row['correlation_id']);
    if (entity['digest'] != null) {
      payrollDigest(entity['digest']);
    }
    if (row['warnings'] is! List || (row['warnings'] as List).isNotEmpty) {
      throw const FormatException('Unexpected correction warnings.');
    }
    if (row['command_id'] != commandId ||
        id != null && entity['id'] != id ||
        version != null && entity['version'] != version + 1) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'Correction confirmation differs from its saved identity or version.',
        retryable: true,
      );
    }
    return row;
  }

  @override
  Future<Map<String, Object?>?> ownReceipt(
    TenantContext scope,
    String commandId,
    String capability,
  ) async {
    if (!capabilities.contains(capability)) {
      throw const FormatException('Correction receipt capability is invalid.');
    }
    final actions = switch (capability) {
      'people.payroll.correction.prepare' => ['prepare'],
      'people.payroll.correction.approve' => ['approve', 'reject'],
      'people.payroll.post' => ['post'],
      'people.payroll.reverse' => ['reverse'],
      'people.payroll.settle' => ['settlement.record', 'settlement.reverse'],
      _ => throw const FormatException('Correction receipt action is invalid.'),
    };
    for (final action in actions) {
      final value = await _rpc('people_payroll_correction_own_receipt', scope, {
        'p_command_id': calendarUuid(commandId),
        'p_action': action,
      });
      if (value != null) {
        return _confirmation(value, scope, commandId);
      }
    }
    return null;
  }

  @override
  Future<Map<String, Object?>> executeCorrection(
    PayrollCorrectionCommandKind kind,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    final expected = command.expectedEntityVersion;
    if (expected == null) {
      throw const FormatException('Correction expected version is required.');
    }
    final payload = workforceMap(jsonDecode(jsonEncode(command.payload)));
    PayrollCorrectionCommands.validate(kind, payload, expected);
    final response = await _rpc(
      kind == PayrollCorrectionCommandKind.correction
          ? 'people_payroll_correction_command'
          : 'people_payroll_correction_settlement',
      command.context,
      {
        'p_command_id': command.commandId,
        'p_idempotency_key': command.idempotencyKey,
        'p_client_timestamp': command.clientTimestamp.toUtc().toIso8601String(),
        'p_payload': payload,
        'p_expected_version': expected,
      },
      command: true,
    );
    return _confirmation(
      response,
      command.context,
      command.commandId,
      id: payload['id'] as String,
      version: expected,
    );
  }
}

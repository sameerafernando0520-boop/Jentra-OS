import 'dart:convert';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_domain/jentra_projects.dart';
import 'package:jentra_domain/jentra_project_finance.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class SupabaseProjectFinanceGateway implements ProjectFinanceRepository {
  SupabaseProjectFinanceGateway(
    this.client, {
    this.timeout = const Duration(seconds: 30),
  });
  final SupabaseClient client;
  final Duration timeout;
  Future<Object?> _rpc(
    String name,
    TenantContext s,
    Map<String, Object?> p, {
    bool command = false,
  }) async {
    if (!s.hasOperationalScope || client.auth.currentUser?.id != s.actorId) {
      throw const DomainError(
        code: 'AUTHENTICATION_REQUIRED',
        message: 'Select a signed-in project scope.',
      );
    }
    try {
      final r = await client
          .schema('api')
          .rpc(
            name,
            params: {
              'p_tenant_id': s.tenantId,
              'p_legal_entity_id': s.legalEntityId,
              'p_branch_id': s.branchId,
              ...p,
            },
          )
          .timeout(timeout);
      if (client.auth.currentUser?.id != s.actorId) {
        throw DomainError(
          code: command ? 'UNCERTAIN_RESULT' : 'AUTHENTICATION_REQUIRED',
          message: 'The account changed. Reconcile the original request.',
          retryable: command,
        );
      }
      return r;
    } on PostgrestException catch (e) {
      final code = switch ((e.code, e.message)) {
        ('PGRST202', _) => 'FEATURE_NOT_INSTALLED',
        ('42501', 'PROJECT_ENTITLEMENT_REQUIRED') => 'FEATURE_NOT_ENTITLED',
        ('42501', _) => 'PERMISSION_DENIED',
        ('40001', _) => 'VERSION_CONFLICT',
        ('22023', 'IDEMPOTENCY_MISMATCH') => 'IDEMPOTENCY_MISMATCH',
        ('P0002', _) => 'RESOURCE_NOT_FOUND',
        ('55000', _) => 'STATE_CONFLICT',
        (
          '22023' ||
              '22P02' ||
              '22007' ||
              '22008' ||
              '23514' ||
              '23503' ||
              '23502',
          _,
        ) =>
          'VALIDATION_ERROR',
        ('23505', _) => 'IDENTITY_EXISTS',
        _ => command ? 'UNCERTAIN_RESULT' : 'SERVICE_UNAVAILABLE',
      };
      throw DomainError(
        code: code,
        message: switch (code) {
          'FEATURE_NOT_INSTALLED' =>
            'Project finance is awaiting development installation.',
          'FEATURE_NOT_ENTITLED' =>
            'The current plan does not provide project finance.',
          'PERMISSION_DENIED' =>
            'Current scope, capability or MFA does not allow this action.',
          'VERSION_CONFLICT' =>
            'The original source changed. Compare its current version.',
          'STATE_CONFLICT' =>
            'The expense, obligation or invoice state prevents this action.',
          'VALIDATION_ERROR' =>
            'Check exact amounts, dates and named source evidence.',
          'IDEMPOTENCY_MISMATCH' =>
            'Reconcile the original request associated with this key.',
          'RESOURCE_NOT_FOUND' =>
            'The source is unavailable in this project scope.',
          'IDENTITY_EXISTS' => 'This immutable source identity already exists.',
          _ =>
            command
                ? 'The result is uncertain. Reconcile the exact encrypted request.'
                : 'Project finance is unavailable. Retry the scoped read.',
        },
        retryable: code == 'UNCERTAIN_RESULT' || code == 'SERVICE_UNAVAILABLE',
      );
    } on DomainError {
      rethrow;
    } catch (_) {
      throw DomainError(
        code: command ? 'UNCERTAIN_RESULT' : 'SERVICE_UNAVAILABLE',
        message: command
            ? 'The result is uncertain. Reconcile the exact encrypted request.'
            : 'Project finance is unavailable.',
        retryable: true,
      );
    }
  }

  @override
  Future<void> authorize(TenantContext s, String capability) async {
    if (!{
      'projects.cost.view',
      'projects.expenses.manage',
      'projects.expenses.approve',
      'projects.expenses.post',
      'projects.expenses.settle',
      'projects.billing.manage',
      'projects.margin.view',
    }.contains(capability)) {
      throw const FormatException('Invalid finance capability.');
    }
    final r = projectMap(
      await _rpc('projects_finance_authorize', s, {'p_capability': capability}),
    );
    calendarFields(r, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'actor_id',
      'capability',
      'authorized',
      'supplier_ap_available',
      'attachments_available',
      'sales_available',
    });
    projectScope(r, s);
    if (r['actor_id'] != s.actorId ||
        r['capability'] != capability ||
        r['authorized'] != true ||
        r['supplier_ap_available'] != false ||
        r['attachments_available'] != false ||
        r['sales_available'] != true) {
      throw const FormatException('Finance provider authorization changed.');
    }
  }

  ProjectFinancePage<T> _page<T>(
    Map<String, Object?> r,
    String? after,
    String Function(T) id,
    T Function(Map<String, Object?>) read,
  ) {
    final rows = r['rows'];
    if (rows is! List || rows.length > 50) {
      throw const FormatException('Invalid finance page.');
    }
    final List<T> values;
    try {
      values = rows.map((v) => read(projectMap(v))).toList();
    } catch (_) {
      throw const FormatException('Finance page projection is invalid.');
    }
    String? last = after;
    for (final row in values) {
      final next = id(row);
      if (last != null && next.compareTo(last) <= 0) {
        throw const FormatException('Finance page order changed.');
      }
      last = next;
    }
    final next = projectOptionalIdentity(r['next_after']);
    if (next != null && (values.length != 50 || next != last)) {
      throw const FormatException('Finance continuation changed.');
    }
    return ProjectFinancePage(List.unmodifiable(values), next);
  }

  @override
  Future<ProjectFinancePage<ProjectFinanceRow>> detail(
    TenantContext s,
    String projectId,
    String currency,
    ProjectFinanceSection section, {
    String? after,
    String? targetId,
  }) async {
    projectIdentity(projectId);
    projectOptionalIdentity(after);
    projectOptionalIdentity(targetId);
    final r = projectMap(
      await _rpc('projects_finance_detail', s, {
        'p_project_id': projectId,
        'p_kind': section.name,
        'p_after': after,
        'p_target_id': targetId,
      }),
    );
    calendarFields(r, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'project_id',
      'kind',
      'rows',
      'next_after',
    });
    projectScope(r, s);
    if (r['project_id'] != projectId || r['kind'] != section.name) {
      throw const FormatException('Finance project ownership changed.');
    }
    return _page(r, after, (v) => v.id, (j) {
      if (section == ProjectFinanceSection.expenses) {
        projectScope(j, s);
        if (j['project_id'] != projectId) {
          throw const FormatException('Expense project changed.');
        }
      }
      final v = ProjectFinanceRow.fromJson(section, j, currency);
      if (targetId != null && v.id != targetId) {
        throw const FormatException('Finance target changed.');
      }
      return v;
    });
  }

  @override
  Future<ProjectFinancePage<ProjectFinanceChoice>> choices(
    TenantContext s,
    String kind, {
    String? after,
    String? projectId,
  }) async {
    if (!{
      'employees',
      'expense_accounts',
      'tax_accounts',
      'liability_accounts',
      'banks',
      'products',
      'input_tax',
      'output_tax',
      'rates',
      'tasks',
      'service_sources',
    }.contains(kind)) {
      throw const FormatException('Unknown finance picker.');
    }
    projectOptionalIdentity(after);
    projectOptionalIdentity(projectId);
    final r = projectMap(
      await _rpc('projects_finance_pickers', s, {
        'p_kind': kind,
        'p_after': after,
        'p_project_id': projectId,
      }),
    );
    calendarFields(r, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'kind',
      'rows',
      'next_after',
    });
    projectScope(r, s);
    if (r['kind'] != kind) {
      throw const FormatException('Finance picker changed.');
    }
    return _page(r, after, (v) => v.id, ProjectFinanceChoice.fromJson);
  }

  @override
  Future<ProjectMargin> margin(
    TenantContext s,
    String projectId,
    DateTime asOf,
    CivilDate effectiveDate,
  ) async {
    projectIdentity(projectId);
    final utc = asOf.toUtc();
    final r = projectMap(
      await _rpc('projects_margin', s, {
        'p_project_id': projectId,
        'p_as_of': utc.toIso8601String(),
        'p_effective_date': effectiveDate.value,
      }),
    );
    projectScope(r, s);
    final result = ProjectMargin.fromJson(r);
    if (r['project_id'] != projectId ||
        result.asOf.toUtc() != utc ||
        result.effectiveDate.value != effectiveDate.value) {
      throw const FormatException('Margin date or ownership changed.');
    }
    return result;
  }

  Map<String, Object?> _receipt(
    Map<String, Object?> r,
    TenantContext s, {
    String? commandId,
    String? action,
    Map<String, Object?>? payload,
    int? version,
  }) {
    calendarFields(r, {
      'request_id',
      'command_id',
      'correlation_id',
      'entity',
      'warnings',
    });
    for (final k in ['request_id', 'command_id', 'correlation_id']) {
      projectIdentity(r[k]);
    }
    final entity = projectMap(r['entity']);
    const allowedEntity = {
      'id',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'project_id',
      'employee_id',
      'version',
      'status',
      'revision_id',
      'journal_id',
      'invoice_id',
    };
    if (!entity.keys.toSet().containsAll({
          'id',
          'tenant_id',
          'legal_entity_id',
          'branch_id',
          'project_id',
          'version',
          'status',
        }) ||
        entity.keys.any((key) => !allowedEntity.contains(key))) {
      throw const FormatException('Finance receipt fields changed.');
    }
    projectScope(entity, s);
    projectIdentity(entity['id']);
    projectIdentity(entity['project_id']);
    workforceInteger(entity['version'], positive: true);
    final allowedStatus = switch (action) {
      'expense_create' || 'expense_correct' => {'draft'},
      'expense_submit' => {'submitted'},
      'expense_approve' => {'approved'},
      'expense_reject' => {'rejected'},
      'expense_cancel' || 'billing_cancel' => {'cancelled'},
      'expense_post' || 'billing_post' => {'posted'},
      'expense_reverse' || 'settlement_reverse' => {'reversed'},
      'settle' => {'recorded'},
      'service_source' => {'available'},
      'billing_prepare' || 'billing_submit' || 'billing_decide' => {'prepared'},
      _ => <String>{},
    };
    projectState(entity['status'], allowedStatus);
    for (final k in [
      'employee_id',
      'revision_id',
      'journal_id',
      'invoice_id',
    ]) {
      if (entity.containsKey(k)) {
        projectIdentity(entity[k]);
      }
    }
    if (commandId != null && r['command_id'] != commandId ||
        r['warnings'] is! List ||
        (r['warnings'] as List).isNotEmpty) {
      throw const FormatException('Finance receipt changed.');
    }
    if (payload != null &&
        (entity['id'] != payload['id'] ||
            entity['project_id'] != payload['project_id'] ||
            entity['version'] != version! + 1)) {
      throw const FormatException('Finance confirmation changed.');
    }
    if (payload != null &&
        action == 'billing_prepare' &&
        entity['invoice_id'] != payload['invoice_id']) {
      throw const FormatException('Finance invoice confirmation changed.');
    }
    return r;
  }

  @override
  Future<Map<String, Object?>> command(
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    final p = projectMap(jsonDecode(jsonEncode(c.payload)));
    final a = p['action'] as String;
    validateProjectFinanceCommand(a, p);
    projectIdentity(c.commandId);
    projectIdentity(c.idempotencyKey);
    if (c.expectedEntityVersion == null ||
        c.expectedEntityVersion! < 0 ||
        c.expectedEntityVersion! >= 9007199254740991) {
      throw const FormatException('Expected finance version invalid.');
    }
    final r = await _rpc('projects_finance_command', c.context, {
      'p_command_id': c.commandId,
      'p_idempotency_key': c.idempotencyKey,
      'p_issued_at': c.clientTimestamp.toUtc().toIso8601String(),
      'p_payload': p,
      'p_expected_version': c.expectedEntityVersion,
    }, command: true);
    try {
      return _receipt(
        projectMap(r),
        c.context,
        commandId: c.commandId,
        action: a,
        payload: p,
        version: c.expectedEntityVersion,
      );
    } catch (_) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'The receipt does not match the original finance request.',
        retryable: true,
      );
    }
  }

  @override
  Future<Map<String, Object?>?> receipt(
    TenantContext s,
    String commandId,
    String action,
  ) async {
    projectIdentity(commandId);
    projectFinanceCapability(action);
    final r = await _rpc('projects_finance_own_receipt', s, {
      'p_command_id': commandId,
      'p_action': action,
    });
    return r == null
        ? null
        : _receipt(projectMap(r), s, commandId: commandId, action: action);
  }
}

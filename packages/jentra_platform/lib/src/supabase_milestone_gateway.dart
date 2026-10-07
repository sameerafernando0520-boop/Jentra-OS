import 'dart:async';
import 'dart:convert';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_domain/jentra_projects.dart';
import 'package:jentra_domain/jentra_milestones.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_projects_gateway.dart';

final class SupabaseMilestoneGateway implements MilestoneRepository {
  SupabaseMilestoneGateway(
    this.client, {
    this.timeout = const Duration(seconds: 30),
  }) : projects = SupabaseProjectGateway(client, timeout: timeout);
  final SupabaseClient client;
  final Duration timeout;
  @override
  final ProjectRepository projects;
  @override
  Future<void> authorize(TenantContext scope, String capability) async {
    if (!{
      'projects.view',
      'projects.manage',
      'projects.approve',
    }.contains(capability)) {
      throw const FormatException('Milestone capability is invalid.');
    }
    await projects.authorize(scope, capability);
  }

  Future<Object?> _rpc(
    String name,
    TenantContext s,
    Map<String, Object?> args, {
    bool command = false,
  }) async {
    if (!s.hasOperationalScope || client.auth.currentUser?.id != s.actorId) {
      throw const DomainError(
        code: 'AUTHENTICATION_REQUIRED',
        message: 'Select a signed-in entity and branch.',
      );
    }
    try {
      final result = await client
          .schema('api')
          .rpc(
            name,
            params: {
              'p_tenant_id': s.tenantId,
              'p_legal_entity_id': s.legalEntityId,
              'p_branch_id': s.branchId,
              ...args,
            },
          )
          .timeout(timeout);
      // A known command result still needs durable original-scope acknowledgement.
      if (!command && client.auth.currentUser?.id != s.actorId) {
        throw const DomainError(
          code: 'AUTHENTICATION_REQUIRED',
          message: 'The signed-in account changed.',
        );
      }
      return result;
    } on PostgrestException catch (e) {
      final code = switch ((e.code, e.message)) {
        ('PGRST202', _) => 'FEATURE_NOT_INSTALLED',
        ('42501', 'PROJECT_ENTITLEMENT_REQUIRED') => 'FEATURE_NOT_ENTITLED',
        ('42501', _) => 'PERMISSION_DENIED',
        ('40001', _) => 'VERSION_CONFLICT',
        ('22023', 'IDEMPOTENCY_MISMATCH') => 'IDEMPOTENCY_MISMATCH',
        ('55000', 'MILESTONE_BILLING_IMPACT_REQUIRED') =>
          'MILESTONE_BILLING_IMPACT_REQUIRED',
        ('55000', _) => 'STATE_CONFLICT',
        ('P0002', _) => 'RESOURCE_NOT_FOUND',
        ('23505', _) => 'IDENTITY_EXISTS',
        (
          '22023' ||
              '22007' ||
              '22008' ||
              '22P02' ||
              '23514' ||
              '23503' ||
              '23502',
          _,
        ) =>
          'VALIDATION_ERROR',
        _ => command ? 'UNCERTAIN_RESULT' : 'SERVICE_UNAVAILABLE',
      };
      throw DomainError(
        code: code,
        message: switch (code) {
          'FEATURE_NOT_INSTALLED' =>
            'Milestones are awaiting reviewed development installation.',
          'FEATURE_NOT_ENTITLED' =>
            'Projects are unavailable under the current workspace plan.',
          'PERMISSION_DENIED' =>
            'Current scope, capability and MFA are required.',
          'VERSION_CONFLICT' =>
            'The milestone changed. Compare its current revision.',
          'MILESTONE_BILLING_IMPACT_REQUIRED' =>
            'A reserved or consumed invoice source requires a governed finance impact.',
          'STATE_CONFLICT' =>
            'Check the current approved plan, completed task and milestone lifecycle.',
          'VALIDATION_ERROR' =>
            'Check the named sources, exact amount, dated owner and payment terms.',
          'IDEMPOTENCY_MISMATCH' =>
            'Reconcile the exact original saved request.',
          'IDENTITY_EXISTS' => 'This milestone identity already exists.',
          'RESOURCE_NOT_FOUND' =>
            'This milestone is unavailable in the selected scope.',
          _ =>
            command
                ? 'The result is uncertain. Reconcile the exact encrypted request.'
                : 'Milestones are unavailable. Retry the scoped read.',
        },
        retryable: {'UNCERTAIN_RESULT', 'SERVICE_UNAVAILABLE'}.contains(code),
      );
    } on DomainError {
      rethrow;
    } catch (_) {
      throw DomainError(
        code: command ? 'UNCERTAIN_RESULT' : 'SERVICE_UNAVAILABLE',
        message: command
            ? 'The result is uncertain. Reconcile the exact encrypted request.'
            : 'Milestones are unavailable.',
        retryable: true,
      );
    }
  }

  ProjectPage<T> _page<T>(
    Object? rows,
    Object? next,
    String? after,
    T Function(Map<String, Object?>) parse,
    String Function(T) id,
  ) {
    if (rows is! List || rows.length > 50) {
      throw const FormatException('Milestone page exceeds its bound.');
    }
    final out = <T>[];
    String? previous = after;
    for (final raw in rows) {
      final value = parse(milestoneMap(raw)), key = id(value);
      if (previous != null && key.compareTo(previous) <= 0) {
        throw const FormatException('Milestone cursor order changed.');
      }
      previous = key;
      out.add(value);
    }
    final cursor = projectOptionalIdentity(next);
    if (cursor != null && (out.length != 50 || cursor != previous)) {
      throw const FormatException('Milestone cursor changed.');
    }
    return ProjectPage(out, cursor);
  }

  @override
  Future<ProjectPage<MilestoneRecord>> list(
    TenantContext scope,
    String project, {
    String? after,
  }) async {
    projectIdentity(project);
    projectOptionalIdentity(after);
    final r = milestoneMap(
      await _rpc('project_milestones', scope, {
        'p_project_id': project,
        'p_after': after,
      }),
    );
    calendarFields(r, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'project_id',
      'items',
      'next_after',
    });
    projectScope(r, scope);
    if (r['project_id'] != project) {
      throw const FormatException('Milestone project changed.');
    }
    return _page(
      r['items'],
      r['next_after'],
      after,
      (x) => MilestoneRecord.fromJson(x, scope, project),
      (x) => x.id,
    );
  }

  @override
  Future<MilestoneDetail> detail(
    TenantContext scope,
    String project,
    String id, {
    String kind = 'events',
    String? after,
  }) async {
    projectIdentity(project);
    projectIdentity(id);
    projectOptionalIdentity(after);
    if (!{'events', 'revisions'}.contains(kind)) {
      throw const FormatException('Unknown milestone history.');
    }
    final r = milestoneMap(
      await _rpc('project_milestone_detail', scope, {
        'p_project_id': project,
        'p_id': id,
        'p_after': after,
        'p_kind': kind,
      }),
    );
    calendarFields(r, {'record', 'kind', 'rows', 'next_after'});
    final record = MilestoneRecord.fromJson(
      milestoneMap(r['record']),
      scope,
      project,
    );
    if (record.id != id || r['kind'] != kind) {
      throw const FormatException('Milestone history identity changed.');
    }
    final page = _page(
      r['rows'],
      r['next_after'],
      after,
      (x) => MilestoneHistory.fromJson(x, scope, project, id, kind),
      (x) => x.id,
    );
    return MilestoneDetail(record, kind, page.rows, page.next);
  }

  @override
  Future<Map<String, Object?>> execute(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    final c = CommandEnvelope<Map<String, Object?>>(
      commandId: command.commandId,
      idempotencyKey: command.idempotencyKey,
      context: command.context,
      payload: milestoneMap(jsonDecode(jsonEncode(command.payload))),
      expectedEntityVersion: command.expectedEntityVersion,
      clientTimestamp: command.clientTimestamp,
    );
    MilestoneCommands.validate(c.payload['action'] as String, c.payload);
    if (c.expectedEntityVersion == null ||
        c.expectedEntityVersion! < 0 ||
        c.expectedEntityVersion! >= 9007199254740990) {
      throw const FormatException('Milestone command version is invalid.');
    }
    final raw = await _rpc('project_milestone_command', c.context, {
      'p_command_id': c.commandId,
      'p_idempotency_key': c.idempotencyKey,
      'p_issued_at': c.clientTimestamp.toIso8601String(),
      'p_payload': c.payload,
      'p_expected_version': c.expectedEntityVersion,
    }, command: true);
    try {
      return milestoneReceipt(
        raw,
        c.context,
        c.payload['project_id'] as String,
        request: c,
      );
    } catch (_) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'The confirmation differs from the original saved request.',
        retryable: true,
      );
    }
  }

  @override
  Future<Map<String, Object?>?> ownReceipt(
    TenantContext scope,
    String project,
    String action,
    String key,
  ) async {
    projectIdentity(project);
    projectIdentity(key);
    MilestoneCommands.capability(action);
    final raw = await _rpc('project_milestone_own_receipt', scope, {
      'p_project_id': project,
      'p_action': action,
      'p_idempotency_key': key,
    });
    return raw == null ? null : milestoneReceipt(raw, scope, project);
  }
}

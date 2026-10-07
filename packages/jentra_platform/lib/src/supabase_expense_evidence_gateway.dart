import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_domain/jentra_expense_evidence.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class SupabaseExpenseEvidenceGateway
    implements ExpenseEvidenceRepository {
  SupabaseExpenseEvidenceGateway(this.client);
  final SupabaseClient client;
  void _require(TenantContext scope) {
    if (!scope.hasOperationalScope ||
        client.auth.currentUser?.id != scope.actorId) {
      throw const DomainError(
        code: 'AUTHENTICATION_REQUIRED',
        message: 'Select a signed-in entity and branch.',
      );
    }
    calendarUuid(scope.tenantId);
    calendarUuid(scope.legalEntityId);
    calendarUuid(scope.branchId);
  }

  Map<String, Object?> _scope(TenantContext s) => {
    'p_tenant_id': s.tenantId,
    'p_legal_entity_id': s.legalEntityId,
    'p_branch_id': s.branchId,
  };
  DomainError _error(String? db, String? safe) {
    final code = switch ((db, safe)) {
      ('PGRST202', _) => 'FEATURE_NOT_INSTALLED',
      ('42501', _) => 'PERMISSION_DENIED',
      ('40001', _) => 'VERSION_CONFLICT',
      ('22023', 'IDEMPOTENCY_MISMATCH') => 'IDEMPOTENCY_MISMATCH',
      (
        '55000',
        'EXPENSE_RETENTION_WORKER_UNAVAILABLE' ||
            'EXPENSE_RETENTION_POLICY_REQUIRED',
      ) =>
        'EVIDENCE_UNAVAILABLE',
      ('55000', 'EXPENSE_EVIDENCE_CONTENT_UNAVAILABLE') =>
        'EVIDENCE_CONTENT_UNAVAILABLE',
      ('55000', 'EXPENSE_FINANCIAL_RETENTION_REQUIRED') =>
        'FINANCIAL_RETENTION_REQUIRED',
      ('55000', 'EXPENSE_EVIDENCE_VERIFICATION_REQUIRED') =>
        'EVIDENCE_VERIFICATION_REQUIRED',
      ('22023' || '23503' || '23514' || '23505' || '54000', _) =>
        'VALIDATION_ERROR',
      _ => 'UNCERTAIN_RESULT',
    };
    return DomainError(
      code: code,
      message: switch (code) {
        'FEATURE_NOT_INSTALLED' =>
          'Protected expense evidence needs the reviewed development update.',
        'PERMISSION_DENIED' =>
          'Current attachment, private cost and scoped MFA authority are required.',
        'VERSION_CONFLICT' =>
          'Evidence changed. Compare the current source before submitting a new request.',
        'IDEMPOTENCY_MISMATCH' =>
          'The saved request identity belongs to different content.',
        'EVIDENCE_UNAVAILABLE' =>
          'Evidence delivery is unavailable until its retention policy and private worker are verified.',
        'EVIDENCE_CONTENT_UNAVAILABLE' =>
          'Document bytes are no longer available under the retention policy.',
        'FINANCIAL_RETENTION_REQUIRED' =>
          'Financial evidence must remain retained until the expense is terminal.',
        'EVIDENCE_VERIFICATION_REQUIRED' =>
          'Choose and verify the exact reserved file before completion.',
        'VALIDATION_ERROR' =>
          'Check the bounded evidence fields and identities.',
        _ =>
          'Confirmation is uncertain. Preserve and retry the exact encrypted request.',
      },
    );
  }

  Future<Object?> _rpc(
    String name,
    TenantContext s,
    Map<String, Object?> args,
  ) async {
    _require(s);
    try {
      final raw = await client
          .schema('api')
          .rpc(name, params: {..._scope(s), ...args});
      _require(s);
      return raw;
    } on PostgrestException catch (e) {
      throw _error(e.code, e.message);
    }
  }

  void _responseScope(
    Map<String, Object?> row,
    TenantContext s,
    Set<String> extra,
  ) {
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      ...extra,
    });
    if (row['tenant_id'] != s.tenantId ||
        row['legal_entity_id'] != s.legalEntityId ||
        row['branch_id'] != s.branchId) {
      throw const FormatException(
        'Evidence response belongs to another scope.',
      );
    }
  }

  @override
  Future<bool> authorize(
    TenantContext s,
    String? project,
    String? expense,
    String capability,
  ) async {
    if (!{
          expenseEvidenceView,
          expenseEvidenceExport,
          expenseEvidenceRetention,
          expenseEvidenceManage,
        }.contains(capability) ||
        (project == null) != (expense == null)) {
      throw const FormatException('Evidence access scope is invalid.');
    }
    if (project != null) {
      calendarUuid(project);
      calendarUuid(expense);
    }
    final row = workforceMap(
      await _rpc('projects_expense_evidence_access', s, {
        'p_project_id': project,
        'p_expense_id': expense,
        'p_capability': capability,
      }),
    );
    _responseScope(row, s, {
      'project_id',
      'expense_id',
      'actor_id',
      'authorized',
      'available',
    });
    if (row['project_id'] != project ||
        row['expense_id'] != expense ||
        row['actor_id'] != s.actorId ||
        row['authorized'] != true ||
        row['available'] is! bool) {
      throw const FormatException('Evidence access confirmation is invalid.');
    }
    return row['available'] as bool;
  }

  @override
  Future<ExpenseEvidencePage> documents(
    TenantContext s,
    String project,
    String expense, {
    String? after,
  }) async {
    calendarUuid(project);
    calendarUuid(expense);
    if (after != null) calendarUuid(after);
    final row = workforceMap(
      await _rpc('projects_expense_evidence_list', s, {
        'p_project_id': project,
        'p_expense_id': expense,
        'p_after': after,
      }),
    );
    _responseScope(row, s, {'project_id', 'expense_id', 'items', 'next_after'});
    if (row['project_id'] != project ||
        row['expense_id'] != expense ||
        row['items'] is! List ||
        (row['items'] as List).length > 50) {
      throw const FormatException('Evidence metadata page is invalid.');
    }
    final items = (row['items'] as List)
        .map((x) => ExpenseEvidenceDocument.fromJson(workforceMap(x)))
        .toList();
    var previous = after;
    for (final doc in items) {
      if (previous != null && doc.id.compareTo(previous) <= 0) {
        throw const FormatException('Evidence cursor order is invalid.');
      }
      previous = doc.id;
    }
    final next = row['next_after'] == null
        ? null
        : calendarUuid(row['next_after']);
    if (next != null && (items.length != 50 || next != items.last.id)) {
      throw const FormatException('Evidence continuation is invalid.');
    }
    return ExpenseEvidencePage(List.unmodifiable(items), next);
  }

  CommandEnvelope<Map<String, Object?>> _snapshot(
    CommandEnvelope<Map<String, Object?>> input,
  ) {
    _require(input.context);
    calendarUuid(input.commandId);
    calendarUuid(input.idempotencyKey);
    final version = input.expectedEntityVersion;
    if (version == null || version < 0 || version >= 9007199254740991) {
      throw const FormatException('Evidence version is invalid.');
    }
    return CommandEnvelope(
      commandId: input.commandId,
      idempotencyKey: input.idempotencyKey,
      context: input.context,
      clientTimestamp: input.clientTimestamp,
      expectedEntityVersion: version,
      payload: ExpenseEvidenceCommands.validate(input.payload),
    );
  }

  ExpenseEvidenceConfirmation _confirmation(
    Object? raw,
    CommandEnvelope<Map<String, Object?>> input,
  ) {
    final result = ExpenseEvidenceConfirmation.fromJson(workforceMap(raw));
    final e = result.entity;
    _responseScope(e, input.context, {
      'id',
      'version',
      'action',
      if (e['action'] != 'policy_create') ...{
        'digest',
        'record_version',
        'status',
        'project_id',
        'expense_id',
      },
    });
    if (result.commandId != input.commandId ||
        e['id'] != input.payload['id'] ||
        e['action'] != input.payload['action'] ||
        e['project_id'] != input.payload['project_id'] ||
        e['expense_id'] != input.payload['expense_id'] ||
        result.recordVersion != input.expectedEntityVersion! + 1) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Evidence confirmation did not match the exact saved request.',
      );
    }
    return result;
  }

  @override
  Future<ExpenseEvidenceConfirmation> command(
    CommandEnvelope<Map<String, Object?>> input,
  ) async {
    final c = _snapshot(input);
    return _confirmation(
      await _rpc('projects_expense_evidence_command', c.context, {
        'p_command_id': c.commandId,
        'p_idempotency_key': c.idempotencyKey,
        'p_issued_at': c.clientTimestamp.toIso8601String(),
        'p_payload': c.payload,
        'p_expected_version': c.expectedEntityVersion,
      }),
      c,
    );
  }

  @override
  Future<ExpenseEvidenceConfirmation?> receipt(
    TenantContext s,
    String commandId,
  ) async {
    calendarUuid(commandId);
    final raw = await _rpc('projects_expense_evidence_own_receipt', s, {
      'p_command_id': commandId,
    });
    if (raw == null) return null;
    final result = ExpenseEvidenceConfirmation.fromJson(workforceMap(raw));
    _responseScope(result.entity, s, {
      'id',
      'version',
      'action',
      if (result.entity['action'] != 'policy_create') ...{
        'digest',
        'record_version',
        'status',
        'project_id',
        'expense_id',
      },
    });
    if (result.commandId != commandId) {
      throw const FormatException(
        'Evidence receipt belongs to another request.',
      );
    }
    return result;
  }

  Future<String> _checksum(Uint8List bytes) async => (await Sha256().hash(
    bytes,
  )).bytes.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  Map<String, Object?> _metadata(
    TenantContext s,
    String project,
    String expense,
    String document,
    String operation,
  ) {
    _require(s);
    calendarUuid(project);
    calendarUuid(expense);
    calendarUuid(document);
    return {
      'tenant_id': s.tenantId,
      'legal_entity_id': s.legalEntityId,
      'branch_id': s.branchId,
      'project_id': project,
      'expense_id': expense,
      'document_id': document,
      'operation': operation,
    };
  }

  Future<Object?> _edge(
    TenantContext s,
    Map<String, Object?> metadata, {
    Uint8List? bytes,
    String? mime,
  }) async {
    _require(s);
    try {
      final response = await client.functions.invoke(
        'expense-private-documents',
        headers: {
          'x-jentra-expense-request': base64Encode(
            utf8.encode(jsonEncode(metadata)),
          ),
          'Content-Type': ?mime,
        },
        body: bytes,
      );
      _require(s);
      return response.data;
    } on FunctionException catch (e) {
      final safe = e.details is Map
          ? (e.details as Map)['code'] as String?
          : null;
      if (e.status == 401 || e.status == 403) throw _error('42501', null);
      if (safe == 'VERSION_CONFLICT') throw _error('40001', null);
      if ({
        'EXPENSE_RETENTION_WORKER_UNAVAILABLE',
        'EXPENSE_RETENTION_POLICY_REQUIRED',
        'EXPENSE_EVIDENCE_CONTENT_UNAVAILABLE',
        'EXPENSE_EVIDENCE_VERIFICATION_REQUIRED',
      }.contains(safe)) {
        throw _error('55000', safe);
      }
      if (e.status == 400 ||
          e.status == 413 ||
          safe == 'EXPENSE_EVIDENCE_BYTES_MISMATCH') {
        throw _error('22023', null);
      }
      throw _error(null, null);
    }
  }

  @override
  Future<ExpenseEvidenceConfirmation> upload(
    CommandEnvelope<Map<String, Object?>> input,
    ExpenseEvidenceDocument doc,
    Uint8List bytes,
  ) async {
    final c = _snapshot(input);
    final frozen = Uint8List.fromList(bytes);
    if (c.payload['action'] != 'complete' ||
        c.payload['id'] != doc.id ||
        c.expectedEntityVersion != doc.recordVersion ||
        !{'reserved', 'verified', 'active'}.contains(doc.status) ||
        frozen.length != doc.byteSize ||
        await _checksum(frozen) != doc.checksum) {
      throw const FormatException(
        'Choose the exact reserved file for the saved completion.',
      );
    }
    _require(c.context);
    final metadata =
        _metadata(
            c.context,
            c.payload['project_id'] as String,
            c.payload['expense_id'] as String,
            doc.id,
            'upload',
          )
          ..['completion'] = {
            'command_id': c.commandId,
            'idempotency_key': c.idempotencyKey,
            'issued_at': c.clientTimestamp.toIso8601String(),
            'expected_version': c.expectedEntityVersion,
          };
    return _confirmation(
      await _edge(c.context, metadata, bytes: frozen, mime: doc.mime),
      c,
    );
  }

  @override
  Future<Uint8List> document(
    TenantContext s,
    String project,
    String expense,
    ExpenseEvidenceDocument doc, {
    bool export = false,
  }) async {
    if (!doc.isActive) {
      throw const FormatException('Evidence bytes are no longer active.');
    }
    final raw = await _edge(
      s,
      _metadata(s, project, expense, doc.id, export ? 'export' : 'download'),
    );
    if (raw is! Uint8List ||
        raw.length != doc.byteSize ||
        await _checksum(raw) != doc.checksum) {
      throw const FormatException('Evidence bytes failed verification.');
    }
    _require(s);
    return Uint8List.fromList(raw);
  }
}

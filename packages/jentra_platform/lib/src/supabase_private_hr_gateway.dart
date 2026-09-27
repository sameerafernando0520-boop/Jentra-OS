import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class SupabasePrivateHrGateway implements HrRepository {
  SupabasePrivateHrGateway(this.client);
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

  Map<String, Object?> _scope(TenantContext scope) => {
    'p_tenant_id': scope.tenantId,
    'p_legal_entity_id': scope.legalEntityId,
    'p_branch_id': scope.branchId,
  };
  DomainError _error(String? dbCode, String? safeCode) {
    final code = switch ((dbCode, safeCode)) {
      ('PGRST202', _) => 'FEATURE_NOT_INSTALLED',
      ('42501', 'PEOPLE_ENTITLEMENT_REQUIRED') => 'FEATURE_NOT_ENTITLED',
      ('42501', 'HR_MFA_REQUIRED') => 'MFA_REQUIRED',
      ('42501', 'HR_ACTIVE_LINK_REQUIRED') => 'SELF_LINK_REQUIRED',
      ('42501', _) => 'PERMISSION_DENIED',
      ('40001', _) => 'VERSION_CONFLICT',
      ('22023', 'IDEMPOTENCY_MISMATCH') => 'IDEMPOTENCY_MISMATCH',
      ('55000', 'HR_CONTENT_EXPIRED') => 'HR_CONTENT_EXPIRED',
      ('55000', 'HR_RETENTION_WORKER_UNAVAILABLE') =>
        'HR_RETENTION_WORKER_UNAVAILABLE',
      ('55000', 'HR_LEGAL_HOLD') => 'HR_LEGAL_HOLD',
      ('55000', 'HR_UPLOAD_VERIFICATION_REQUIRED') =>
        'HR_UPLOAD_VERIFICATION_REQUIRED',
      ('55000', 'HR_LINK_ALREADY_EXISTS') => 'HR_LINK_ALREADY_EXISTS',
      ('55000', 'HR_PURGE_ALREADY_STARTED') => 'HR_PURGE_ALREADY_STARTED',
      ('22023' || '23503' || '23514' || '23505' || '54000', _) =>
        'VALIDATION_ERROR',
      _ => 'UNCERTAIN_RESULT',
    };
    return DomainError(
      code: code,
      message: switch (code) {
        'FEATURE_NOT_INSTALLED' =>
          'Private HR needs the reviewed development update.',
        'FEATURE_NOT_ENTITLED' => 'People is not enabled for this business.',
        'PERMISSION_DENIED' => 'Current private HR access or MFA is required.',
        'MFA_REQUIRED' =>
          'Complete MFA before managing or exporting private HR.',
        'SELF_LINK_REQUIRED' =>
          'Accept an exact account link before using self service.',
        'VERSION_CONFLICT' =>
          'The server version changed. Compare before replacing the draft.',
        'HR_RETENTION_WORKER_UNAVAILABLE' =>
          'Private content is unavailable until the retention worker passes its deployment checks.',
        'HR_CONTENT_EXPIRED' =>
          'Private content has expired or erasure has started.',
        'HR_LEGAL_HOLD' => 'A legal hold blocks erasure.',
        'HR_PURGE_ALREADY_STARTED' =>
          'Erasure has already started; a hold cannot recall it.',
        'HR_LINK_ALREADY_EXISTS' =>
          'This employee or account already has an active proposal or link.',
        'HR_UPLOAD_VERIFICATION_REQUIRED' =>
          'Upload and verify the exact reserved file before confirmation.',
        'VALIDATION_ERROR' =>
          'Check the bounded fields, identities and workflow state.',
        'IDEMPOTENCY_MISMATCH' =>
          'The original request identity belongs to different content.',
        _ =>
          'Confirmation is uncertain. Preserve and retry the exact saved request.',
      },
    );
  }

  Future<Object?> _rpc(
    String name,
    TenantContext scope,
    Map<String, Object?> args,
  ) async {
    _require(scope);
    try {
      final raw = await client
          .schema('api')
          .rpc(name, params: {..._scope(scope), ...args});
      _require(scope);
      return raw;
    } on PostgrestException catch (error) {
      throw _error(error.code, error.message);
    }
  }

  void _responseScope(
    Map<String, Object?> row,
    TenantContext scope,
    Set<String> extra,
  ) {
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      ...extra,
    });
    if (row['tenant_id'] != scope.tenantId ||
        row['legal_entity_id'] != scope.legalEntityId ||
        row['branch_id'] != scope.branchId) {
      throw const FormatException(
        'Private HR response belongs to another scope.',
      );
    }
  }

  HrPage _page(
    Map<String, Object?> row,
    String key,
    HrRecordKind kind,
    String? after,
  ) {
    final raw = row[key];
    if (raw is! List || raw.length > 50) {
      throw const FormatException('Private HR page exceeds its bound.');
    }
    final rows = raw.map((x) => HrRecord.fromJson(kind, hrMap(x))).toList();
    var previous = after;
    for (final item in rows) {
      if (previous != null && item.id.compareTo(previous) <= 0) {
        throw const FormatException('Private HR cursor order is invalid.');
      }
      previous = item.id;
    }
    final cursor = row['next_cursor'] == null
        ? null
        : calendarUuid(row['next_cursor']);
    if (cursor != null && (rows.length != 50 || cursor != rows.last.id)) {
      throw const FormatException('Private HR continuation is invalid.');
    }
    return HrPage(List.unmodifiable(rows), cursor);
  }

  @override
  Future<void> authorize(
    TenantContext scope,
    String? employee,
    String capability,
  ) async {
    final row = hrMap(
      await _rpc('people_hr_access', scope, {
        'p_employee_id': employee,
        'p_capability': capability,
      }),
    );
    calendarFields(row, {'authorized', 'actor_id'});
    if (row['authorized'] != true || row['actor_id'] != scope.actorId) {
      throw const FormatException('Private access confirmation is invalid.');
    }
  }

  @override
  Future<HrPage> subjects(
    TenantContext scope,
    String capability, {
    String search = '',
    String? after,
  }) async {
    if (search.length > 160) {
      throw const FormatException('Subject search exceeds its bound.');
    }
    if (after != null) calendarUuid(after);
    final row = hrMap(
      await _rpc('people_hr_subjects', scope, {
        'p_capability': capability,
        'p_search': search,
        'p_after': after,
      }),
    );
    _responseScope(row, scope, {'items', 'next_cursor'});
    return _page(row, 'items', HrRecordKind.subject, after);
  }

  @override
  Future<HrProfileState> contacts(
    TenantContext scope,
    String employee, {
    String? after,
  }) async {
    calendarUuid(employee);
    if (after != null) calendarUuid(after);
    final row = hrMap(
      await _rpc('people_hr_profile', scope, {
        'p_employee_id': employee,
        'p_after': after,
      }),
    );
    _responseScope(row, scope, {
      'employee_id',
      'profile',
      'history',
      'next_cursor',
    });
    if (row['employee_id'] != employee) {
      throw const FormatException(
        'Private contact belongs to another employee.',
      );
    }
    final profile = row['profile'] == null
        ? null
        : HrRecord.fromJson(HrRecordKind.profile, hrMap(row['profile']));
    if (profile != null && profile.id != employee) {
      throw const FormatException('Private contact identity is invalid.');
    }
    return HrProfileState(
      profile,
      _page(row, 'history', HrRecordKind.profileRevision, after),
    );
  }

  @override
  Future<HrPage> page(
    TenantContext scope,
    HrCollection collection, {
    String? employee,
    String? reviewId,
    String? after,
  }) async {
    if (after != null) calendarUuid(after);
    final (name, kind) = switch (collection) {
      HrCollection.documents => ('people_hr_documents', HrRecordKind.document),
      HrCollection.reviews => ('people_hr_reviews', HrRecordKind.review),
      HrCollection.reviewHistory => (
        'people_hr_review_history',
        HrRecordKind.reviewHistory,
      ),
      HrCollection.links => ('people_hr_links', HrRecordKind.link),
      HrCollection.memberships => (
        'people_hr_memberships',
        HrRecordKind.membership,
      ),
      HrCollection.inbox => ('people_hr_link_inbox', HrRecordKind.inbox),
    };
    final needsEmployee = !{
      HrCollection.memberships,
      HrCollection.inbox,
    }.contains(collection);
    if (needsEmployee) calendarUuid(employee);
    if (collection == HrCollection.reviewHistory) calendarUuid(reviewId);
    final row = hrMap(
      await _rpc(name, scope, {
        'p_after': after,
        if (needsEmployee) 'p_employee_id': employee,
        if (collection == HrCollection.reviewHistory) 'p_review_id': reviewId,
      }),
    );
    _responseScope(row, scope, {
      'items',
      'next_cursor',
      if (needsEmployee) 'employee_id',
      if (collection == HrCollection.reviewHistory) 'review_id',
    });
    if (needsEmployee && row['employee_id'] != employee ||
        collection == HrCollection.reviewHistory &&
            row['review_id'] != reviewId) {
      throw const FormatException(
        'Private HR page belongs to another aggregate.',
      );
    }
    return _page(row, 'items', kind, after);
  }

  @override
  Future<HrPolicyState> policy(TenantContext scope) async {
    final row = hrMap(await _rpc('people_hr_policy', scope, {}));
    _responseScope(row, scope, {'policy', 'worker_ready'});
    if (row['worker_ready'] is! bool) {
      throw const FormatException('Retention readiness is invalid.');
    }
    return HrPolicyState(
      row['policy'] == null
          ? null
          : HrRecord.fromJson(HrRecordKind.policy, hrMap(row['policy'])),
      row['worker_ready'] as bool,
    );
  }

  @override
  Future<HrRecord> self(TenantContext scope) async {
    final row = hrMap(await _rpc('people_hr_self', scope, {}));
    _responseScope(row, scope, {'employee_id', 'display_name'});
    return HrRecord.fromJson(HrRecordKind.self, {
      'employee_id': row['employee_id'],
      'display_name': row['display_name'],
    });
  }

  HrConfirmation _confirmation(
    Object? raw,
    CommandEnvelope<Map<String, Object?>> command,
  ) {
    final result = HrConfirmation.fromJson(hrMap(raw));
    final e = result.entity;
    final p = command.payload;
    if (result.commandId != command.commandId ||
        e['tenant_id'] != command.context.tenantId ||
        e['legal_entity_id'] != command.context.legalEntityId ||
        e['branch_id'] != command.context.branchId ||
        e['id'] != p['id'] ||
        e['employee_id'] != p['employee_id'] ||
        e['action'] != p['action'] ||
        e['revision_id'] != p['revision_id'] &&
            !{
              'review_submit',
              'review_decide',
              'review_acknowledge',
              'review_close',
            }.contains(p['action']) ||
        result.version != (command.expectedEntityVersion ?? 0) + 1) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'Private confirmation did not match the sealed request. Preserve it for exact retry.',
      );
    }
    return result;
  }

  @override
  Future<HrConfirmation> command(
    CommandEnvelope<Map<String, Object?>> input,
  ) async {
    final command = _snapshot(input);
    final action = command.payload['action'] as String;
    HrCommands.validate(action, command.payload);
    calendarUuid(command.commandId);
    calendarUuid(command.idempotencyKey);
    if (command.expectedEntityVersion == null ||
        command.expectedEntityVersion! < 0 ||
        command.expectedEntityVersion! >= 9007199254740991) {
      throw const FormatException('Expected private version is invalid.');
    }
    final row = await _rpc('people_hr_command', command.context, {
      'p_command_id': command.commandId,
      'p_idempotency_key': command.idempotencyKey,
      'p_client_timestamp': command.clientTimestamp.toIso8601String(),
      'p_payload': command.payload,
      'p_expected_version': command.expectedEntityVersion,
    });
    return _confirmation(row, command);
  }

  @override
  Future<HrConfirmation?> receipt(TenantContext scope, String commandId) async {
    calendarUuid(commandId);
    final raw = await _rpc('people_hr_own_receipt', scope, {
      'p_command_id': commandId,
    });
    if (raw == null) return null;
    final result = HrConfirmation.fromJson(hrMap(raw));
    final e = result.entity;
    if (result.commandId != commandId ||
        e['tenant_id'] != scope.tenantId ||
        e['legal_entity_id'] != scope.legalEntityId ||
        e['branch_id'] != scope.branchId) {
      throw const FormatException(
        'Private receipt belongs to another request.',
      );
    }
    return result;
  }

  Future<String> _checksum(Uint8List bytes) async => (await Sha256().hash(
    bytes,
  )).bytes.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  CommandEnvelope<Map<String, Object?>> _snapshot(
    CommandEnvelope<Map<String, Object?>> input,
  ) => CommandEnvelope(
    commandId: input.commandId,
    idempotencyKey: input.idempotencyKey,
    context: input.context,
    clientTimestamp: input.clientTimestamp,
    expectedEntityVersion: input.expectedEntityVersion,
    payload: hrMap(jsonDecode(jsonEncode(input.payload))),
  );

  @override
  Future<Map<String, Object?>> exportContent(
    TenantContext scope,
    String exportId,
  ) async {
    calendarUuid(exportId);
    final row = hrMap(
      await _rpc('people_hr_export_content', scope, {'p_export_id': exportId}),
    );
    _responseScope(row, scope, {
      'format',
      'export_id',
      'employee_id',
      'kind',
      'source_id',
      'source_version',
      'revision_id',
      'body',
      'digest',
      'recorded_by',
      'recorded_at',
    });
    if (row['format'] != 'w4-hr-export-v1' ||
        row['export_id'] != exportId ||
        !{'profile', 'review'}.contains(row['kind'])) {
      throw const FormatException('Private export response is invalid.');
    }
    for (final key in {
      'employee_id',
      'source_id',
      'revision_id',
      'recorded_by',
    }) {
      calendarUuid(row[key]);
    }
    organizationVersion(row['source_version']);
    organizationTimestamp(row['recorded_at']);
    hrDigest(row['digest']);
    if (row['kind'] == 'profile') {
      if (row['source_id'] != row['employee_id']) {
        throw const FormatException('Private export source is invalid.');
      }
      hrContact(hrMap(row['body']));
    } else {
      hrReviewBody(hrMap(row['body']));
    }
    return hrMap(jsonDecode(jsonEncode(row)));
  }

  Map<String, Object?> _docMetadata(
    TenantContext scope,
    String employee,
    HrRecord doc,
    String operation,
  ) {
    _require(scope);
    calendarUuid(employee);
    if (doc.kind != HrRecordKind.document) {
      throw const FormatException('Expected a private document.');
    }
    return {
      'tenant_id': scope.tenantId,
      'legal_entity_id': scope.legalEntityId,
      'branch_id': scope.branchId,
      'employee_id': employee,
      'document_id': doc.id,
      'operation': operation,
    };
  }

  Future<Object?> _edge(
    TenantContext scope,
    Map<String, Object?> metadata, {
    Uint8List? bytes,
    String? mime,
  }) async {
    _require(scope);
    try {
      final response = await client.functions.invoke(
        'people-private-documents',
        headers: {
          'x-jentra-hr-request': base64Encode(
            utf8.encode(jsonEncode(metadata)),
          ),
          'Content-Type': ?mime,
        },
        body: bytes,
      );
      _require(scope);
      return response.data;
    } on FunctionException catch (error) {
      final safe = error.details is Map
          ? (error.details as Map)['code'] as String?
          : null;
      if (error.status == 401) throw _error('42501', null);
      if (error.status == 403) throw _error('42501', null);
      if (safe == 'VERSION_CONFLICT') throw _error('40001', null);
      if ({
        'HR_RETENTION_WORKER_UNAVAILABLE',
        'HR_CONTENT_EXPIRED',
        'HR_UPLOAD_VERIFICATION_REQUIRED',
      }.contains(safe)) {
        throw _error('55000', safe);
      }
      if (error.status == 400 ||
          error.status == 413 ||
          safe == 'HR_DOCUMENT_BYTES_MISMATCH') {
        throw _error('22023', null);
      }
      throw _error(null, null);
    }
  }

  @override
  Future<Uint8List> document(
    TenantContext scope,
    String employee,
    HrRecord doc, {
    bool export = false,
  }) async {
    final row = doc.toJson();
    if (row['status'] != 'active') {
      throw const FormatException('The document is not confirmed.');
    }
    final raw = await _edge(
      scope,
      _docMetadata(scope, employee, doc, export ? 'export' : 'download'),
    );
    if (raw is! Uint8List ||
        raw.length != row['byte_size'] ||
        await _checksum(raw) != row['checksum']) {
      throw const FormatException(
        'Private document bytes failed verification.',
      );
    }
    _require(scope);
    return Uint8List.fromList(raw);
  }

  @override
  Future<HrConfirmation> upload(
    CommandEnvelope<Map<String, Object?>> input,
    HrRecord doc,
    Uint8List bytes,
  ) async {
    final completion = _snapshot(input);
    HrCommands.validate('document_complete', completion.payload);
    calendarUuid(completion.commandId);
    calendarUuid(completion.idempotencyKey);
    if (completion.payload['id'] != doc.id ||
        completion.expectedEntityVersion == null ||
        completion.expectedEntityVersion! < 1 ||
        completion.expectedEntityVersion! >= 9007199254740991) {
      throw const FormatException('Document completion identity is invalid.');
    }
    // Snapshot before awaits; caller mutation cannot change verified upload bytes.
    final frozen = Uint8List.fromList(bytes);
    final row = doc.toJson();
    if (frozen.length != row['byte_size'] ||
        await _checksum(frozen) != row['checksum']) {
      throw const FormatException('Choose the exact reserved file.');
    }
    final metadata =
        _docMetadata(
            completion.context,
            completion.payload['employee_id'] as String,
            doc,
            'upload',
          )
          ..['completion'] = {
            'command_id': completion.commandId,
            'idempotency_key': completion.idempotencyKey,
            'client_timestamp': completion.clientTimestamp.toIso8601String(),
            'expected_version': completion.expectedEntityVersion,
          };
    final result = await _edge(
      completion.context,
      metadata,
      bytes: frozen,
      mime: row['mime'] as String,
    );
    return _confirmation(result, completion);
  }
}

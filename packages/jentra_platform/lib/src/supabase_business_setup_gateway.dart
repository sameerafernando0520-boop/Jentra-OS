import 'dart:convert';
import 'dart:typed_data';

import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Supabase adapter for the versioned Wave 2 `api` schema.
final class SupabaseBusinessSetupGateway
    implements BusinessSetupRepository, SetupImportExportRepository {
  SupabaseBusinessSetupGateway(this._client);

  final SupabaseClient _client;
  static const _uuid = Uuid();

  @override
  Future<CursorPage<SetupRecord>> list(
    BusinessSetupResource resource, {
    required TenantContext context,
    SetupListQuery? query,
  }) async {
    final request = query ?? SetupListQuery();
    if (resource.requiresLegalEntity && !context.hasAccountingScope) {
      throw const DomainError(
        code: 'LEGAL_ENTITY_REQUIRED',
        message: 'Choose a legal entity before opening this setup list.',
        fieldDetails: {'legal_entity_id': 'Required for this resource.'},
      );
    }

    var builder = _client.schema('api').from(resource.apiView).select();
    if (resource != BusinessSetupResource.currencies) {
      builder = builder.eq('tenant_id', context.tenantId);
    }
    if (resource.requiresLegalEntity) {
      builder = builder.eq('legal_entity_id', context.legalEntityId!);
    }
    if (request.status != null && request.status!.isNotEmpty) {
      builder = builder.eq('status', request.status!);
    }
    if (request.normalizedSearch.isNotEmpty) {
      final value = _postgrestQuotedPattern(request.normalizedSearch);
      builder = builder.or('code.ilike.$value,name.ilike.$value');
    }

    final offset = _decodeOffset(request.cursor);
    var ordered = builder.order('id', ascending: true);
    final response = await ordered.range(offset, offset + request.limit);
    final rawRows = (response as List)
        .map((item) => (item as Map).cast<String, Object?>())
        .toList(growable: false);
    final hasNext = rawRows.length > request.limit;
    final visible = hasNext
        ? rawRows.take(request.limit).toList(growable: false)
        : rawRows;
    return CursorPage<SetupRecord>(
      items: visible
          .map((row) => SetupRecord.fromJson(resource, row))
          .toList(growable: false),
      limit: request.limit,
      nextCursor: hasNext ? _encodeOffset(offset + request.limit) : null,
      filters: <String, Object?>{
        'search': request.normalizedSearch,
        if (request.status != null) 'status': request.status,
      },
      sort: const ['id'],
    );
  }

  @override
  Future<SetupRecord?> findById(
    BusinessSetupResource resource, {
    required TenantContext context,
    required String id,
  }) async {
    if (resource.requiresLegalEntity && !context.hasAccountingScope) {
      throw const DomainError(
        code: 'LEGAL_ENTITY_REQUIRED',
        message: 'Choose a legal entity before opening this setup record.',
        fieldDetails: {'legal_entity_id': 'Required for this resource.'},
      );
    }

    var builder = _client
        .schema('api')
        .from(resource.apiView)
        .select()
        .eq('id', id);
    if (resource != BusinessSetupResource.currencies) {
      builder = builder.eq('tenant_id', context.tenantId);
    }
    if (resource.requiresLegalEntity) {
      builder = builder.eq('legal_entity_id', context.legalEntityId!);
    }
    final response = await builder.maybeSingle();
    return response == null
        ? null
        : SetupRecord.fromJson(
            resource,
            (response as Map).cast<String, Object?>(),
          );
  }

  @override
  Future<CommandResult<SetupRecord>> upsert(
    BusinessSetupResource resource, {
    required TenantContext context,
    required Map<String, Object?> payload,
    required String idempotencyKey,
    int? expectedVersion,
  }) async {
    if (resource.isReadOnly || resource.rpcName == null) {
      return CommandResult.failure(
        requestId: idempotencyKey,
        error: const DomainError(
          code: 'READ_ONLY_RESOURCE',
          message: 'This setup resource is read-only.',
        ),
      );
    }
    final validation = BusinessSetupValidator.validate(resource, payload);
    if (!validation.isValid) {
      return CommandResult.failure(
        requestId: idempotencyKey,
        error: DomainError(
          code: 'VALIDATION_ERROR',
          message: 'Review the highlighted setup fields.',
          fieldDetails: <String, String>{
            for (final issue in validation.issues) issue.field: issue.message,
          },
        ),
      );
    }

    final params = <String, Object?>{
      'p_tenant_id': context.tenantId,
      'p_payload': payload,
      'p_idempotency_key': idempotencyKey,
      if (resource != BusinessSetupResource.attachments)
        'p_expected_version': expectedVersion,
      if (resource.requiresLegalEntity)
        'p_legal_entity_id': context.legalEntityId,
      if (resource == BusinessSetupResource.workflowDefinitions)
        'p_legal_entity_id': context.legalEntityId,
    };
    return _runRecordCommand(
      resource,
      resource.rpcName!,
      params,
      fallbackRequestId: idempotencyKey,
    );
  }

  Future<CommandResult<SetupRecord>> reserveDocumentNumber({
    required TenantContext context,
    required String sequenceId,
    required DateTime documentDate,
    String? idempotencyKey,
  }) {
    final requestId = idempotencyKey ?? _uuid.v4();
    return _runRecordCommand(
      BusinessSetupResource.documentSequences,
      'reserve_document_number',
      <String, Object?>{
        'p_tenant_id': context.tenantId,
        'p_sequence_id': sequenceId,
        'p_document_date': _dateOnly(documentDate),
        'p_idempotency_key': requestId,
      },
      fallbackRequestId: requestId,
    );
  }

  Future<CommandResult<SetupRecord>> markNotificationRead({
    required TenantContext context,
    required SetupRecord notification,
    String? idempotencyKey,
  }) {
    final requestId = idempotencyKey ?? _uuid.v4();
    return _runRecordCommand(
      BusinessSetupResource.notifications,
      'mark_notification_read',
      <String, Object?>{
        'p_tenant_id': context.tenantId,
        'p_notification_id': notification.id,
        'p_expected_version': notification.version,
        'p_idempotency_key': requestId,
      },
      fallbackRequestId: requestId,
    );
  }

  Future<CommandResult<SetupRecord>> completeAttachment({
    required TenantContext context,
    required SetupRecord attachment,
    String? checksumSha256,
    String? idempotencyKey,
  }) {
    final requestId = idempotencyKey ?? _uuid.v4();
    return _runRecordCommand(
      BusinessSetupResource.attachments,
      'complete_attachment',
      <String, Object?>{
        'p_tenant_id': context.tenantId,
        'p_attachment_id': attachment.id,
        'p_checksum_sha256': checksumSha256,
        'p_expected_version': attachment.version,
        'p_idempotency_key': requestId,
      },
      fallbackRequestId: requestId,
    );
  }

  Future<void> uploadAttachment({
    required SetupRecord attachment,
    required Uint8List bytes,
  }) async {
    final mimeType = attachment.fields['mime_type']?.toString();
    final objectPath = attachment.fields['object_path']?.toString();
    if (mimeType == null || objectPath == null) {
      throw const DomainError(
        code: 'ATTACHMENT_CONTRACT_INVALID',
        message: 'Attachment upload metadata is incomplete.',
      );
    }
    await _client.storage
        .from('jentra-attachments')
        .uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
  }

  Future<String> createSignedAttachmentUrl(SetupRecord attachment) async {
    final objectPath = attachment.fields['object_path']?.toString();
    if (attachment.status != 'ready' || objectPath == null) {
      throw const DomainError(
        code: 'ATTACHMENT_NOT_READY',
        message: 'The attachment is not ready for download.',
      );
    }
    return _client.storage
        .from('jentra-attachments')
        .createSignedUrl(
          objectPath,
          AttachmentFilePolicy.signedReadLifetime.inSeconds,
        );
  }

  @override
  Future<CommandResult<SetupRecord>> importRecords({
    required BusinessSetupResource resource,
    required TenantContext context,
    required String format,
    required String fileName,
    required int fileSize,
    required TabularDocument document,
    required String idempotencyKey,
  }) => _runRecordCommand(
    BusinessSetupResource.importJobs,
    'import_setup_records',
    <String, Object?>{
      'p_tenant_id': context.tenantId,
      'p_legal_entity_id': context.legalEntityId,
      'p_resource': resource.apiView,
      'p_file_format': format,
      'p_file_name': fileName,
      'p_file_size': fileSize,
      'p_rows': document.toRowMaps(),
      'p_idempotency_key': idempotencyKey,
    },
    fallbackRequestId: idempotencyKey,
  );

  @override
  Future<CommandResult<SetupRecord>> recordExport({
    required BusinessSetupResource resource,
    required TenantContext context,
    required String format,
    required String fileName,
    required int fileSize,
    required int rowCount,
    required List<String> columns,
    required Map<String, Object?> filters,
    required String idempotencyKey,
  }) => _runRecordCommand(
    BusinessSetupResource.exportJobs,
    'create_export_job',
    <String, Object?>{
      'p_tenant_id': context.tenantId,
      'p_resource': resource.apiView,
      'p_file_format': format,
      'p_filters': filters,
      'p_columns': columns,
      'p_row_count': rowCount,
      'p_file_name': fileName,
      'p_file_size': fileSize,
      'p_idempotency_key': idempotencyKey,
    },
    fallbackRequestId: idempotencyKey,
  );

  Future<CommandResult<SetupRecord>> _runRecordCommand(
    BusinessSetupResource responseResource,
    String function,
    Map<String, Object?> params, {
    required String fallbackRequestId,
  }) async {
    try {
      final raw = await _client.schema('api').rpc(function, params: params);
      final response = (raw as Map).cast<String, Object?>();
      final entity = (response['entity'] as Map).cast<String, Object?>();
      return CommandResult.success(
        requestId: response['request_id']?.toString() ?? fallbackRequestId,
        entity: SetupRecord.fromJson(responseResource, entity),
        warnings: (response['warnings'] as List? ?? const [])
            .map((warning) => warning.toString())
            .toList(growable: false),
      );
    } on PostgrestException catch (error) {
      return CommandResult.failure(
        requestId: fallbackRequestId,
        error: _mapPostgrestError(error),
      );
    } on AuthException catch (error) {
      return CommandResult.failure(
        requestId: fallbackRequestId,
        error: DomainError(
          code: 'AUTHENTICATION_REQUIRED',
          message: error.message,
          retryable: false,
        ),
      );
    } on Object {
      return CommandResult.failure(
        requestId: fallbackRequestId,
        error: const DomainError(
          code: 'NETWORK_ERROR',
          message: 'Jentra could not confirm the command with the server.',
          retryable: true,
        ),
      );
    }
  }

  static DomainError _mapPostgrestError(PostgrestException error) {
    final message = error.message;
    final details = error.details?.toString() ?? '';
    final hint = error.hint?.toString() ?? '';
    final code = switch (error.code) {
      '42501' => 'PERMISSION_DENIED',
      '22023' || '22P02' || '23514' =>
        message.contains('Idempotency key')
            ? 'IDEMPOTENCY_MISMATCH'
            : 'VALIDATION_ERROR',
      '23505' || '23P01' => 'CONFLICT',
      '23503' => 'INVALID_REFERENCE',
      '40001' => 'VERSION_CONFLICT',
      'P0002' =>
        message.contains('upload is missing') ? 'UPLOAD_MISSING' : 'NOT_FOUND',
      '55000' => 'INVALID_STATE',
      _ => 'SERVER_ERROR',
    };
    return DomainError(
      code: code,
      message: message,
      fieldDetails: <String, String>{
        if (details.isNotEmpty) '_details': details,
        if (hint.isNotEmpty) '_hint': hint,
      },
      retryable: error.code == '40001' || error.code == 'PGRST003',
    );
  }

  static String _postgrestQuotedPattern(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    return '"%$escaped%"';
  }

  static String _encodeOffset(int value) =>
      base64Url.encode(utf8.encode(jsonEncode(<String, int>{'offset': value})));

  static int _decodeOffset(String? cursor) {
    if (cursor == null || cursor.isEmpty) return 0;
    try {
      final raw = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(cursor))),
      );
      final offset = (raw as Map)['offset'];
      if (offset is int && offset >= 0) return offset;
    } on Object {
      // Converted below to a stable boundary error.
    }
    throw const DomainError(
      code: 'INVALID_CURSOR',
      message: 'The setup page cursor is invalid.',
    );
  }

  static String _dateOnly(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }
}

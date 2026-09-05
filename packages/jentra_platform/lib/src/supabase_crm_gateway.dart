import 'dart:convert';

import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase adapter for the approved Wave 3 CRM read models and named commands.
final class SupabaseCrmGateway implements CrmRepository {
  SupabaseCrmGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<CursorPage<CrmPipelineEntry>> listPipeline({
    required TenantContext context,
    CrmPipelineQuery? query,
  }) async {
    _requireAccountingScope(context, 'opening the CRM pipeline');
    final request = query ?? CrmPipelineQuery();

    try {
      var builder = _client
          .schema('api')
          .from('crm_pipeline_entries')
          .select()
          .eq('tenant_id', context.tenantId)
          .eq('legal_entity_id', context.legalEntityId!);
      if (context.branchId != null) {
        builder = builder.eq('branch_id', context.branchId!);
      }
      if (request.entryType != null) {
        builder = builder.eq('entry_type', request.entryType!.apiValue);
      }
      if (request.stage?.isNotEmpty ?? false) {
        builder = builder.eq('stage', request.stage!);
      }
      if (request.status?.isNotEmpty ?? false) {
        builder = builder.eq('status', request.status!);
      }
      if (request.closingFrom != null) {
        builder = builder.gte(
          'expected_close_date',
          _dateOnly(request.closingFrom!),
        );
      }
      if (request.closingTo != null) {
        builder = builder.lte(
          'expected_close_date',
          _dateOnly(request.closingTo!),
        );
      }
      if (request.normalizedSearch.isNotEmpty) {
        final pattern = _postgrestQuotedPattern(request.normalizedSearch);
        builder = builder.or('code.ilike.$pattern,name.ilike.$pattern');
      }
      final cursorId = _decodeCursor(request.cursor);
      if (cursorId != null) {
        builder = builder.gt('id', cursorId);
      }

      final raw = await builder
          .order('id', ascending: true)
          .limit(request.limit + 1);
      final rows = _jsonRows(raw, 'api.crm_pipeline_entries');
      final hasNext = rows.length > request.limit;
      final visible = hasNext
          ? rows.take(request.limit).toList(growable: false)
          : rows;
      final items = visible
          .map(CrmPipelineEntry.fromJson)
          .toList(growable: false);
      return CursorPage<CrmPipelineEntry>(
        items: items,
        limit: request.limit,
        nextCursor: hasNext ? _encodeCursor(items.last.id) : null,
        filters: <String, Object?>{
          'search': request.normalizedSearch,
          if (request.entryType != null)
            'entry_type': request.entryType!.apiValue,
          if (request.stage != null) 'stage': request.stage,
          if (request.status != null) 'status': request.status,
          if (request.closingFrom != null)
            'closing_from': _dateOnly(request.closingFrom!),
          if (request.closingTo != null)
            'closing_to': _dateOnly(request.closingTo!),
        },
        sort: const ['id'],
      );
    } on PostgrestException catch (error) {
      throw _mapPostgrestError(error);
    } on AuthException catch (error) {
      throw DomainError(
        code: 'AUTHENTICATION_REQUIRED',
        message: error.message,
      );
    } on FormatException catch (error) {
      throw DomainError(
        code: 'CONTRACT_ERROR',
        message: 'The CRM pipeline response did not match its public contract.',
        fieldDetails: {'_details': error.message},
      );
    }
  }

  @override
  Future<List<CrmActivity>> listActivities({
    required TenantContext context,
    required CrmAggregateType aggregateType,
    required String aggregateId,
    int limit = 50,
  }) async {
    _requireAccountingScope(context, 'loading CRM activity');
    if (limit < 1 || limit > 500) {
      throw ArgumentError.value(
        limit,
        'limit',
        'Expected a value from 1 to 500.',
      );
    }
    if (aggregateId.trim().isEmpty) {
      throw const DomainError(
        code: 'VALIDATION_ERROR',
        message: 'Choose a CRM record before loading its activity.',
        fieldDetails: {'aggregate_id': 'Required.'},
      );
    }

    try {
      var builder = _client
          .schema('api')
          .from('crm_activities')
          .select()
          .eq('tenant_id', context.tenantId)
          .eq('legal_entity_id', context.legalEntityId!)
          .eq('aggregate_type', aggregateType.apiValue)
          .eq('aggregate_id', aggregateId);
      if (context.branchId != null) {
        builder = builder.eq('branch_id', context.branchId!);
      }
      final raw = await builder
          .order('activity_at', ascending: false)
          .order('id', ascending: false)
          .limit(limit);
      return _jsonRows(
        raw,
        'api.crm_activities',
      ).map(CrmActivity.fromJson).toList(growable: false);
    } on PostgrestException catch (error) {
      throw _mapPostgrestError(error);
    } on AuthException catch (error) {
      throw DomainError(
        code: 'AUTHENTICATION_REQUIRED',
        message: error.message,
      );
    } on FormatException catch (error) {
      throw DomainError(
        code: 'CONTRACT_ERROR',
        message: 'The CRM activity response did not match its public contract.',
        fieldDetails: {'_details': error.message},
      );
    }
  }

  @override
  Future<CrmLead?> findLead({
    required TenantContext context,
    required String id,
  }) => _findRecord(
    context: context,
    id: id,
    view: 'crm_leads',
    decode: CrmLead.fromJson,
  );

  @override
  Future<CrmOpportunity?> findOpportunity({
    required TenantContext context,
    required String id,
  }) => _findRecord(
    context: context,
    id: id,
    view: 'crm_opportunities',
    decode: CrmOpportunity.fromJson,
  );

  Future<T?> _findRecord<T>({
    required TenantContext context,
    required String id,
    required String view,
    required T Function(Map<String, Object?> json) decode,
  }) async {
    _requireAccountingScope(context, 'loading CRM detail');
    if (id.trim().isEmpty) {
      throw const DomainError(
        code: 'VALIDATION_ERROR',
        message: 'Choose a CRM record before loading its detail.',
        fieldDetails: {'id': 'Required.'},
      );
    }

    try {
      var builder = _client
          .schema('api')
          .from(view)
          .select()
          .eq('tenant_id', context.tenantId)
          .eq('legal_entity_id', context.legalEntityId!)
          .eq('id', id);
      if (context.branchId != null) {
        builder = builder.eq('branch_id', context.branchId!);
      }
      final raw = await builder.maybeSingle();
      return raw == null ? null : decode(_jsonObject(raw, 'api.$view'));
    } on PostgrestException catch (error) {
      throw _mapPostgrestError(error);
    } on AuthException catch (error) {
      throw DomainError(
        code: 'AUTHENTICATION_REQUIRED',
        message: error.message,
      );
    } on FormatException catch (error) {
      throw DomainError(
        code: 'CONTRACT_ERROR',
        message: 'The CRM detail response did not match its public contract.',
        fieldDetails: {'_details': error.message},
      );
    }
  }

  @override
  Future<CrmPipelineSummary> getPipelineSummary({
    required TenantContext context,
    required DateTime asOfDate,
  }) async {
    _requireAccountingScope(context, 'loading the CRM pipeline summary');
    try {
      final raw = await _client
          .schema('api')
          .rpc(
            'get_crm_pipeline_summary',
            params: <String, Object?>{
              'p_tenant_id': context.tenantId,
              'p_legal_entity_id': context.legalEntityId,
              'p_branch_id': context.branchId,
              'p_as_of_date': _dateOnly(asOfDate),
            },
          );
      return CrmPipelineSummary.fromJson(
        _jsonObject(raw, 'api.get_crm_pipeline_summary'),
      );
    } on PostgrestException catch (error) {
      throw _mapPostgrestError(error);
    } on AuthException catch (error) {
      throw DomainError(
        code: 'AUTHENTICATION_REQUIRED',
        message: error.message,
      );
    } on FormatException catch (error) {
      throw DomainError(
        code: 'CONTRACT_ERROR',
        message: 'The CRM summary response did not match its public contract.',
        fieldDetails: {'_details': error.message},
      );
    }
  }

  @override
  Future<CommandResult<CrmLead>> upsertLead(
    CommandEnvelope<CrmLeadDraft> command,
  ) => _runCommand(
    function: 'upsert_lead',
    command: command,
    validation: command.payload.validate(),
    encodePayload: (draft) => draft.toJson(),
    decodeEntity: CrmLead.fromJson,
  );

  @override
  Future<CommandResult<CrmActivity>> recordActivity(
    CommandEnvelope<CrmActivityDraft> command,
  ) => _runCommand(
    function: 'record_crm_activity',
    command: command,
    validation: command.payload.validate(),
    encodePayload: (draft) => draft.toJson(),
    decodeEntity: CrmActivity.fromJson,
  );

  @override
  Future<CommandResult<CrmOpportunity>> upsertOpportunity(
    CommandEnvelope<CrmOpportunityDraft> command,
  ) => _runCommand(
    function: 'upsert_opportunity',
    command: command,
    validation: command.payload.validate(),
    encodePayload: (draft) => draft.toJson(),
    decodeEntity: CrmOpportunity.fromJson,
  );

  @override
  Future<CommandResult<CrmLeadConversion>> convertLead(
    CommandEnvelope<CrmLeadConversionDraft> command,
  ) => _runCommand(
    function: 'convert_lead',
    command: command,
    validation: command.payload.validate(),
    encodePayload: (draft) => draft.toJson(),
    decodeEntity: CrmLeadConversion.fromJson,
  );

  Future<CommandResult<T>> _runCommand<T, P>({
    required String function,
    required CommandEnvelope<P> command,
    required ValidationResult validation,
    required Map<String, Object?> Function(P payload) encodePayload,
    required T Function(Map<String, Object?> json) decodeEntity,
  }) async {
    if (!validation.isValid) {
      return CommandResult.failure(
        requestId: command.idempotencyKey,
        error: DomainError(
          code: 'VALIDATION_ERROR',
          message: 'Review the highlighted CRM fields.',
          fieldDetails: <String, String>{
            for (final issue in validation.issues) issue.field: issue.message,
          },
        ),
      );
    }
    if (!command.context.hasAccountingScope) {
      return CommandResult.failure(
        requestId: command.idempotencyKey,
        error: const DomainError(
          code: 'LEGAL_ENTITY_REQUIRED',
          message: 'Choose a legal entity before running a CRM command.',
          fieldDetails: {'legal_entity_id': 'Required.'},
        ),
      );
    }

    try {
      final raw = await _client
          .schema('api')
          .rpc(
            function,
            params: <String, Object?>{
              'p_tenant_id': command.context.tenantId,
              'p_legal_entity_id': command.context.legalEntityId,
              'p_branch_id': command.context.branchId,
              'p_command_id': command.commandId,
              'p_idempotency_key': command.idempotencyKey,
              'p_client_timestamp': command.clientTimestamp.toIso8601String(),
              'p_payload': encodePayload(command.payload),
              'p_expected_entity_version': command.expectedEntityVersion,
            },
          );
      final response = _jsonObject(raw, 'api.$function');
      final entity = _jsonObject(response['entity'], 'api.$function.entity');
      final rawWarnings = response['warnings'];
      if (rawWarnings != null && rawWarnings is! List) {
        throw FormatException(
          'Expected warning array from api.$function.',
          rawWarnings,
        );
      }
      return CommandResult.success(
        requestId: response['request_id']?.toString() ?? command.idempotencyKey,
        entity: decodeEntity(entity),
        warnings: (rawWarnings as List? ?? const <Object?>[])
            .map((warning) => warning.toString())
            .toList(growable: false),
      );
    } on PostgrestException catch (error) {
      return CommandResult.failure(
        requestId: command.idempotencyKey,
        error: _mapPostgrestError(error),
      );
    } on AuthException catch (error) {
      return CommandResult.failure(
        requestId: command.idempotencyKey,
        error: DomainError(
          code: 'AUTHENTICATION_REQUIRED',
          message: error.message,
        ),
      );
    } on FormatException catch (error) {
      return CommandResult.failure(
        requestId: command.idempotencyKey,
        error: DomainError(
          code: 'CONTRACT_ERROR',
          message:
              'The CRM command response did not match its public contract.',
          fieldDetails: {'_details': error.message},
        ),
      );
    } on Object {
      return CommandResult.failure(
        requestId: command.idempotencyKey,
        error: const DomainError(
          code: 'NETWORK_ERROR',
          message: 'Jentra could not confirm the CRM command with the server.',
          retryable: true,
        ),
      );
    }
  }

  static void _requireAccountingScope(TenantContext context, String action) {
    if (!context.hasAccountingScope) {
      throw DomainError(
        code: 'LEGAL_ENTITY_REQUIRED',
        message: 'Choose a legal entity before $action.',
        fieldDetails: const {'legal_entity_id': 'Required.'},
      );
    }
  }

  static List<Map<String, Object?>> _jsonRows(Object? raw, String boundary) {
    if (raw is! List) {
      throw FormatException('Expected row array from $boundary.', raw);
    }
    return raw
        .map((item) => _jsonObject(item, '$boundary row'))
        .toList(growable: false);
  }

  static Map<String, Object?> _jsonObject(Object? raw, String boundary) {
    if (raw is! Map) {
      throw FormatException('Expected JSON object from $boundary.', raw);
    }
    return raw.cast<String, Object?>();
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
      'P0002' => 'NOT_FOUND',
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

  static String _encodeCursor(String id) =>
      base64Url.encode(utf8.encode(jsonEncode(<String, String>{'id': id})));

  static String? _decodeCursor(String? cursor) {
    if (cursor == null || cursor.isEmpty) return null;
    try {
      final raw = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(cursor))),
      );
      final id = (raw as Map)['id'];
      if (id is String && id.isNotEmpty) return id;
    } on Object {
      // Converted to a stable boundary error below.
    }
    throw const DomainError(
      code: 'INVALID_CURSOR',
      message: 'The CRM page cursor is invalid.',
    );
  }

  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

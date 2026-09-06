import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase adapter for the Wave 3 quotation-to-reservation contracts.
final class SupabaseLeadToCashGateway
    implements LeadToCashRepository, QuotationWorkspaceRepository {
  SupabaseLeadToCashGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<CursorPage<SalesQuotation>> pageQuotations({
    required TenantContext context,
    required QuotationListQuery query,
  }) => _readQuotation(() async {
    var builder = _quotationRead(context, 'sales_quotations');
    if (query.cursor != null) builder = builder.gt('id', query.cursor!);
    if (query.status != null) builder = builder.eq('status', query.status!);
    if (query.search.isNotEmpty) {
      final literal = query.search
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      builder = builder.ilike('document_number', '%$literal%');
    }
    final rows = _jsonRows(
      await builder.order('id', ascending: true).limit(query.limit),
      'quotations',
    );
    final items = rows.map(SalesQuotation.fromJson).toList(growable: false);
    return CursorPage(
      items: items,
      limit: query.limit,
      nextCursor: items.length == query.limit ? items.last.id : null,
    );
  });

  @override
  Future<QuotationDetail?> loadQuotationDetail({
    required TenantContext context,
    required String id,
  }) => _find(
    context: context,
    view: 'sales_quotation_details',
    id: id,
    decode: QuotationDetail.fromJson,
  );

  @override
  Future<List<SalesQuotationRevision>> quotationRevisions({
    required TenantContext context,
    required String id,
    int beforeRevision = 2147483647,
  }) => _readQuotation(() async {
    final rows = await _quotationRead(context, 'sales_quotation_revisions')
        .eq('quotation_id', id)
        .lt('revision_number', beforeRevision)
        .order('revision_number', ascending: false)
        .limit(100);
    return _jsonRows(
      rows,
      'quotation revisions',
    ).map(SalesQuotationRevision.fromJson).toList(growable: false);
  });

  @override
  Future<List<Map<String, Object?>>> quotationDecisions({
    required TenantContext context,
    required String id,
    String? beforeId,
  }) => _readQuotation(() async {
    var builder = _quotationRead(
      context,
      'sales_quotation_decisions',
    ).eq('quotation_id', id);
    if (beforeId != null) builder = builder.lt('id', beforeId);
    return _jsonRows(
      await builder.order('id', ascending: false).limit(100),
      'quotation decisions',
    );
  });

  PostgrestFilterBuilder<List<Map<String, dynamic>>> _quotationRead(
    TenantContext context,
    String view,
  ) {
    _requireLegalEntity(context, 'loading quotations');
    var builder = _client
        .schema('api')
        .from(view)
        .select()
        .eq('tenant_id', context.tenantId)
        .eq('legal_entity_id', context.legalEntityId!);
    if (context.branchId != null) {
      builder = builder.eq('branch_id', context.branchId!);
    }
    return builder;
  }

  Future<T> _readQuotation<T>(Future<T> Function() read) async {
    try {
      return await read();
    } on PostgrestException catch (error) {
      throw _mapPostgrestError(error);
    } on FormatException catch (error) {
      throw DomainError(
        code: 'CONTRACT_ERROR',
        message: 'Quotation data did not match its exact contract.',
        fieldDetails: {'_details': error.message},
      );
    }
  }

  @override
  Future<List<SalesQuotation>> listQuotations({
    required TenantContext context,
  }) => _list(
    context: context,
    view: 'sales_quotations',
    decode: SalesQuotation.fromJson,
  );

  @override
  Future<SalesQuotation?> findQuotation({
    required TenantContext context,
    required String id,
  }) => _find(
    context: context,
    view: 'sales_quotations',
    id: id,
    decode: SalesQuotation.fromJson,
  );

  @override
  Future<List<SalesOrder>> listSalesOrders({required TenantContext context}) =>
      _list(
        context: context,
        view: 'sales_orders',
        decode: SalesOrder.fromJson,
      );

  @override
  Future<SalesOrder?> findSalesOrder({
    required TenantContext context,
    required String id,
  }) => _find(
    context: context,
    view: 'sales_orders',
    id: id,
    decode: SalesOrder.fromJson,
  );

  @override
  Future<CommandResult<SalesQuotation>> upsertQuotation(
    CommandEnvelope<QuotationDraft> command,
  ) => _runCommand(
    function: 'upsert_sales_quotation',
    command: command,
    validation: command.payload.validate(),
    encodePayload: (payload) => payload.toJson(),
    decodeEntity: SalesQuotation.fromJson,
  );

  @override
  Future<CommandResult<SalesQuotation>> transitionQuotation(
    CommandEnvelope<OperationalDocumentTransition> command,
  ) => _runCommand(
    function: 'transition_operational_document',
    command: command,
    validation: _documentValidation(
      command.payload,
      OperationalDocumentType.salesQuotation,
    ),
    encodePayload: (payload) => payload.toJson(),
    decodeEntity: SalesQuotation.fromJson,
  );

  @override
  Future<CommandResult<SalesQuotation>> decideQuotationApproval(
    CommandEnvelope<OperationalApprovalDecision> command,
  ) => _runCommand(
    function: 'decide_operational_approval',
    command: command,
    validation: _approvalValidation(command.payload),
    encodePayload: (payload) => payload.toJson(),
    decodeEntity: SalesQuotation.fromJson,
  );

  @override
  Future<CommandResult<SalesOrder>> convertQuotation(
    CommandEnvelope<QuotationConversionDraft> command,
  ) => _runCommand(
    function: 'convert_quotation_to_order',
    command: command,
    validation: command.payload.validate(),
    encodePayload: (payload) => payload.toJson(),
    decodeEntity: SalesOrder.fromJson,
  );

  @override
  Future<CommandResult<SalesOrder>> upsertSalesOrder(
    CommandEnvelope<SalesOrderDraft> command,
  ) => _runCommand(
    function: 'upsert_sales_order',
    command: command,
    validation: command.payload.validate(),
    encodePayload: (payload) => payload.toJson(),
    decodeEntity: SalesOrder.fromJson,
  );

  @override
  Future<CommandResult<SalesOrder>> transitionSalesOrder(
    CommandEnvelope<OperationalDocumentTransition> command,
  ) => _runCommand(
    function: 'transition_operational_document',
    command: command,
    validation: _documentValidation(
      command.payload,
      OperationalDocumentType.salesOrder,
    ),
    encodePayload: (payload) => payload.toJson(),
    decodeEntity: SalesOrder.fromJson,
  );

  @override
  Future<CommandResult<SalesOrder>> reserveStock(
    CommandEnvelope<StockReservationDraft> command,
  ) => _runCommand(
    function: 'reserve_sales_order_stock',
    command: command,
    validation: command.payload.validate(),
    encodePayload: (payload) => payload.toJson(),
    decodeEntity: SalesOrder.fromJson,
  );

  Future<List<T>> _list<T>({
    required TenantContext context,
    required String view,
    required T Function(Map<String, Object?> json) decode,
  }) async {
    _requireLegalEntity(context, 'loading lead-to-cash records');
    try {
      var builder = _client
          .schema('api')
          .from(view)
          .select()
          .eq('tenant_id', context.tenantId)
          .eq('legal_entity_id', context.legalEntityId!);
      if (context.branchId != null) {
        builder = builder.eq('branch_id', context.branchId!);
      }
      final raw = await builder.order('created_at', ascending: false);
      return _jsonRows(raw, 'api.$view').map(decode).toList(growable: false);
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
        message: 'The $view response did not match its public contract.',
        fieldDetails: {'_details': error.message},
      );
    }
  }

  Future<T?> _find<T>({
    required TenantContext context,
    required String view,
    required String id,
    required T Function(Map<String, Object?> json) decode,
  }) async {
    _requireLegalEntity(context, 'loading lead-to-cash detail');
    if (id.trim().isEmpty) {
      throw const DomainError(
        code: 'VALIDATION_ERROR',
        message: 'Choose a document before loading its detail.',
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
        message: 'The $view response did not match its public contract.',
        fieldDetails: {'_details': error.message},
      );
    }
  }

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
          message: 'Review the highlighted lead-to-cash fields.',
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
          message: 'Choose a legal entity before running this command.',
          fieldDetails: {'legal_entity_id': 'Required.'},
        ),
      );
    }
    if (!command.context.hasOperationalScope) {
      return CommandResult.failure(
        requestId: command.idempotencyKey,
        error: const DomainError(
          code: 'BRANCH_REQUIRED',
          message: 'Choose a branch before running this command.',
          fieldDetails: {'branch_id': 'Required.'},
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
      final warnings = response['warnings'];
      if (warnings != null && warnings is! List) {
        throw FormatException(
          'Expected warning array from api.$function.',
          warnings,
        );
      }
      return CommandResult.success(
        requestId: response['request_id']?.toString() ?? command.idempotencyKey,
        entity: decodeEntity(
          _jsonObject(response['entity'], 'api.$function.entity'),
        ),
        warnings: (warnings as List? ?? const <Object?>[])
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
          message: 'The command response did not match its public contract.',
          fieldDetails: {'_details': error.message},
        ),
      );
    } on Object {
      return CommandResult.failure(
        requestId: command.idempotencyKey,
        error: const DomainError(
          code: 'NETWORK_ERROR',
          message: 'Jentra could not confirm the command with the server.',
          retryable: true,
        ),
      );
    }
  }

  static ValidationResult _documentValidation(
    OperationalDocumentTransition payload,
    OperationalDocumentType expected,
  ) => ValidationResult([
    ...payload.validate().issues,
    if (payload.documentType != expected)
      const ValidationIssue(
        field: 'document_type',
        message: 'Document type does not match this operation.',
      ),
  ]);

  static ValidationResult _approvalValidation(
    OperationalApprovalDecision payload,
  ) => ValidationResult([
    ...payload.validate().issues,
    if (payload.documentType != OperationalDocumentType.salesQuotation)
      const ValidationIssue(
        field: 'document_type',
        message: 'Only quotation approval is available in this slice.',
      ),
  ]);

  static void _requireLegalEntity(TenantContext context, String action) {
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
      '42501' =>
        message.contains('SEGREGATION_OF_DUTIES')
            ? 'SEGREGATION_OF_DUTIES_VIOLATION'
            : 'PERMISSION_DENIED',
      '22023' || '22P02' || '23514' =>
        message.contains('IDEMPOTENCY')
            ? 'IDEMPOTENCY_MISMATCH'
            : 'VALIDATION_ERROR',
      '23503' => 'INVALID_REFERENCE',
      '23505' || '23P01' => 'CONFLICT',
      '40001' => 'VERSION_CONFLICT',
      'P0002' => 'NOT_FOUND',
      '55000' => message,
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
}

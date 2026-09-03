import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';

final businessSetupControllerProvider =
    AsyncNotifierProvider<BusinessSetupController, BusinessSetupState>(
      BusinessSetupController.new,
    );

final class BusinessSetupState {
  const BusinessSetupState({
    required this.category,
    required this.resource,
    required this.items,
    required this.capabilities,
    required this.connectivity,
    this.search = '',
    this.status,
    this.nextCursor,
    this.loading = false,
    this.fromCache = false,
    this.error,
  });

  final BusinessSetupCategory category;
  final BusinessSetupResource resource;
  final List<SetupRecord> items;
  final Set<String> capabilities;
  final ConnectivityState connectivity;
  final String search;
  final String? status;
  final String? nextCursor;
  final bool loading;
  final bool fromCache;
  final DomainError? error;

  bool get canView => capabilities.contains(resource.viewPermission);
  bool get canManage => capabilities.contains(resource.managePermission);
  bool get isOnline => connectivity == ConnectivityState.online;

  BusinessSetupState copyWith({
    BusinessSetupCategory? category,
    BusinessSetupResource? resource,
    List<SetupRecord>? items,
    Set<String>? capabilities,
    ConnectivityState? connectivity,
    String? search,
    String? status,
    String? nextCursor,
    bool? loading,
    bool? fromCache,
    DomainError? error,
    bool clearStatus = false,
    bool clearCursor = false,
    bool clearError = false,
  }) => BusinessSetupState(
    category: category ?? this.category,
    resource: resource ?? this.resource,
    items: items ?? this.items,
    capabilities: capabilities ?? this.capabilities,
    connectivity: connectivity ?? this.connectivity,
    search: search ?? this.search,
    status: clearStatus ? null : status ?? this.status,
    nextCursor: clearCursor ? null : nextCursor ?? this.nextCursor,
    loading: loading ?? this.loading,
    fromCache: fromCache ?? this.fromCache,
    error: clearError ? null : error ?? this.error,
  );
}

enum SetupSaveStatus { draftSaved, savedOnline, failed }

final class SetupSaveOutcome {
  const SetupSaveOutcome(
    this.status,
    this.message, {
    this.error,
    this.serverRecord,
  });

  final SetupSaveStatus status;
  final String message;
  final DomainError? error;
  final SetupRecord? serverRecord;
}

final class BusinessSetupController extends AsyncNotifier<BusinessSetupState> {
  static const _uuid = Uuid();

  @override
  Future<BusinessSetupState> build() async {
    final scope = await ref.watch(businessScopeProvider.future);
    final gateway = ref.watch(foundationGatewayProvider);
    final context = scope.toContext(
      gateway?.currentUser?.id ?? 'preview-actor',
    );
    final capabilities = await ref.watch(businessCapabilitiesProvider.future);
    final connectivity =
        ref.watch(connectivityStateProvider).value ?? ConnectivityState.online;
    final visibleResources = BusinessSetupResource.values
        .where((resource) => capabilities.contains(resource.viewPermission))
        .toList(growable: false);
    final initialResource =
        visibleResources.contains(BusinessSetupResource.accounts)
        ? BusinessSetupResource.accounts
        : visibleResources.firstOrNull ?? BusinessSetupResource.accounts;
    final initial = BusinessSetupState(
      category: initialResource.category,
      resource: initialResource,
      items: const [],
      capabilities: capabilities,
      connectivity: connectivity,
      loading: true,
    );
    return _fetch(initial, context: context);
  }

  Future<void> selectCategory(BusinessSetupCategory category) async {
    final current = state.value;
    if (current == null || current.category == category) return;
    final candidates = BusinessSetupResource.values
        .where(
          (resource) =>
              resource.category == category &&
              current.capabilities.contains(resource.viewPermission),
        )
        .toList(growable: false);
    final resource = _preferredResource(category, candidates);
    if (resource == null) {
      state = AsyncData(
        current.copyWith(
          category: category,
          items: const [],
          error: const DomainError(
            code: 'PERMISSION_DENIED',
            message: 'Your role cannot open resources in this category.',
          ),
          clearCursor: true,
        ),
      );
      return;
    }
    await selectResource(resource);
  }

  Future<void> selectResource(BusinessSetupResource resource) async {
    final current = state.value;
    if (current == null || current.resource == resource) return;
    final next = current.copyWith(
      category: resource.category,
      resource: resource,
      search: '',
      items: const [],
      loading: true,
      clearStatus: true,
      clearCursor: true,
      clearError: true,
    );
    state = AsyncData(next);
    await _loadIntoState(next);
  }

  Future<void> setSearch(String search) async {
    final current = state.value;
    if (current == null || current.search == search) return;
    final next = current.copyWith(
      search: search,
      loading: true,
      clearCursor: true,
      clearError: true,
    );
    state = AsyncData(next);
    await _loadIntoState(next);
  }

  Future<void> setStatus(String? status) async {
    final current = state.value;
    if (current == null || current.status == status) return;
    final next = current.copyWith(
      status: status,
      loading: true,
      clearStatus: status == null,
      clearCursor: true,
      clearError: true,
    );
    state = AsyncData(next);
    await _loadIntoState(next);
  }

  Future<void> refresh() async {
    final current = state.value;
    if (current == null) return;
    final next = current.copyWith(
      loading: true,
      clearCursor: true,
      clearError: true,
    );
    state = AsyncData(next);
    await _loadIntoState(next);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.nextCursor == null || current.loading) {
      return;
    }
    final next = current.copyWith(loading: true, clearError: true);
    state = AsyncData(next);
    await _loadIntoState(next, append: true);
  }

  Future<SetupSaveOutcome> saveDraft({
    required BusinessSetupResource resource,
    required Map<String, Object?> payload,
    SetupRecord? existing,
  }) async {
    final context = ref.read(activeTenantContextProvider);
    if (context == null) {
      return const SetupSaveOutcome(
        SetupSaveStatus.failed,
        'Choose a business scope first.',
      );
    }
    final draftId = existing?.id ?? _draftId(resource, payload: payload);
    final effectivePayload = _scopePayload(resource, context, payload);
    try {
      await ref
          .read(encryptedDraftRepositoryProvider)
          .save(
            id: draftId,
            tenantId: context.tenantId,
            entityType: resource.name,
            payload: effectivePayload,
            localVersion: (existing?.version ?? 0) + 1,
            serverVersion: existing?.version,
          );
      return const SetupSaveOutcome(
        SetupSaveStatus.draftSaved,
        'Encrypted draft saved on this device.',
      );
    } on Object {
      return const SetupSaveOutcome(
        SetupSaveStatus.failed,
        'The encrypted draft could not be saved.',
        error: DomainError(
          code: 'LOCAL_STORAGE_ERROR',
          message: 'The encrypted draft could not be saved.',
          retryable: true,
        ),
      );
    }
  }

  Future<SetupSaveOutcome> saveOnline({
    required BusinessSetupResource resource,
    required Map<String, Object?> payload,
    SetupRecord? existing,
  }) async {
    final validation = BusinessSetupValidator.validate(resource, payload);
    if (!validation.isValid) {
      return SetupSaveOutcome(
        SetupSaveStatus.failed,
        'Review the highlighted fields.',
        error: DomainError(
          code: 'VALIDATION_ERROR',
          message: 'Review the highlighted setup fields.',
          fieldDetails: {
            for (final issue in validation.issues) issue.field: issue.message,
          },
        ),
      );
    }
    final draftOutcome = await saveDraft(
      resource: resource,
      payload: payload,
      existing: existing,
    );
    if (draftOutcome.status == SetupSaveStatus.failed) return draftOutcome;
    final current = state.value;
    final context = ref.read(activeTenantContextProvider);
    if (current == null || context == null) return draftOutcome;
    if (!current.canManage) {
      return const SetupSaveOutcome(
        SetupSaveStatus.failed,
        'Your role can view this list but cannot change it.',
        error: DomainError(
          code: 'PERMISSION_DENIED',
          message: 'Your role cannot manage this setup resource.',
        ),
      );
    }
    if (!current.isOnline) {
      return const SetupSaveOutcome(
        SetupSaveStatus.draftSaved,
        'You are offline. The encrypted draft is safe on this device.',
      );
    }

    final concreteGateway = ref.read(businessSetupGatewayProvider);
    final draftId = existing?.id ?? _draftId(resource, payload: payload);
    final effectivePayload = _scopePayload(resource, context, payload);
    if (concreteGateway == null) {
      final preview = _previewFromPayload(
        resource,
        context,
        effectivePayload,
        existing: existing,
      );
      state = AsyncData(
        current.copyWith(
          items: [
            preview,
            ...current.items.where((item) => item.id != preview.id),
          ],
          clearError: true,
        ),
      );
      await ref.read(encryptedDraftRepositoryProvider).delete(draftId);
      return const SetupSaveOutcome(
        SetupSaveStatus.savedOnline,
        'Saved in development preview.',
      );
    }

    final result = await concreteGateway.upsert(
      resource,
      context: context,
      payload: effectivePayload,
      expectedVersion: existing?.version,
      idempotencyKey: _requestId(),
    );
    if (result.isFailure) {
      if (result.error?.code == 'VERSION_CONFLICT' && existing != null) {
        SetupRecord? serverRecord;
        try {
          serverRecord = await concreteGateway.findById(
            resource,
            context: context,
            id: existing.id,
          );
        } on Object {
          // The local draft still remains conflicted if the follow-up read fails.
        }
        final serverVersion = serverRecord?.version ?? existing.version + 1;
        await ref
            .read(encryptedDraftRepositoryProvider)
            .markConflict(id: existing.id, serverVersion: serverVersion);
        final error = result.error!;
        return SetupSaveOutcome(
          SetupSaveStatus.failed,
          'A newer server version exists. Reload it or merge your encrypted draft explicitly.',
          error: DomainError(
            code: error.code,
            message:
                'A newer server version exists. Reload it or merge your encrypted draft explicitly.',
            fieldDetails: {
              ...error.fieldDetails,
              'local_version': existing.version.toString(),
              'server_version': serverVersion.toString(),
            },
            retryable: true,
            correlationId: error.correlationId,
          ),
          serverRecord: serverRecord,
        );
      }
      return SetupSaveOutcome(
        SetupSaveStatus.failed,
        result.error!.message,
        error: result.error,
      );
    }
    await ref.read(encryptedDraftRepositoryProvider).delete(draftId);
    await refresh();
    return SetupSaveOutcome(
      SetupSaveStatus.savedOnline,
      '${resource.singularLabel} saved.',
    );
  }

  Future<SetupSaveOutcome> importDocument({
    required String format,
    required String fileName,
    required int fileSize,
    required TabularDocument document,
  }) async {
    final current = state.value;
    final context = ref.read(activeTenantContextProvider);
    final gateway = ref.read(businessSetupGatewayProvider);
    if (current == null || context == null) {
      return const SetupSaveOutcome(
        SetupSaveStatus.failed,
        'Choose a business scope first.',
      );
    }
    if (!current.isOnline) {
      return const SetupSaveOutcome(
        SetupSaveStatus.failed,
        'Reconnect before applying an import.',
        error: DomainError(
          code: 'ONLINE_CONFIRMATION_REQUIRED',
          message: 'Imports require a live server confirmation.',
          retryable: true,
        ),
      );
    }
    if (!current.canManage) {
      return const SetupSaveOutcome(
        SetupSaveStatus.failed,
        'Your role cannot import this resource.',
      );
    }
    if (gateway == null) {
      return const SetupSaveOutcome(
        SetupSaveStatus.savedOnline,
        'Import validated in development preview.',
      );
    }
    final result = await gateway.importRecords(
      resource: current.resource,
      context: context,
      format: format,
      fileName: fileName,
      fileSize: fileSize,
      document: document,
      idempotencyKey: _requestId(),
    );
    if (result.isFailure) {
      return SetupSaveOutcome(
        SetupSaveStatus.failed,
        result.error!.message,
        error: result.error,
      );
    }
    await refresh();
    return const SetupSaveOutcome(
      SetupSaveStatus.savedOnline,
      'Import applied atomically.',
    );
  }

  Future<SetupSaveOutcome> recordExport({
    required String format,
    required String fileName,
    required int fileSize,
    required int rowCount,
    required List<String> columns,
  }) async {
    final current = state.value;
    final context = ref.read(activeTenantContextProvider);
    final gateway = ref.read(businessSetupGatewayProvider);
    if (current == null || context == null || !current.isOnline) {
      return const SetupSaveOutcome(
        SetupSaveStatus.failed,
        'Reconnect before exporting audited business data.',
      );
    }
    if (!current.canView) {
      return const SetupSaveOutcome(
        SetupSaveStatus.failed,
        'Your role cannot export this resource.',
      );
    }
    if (gateway == null) {
      return const SetupSaveOutcome(
        SetupSaveStatus.savedOnline,
        'Export recorded in development preview.',
      );
    }
    final result = await gateway.recordExport(
      resource: current.resource,
      context: context,
      format: format,
      fileName: fileName,
      fileSize: fileSize,
      rowCount: rowCount,
      columns: columns,
      filters: {
        if (current.search.trim().isNotEmpty) 'search': current.search.trim(),
        if (current.status != null) 'status': current.status,
      },
      idempotencyKey: _requestId(),
    );
    if (result.isFailure) {
      return SetupSaveOutcome(
        SetupSaveStatus.failed,
        result.error!.message,
        error: result.error,
      );
    }
    return const SetupSaveOutcome(
      SetupSaveStatus.savedOnline,
      'Export saved and audit job recorded.',
    );
  }

  Future<String> createAttachmentReadUrl(SetupRecord attachment) async {
    final current = state.value;
    final gateway = ref.read(businessSetupGatewayProvider);
    if (current == null || !current.isOnline) {
      throw const DomainError(
        code: 'ONLINE_CONFIRMATION_REQUIRED',
        message: 'Reconnect before opening a private attachment.',
        retryable: true,
      );
    }
    if (!current.canView) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Your role cannot open this attachment.',
      );
    }
    if (gateway == null) {
      throw const DomainError(
        code: 'PREVIEW_ONLY',
        message:
            'Signed attachment links require a configured Supabase session.',
      );
    }
    return gateway.createSignedAttachmentUrl(attachment);
  }

  Future<SetupSaveOutcome> uploadAttachment({
    required String aggregateType,
    required String aggregateId,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final current = state.value;
    final context = ref.read(activeTenantContextProvider);
    final gateway = ref.read(businessSetupGatewayProvider);
    if (current == null || context == null || !current.isOnline) {
      return const SetupSaveOutcome(
        SetupSaveStatus.failed,
        'Reconnect before uploading an attachment.',
      );
    }
    if (!current.canManage) {
      return const SetupSaveOutcome(
        SetupSaveStatus.failed,
        'Your role cannot upload attachments.',
      );
    }
    final validation = AttachmentFilePolicy.validate(
      fileName: fileName,
      mimeType: mimeType,
      byteSize: bytes.length,
    );
    if (!validation.isValid) {
      return SetupSaveOutcome(
        SetupSaveStatus.failed,
        validation.issues.first.message,
        error: DomainError(
          code: 'VALIDATION_ERROR',
          message: 'The attachment is not allowed.',
          fieldDetails: {
            for (final issue in validation.issues) issue.field: issue.message,
          },
        ),
      );
    }
    if (gateway == null) {
      return const SetupSaveOutcome(
        SetupSaveStatus.savedOnline,
        'Attachment validated in development preview.',
      );
    }
    final registered = await gateway.upsert(
      BusinessSetupResource.attachments,
      context: context,
      payload: {
        'aggregate_type': aggregateType,
        'aggregate_id': aggregateId,
        'file_name': fileName,
        'mime_type': mimeType,
        'byte_size': bytes.length,
      },
      idempotencyKey: _requestId(),
    );
    if (registered.isFailure) {
      return SetupSaveOutcome(
        SetupSaveStatus.failed,
        registered.error!.message,
        error: registered.error,
      );
    }
    final staged = registered.entity!;
    try {
      await gateway.uploadAttachment(attachment: staged, bytes: bytes);
    } on Object {
      return const SetupSaveOutcome(
        SetupSaveStatus.failed,
        'The file upload stopped. Its staged record can be retried safely.',
        error: DomainError(
          code: 'UPLOAD_FAILED',
          message: 'The attachment upload could not be completed.',
          retryable: true,
        ),
      );
    }
    final completed = await gateway.completeAttachment(
      context: context,
      attachment: staged,
      idempotencyKey: _requestId(),
    );
    if (completed.isFailure) {
      return SetupSaveOutcome(
        SetupSaveStatus.failed,
        completed.error!.message,
        error: completed.error,
      );
    }
    await refresh();
    return const SetupSaveOutcome(
      SetupSaveStatus.savedOnline,
      'Attachment uploaded and confirmed.',
    );
  }

  Future<SetupSaveOutcome> reserveNextNumber(SetupRecord sequence) async {
    final current = state.value;
    final context = ref.read(activeTenantContextProvider);
    final gateway = ref.read(businessSetupGatewayProvider);
    if (current == null || context == null || !current.isOnline) {
      return const SetupSaveOutcome(
        SetupSaveStatus.failed,
        'Reconnect before reserving a document number.',
      );
    }
    if (!current.canView) {
      return const SetupSaveOutcome(
        SetupSaveStatus.failed,
        'Your role cannot reserve from this sequence.',
      );
    }
    if (gateway == null) {
      final next =
          int.tryParse(
            (sequence.fields['next_value'] ?? sequence.fields['next_number'])
                .toString(),
          ) ??
          1;
      final prefix =
          sequence.fields['prefix']?.toString() ??
          sequence.fields['prefix_template']?.toString() ??
          '';
      final suffix = sequence.fields['suffix']?.toString() ?? '';
      final padding =
          int.tryParse(sequence.fields['padding']?.toString() ?? '') ?? 6;
      return SetupSaveOutcome(
        SetupSaveStatus.savedOnline,
        'Reserved $prefix${next.toString().padLeft(padding, '0')}$suffix in development preview.',
      );
    }
    final result = await gateway.reserveDocumentNumber(
      context: context,
      sequenceId: sequence.id,
      documentDate: DateTime.now(),
      idempotencyKey: _requestId(),
    );
    if (result.isFailure) {
      return SetupSaveOutcome(
        SetupSaveStatus.failed,
        result.error!.message,
        error: result.error,
      );
    }
    await refresh();
    return SetupSaveOutcome(
      SetupSaveStatus.savedOnline,
      'Reserved ${result.entity!.fields['number']}.',
    );
  }

  Future<SetupSaveOutcome> markNotificationRead(
    SetupRecord notification,
  ) async {
    final current = state.value;
    final context = ref.read(activeTenantContextProvider);
    final gateway = ref.read(businessSetupGatewayProvider);
    if (current == null || context == null || !current.isOnline) {
      return const SetupSaveOutcome(
        SetupSaveStatus.failed,
        'Reconnect before changing notification state.',
      );
    }
    if (gateway == null) {
      final updated = SetupRecord(
        resource: notification.resource,
        id: notification.id,
        tenantId: notification.tenantId,
        code: notification.code,
        name: notification.name,
        status: 'read',
        version: notification.version + 1,
        createdAt: notification.createdAt,
        updatedAt: DateTime.now().toUtc(),
        fields: {...notification.fields, 'read_at': DateTime.now().toUtc()},
      );
      state = AsyncData(
        current.copyWith(
          items: [
            for (final item in current.items)
              if (item.id == updated.id) updated else item,
          ],
        ),
      );
      return const SetupSaveOutcome(
        SetupSaveStatus.savedOnline,
        'Notification marked as read.',
      );
    }
    final result = await gateway.markNotificationRead(
      context: context,
      notification: notification,
      idempotencyKey: _requestId(),
    );
    if (result.isFailure) {
      return SetupSaveOutcome(
        SetupSaveStatus.failed,
        result.error!.message,
        error: result.error,
      );
    }
    await refresh();
    return const SetupSaveOutcome(
      SetupSaveStatus.savedOnline,
      'Notification marked as read.',
    );
  }

  Future<void> _loadIntoState(
    BusinessSetupState requested, {
    bool append = false,
  }) async {
    final scope = await ref.read(businessScopeProvider.future);
    final gateway = ref.read(foundationGatewayProvider);
    final context = scope.toContext(
      gateway?.currentUser?.id ?? 'preview-actor',
    );
    state = AsyncData(
      await _fetch(requested, context: context, append: append),
    );
  }

  Future<BusinessSetupState> _fetch(
    BusinessSetupState requested, {
    required TenantContext context,
    bool append = false,
  }) async {
    if (!requested.capabilities.contains(requested.resource.viewPermission)) {
      return requested.copyWith(
        items: const [],
        loading: false,
        error: const DomainError(
          code: 'PERMISSION_DENIED',
          message: 'Your role cannot view this setup resource.',
        ),
        clearCursor: true,
      );
    }
    final query = SetupListQuery(
      search: requested.search,
      status: requested.status,
      cursor: append ? requested.nextCursor : null,
    );
    final gateway = ref.read(businessSetupGatewayProvider);
    if (gateway == null) {
      final records = _filterPreview(
        _previewRecords(requested.resource, context),
        requested.search,
        requested.status,
      );
      return requested.copyWith(
        items: records,
        loading: false,
        fromCache: false,
        clearCursor: true,
        clearError: true,
      );
    }

    if (requested.connectivity != ConnectivityState.online) {
      try {
        final cached = await ref
            .read(referenceCacheRepositoryProvider)
            .readResource(
              tenantId: context.tenantId,
              resource: requested.resource,
              legalEntityId: requested.resource.requiresLegalEntity
                  ? context.legalEntityId
                  : null,
            );
        return requested.copyWith(
          items: _filterPreview(cached, requested.search, requested.status),
          loading: false,
          fromCache: true,
          clearCursor: true,
          clearError: true,
        );
      } on Object {
        return requested.copyWith(
          items: const [],
          loading: false,
          fromCache: true,
          error: const DomainError(
            code: 'CACHE_UNAVAILABLE',
            message: 'No readable cached data is available for this list.',
            retryable: true,
          ),
          clearCursor: true,
        );
      }
    }

    try {
      final page = await gateway.list(
        requested.resource,
        context: context,
        query: query,
      );
      if (!append && requested.search.isEmpty && requested.status == null) {
        await ref
            .read(referenceCacheRepositoryProvider)
            .replaceResource(
              tenantId: context.tenantId,
              resource: requested.resource,
              records: page.items,
            );
      }
      return requested.copyWith(
        items: append ? [...requested.items, ...page.items] : page.items,
        nextCursor: page.nextCursor,
        loading: false,
        fromCache: false,
        clearCursor: page.nextCursor == null,
        clearError: true,
      );
    } on DomainError catch (error) {
      return requested.copyWith(
        items: append ? requested.items : const [],
        loading: false,
        error: error,
        clearCursor: true,
      );
    } on Object {
      return requested.copyWith(
        items: append ? requested.items : const [],
        loading: false,
        error: const DomainError(
          code: 'NETWORK_ERROR',
          message: 'Jentra could not load this setup list.',
          retryable: true,
        ),
        clearCursor: true,
      );
    }
  }

  static BusinessSetupResource? _preferredResource(
    BusinessSetupCategory category,
    List<BusinessSetupResource> candidates,
  ) {
    if (candidates.isEmpty) return null;
    final preferred = switch (category) {
      BusinessSetupCategory.finance => BusinessSetupResource.accounts,
      BusinessSetupCategory.parties => BusinessSetupResource.parties,
      BusinessSetupCategory.catalogue => BusinessSetupResource.products,
      BusinessSetupCategory.governance =>
        BusinessSetupResource.documentSequences,
      BusinessSetupCategory.filesAndData => BusinessSetupResource.attachments,
      BusinessSetupCategory.reports => BusinessSetupResource.reportDefinitions,
    };
    return candidates.contains(preferred) ? preferred : candidates.first;
  }

  static List<SetupRecord> _filterPreview(
    List<SetupRecord> source,
    String search,
    String? status,
  ) {
    final query = search.trim().toLowerCase();
    return source
        .where((record) {
          final matchesStatus = status == null || record.status == status;
          final haystack = <Object?>[
            record.code,
            record.name,
            ...record.fields.values,
          ].join(' ').toLowerCase();
          return matchesStatus && (query.isEmpty || haystack.contains(query));
        })
        .toList(growable: false);
  }

  static String _requestId() => _uuid.v4();

  static Map<String, Object?> _scopePayload(
    BusinessSetupResource resource,
    TenantContext context,
    Map<String, Object?> payload,
  ) {
    if (resource != BusinessSetupResource.documentSequences) return payload;
    return <String, Object?>{
      ...payload,
      'legal_entity_id': context.legalEntityId,
      'branch_id': context.branchId,
    };
  }

  static String _draftId(
    BusinessSetupResource resource, {
    Map<String, Object?> payload = const {},
  }) {
    final identity =
        payload['id'] ??
        payload['code'] ??
        payload['sku'] ??
        payload['document_type'] ??
        payload['name'] ??
        DateTime.now().microsecondsSinceEpoch;
    final safeIdentity = identity.toString().trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9_-]+'),
      '-',
    );
    return 'draft-${resource.name}-$safeIdentity';
  }

  static SetupRecord _previewFromPayload(
    BusinessSetupResource resource,
    TenantContext context,
    Map<String, Object?> payload, {
    SetupRecord? existing,
  }) {
    final now = DateTime.now().toUtc();
    final code = switch (resource) {
      BusinessSetupResource.products => payload['sku'],
      BusinessSetupResource.documentSequences => payload['document_type'],
      BusinessSetupResource.workflowDefinitions => payload['document_type'],
      _ => payload['code'],
    };
    final name = switch (resource) {
      BusinessSetupResource.parties => payload['display_name'],
      BusinessSetupResource.reportDefinitions => payload['title'],
      _ => payload['name'],
    };
    return SetupRecord(
      resource: resource,
      id: existing?.id ?? _draftId(resource, payload: payload),
      tenantId: context.tenantId,
      legalEntityId: resource.requiresLegalEntity
          ? context.legalEntityId
          : null,
      code: code?.toString() ?? '',
      name: name?.toString() ?? code?.toString() ?? resource.singularLabel,
      status: payload['status']?.toString() ?? 'active',
      version: (existing?.version ?? 0) + 1,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      fields: payload,
    );
  }

  static List<SetupRecord> _previewRecords(
    BusinessSetupResource resource,
    TenantContext context,
  ) {
    final now = DateTime.utc(2026, 9, 1, 8, 30);
    SetupRecord record(
      String id,
      String code,
      String name,
      Map<String, Object?> fields, {
      String status = 'active',
    }) => SetupRecord(
      resource: resource,
      id: id,
      tenantId: resource == BusinessSetupResource.currencies
          ? ''
          : context.tenantId,
      legalEntityId: resource.requiresLegalEntity
          ? context.legalEntityId
          : null,
      code: code,
      name: name,
      status: status,
      version: 1,
      createdAt: now,
      updatedAt: now,
      fields: fields,
    );

    return switch (resource) {
      BusinessSetupResource.currencies => [
        record('LKR', 'LKR', 'Sri Lankan Rupee', const {'minor_units': 2}),
        record('USD', 'USD', 'US Dollar', const {'minor_units': 2}),
        record('EUR', 'EUR', 'Euro', const {'minor_units': 2}),
        record('SAR', 'SAR', 'Saudi Riyal', const {'minor_units': 2}),
      ],
      BusinessSetupResource.exchangeRates => [
        record('rate-1', 'USD/LKR', 'US Dollar to Sri Lankan Rupee', const {
          'source_currency_code': 'USD',
          'target_currency_code': 'LKR',
          'rate': '302.4500000000',
          'effective_date': '2026-09-01',
          'rate_type': 'spot',
        }),
      ],
      BusinessSetupResource.taxDefinitions => [
        record('tax-1', 'VAT18', 'VAT Output 18%', const {
          'rate': '18.000000',
          'kind': 'output',
          'valid_from': '2026-01-01',
        }),
        record('tax-2', 'SVAT', 'Suspended VAT', const {
          'rate': '0.000000',
          'kind': 'output',
          'valid_from': '2026-01-01',
        }),
      ],
      BusinessSetupResource.accounts => [
        record('account-1000', '1000', 'Cash and cash equivalents', const {
          'account_type': 'asset',
          'normal_balance': 'debit',
          'is_posting': true,
        }),
        record('account-1100', '1100', 'Trade receivables', const {
          'account_type': 'asset',
          'normal_balance': 'debit',
          'is_posting': true,
        }),
        record('account-4000', '4000', 'Sales revenue', const {
          'account_type': 'revenue',
          'normal_balance': 'credit',
          'is_posting': true,
        }),
        record('account-5100', '5100', 'Cost of goods sold', const {
          'account_type': 'expense',
          'normal_balance': 'debit',
          'is_posting': true,
        }),
      ],
      BusinessSetupResource.fiscalPeriods => [
        record('period-1', 'FY26-09', 'September 2026', const {
          'start_date': '2026-09-01',
          'end_date': '2026-09-30',
          'state': 'open',
        }),
      ],
      BusinessSetupResource.parties => [
        record('party-1', 'CUS-001', 'Ceylon Retail Group', const {
          'kind': 'customer',
          'legal_name': 'Ceylon Retail Group (Pvt) Ltd',
        }),
        record('party-2', 'SUP-001', 'Lanka Packaging', const {
          'kind': 'supplier',
          'legal_name': 'Lanka Packaging PLC',
        }),
      ],
      BusinessSetupResource.contacts => [
        record('contact-1', 'NIM-001', 'Nimali Perera', const {
          'party_id': 'party-1',
          'email': 'nimali@example.lk',
          'role': 'Finance manager',
        }),
      ],
      BusinessSetupResource.units => [
        record('unit-1', 'EA', 'Each', const {
          'symbol': 'ea',
          'category': 'quantity',
          'precision': 0,
        }),
        record('unit-2', 'KG', 'Kilogram', const {
          'symbol': 'kg',
          'category': 'weight',
          'precision': 3,
        }),
      ],
      BusinessSetupResource.products => [
        record('product-1', 'JTR-TEA-100', 'Ceylon Tea 100 g', const {
          'kind': 'stocked',
          'tracking_mode': 'lot',
          'base_unit_id': 'unit-1',
        }),
        record('product-2', 'JTR-SVC-01', 'Equipment inspection', const {
          'kind': 'service',
          'tracking_mode': 'none',
          'base_unit_id': 'unit-1',
        }),
      ],
      BusinessSetupResource.documentSequences => [
        record('sequence-1', 'SALES_INVOICE', 'Sales invoices', const {
          'document_type': 'sales_invoice',
          'prefix': 'INV-2026-',
          'padding': 5,
          'next_number': 1085,
          'reset_policy': 'yearly',
        }),
      ],
      BusinessSetupResource.workflowDefinitions => [
        record(
          'workflow-1',
          'PURCHASE_ORDER',
          'Purchase-order approval',
          const {
            'document_type': 'purchase_order',
            'lifecycle': {
              'states': [
                'draft',
                'submitted',
                'approved',
                'rejected',
                'posted',
                'settled',
                'fulfilled',
                'closed',
                'cancelled',
                'reversed',
              ],
              'transitions': [
                ['draft', 'submitted'],
                ['draft', 'cancelled'],
                ['submitted', 'approved'],
                ['submitted', 'rejected'],
                ['submitted', 'cancelled'],
                ['rejected', 'draft'],
                ['rejected', 'cancelled'],
                ['approved', 'posted'],
                ['approved', 'cancelled'],
                ['posted', 'settled'],
                ['posted', 'fulfilled'],
                ['posted', 'closed'],
                ['posted', 'reversed'],
                ['settled', 'closed'],
                ['fulfilled', 'closed'],
              ],
            },
          },
          status: 'draft',
        ),
      ],
      BusinessSetupResource.approvalMatrixSteps => [
        record('approval-1', 'PO-01', 'Finance review', const {
          'workflow_definition_id': 'workflow-1',
          'role_id': 'finance-manager',
          'step_order': 1,
          'minimum_amount': '100000.000000',
        }),
      ],
      BusinessSetupResource.attachments => [
        record('attachment-1', 'ATT-001', 'chart-of-accounts.xlsx', const {
          'mime_type':
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          'byte_size': 18420,
          'aggregate_type': 'import_job',
        }, status: 'ready'),
      ],
      BusinessSetupResource.notifications => [
        record(
          'notification-1',
          'SETUP_READY',
          'Business setup is ready',
          const {
            'body': 'The shared foundation catalogue is available.',
            'read_at': null,
          },
          status: 'unread',
        ),
      ],
      BusinessSetupResource.importJobs => [
        record('import-1', 'IMP-260901', 'Product catalogue import', const {
          'resource': 'products',
          'format': 'xlsx',
          'row_count': 42,
        }, status: 'completed'),
      ],
      BusinessSetupResource.exportJobs => [
        record('export-1', 'EXP-260901', 'Chart of accounts export', const {
          'resource': 'accounts',
          'format': 'csv',
          'row_count': 84,
        }, status: 'completed'),
      ],
      BusinessSetupResource.reportDefinitions => [
        record('report-1', 'COA-ACTIVE', 'Active chart of accounts', const {
          'source_view': 'accounts',
          'columns': ['code', 'name', 'account_type', 'status'],
        }),
      ],
    };
  }
}

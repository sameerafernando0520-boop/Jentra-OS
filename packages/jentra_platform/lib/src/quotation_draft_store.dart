import 'dart:async';
import 'dart:convert';

import 'package:jentra_domain/jentra_domain.dart';
import 'package:uuid/uuid.dart';

import 'draft_repository.dart';

/// An immutable, persisted wire envelope. Replay never invents a new timestamp,
/// request key, version, or payload after an uncertain transport outcome.
final class QuotationPendingCommand {
  QuotationPendingCommand._(Map<String, Object?> json)
    : _encoded = jsonEncode(json);

  final String _encoded;
  Map<String, Object?> toJson() =>
      (jsonDecode(_encoded) as Map).cast<String, Object?>();
  String get verb => toJson()['verb']! as String;
  CommandEnvelope<Map<String, Object?>> get envelope {
    final json = (toJson()['envelope']! as Map).cast<String, Object?>();
    return CommandEnvelope(
      commandId: json['command_id']! as String,
      idempotencyKey: json['idempotency_key']! as String,
      context: TenantContext.fromJson(
        (json['context']! as Map).cast<String, Object?>(),
      ),
      payload: (json['payload']! as Map).cast<String, Object?>(),
      clientTimestamp: DateTime.parse(json['client_timestamp']! as String),
      expectedEntityVersion: json['expected_entity_version'] as int?,
    );
  }
}

final class QuotationLocalDraft {
  const QuotationLocalDraft({
    required this.form,
    required this.expectedVersion,
    required this.localVersion,
    this.pending,
    this.errorCode,
  });
  final Map<String, Object?> form;
  final int? expectedVersion;
  final int localVersion;
  final QuotationPendingCommand? pending;
  final String? errorCode;
}

final class QuotationRecoveryEntry {
  const QuotationRecoveryEntry({required this.slot, required this.draft});
  final String slot;
  final QuotationLocalDraft draft;
}

/// Raw editor fields may be incomplete; only prepare receives validated command
/// input. No automatic network sync or conflict merge is performed here.
final class QuotationDraftStore {
  QuotationDraftStore(this._repository) : _orders = false, _procurement = false;
  QuotationDraftStore.orders(this._repository)
    : _orders = true,
      _procurement = false;
  QuotationDraftStore.procurement(this._repository)
    : _orders = false,
      _procurement = true;
  final EncryptedDraftRepository _repository;
  final bool _orders;
  final bool _procurement;
  String get _prefix => _procurement
      ? 'procurement:'
      : _orders
      ? 'order:'
      : 'quotation:';
  String get _entityType => _procurement
      ? 'procurement.requisition'
      : _orders
      ? 'sales.order'
      : 'sales.quotation';
  static const _uuid = Uuid();
  // Serialize store instances sharing a database too. This guards double-clicks
  // and overlapping editor instances in one application process.
  static final _queues = <String, Future<void>>{};

  Future<CursorPage<QuotationRecoveryEntry>> pageDrafts(
    TenantContext context, {
    String? afterId,
  }) async {
    final ids = await _repository.pageIds(
      tenantId: context.tenantId,
      entityType: _entityType,
      afterId: afterId,
    );
    final entries = <QuotationRecoveryEntry>[];
    for (final id in ids) {
      if (!id.startsWith(_prefix)) continue;
      final identity =
          jsonDecode(
                utf8.decode(base64Url.decode(id.substring(_prefix.length))),
              )
              as List;
      if (TenantContext.fromJson(
            (identity[0] as Map).cast<String, Object?>(),
          ) !=
          context) {
        continue;
      }
      final slot = identity[1] as String;
      final draft = await load(context, slot);
      if (draft != null) {
        entries.add(QuotationRecoveryEntry(slot: slot, draft: draft));
      }
    }
    return CursorPage(
      items: entries,
      limit: 100,
      nextCursor: ids.length == 100 ? ids.last : null,
    );
  }

  String _key(TenantContext context, String slot) =>
      '$_prefix${base64Url.encode(utf8.encode(jsonEncode([context.toJson(), slot])))}';

  Future<T> _locked<T>(String key, Future<T> Function() action) async {
    final previous = _queues[key] ?? Future<void>.value();
    final done = Completer<void>();
    final current = done.future;
    _queues[key] = current;
    await previous;
    try {
      return await action();
    } finally {
      done.complete();
      if (identical(_queues[key], current)) _queues.remove(key);
    }
  }

  Future<QuotationLocalDraft?> load(TenantContext context, String slot) async {
    final row = await _repository.find(_key(context, slot));
    if (row == null) return null;
    final data = row.payload;
    if (row.tenantId != context.tenantId ||
        row.entityType != _entityType ||
        TenantContext.fromJson(
              (data['scope']! as Map).cast<String, Object?>(),
            ) !=
            context) {
      throw const DomainError(
        code: 'DRAFT_SCOPE_MISMATCH',
        message: 'This draft belongs to a different business scope.',
      );
    }
    return QuotationLocalDraft(
      form: (data['form']! as Map).cast<String, Object?>(),
      expectedVersion: row.serverVersion,
      localVersion: row.localVersion,
      pending: data['pending'] == null
          ? null
          : QuotationPendingCommand._(
              (data['pending']! as Map).cast<String, Object?>(),
            ),
      errorCode: data['error_code'] as String?,
    );
  }

  Future<void> _write(
    TenantContext context,
    String slot,
    QuotationLocalDraft state,
  ) => _repository.save(
    id: _key(context, slot),
    tenantId: context.tenantId,
    entityType: _entityType,
    payload: {
      'scope': context.toJson(),
      'form': state.form,
      'pending': state.pending?.toJson(),
      'error_code': state.errorCode,
    },
    localVersion: state.localVersion,
    serverVersion: state.expectedVersion,
    syncState: state.errorCode == 'VERSION_CONFLICT'
        ? DraftSyncState.conflicted
        : DraftSyncState.localOnly,
  );

  Future<void> save(
    TenantContext context,
    String slot,
    Map<String, Object?> form, {
    int? expectedVersion,
    bool resolveConflict = false,
  }) => _locked(_key(context, slot), () async {
    final old = await load(context, slot);
    if (old?.pending != null) throw _pendingError;
    if (old?.errorCode == 'VERSION_CONFLICT' && !resolveConflict) {
      throw _conflictError;
    }
    await _write(
      context,
      slot,
      QuotationLocalDraft(
        form: form,
        expectedVersion: expectedVersion,
        localVersion: (old?.localVersion ?? 0) + 1,
      ),
    );
  });

  Future<QuotationPendingCommand> prepare(
    TenantContext context,
    String slot, {
    required String verb,
    required Map<String, Object?> payload,
    int? expectedVersion,
  }) => _locked(_key(context, slot), () async {
    if (!(_orders
            ? const {
                'save',
                'convert',
                'fulfillment',
                'confirm',
                'cancel',
                'reserve',
              }
            : const {
                'save',
                'submit',
                'recall',
                'accept',
                'expire',
                'cancel',
                'approve',
                'reject',
              })
        .contains(verb)) {
      throw const DomainError(
        code: 'VALIDATION_ERROR',
        message: 'Unknown document command.',
      );
    }
    final old = await load(context, slot);
    if (old?.errorCode == 'VERSION_CONFLICT') throw _conflictError;
    final pending = old?.pending;
    if (pending != null) {
      final envelope = pending.envelope;
      if (pending.verb != verb ||
          envelope.expectedEntityVersion != expectedVersion ||
          _canonical(envelope.payload) != _canonical(payload)) {
        throw _pendingError;
      }
      return pending;
    }
    if (old != null && old.expectedVersion != expectedVersion) {
      throw _conflictError;
    }
    final command = QuotationPendingCommand._({
      'verb': verb,
      'envelope': CommandEnvelope<Map<String, Object?>>(
        commandId: _uuid.v4(),
        idempotencyKey: _uuid.v4(),
        context: context,
        payload: payload,
        expectedEntityVersion: expectedVersion,
      ).toJson((value) => value),
    });
    await _write(
      context,
      slot,
      QuotationLocalDraft(
        form: old?.form ?? payload,
        expectedVersion: expectedVersion,
        localVersion: (old?.localVersion ?? 0) + 1,
        pending: command,
      ),
    );
    return command;
  });

  Future<void> recordFailure(
    TenantContext context,
    String slot,
    DomainError error, {
    required String commandId,
  }) => _locked(_key(context, slot), () async {
    final old = await load(context, slot);
    if (old?.pending == null) return;
    if (old!.pending!.envelope.commandId != commandId) throw _pendingError;
    // Only known pre-commit rejections release the envelope. Unknown errors,
    // timeouts and malformed success responses may follow a committed command.
    final definite = const {
      'VERSION_CONFLICT',
      'VALIDATION_ERROR',
      'PERMISSION_DENIED',
      'AUTHENTICATION_REQUIRED',
      'INVALID_REFERENCE',
      'NOT_FOUND',
      'CONFLICT',
      'SEGREGATION_OF_DUTIES_VIOLATION',
      'BRANCH_REQUIRED',
      'LEGAL_ENTITY_REQUIRED',
      'WORKFLOW_CONFIGURATION_ERROR',
      'WORKFLOW_TRANSITION_INVALID',
      'QUOTATION_RECALCULATION_REQUIRED',
      'INVALID_DOCUMENT_STATE',
      'QUOTATION_EXPIRED',
      'QUOTATION_NOT_EXPIRED',
      'ACCEPTED_QUOTATION_IMMUTABLE',
      'QUOTATION_REVISION_NOT_ALLOWED',
      'QUOTATION_REVISION_REQUIRED',
      'QUOTATION_NOT_DRAFT',
      'QUOTATION_HAS_NO_LINES',
      'QUOTATION_NOT_RECALLABLE',
      'QUOTATION_NOT_ACCEPTABLE',
      'QUOTATION_NOT_EXPIRABLE',
      'QUOTATION_NOT_CANCELLABLE',
      'APPROVAL_NOT_PENDING',
      'APPROVAL_REQUEST_NOT_FOUND',
      'CUSTOMER_INACTIVE',
      'CREDIT_CURRENCY_MISMATCH',
      'WAREHOUSE_INACTIVE',
      'PRODUCT_NOT_RESERVABLE',
      'SALES_ORDER_NOT_EDITABLE',
      'SALES_ORDER_NOT_CONFIRMABLE',
      'SALES_ORDER_NOT_CANCELLABLE',
      'FULFILLED_ORDER_NOT_CANCELLABLE',
      'SALES_ORDER_NOT_RESERVABLE',
      'ORDER_NOT_EDITABLE',
      'ORDER_NOT_CONFIRMABLE',
      'ORDER_NOT_CANCELLABLE',
      'ORDER_ALREADY_FULFILLED',
      'ORDER_NOT_RESERVABLE',
      'CONVERTED_ORDER_SOURCE_IMMUTABLE',
      'FULFILLMENT_FIELDS_ONLY',
    }.contains(error.code);
    await _write(
      context,
      slot,
      QuotationLocalDraft(
        form: old.form,
        expectedVersion: old.expectedVersion,
        localVersion: old.localVersion + 1,
        pending: definite ? null : old.pending,
        errorCode: error.code,
      ),
    );
  });

  /// Call only after a confirmed success for this exact pending command.
  /// Replace the sealed request and confirmed form in one encrypted write.
  /// A failed write retains the original request for an identical retry.
  Future<void> confirm(
    TenantContext context,
    String slot,
    String commandId, {
    required Map<String, Object?> form,
    int? expectedVersion,
  }) => _locked(_key(context, slot), () async {
    final old = await load(context, slot);
    if (old?.pending?.envelope.commandId != commandId) throw _pendingError;
    await _write(
      context,
      slot,
      QuotationLocalDraft(
        form: form,
        expectedVersion: expectedVersion,
        localVersion: old!.localVersion + 1,
      ),
    );
  });

  /// Call only after a confirmed success for this exact pending command.
  Future<void> complete(TenantContext context, String slot, String commandId) =>
      _locked(_key(context, slot), () async {
        final old = await load(context, slot);
        if (old?.pending?.envelope.commandId != commandId) throw _pendingError;
        await _repository.delete(_key(context, slot));
      });

  Future<void> discard(TenantContext context, String slot) =>
      _locked(_key(context, slot), () async {
        if ((await load(context, slot))?.pending != null) throw _pendingError;
        await _repository.delete(_key(context, slot));
      });

  static String _canonical(Object? value) => jsonEncode(_sorted(value));
  static Object? _sorted(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _sorted(value[key])};
    }
    if (value is List) return value.map(_sorted).toList();
    return value;
  }

  static const _pendingError = DomainError(
    code: 'COMMAND_PENDING',
    message: 'Resolve or retry the stored command before changing this draft.',
  );
  static const _conflictError = DomainError(
    code: 'VERSION_CONFLICT',
    message:
        'Compare the latest server revision and explicitly resolve this draft.',
  );
}

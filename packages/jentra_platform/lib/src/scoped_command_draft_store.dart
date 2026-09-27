import 'dart:async';
import 'dart:convert';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:uuid/uuid.dart';
import 'draft_repository.dart';

/// Operational module drafts. Each module supplies its own allowlist/validator;
/// this store is not a private-document or private-profile cache.
final class ScopedPendingCommand {
  ScopedPendingCommand(
    String action,
    CommandEnvelope<Map<String, Object?>> command,
  ) : _wire = jsonEncode({
        'action': action,
        'envelope': command.toJson((p) => p),
      });
  ScopedPendingCommand.fromJson(Map<String, Object?> row)
    : _wire = jsonEncode(row);
  final String _wire;
  Map<String, Object?> toJson() =>
      Map<String, Object?>.from(jsonDecode(_wire) as Map);
  String get action => toJson()['action'] as String;
  CommandEnvelope<Map<String, Object?>> get envelope {
    final row = Map<String, Object?>.from(toJson()['envelope'] as Map);
    return CommandEnvelope(
      commandId: row['command_id'] as String,
      idempotencyKey: row['idempotency_key'] as String,
      context: TenantContext.fromJson(
        Map<String, Object?>.from(row['context'] as Map),
      ),
      payload: Map<String, Object?>.from(row['payload'] as Map),
      clientTimestamp: DateTime.parse(row['client_timestamp'] as String),
      expectedEntityVersion: row['expected_entity_version'] as int,
    );
  }
}

final class ScopedCommandDraft {
  const ScopedCommandDraft({
    required this.aggregateId,
    required this.action,
    required this.form,
    required this.version,
    required this.localVersion,
    this.pending,
    this.errorCode,
  });
  final String aggregateId, action;
  final Map<String, Object?> form;
  final int version, localVersion;
  final ScopedPendingCommand? pending;
  final String? errorCode;
}

final class ScopedDraftPage {
  const ScopedDraftPage(this.items, this.nextCursor);
  final List<ScopedCommandDraft> items;
  final String? nextCursor;
}

final class ScopedCommandDraftStore {
  ScopedCommandDraftStore(
    this.repository, {
    required this.entityType,
    required this.fields,
    required this.validate,
    required this.definiteFailures,
  });
  final EncryptedDraftRepository repository;
  final String entityType;
  final Set<String> Function(String action) fields;
  final void Function(String action, Map<String, Object?> payload) validate;
  final Set<String> definiteFailures;
  static const uuid = Uuid();
  static final _queues = <String, Future<void>>{};
  String _prefix(TenantContext scope) =>
      'w4:$entityType:${base64Url.encode(utf8.encode(jsonEncode(scope.toJson())))}:';
  String _key(TenantContext scope, String id) => '${_prefix(scope)}$id';
  Future<T> _locked<T>(String key, Future<T> Function() work) async {
    final previous = _queues[key] ?? Future<void>.value();
    final done = Completer<void>();
    _queues[key] = done.future;
    await previous;
    try {
      return await work();
    } finally {
      done.complete();
      if (identical(_queues[key], done.future)) {
        _queues.remove(key);
      }
    }
  }

  void _form(String action, Map<String, Object?> form, String id) {
    final allow = fields(action);
    if (form['id'] != id || form.keys.any((k) => !allow.contains(k))) {
      throw const FormatException(
        'Draft contains an unrelated identity or unexpected fields.',
      );
    }
    final bytes = utf8.encode(jsonEncode(form)).length;
    if (bytes > 256 * 1024) {
      throw const FormatException('Draft exceeds its bounded size.');
    }
  }

  Future<ScopedCommandDraft?> load(TenantContext scope, String id) async {
    final row = await repository.find(_key(scope, id));
    if (row == null) {
      return null;
    }
    final data = row.payload;
    if (row.tenantId != scope.tenantId ||
        row.entityType != entityType ||
        data['aggregate_id'] != id ||
        TenantContext.fromJson(
              Map<String, Object?>.from(data['scope'] as Map),
            ) !=
            scope) {
      throw const DomainError(
        code: 'DRAFT_SCOPE_MISMATCH',
        message: 'The stored request belongs to another scope.',
      );
    }
    final action = data['action'] as String;
    final form = Map<String, Object?>.from(data['form'] as Map);
    _form(action, form, id);
    final pending = data['pending'] == null
        ? null
        : ScopedPendingCommand.fromJson(
            Map<String, Object?>.from(data['pending'] as Map),
          );
    if (pending != null) {
      final command = pending.envelope;
      validate(pending.action, command.payload);
      if (command.context != scope ||
          command.payload['id'] != id ||
          pending.action != action ||
          command.expectedEntityVersion != row.serverVersion) {
        throw const DomainError(
          code: 'DRAFT_SCOPE_MISMATCH',
          message: 'The sealed request does not match this draft.',
        );
      }
    }
    return ScopedCommandDraft(
      aggregateId: id,
      action: action,
      form: form,
      version: row.serverVersion ?? 0,
      localVersion: row.localVersion,
      pending: pending,
      errorCode: data['error_code'] as String?,
    );
  }

  Future<ScopedDraftPage> page(TenantContext scope, {String? after}) async {
    final ids = await repository.pageIds(
      tenantId: scope.tenantId,
      entityType: entityType,
      afterId: after,
      limit: 50,
    );
    final items = <ScopedCommandDraft>[];
    for (final key in ids.where((k) => k.startsWith(_prefix(scope)))) {
      final row = await load(scope, key.substring(_prefix(scope).length));
      if (row != null) {
        items.add(row);
      }
    }
    return ScopedDraftPage(
      List.unmodifiable(items),
      ids.length == 50 ? ids.last : null,
    );
  }

  Future<void> _write(TenantContext scope, ScopedCommandDraft draft) =>
      repository.save(
        id: _key(scope, draft.aggregateId),
        tenantId: scope.tenantId,
        entityType: entityType,
        payload: {
          'scope': scope.toJson(),
          'aggregate_id': draft.aggregateId,
          'action': draft.action,
          'form': draft.form,
          'pending': draft.pending?.toJson(),
          'error_code': draft.errorCode,
        },
        localVersion: draft.localVersion,
        serverVersion: draft.version,
        syncState: draft.errorCode == 'VERSION_CONFLICT'
            ? DraftSyncState.conflicted
            : DraftSyncState.localOnly,
      );
  Future<void> save(
    TenantContext scope,
    String id,
    String action,
    Map<String, Object?> input,
    int version, {
    bool resolveConflict = false,
  }) {
    final form = Map<String, Object?>.from(
      jsonDecode(jsonEncode(input)) as Map,
    );
    return _locked(_key(scope, id), () async {
      _form(action, form, id);
      final old = await load(scope, id);
      if (old?.pending != null) {
        throw const DomainError(
          code: 'COMMAND_PENDING',
          message: 'Resolve the original saved request before editing.',
        );
      }
      if (old?.errorCode == 'VERSION_CONFLICT' && !resolveConflict) {
        throw const DomainError(
          code: 'VERSION_CONFLICT',
          message: 'Compare the current server version first.',
        );
      }
      await _write(
        scope,
        ScopedCommandDraft(
          aggregateId: id,
          action: action,
          form: Map.from(form),
          version: version,
          localVersion: (old?.localVersion ?? 0) + 1,
        ),
      );
    });
  }

  Future<ScopedPendingCommand> prepare(
    TenantContext scope,
    String id,
    String action,
    Map<String, Object?> input,
    int version,
  ) {
    final payload = Map<String, Object?>.from(
      jsonDecode(jsonEncode(input)) as Map,
    );
    return _locked(_key(scope, id), () async {
      _form(action, payload, id);
      validate(action, payload);
      if (version < 0 || version >= 9007199254740991) {
        throw const FormatException('Expected version is invalid.');
      }
      final old = await load(scope, id);
      if (old?.pending != null) {
        final sealed = old!.pending!;
        if (sealed.action == action &&
            sealed.envelope.expectedEntityVersion == version &&
            _canonical(sealed.envelope.payload) == _canonical(payload)) {
          return sealed;
        }
        throw const DomainError(
          code: 'COMMAND_PENDING',
          message: 'Retry the exact original saved request before changing it.',
        );
      }
      if (old?.errorCode == 'VERSION_CONFLICT' ||
          old != null && old.version != version) {
        throw const DomainError(
          code: 'VERSION_CONFLICT',
          message: 'Resolve the stale draft before retrying.',
        );
      }
      final pending = ScopedPendingCommand(
        action,
        CommandEnvelope(
          commandId: uuid.v4(),
          idempotencyKey: uuid.v4(),
          context: scope,
          payload: payload,
          expectedEntityVersion: version,
        ),
      );
      await _write(
        scope,
        ScopedCommandDraft(
          aggregateId: id,
          action: action,
          form: old?.form ?? Map.from(payload),
          version: version,
          localVersion: (old?.localVersion ?? 0) + 1,
          pending: pending,
        ),
      );
      return pending;
    });
  }

  Future<void> recordFailure(
    TenantContext scope,
    String id,
    String commandId,
    DomainError error,
  ) => _locked(_key(scope, id), () async {
    final old = await load(scope, id);
    if (old?.pending?.envelope.commandId != commandId) {
      return;
    }
    await _write(
      scope,
      ScopedCommandDraft(
        aggregateId: id,
        action: old!.action,
        form: old.form,
        version: old.version,
        localVersion: old.localVersion + 1,
        pending: definiteFailures.contains(error.code) ? null : old.pending,
        errorCode: error.code,
      ),
    );
  });
  Future<void> complete(TenantContext scope, String id, String commandId) =>
      _locked(_key(scope, id), () async {
        if ((await load(scope, id))?.pending?.envelope.commandId != commandId) {
          throw const DomainError(
            code: 'COMMAND_PENDING',
            message: 'Confirmation does not match the stored request.',
          );
        }
        await repository.delete(_key(scope, id));
      });
  Future<void> discard(TenantContext scope, String id) =>
      _locked(_key(scope, id), () async {
        if ((await load(scope, id))?.pending != null) {
          throw const DomainError(
            code: 'COMMAND_PENDING',
            message: 'Resolve the sealed request before discarding.',
          );
        }
        await repository.delete(_key(scope, id));
      });
  static String _canonical(Object? value) => jsonEncode(_sort(value));
  static Object? _sort(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final k in keys) k: _sort(value[k])};
    }
    if (value is List) {
      return value.map(_sort).toList();
    }
    return value;
  }
}

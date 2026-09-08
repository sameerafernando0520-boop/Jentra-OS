import 'dart:async';
import 'dart:convert';
import 'package:jentra_domain/jentra_receivables.dart';
import 'package:uuid/uuid.dart';
import 'draft_repository.dart';

final class ReceivableLocalDraft {
  ReceivableLocalDraft(Map<String, Object?> json) : _encoded = jsonEncode(json);
  final String _encoded;
  Map<String, Object?> get data => receivableMap(jsonDecode(_encoded));
  Map<String, Object?> get form => receivableMap(data['form']);
  int? get version => data['version'] as int?;
  bool get pending => data['pending'] != null;
  String? get error => data['error'] as String?;
  String get rpc => receivableMap(data['pending'])['rpc']! as String;
  CommandEnvelope<Map<String, Object?>> get envelope {
    final e = receivableMap(receivableMap(data['pending'])['envelope']);
    return CommandEnvelope(
      commandId: e['command_id']! as String,
      idempotencyKey: e['idempotency_key']! as String,
      context: TenantContext.fromJson(receivableMap(e['context'])),
      payload: receivableMap(e['payload']),
      expectedEntityVersion: e['expected_entity_version'] as int?,
      clientTimestamp: DateTime.parse(e['client_timestamp']! as String),
    );
  }
}

/// Separate namespace; never touches quotation or AC-304 recovery rows.
final class ReceivableDraftStore {
  ReceivableDraftStore(this.repository, {String Function()? newId})
    : _newId = newId ?? _randomId;
  final EncryptedDraftRepository repository;
  final String Function() _newId;
  static String _randomId() => const Uuid().v4();
  static final _queues = <String, Future<void>>{};
  String _key(TenantContext scope, String slot) =>
      'receivable:${base64Url.encode(utf8.encode(jsonEncode([scope.toJson(), slot])))}';
  Future<T> _locked<T>(String key, Future<T> Function() action) async {
    final prior = _queues[key] ?? Future<void>.value(),
        done = Completer<void>();
    _queues[key] = done.future;
    await prior;
    try {
      return await action();
    } finally {
      done.complete();
      if (identical(_queues[key], done.future)) _queues.remove(key);
    }
  }

  Future<ReceivableLocalDraft?> load(TenantContext scope, String slot) async {
    final row = await repository.find(_key(scope, slot));
    if (row == null) return null;
    if (row.entityType != 'sales.receivables' ||
        row.tenantId != scope.tenantId ||
        TenantContext.fromJson(receivableMap(row.payload['scope'])) != scope) {
      throw const ReceivableFailure(
        'SCOPE_MISMATCH',
        'Draft belongs to a different business scope.',
        definite: true,
      );
    }
    return ReceivableLocalDraft(row.payload);
  }

  Future<void> _write(
    TenantContext scope,
    String slot,
    Map<String, Object?> value,
  ) => repository.save(
    id: _key(scope, slot),
    tenantId: scope.tenantId,
    entityType: 'sales.receivables',
    payload: {...value, 'scope': scope.toJson()},
    localVersion: DateTime.now().microsecondsSinceEpoch,
    serverVersion: value['version'] as int?,
    syncState: value['error'] == 'VERSION_CONFLICT'
        ? DraftSyncState.conflicted
        : DraftSyncState.localOnly,
  );
  Future<void> save(
    TenantContext scope,
    String slot,
    Map<String, Object?> form,
    int? version,
  ) => _locked(_key(scope, slot), () async {
    final old = await load(scope, slot);
    if (old?.pending == true || old?.error == 'VERSION_CONFLICT') {
      throw const ReceivableFailure(
        'RECOVERY_REQUIRED',
        'Resolve the saved command or conflict first.',
        definite: true,
      );
    }
    await _write(scope, slot, {'form': form, 'version': version});
  });
  Future<ReceivableLocalDraft> prepare(
    TenantContext scope,
    String slot,
    String rpc,
    Map<String, Object?> payload,
    int? version,
  ) => _locked(_key(scope, slot), () async {
    final old = await load(scope, slot);
    if (old?.pending == true) {
      if (old!.rpc != rpc ||
          jsonEncode(old.envelope.payload) != jsonEncode(payload) ||
          old.version != version) {
        throw const ReceivableFailure(
          'RECOVERY_REQUIRED',
          'Retry the existing saved command first.',
          definite: true,
        );
      }
      return old;
    }
    if (old?.error == 'VERSION_CONFLICT') {
      throw const ReceivableFailure(
        'VERSION_CONFLICT',
        'Reload the server document before editing.',
        definite: true,
      );
    }
    final value = {
      'form': old?.form ?? payload,
      'version': version,
      'pending': {
        'rpc': rpc,
        'envelope': CommandEnvelope<Map<String, Object?>>(
          commandId: _newId(),
          idempotencyKey: _newId(),
          context: scope,
          payload: payload,
          expectedEntityVersion: version,
        ).toJson((p) => p),
      },
    };
    await _write(scope, slot, value);
    return ReceivableLocalDraft(value);
  });
  Future<void> failure(
    TenantContext scope,
    String slot,
    String commandId,
    ReceivableFailure error,
  ) => _locked(_key(scope, slot), () async {
    final old = await load(scope, slot);
    if (old?.pending != true || old!.envelope.commandId != commandId) return;
    await _write(scope, slot, {
      ...old.data,
      'error': error.code,
      if (error.definite) 'pending': null,
    });
  });
  Future<void> complete(TenantContext scope, String slot, String commandId) =>
      _locked(_key(scope, slot), () async {
        final old = await load(scope, slot);
        if (old?.pending != true || old!.envelope.commandId != commandId) {
          throw const ReceivableFailure(
            'RECOVERY_REQUIRED',
            'Saved command identity changed.',
          );
        }
        await repository.delete(_key(scope, slot));
      });
  Future<void> discard(TenantContext scope, String slot) =>
      _locked(_key(scope, slot), () async {
        if ((await load(scope, slot))?.pending == true) {
          throw const ReceivableFailure(
            'RECOVERY_REQUIRED',
            'An uncertain command cannot be discarded. Retry it first.',
          );
        }
        await repository.delete(_key(scope, slot));
      });
  Future<CursorPage<String>> recovery(
    TenantContext scope, {
    String? cursor,
  }) async {
    final ids = await repository.pageIds(
      tenantId: scope.tenantId,
      entityType: 'sales.receivables',
      afterId: cursor,
    );
    final slots = <String>[];
    for (final id in ids) {
      final identity =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(id.substring('receivable:'.length)),
                ),
              )
              as List;
      if (TenantContext.fromJson(receivableMap(identity[0])) == scope) {
        slots.add(identity[1] as String);
      }
    }
    return CursorPage(
      items: slots,
      limit: 100,
      nextCursor: ids.length == 100 ? ids.last : null,
    );
  }
}

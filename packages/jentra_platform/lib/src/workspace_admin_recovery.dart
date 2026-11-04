import 'dart:async';
import 'dart:convert';

import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_workspace_admin.dart';

import 'draft_repository.dart';

final class WorkspaceAdminPending {
  WorkspaceAdminPending(
    this.action,
    CommandEnvelope<Map<String, Object?>> command,
  ) : _json = jsonEncode(command.toJson((p) => p)) {
    validateWorkspaceAdminCommand(action, command);
  }
  final WorkspaceAdminAction action;
  final String _json;
  Map<String, Object?> get json =>
      (jsonDecode(_json) as Map).cast<String, Object?>();
  CommandEnvelope<Map<String, Object?>> get command {
    final e = json;
    return CommandEnvelope(
      commandId: e['command_id']! as String,
      idempotencyKey: e['idempotency_key']! as String,
      context: TenantContext.fromJson(
        (e['context']! as Map).cast<String, Object?>(),
      ),
      payload: (e['payload']! as Map).cast<String, Object?>(),
      expectedEntityVersion: e['expected_entity_version'] as int?,
      clientTimestamp: DateTime.parse(e['client_timestamp']! as String),
    );
  }
}

abstract interface class WorkspaceAdminRecovery {
  Future<WorkspaceAdminPending?> load(TenantContext scope);
  Future<WorkspaceAdminPending> seal(WorkspaceAdminPending pending);
  Future<void> complete(TenantContext scope, String commandId);
}

/// One exact pending command per actor and full business context. The underlying
/// repository encrypts payloads with the existing OS-protected cipher.
final class EncryptedWorkspaceAdminRecovery implements WorkspaceAdminRecovery {
  EncryptedWorkspaceAdminRecovery(this.repository);
  final EncryptedDraftRepository repository;
  static final _queues = <String, Future<void>>{};
  String _key(TenantContext s) =>
      'workspace-admin:${base64Url.encode(utf8.encode(jsonEncode(s.toJson())))}';
  Future<T> _lock<T>(TenantContext s, Future<T> Function() work) async {
    final key = _key(s),
        previous = _queues[_key(s)] ?? Future<void>.value(),
        done = Completer<void>();
    _queues[key] = done.future;
    await previous;
    try {
      return await work();
    } finally {
      done.complete();
      if (identical(_queues[key], done.future)) _queues.remove(key);
    }
  }

  @override
  Future<WorkspaceAdminPending?> load(TenantContext scope) async {
    final row = await repository.find(_key(scope));
    if (row == null) return null;
    if (row.tenantId != scope.tenantId ||
        row.entityType != 'workspace.admin.command') {
      throw const FormatException('Recovery scope differs.');
    }
    final data = row.payload,
        e = (data['envelope']! as Map).cast<String, Object?>();
    if (TenantContext.fromJson(
          (e['context']! as Map).cast<String, Object?>(),
        ) !=
        scope) {
      throw const FormatException(
        'Recovery belongs to another account or workplace.',
      );
    }
    final action = WorkspaceAdminAction.values
        .where((a) => a.wire == data['action'])
        .firstOrNull;
    if (action == null) {
      throw const FormatException('Unknown recovery command.');
    }
    return WorkspaceAdminPending(
      action,
      CommandEnvelope(
        commandId: e['command_id']! as String,
        idempotencyKey: e['idempotency_key']! as String,
        context: scope,
        payload: (e['payload']! as Map).cast<String, Object?>(),
        expectedEntityVersion: e['expected_entity_version'] as int?,
        clientTimestamp: DateTime.parse(e['client_timestamp']! as String),
      ),
    );
  }

  @override
  Future<WorkspaceAdminPending> seal(
    WorkspaceAdminPending pending,
  ) => _lock(pending.command.context, () async {
    final c = pending.command, old = await load(c.context);
    if (old != null) {
      if (old.action != pending.action ||
          workspaceAdminCanonical(old.json) !=
              workspaceAdminCanonical(pending.json)) {
        throw const DomainError(
          code: 'COMMAND_PENDING',
          message:
              'Resolve the original saved command before making another change.',
        );
      }
      return old;
    }
    await repository.save(
      id: _key(c.context),
      tenantId: c.context.tenantId,
      entityType: 'workspace.admin.command',
      payload: {'action': pending.action.wire, 'envelope': pending.json},
      localVersion: 1,
      serverVersion: c.expectedEntityVersion,
    );
    return pending;
  });
  @override
  Future<void> complete(TenantContext scope, String commandId) =>
      _lock(scope, () async {
        final old = await load(scope);
        if (old?.command.commandId != commandId) {
          throw const FormatException('Recovery command identity differs.');
        }
        await repository.delete(_key(scope));
      });
}

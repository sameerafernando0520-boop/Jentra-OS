import 'dart:convert';
import 'package:cryptography/cryptography.dart';

import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_service.dart';

import 'scoped_command_draft_store.dart';
import 'local_draft_storage_failure.dart';

/// Minimal encrypted evidence of a validated response, independent of cleanup.
/// It contains no service facts, customer evidence, rates or financial amounts.
final class ServiceCommandAcknowledgements {
  const ServiceCommandAcknowledgements(this.store);
  final ScopedCommandDraftStore store;

  String _key(ScopedPendingCommand request) =>
      'service.ack:${base64Url.encode(utf8.encode(jsonEncode(request.envelope.context.toJson())))}:${request.envelope.commandId}';
  Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  Future<String> _digest(ScopedPendingCommand request) async {
    final hash = await Sha256().hash(
      utf8.encode(jsonEncode(_canonical(request.envelope.toJson((p) => p)))),
    );
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> save(
    ScopedPendingCommand request,
    Map<String, Object?> response,
  ) async {
    final command = request.envelope;
    final entity = Map<String, Object?>.from(response['entity'] as Map);
    if (response['command_id'] != command.commandId ||
        entity['id'] != command.payload['id'] ||
        entity['kind'] != ServiceCommands.kind(request.action).name ||
        entity['tenant_id'] != command.context.tenantId ||
        entity['legal_entity_id'] != command.context.legalEntityId ||
        entity['branch_id'] != command.context.branchId ||
        entity['version'] != command.expectedEntityVersion! + 1) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'The confirmation does not match the original service request.',
        retryable: true,
      );
    }
    try {
      await store.repository.save(
        id: _key(request),
        tenantId: command.context.tenantId,
        entityType: 'service.command.acknowledgement',
        payload: {
          'scope': command.context.toJson(),
          'action': request.action,
          'command_id': command.commandId,
          'idempotency_key': command.idempotencyKey,
          'entity_id': command.payload['id'],
          'version': entity['version'],
          'request_digest': await _digest(request),
        },
        localVersion: 1,
        serverVersion: entity['version'] as int,
        syncState: DraftSyncState.localOnly,
      );
    } catch (error) {
      throw localDraftStorageFailure(error);
    }
  }

  Future<bool> contains(ScopedPendingCommand request) async {
    final command = request.envelope;
    final row = await store.repository.find(_key(request));
    if (row == null) return false;
    final body = row.payload;
    if (row.tenantId != command.context.tenantId ||
        row.entityType != 'service.command.acknowledgement' ||
        body.length != 7 ||
        TenantContext.fromJson(
              Map<String, Object?>.from(body['scope'] as Map),
            ) !=
            command.context ||
        body['action'] != request.action ||
        body['command_id'] != command.commandId ||
        body['idempotency_key'] != command.idempotencyKey ||
        body['entity_id'] != command.payload['id'] ||
        body['version'] != command.expectedEntityVersion! + 1 ||
        body['request_digest'] != await _digest(request)) {
      throw const DomainError(
        code: 'DRAFT_SCOPE_MISMATCH',
        message:
            'The saved confirmation belongs to a different service request.',
      );
    }
    return true;
  }
}

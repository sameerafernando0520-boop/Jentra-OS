import 'dart:convert';

import 'package:jentra_domain/jentra_domain.dart';

import 'local_draft_storage_failure.dart';
import 'scoped_command_draft_store.dart';

/// Encrypted confirmation identity persists independently of optional UI reads.
/// No project terms, rates, costs or employee facts are stored here.
final class ProjectCommandAcknowledgements {
  const ProjectCommandAcknowledgements(this.store);
  final ScopedCommandDraftStore store;

  String _key(ScopedPendingCommand request) =>
      'projects.ack:${base64Url.encode(utf8.encode(jsonEncode(request.envelope.context.toJson())))}:${request.envelope.commandId}';

  Future<void> save(
    ScopedPendingCommand request,
    Map<String, Object?> verifiedEntity,
  ) async {
    final command = request.envelope;
    if (verifiedEntity['id'] != command.payload['id'] ||
        verifiedEntity['tenant_id'] != command.context.tenantId ||
        verifiedEntity['legal_entity_id'] != command.context.legalEntityId ||
        verifiedEntity['branch_id'] != command.context.branchId ||
        verifiedEntity['version'] != command.expectedEntityVersion! + 1) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Confirmation does not match the original project request.',
        retryable: true,
      );
    }
    try {
      await store.repository.save(
        id: _key(request),
        tenantId: command.context.tenantId,
        entityType: 'projects.command.acknowledgement',
        payload: {
          'scope': command.context.toJson(),
          'action': request.action,
          'command_id': command.commandId,
          'idempotency_key': command.idempotencyKey,
          'entity_id': command.payload['id'],
          'version': verifiedEntity['version'],
        },
        localVersion: 1,
        serverVersion: verifiedEntity['version'] as int,
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
        row.entityType != 'projects.command.acknowledgement' ||
        body.length != 6 ||
        TenantContext.fromJson(Map<String, Object?>.from(body['scope'] as Map)) !=
            command.context ||
        body['action'] != request.action ||
        body['command_id'] != command.commandId ||
        body['idempotency_key'] != command.idempotencyKey ||
        body['entity_id'] != command.payload['id'] ||
        body['version'] != command.expectedEntityVersion! + 1) {
      throw const DomainError(
        code: 'DRAFT_SCOPE_MISMATCH',
        message: 'The saved confirmation belongs to another project request.',
      );
    }
    return true;
  }
}

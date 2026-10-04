import 'dart:convert';

import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_projects.dart';
import 'package:jentra_domain/jentra_project_finance.dart';

import 'scoped_command_draft_store.dart';

/// Encrypted confirmation identity survives failed draft cleanup. No financial
/// amounts, evidence, source data or response body are retained here.
final class ProjectFinanceCommandAcknowledgements {
  const ProjectFinanceCommandAcknowledgements(this.store);
  final ScopedCommandDraftStore store;
  static const entityType = 'projects.finance.command.acknowledgement';

  String _key(ScopedPendingCommand request) =>
      'projects.finance.ack:${base64Url.encode(utf8.encode(jsonEncode(request.envelope.context.toJson())))}:${request.envelope.commandId}';

  Future<void> save(
    ScopedPendingCommand request,
    Map<String, Object?> response,
  ) async {
    final command = request.envelope, entity = projectMap(response['entity']);
    projectScope(entity, command.context);
    if (response['command_id'] != command.commandId ||
        command.payload['action'] != request.action ||
        entity['id'] != command.payload['id'] ||
        entity['project_id'] != command.payload['project_id'] ||
        entity['version'] != command.expectedEntityVersion! + 1 ||
        !projectFinanceActions.contains(request.action)) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Confirmation differs from the original finance request.',
        retryable: true,
      );
    }
    await store.repository.save(
      id: _key(request),
      tenantId: command.context.tenantId,
      entityType: entityType,
      payload: {
        'scope': command.context.toJson(),
        'action': request.action,
        'command_id': command.commandId,
        'idempotency_key': command.idempotencyKey,
        'entity_id': command.payload['id'],
        'project_id': command.payload['project_id'],
        'version': entity['version'],
      },
      localVersion: 1,
      serverVersion: entity['version'] as int,
      syncState: DraftSyncState.localOnly,
    );
  }

  Future<bool> contains(ScopedPendingCommand request) async {
    final command = request.envelope;
    final row = await store.repository.find(_key(request));
    if (row == null) {
      return false;
    }
    final body = row.payload;
    if (row.tenantId != command.context.tenantId ||
        row.entityType != entityType ||
        body.length != 7 ||
        TenantContext.fromJson(projectMap(body['scope'])) != command.context ||
        body['action'] != request.action ||
        body['command_id'] != command.commandId ||
        body['idempotency_key'] != command.idempotencyKey ||
        body['entity_id'] != command.payload['id'] ||
        body['project_id'] != command.payload['project_id'] ||
        body['version'] != command.expectedEntityVersion! + 1) {
      throw const DomainError(
        code: 'DRAFT_SCOPE_MISMATCH',
        message: 'The saved confirmation belongs to another finance request.',
      );
    }
    return true;
  }
}

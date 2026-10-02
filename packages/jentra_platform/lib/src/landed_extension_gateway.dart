import 'dart:convert';
import 'package:jentra_domain/landed_extension.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_landed_value_gateway.dart';

abstract interface class LandedExtensionGateway {
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? after,
  });
  Future<Map<String, Object?>> preview(
    TenantContext scope,
    Map<String, Object?> payload,
  );
  Future<Map<String, Object?>> post(
    CommandEnvelope<Map<String, Object?>> command,
  );
}

final class SupabaseLandedExtensionGateway implements LandedExtensionGateway {
  SupabaseLandedExtensionGateway(SupabaseClient client)
    : _rpc = SupabaseLandedValueGateway(client);
  final SupabaseLandedValueGateway _rpc;
  void validateScope(Map<String, Object?> evidence, TenantContext scope) {
    if (evidence['tenant_id'] != scope.tenantId ||
        evidence['legal_entity_id'] != scope.legalEntityId ||
        evidence['branch_id'] != scope.branchId ||
        utf8.encode(jsonEncode(evidence)).length > 1048576) {
      throw const FormatException(
        'Landed evidence scope or size could not be verified.',
      );
    }
  }

  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? after,
  }) async {
    final response = resource == 'posted'
        ? await _rpc.rpc('landed_extension_documents', {
            ..._rpc.scopeParams(scope),
            'p_after': after,
          })
        : await _rpc.options(scope, resource, after: after);
    final rows = response['items'];
    if (rows is! List ||
        rows.length > 50 ||
        (response['next_cursor'] != null &&
            response['next_cursor'] is! String)) {
      throw const FormatException('Landed register could not be verified.');
    }
    for (final row in rows) {
      if (row is! Map) {
        throw const FormatException('Landed register row is invalid.');
      }
      LandedExtensionProtocol.identity(row['id']);
      if (resource == 'posted') {
        validateScope(row.cast<String, Object?>(), scope);
        LandedExtensionProtocol.validateEvidence(
          row.cast<String, Object?>(),
          null,
        );
      }
    }
    return response;
  }

  @override
  Future<Map<String, Object?>> preview(
    TenantContext scope,
    Map<String, Object?> payload,
  ) async {
    LandedExtensionProtocol.validateInput(payload);
    final response = await _rpc.rpc('preview_landed_extension', {
      ..._rpc.scopeParams(scope),
      'p_payload': payload,
    });
    validateScope(response, scope);
    LandedExtensionProtocol.validateEvidence(response, payload);
    return response;
  }

  @override
  Future<Map<String, Object?>> post(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    LandedExtensionProtocol.validateInput(command.payload, sealed: true);
    final response = await _rpc.rpc('post_landed_extension', {
      ..._rpc.scopeParams(command.context),
      'p_command_id': command.commandId,
      'p_idempotency_key': command.idempotencyKey,
      'p_client_timestamp': command.clientTimestamp.toIso8601String(),
      'p_expected_entity_version': command.expectedEntityVersion,
      'p_payload': command.payload,
    });
    try {
      if (response['command_id'] != command.commandId ||
          response['entity'] is! Map) {
        throw const FormatException('Command identity could not be verified.');
      }
      LandedExtensionProtocol.identity(response['request_id']);
      final entity = (response['entity'] as Map).cast<String, Object?>();
      validateScope(entity, command.context);
      LandedExtensionProtocol.validateEvidence(entity, command.payload);
      if (entity['id'] != command.payload['id'] ||
          entity['status'] != 'posted' ||
          entity['version'] != 1 ||
          entity['basis_hash'] != command.payload['basis_hash'] ||
          entity['reference'] != command.payload['reference'] ||
          entity['reason'] != command.payload['reason'] ||
          entity['journal_ids'] is! List ||
          (entity['journal_ids'] as List).isEmpty) {
        throw const FormatException('Posting evidence could not be verified.');
      }
      for (final id in entity['journal_ids'] as List) {
        LandedExtensionProtocol.identity(id);
      }
      return entity;
    } on FormatException {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'Posting evidence could not be verified. Retry the identical saved command.',
      );
    }
  }
}

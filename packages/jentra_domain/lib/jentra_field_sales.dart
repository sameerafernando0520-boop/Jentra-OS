import 'dart:convert';

typedef FieldSalesJson = Map<String, dynamic>;

final class FieldSalesFailure implements Exception {
  const FieldSalesFailure(this.code, this.message);
  final String code, message;
}

final class FieldSalesScope {
  const FieldSalesScope(this.tenantId, this.entityId, this.branchId);
  factory FieldSalesScope.fromJson(FieldSalesJson json) => FieldSalesScope(
    json['tenant_id'] as String,
    json['legal_entity_id'] as String,
    json['branch_id'] as String,
  );
  final String tenantId, entityId, branchId;
  String get key => '$tenantId.$entityId.$branchId';
  FieldSalesJson get params => {
    'p_tenant_id': tenantId,
    'p_legal_entity_id': entityId,
    'p_branch_id': branchId,
  };
}

/// Exact immutable request bytes survive a lost response. A different payload
/// must have a different command/key; recovery never dispatches automatically.
final class FieldSalesCommand {
  FieldSalesCommand({
    required this.actorId,
    required this.scope,
    required this.commandId,
    required this.key,
    required this.at,
    required FieldSalesJson payload,
    this.bodyExpired = false,
  }) : _payload = jsonEncode(payload);
  factory FieldSalesCommand.fromJson(FieldSalesJson json) => FieldSalesCommand(
    actorId: json['actor_id'] as String,
    scope: FieldSalesScope.fromJson(json),
    commandId: json['command_id'] as String,
    key: json['key'] as String,
    at: json['at'] as String,
    bodyExpired: json['body_expired'] == true,
    payload: Map<String, dynamic>.from(json['payload'] as Map),
  );
  final String actorId, commandId, key, at, _payload;
  final bool bodyExpired;
  final FieldSalesScope scope;
  FieldSalesJson get payload => jsonDecode(_payload) as FieldSalesJson;
  FieldSalesJson get params => {
    ...scope.params,
    'p_command_id': commandId,
    'p_idempotency_key': key,
    'p_client_timestamp': at,
    'p_payload': payload,
    'p_expected_entity_version': null,
  };
  FieldSalesJson toJson() => {
    'schema': 1,
    'actor_id': actorId,
    'tenant_id': scope.tenantId,
    'legal_entity_id': scope.entityId,
    'branch_id': scope.branchId,
    'command_id': commandId,
    'key': key,
    'at': at,
    'payload': payload,
    'body_expired': bodyExpired,
  };
  FieldSalesCommand expireBody() => FieldSalesCommand(
    actorId: actorId,
    scope: scope,
    commandId: commandId,
    key: key,
    at: at,
    bodyExpired: true,
    payload: {
      'id': payload['id'],
      'source_digest': payload['source_digest'],
      'input': {'customer_id': (payload['input'] as Map)['customer_id']},
    },
  );
  void validateReceipt(FieldSalesJson receipt) {
    final entity = receipt['entity'];
    final input = payload['input'] as Map;
    if (receipt['command_id'] != commandId ||
        entity is! Map ||
        entity['id'] != payload['id'] ||
        entity['tenant_id'] != scope.tenantId ||
        entity['legal_entity_id'] != scope.entityId ||
        entity['branch_id'] != scope.branchId ||
        entity['rep_id'] != actorId ||
        entity['customer_id'] != input['customer_id'] ||
        entity['source_digest'] != payload['source_digest'] ||
        entity['company_state'] != 'submitted' ||
        entity['version'] != '1' ||
        entity['canonical_order_id'] != null ||
        entity['customer_state'] != 'email_link_pending') {
      throw const FieldSalesFailure(
        'RECEIPT_INVALID',
        'The server confirmation did not match. Check the original submission.',
      );
    }
  }
}

FieldSalesJson fieldSalesObject(Object? value) {
  if (value is! Map) {
    throw const FieldSalesFailure(
      'CONTRACT_INVALID',
      'The company service returned an unsupported response.',
    );
  }
  return Map<String, dynamic>.from(value);
}

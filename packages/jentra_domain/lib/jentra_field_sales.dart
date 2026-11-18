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

final _fieldSalesCount = RegExp(r'^\d{1,12}$');
final _fieldSalesDecimal = RegExp(r'^\d{1,14}\.\d{6}$');

/// A Field Sales rep as the company sees it. The label is the HR employee
/// name from the rep's accepted account link, or `Unlinked member ····1234`.
/// A label that could be an e-mail address is refused as a contract fault.
final class FieldSalesRep {
  const FieldSalesRep({
    required this.userId,
    required this.label,
    required this.linked,
    required this.activeCustomerCount,
    required this.submittedCount,
    required this.pendingCount,
    required this.approvedCount,
    required this.rejectedCount,
    required this.approvedTotal,
  });
  factory FieldSalesRep.fromJson(Object? value) {
    final json = fieldSalesObject(value);
    String text(String key, [RegExp? pattern]) {
      final v = json[key];
      if (v is! String ||
          v.trim().isEmpty ||
          (pattern != null && !pattern.hasMatch(v))) {
        throw const FieldSalesFailure(
          'CONTRACT_INVALID',
          'The rep list returned an unsupported row.',
        );
      }
      return v;
    }

    final label = text('label');
    if (label.contains('@') || json['linked'] is! bool) {
      throw const FieldSalesFailure(
        'CONTRACT_INVALID',
        'The rep list returned an unsupported row.',
      );
    }
    return FieldSalesRep(
      userId: text('user_id'),
      label: label,
      linked: json['linked'] as bool,
      activeCustomerCount: text('active_customer_count', _fieldSalesCount),
      submittedCount: text('submitted_count', _fieldSalesCount),
      pendingCount: text('pending_count', _fieldSalesCount),
      approvedCount: text('approved_count', _fieldSalesCount),
      rejectedCount: text('rejected_count', _fieldSalesCount),
      approvedTotal: text('approved_total', _fieldSalesDecimal),
    );
  }
  final String userId, label;
  final bool linked;

  /// Counts and the approved total stay exact server strings.
  final String activeCustomerCount,
      submittedCount,
      pendingCount,
      approvedCount,
      rejectedCount,
      approvedTotal;
}

/// Reps of one company branch for a period of company local dates.
final class FieldSalesRepList {
  const FieldSalesRepList({
    required this.items,
    required this.currencyCode,
    required this.from,
    required this.to,
  });
  factory FieldSalesRepList.fromJson(Object? value) {
    final json = fieldSalesObject(value);
    final items = json['items'];
    final currency = json['currency_code'];
    if (items is! List ||
        currency is! String ||
        currency.isEmpty ||
        json['from'] is! String ||
        json['to'] is! String) {
      throw const FieldSalesFailure(
        'CONTRACT_INVALID',
        'The rep list could not be opened.',
      );
    }
    return FieldSalesRepList(
      items: List.unmodifiable(items.map(FieldSalesRep.fromJson)),
      currencyCode: currency,
      from: json['from'] as String,
      to: json['to'] as String,
    );
  }
  final List<FieldSalesRep> items;
  final String currencyCode, from, to;

  /// The label shown for a request's rep. A rep missing from the list is never
  /// shown by its raw id.
  String labelFor(String? userId) {
    for (final rep in items) {
      if (rep.userId == userId) {
        return rep.label;
      }
    }
    return 'not listed';
  }
}

/// A company local date as the server expects it.
String fieldSalesDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

import 'dart:convert';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:uuid/uuid.dart';
import 'draft_repository.dart';

final class FieldSalesDecision {
  FieldSalesDecision(FieldSalesJson value) : _wire = jsonEncode(value);
  final String _wire;
  FieldSalesJson get json => fieldSalesObject(jsonDecode(_wire));
  String get actor => json['actor'] as String;
  FieldSalesScope get scope => FieldSalesScope.fromJson(json);
  String get commandId => json['command_id'] as String;
  String get key => json['key'] as String;
  bool get expired => json['expired'] == true;
  FieldSalesJson get payload => fieldSalesObject(json['payload']);
  FieldSalesJson get params => {
    ...scope.params,
    'p_command_id': commandId,
    'p_idempotency_key': key,
    'p_client_timestamp': json['at'],
    'p_payload': payload,
    'p_expected_entity_version': json['version'],
  };
  void validate(FieldSalesJson receipt) {
    final e = receipt['entity'];
    final state = payload['decision'] == 'approve' ? 'approved' : 'rejected';
    if (receipt['command_id'] != commandId ||
        e is! Map ||
        e['id'] != payload['id'] ||
        e['tenant_id'] != scope.tenantId ||
        e['legal_entity_id'] != scope.entityId ||
        e['branch_id'] != scope.branchId ||
        e['source_digest'] != payload['source_digest'] ||
        e['decision_by'] != actor ||
        e['company_state'] != state ||
        e['version'] !=
            (BigInt.parse(json['version'] as String) + BigInt.one).toString() ||
        e['customer_state'] != 'email_link_pending' ||
        (state == 'approved' &&
            (e['canonical_state'] != 'draft' ||
                e['canonical_order_id'] is! String)) ||
        (!expired && e['decision_reason'] != payload['reason'])) {
      throw const FieldSalesFailure(
        'RECEIPT_INVALID',
        'Company confirmation did not match the original decision. Check its receipt.',
      );
    }
  }
}

/// Separate encrypted entity type; never enters quotation/Employee recovery.
final class FieldSalesDecisionStore {
  FieldSalesDecisionStore(this.repository);
  final EncryptedDraftRepository repository;
  static final _queues = <String, Future<void>>{};
  String _id(String actor, FieldSalesScope s) =>
      'field-company:$actor:${s.key}';
  Future<T> _locked<T>(String id, Future<T> Function() action) async {
    final previous = _queues[id] ?? Future<void>.value();
    final result = previous.then((_) => action());
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _queues[id] = tail;
    try {
      return await result;
    } finally {
      if (identical(_queues[id], tail)) _queues.remove(id);
    }
  }

  Future<FieldSalesDecision?> load(String actor, FieldSalesScope s) =>
      _locked(_id(actor, s), () => _load(actor, s));
  Future<FieldSalesDecision?> _load(String actor, FieldSalesScope s) async {
    final row = await repository.find(_id(actor, s));
    if (row == null) return null;
    final command = FieldSalesDecision(Map<String, dynamic>.from(row.payload));
    if (row.tenantId != s.tenantId ||
        row.entityType != 'sales.field.company_decision' ||
        command.actor != actor ||
        command.scope.key != s.key) {
      throw const FieldSalesFailure(
        'RECOVERY_SCOPE_INVALID',
        'Company recovery belongs to another actor or scope.',
      );
    }
    final age = DateTime.now().toUtc().difference(
      DateTime.parse(command.json['at'] as String).toUtc(),
    );
    if (!command.expired &&
        (age.isNegative || age >= const Duration(hours: 24))) {
      final json = command.json;
      json['expired'] = true;
      final p = fieldSalesObject(json['payload']);
      p.remove('reason');
      json['payload'] = p;
      await repository.save(
        id: row.id,
        tenantId: s.tenantId,
        entityType: row.entityType,
        payload: json,
        localVersion: row.localVersion + 1,
      );
      return FieldSalesDecision(json);
    }
    return command;
  }

  Future<FieldSalesDecision> prepare(
    String actor,
    FieldSalesScope s,
    FieldSalesJson row,
    String decision,
    String reason,
  ) => _locked(_id(actor, s), () async {
    if (await _load(actor, s) != null) {
      throw const FieldSalesFailure(
        'COMMAND_PENDING',
        'Check the original company decision first.',
      );
    }
    if (!['approve', 'reject'].contains(decision) ||
        reason.trim().isEmpty ||
        reason.length > 500) {
      throw const FieldSalesFailure(
        'VALIDATION_ERROR',
        'Add a company decision reason.',
      );
    }
    final command = FieldSalesDecision({
      'actor': actor,
      'tenant_id': s.tenantId,
      'legal_entity_id': s.entityId,
      'branch_id': s.branchId,
      'command_id': const Uuid().v4(),
      'key': const Uuid().v4(),
      'at': DateTime.now().toUtc().toIso8601String(),
      'version': row['version'],
      'payload': {
        'id': row['id'],
        'source_digest': row['source_digest'],
        'decision': decision,
        'reason': reason.trim(),
      },
    });
    await repository.save(
      id: _id(actor, s),
      tenantId: s.tenantId,
      entityType: 'sales.field.company_decision',
      payload: command.json,
      localVersion: 1,
    );
    return command;
  });
  Future<void> complete(FieldSalesDecision command) =>
      _locked(_id(command.actor, command.scope), () async {
        final current = await _load(command.actor, command.scope);
        if (current?.commandId != command.commandId) {
          throw const FieldSalesFailure(
            'RECOVERY_CHANGED',
            'The saved company decision changed.',
          );
        }
        await repository.delete(_id(command.actor, command.scope));
      });
}

import 'dart:convert';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:uuid/uuid.dart';
import 'draft_repository.dart';

final class FieldConfirmationCompanyCommand {
  FieldConfirmationCompanyCommand(FieldSalesJson json)
    : _wire = jsonEncode(json);
  final String _wire;
  FieldSalesJson get json => fieldSalesObject(jsonDecode(_wire));
  String get actor => json['actor'] as String;
  FieldSalesScope get scope => FieldSalesScope.fromJson(json);
  String get commandId => json['command_id'] as String;
  String get key => json['key'] as String;
  String get action => json['action'] as String;
  bool get expired => json['expired'] == true;
  FieldSalesJson get payload => fieldSalesObject(json['payload']);
  FieldSalesJson get params {
    if (expired) {
      throw const FieldSalesFailure(
        'BODY_EXPIRED',
        'Check the original receipt; this expired request cannot be sent.',
      );
    }
    return {
      ...scope.params,
      'p_command_id': commandId,
      'p_idempotency_key': key,
      'p_client_timestamp': json['at'],
      'p_action': action,
      'p_payload': payload,
      'p_expected_entity_version': json['expected_version'],
    };
  }

  void validate(FieldSalesJson receipt) {
    final entity = receipt['entity'], p = payload;
    final expected = json['expected_version'];
    final version = expected == null
        ? '1'
        : (BigInt.parse(expected as String) + BigInt.one).toString();
    bool matches =
        receipt['command_id'] == commandId &&
        entity is Map &&
        entity['id'] == p['id'] &&
        entity['tenant_id'] == scope.tenantId &&
        entity['legal_entity_id'] == scope.entityId &&
        entity['branch_id'] == scope.branchId &&
        entity['version'] == version;
    if (matches) {
      final e = entity;
      matches = switch (action) {
        'authorize_contact' =>
          e['authorized_by'] == actor &&
              e['customer_id'] == p['customer_id'] &&
              e['active'] == true &&
              e['channel_state'] == 'unverified' &&
              (expired ||
                  e['name'] == p['name'] &&
                      e['email'] == p['email'] &&
                      e['authority_note'] == p['authority_note'] &&
                      DateTime.parse(
                        e['valid_until'] as String,
                      ).isAtSameMomentAs(
                        DateTime.parse(p['valid_until'] as String),
                      )),
        'revoke_contact' => e['active'] == false,
        'issue_order' =>
          e['request_id'] == p['request_id'] &&
              e['request_version'] == p['request_version'] &&
              e['contact_id'] == p['contact_id'] &&
              e['contact_version'] == p['contact_version'] &&
              e['source_digest'] == p['source_digest'] &&
              e['state'] == 'queued_link',
        'revoke_challenge' => e['state'] == 'revoked',
        _ => false,
      };
    }
    if (!matches) {
      throw const FieldSalesFailure(
        'RECEIPT_INVALID',
        'The result did not match the original company request. Check its receipt.',
      );
    }
  }
}

/// Distinct encrypted entity and actor/scope key. No automatic replay. Expiry
/// strips contact details/reasons but preserves enough identity to check receipts.
final class FieldConfirmationCompanyStore {
  FieldConfirmationCompanyStore(this.repository, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  final EncryptedDraftRepository repository;
  final DateTime Function() now;
  static const entityType = 'sales.field.confirmation_company';
  static final _queues = <String, Future<void>>{};
  String _id(String actor, FieldSalesScope scope) =>
      'field-confirmation:$actor:${scope.key}';
  Future<T> _locked<T>(String id, Future<T> Function() work) async {
    final result = (_queues[id] ?? Future<void>.value()).then((_) => work());
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

  Future<FieldConfirmationCompanyCommand?> load(
    String actor,
    FieldSalesScope scope,
  ) => _locked(_id(actor, scope), () => _load(actor, scope));
  Future<FieldConfirmationCompanyCommand?> _load(
    String actor,
    FieldSalesScope scope,
  ) async {
    final row = await repository.find(_id(actor, scope));
    if (row == null) return null;
    var command = FieldConfirmationCompanyCommand(
      Map<String, dynamic>.from(row.payload),
    );
    if (row.entityType != entityType ||
        row.tenantId != scope.tenantId ||
        command.actor != actor ||
        command.scope.key != scope.key ||
        !const {
          'authorize_contact',
          'revoke_contact',
          'issue_order',
          'revoke_challenge',
        }.contains(command.action)) {
      throw const FieldSalesFailure(
        'RECOVERY_SCOPE_INVALID',
        'The saved company request belongs to another actor or scope.',
      );
    }
    final age = now().toUtc().difference(
      DateTime.parse(command.json['at'] as String).toUtc(),
    );
    if (!command.expired &&
        (age.isNegative || age >= const Duration(hours: 24))) {
      final body = command.json, p = command.payload;
      body['payload'] = {
        for (final key in [
          'id',
          'customer_id',
          'request_id',
          'request_version',
          'source_digest',
          'contact_id',
          'contact_version',
        ])
          if (p.containsKey(key)) key: p[key],
      };
      body['expired'] = true;
      await repository.save(
        id: row.id,
        tenantId: scope.tenantId,
        entityType: entityType,
        payload: body,
        localVersion: row.localVersion + 1,
      );
      command = FieldConfirmationCompanyCommand(body);
    }
    return command;
  }

  Future<FieldConfirmationCompanyCommand> prepare(
    String actor,
    FieldSalesScope scope,
    String action,
    FieldSalesJson payload, {
    String? expectedVersion,
  }) => _locked(_id(actor, scope), () async {
    if (await _load(actor, scope) != null) {
      throw const FieldSalesFailure(
        'COMMAND_PENDING',
        'Check the original company request first.',
      );
    }
    final p = fieldSalesObject(jsonDecode(jsonEncode(payload)));
    if (!const {
          'authorize_contact',
          'revoke_contact',
          'issue_order',
          'revoke_challenge',
        }.contains(action) ||
        p['id'] is! String ||
        expectedVersion != null &&
            !RegExp(r'^[1-9]\d*$').hasMatch(expectedVersion) ||
        const {'revoke_contact', 'revoke_challenge'}.contains(action) &&
            expectedVersion == null ||
        action == 'issue_order' && expectedVersion != null) {
      throw const FieldSalesFailure(
        'VALIDATION_ERROR',
        'Review the original company action and version.',
      );
    }
    if (action == 'authorize_contact') {
      for (final key in ['name', 'email', 'authority_note']) {
        if (p[key] is! String) {
          throw const FieldSalesFailure(
            'VALIDATION_ERROR',
            'Complete the authorized contact details.',
          );
        }
        p[key] = (p[key] as String).trim();
      }
      p['email'] = (p['email'] as String).toLowerCase();
      if ((p['name'] as String).isEmpty ||
          (p['name'] as String).length > 200 ||
          (p['authority_note'] as String).isEmpty ||
          (p['authority_note'] as String).length > 1000 ||
          (p['email'] as String).length > 254 ||
          !RegExp(
            r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
          ).hasMatch(p['email'] as String) ||
          p['customer_id'] is! String ||
          p['valid_until'] is! String ||
          DateTime.tryParse(p['valid_until'] as String) == null) {
        throw const FieldSalesFailure(
          'VALIDATION_ERROR',
          'Add a valid contact, company authority note and expiry.',
        );
      }
    } else if (action == 'issue_order') {
      if ([
            'request_id',
            'contact_id',
            'source_digest',
            'request_version',
            'contact_version',
          ].any((key) => p[key] is! String) ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(p['source_digest'] as String) ||
          [
            'request_version',
            'contact_version',
          ].any((key) => !RegExp(r'^[1-9]\d*$').hasMatch(p[key] as String))) {
        throw const FieldSalesFailure(
          'VALIDATION_ERROR',
          'Refresh the request and authorized contact versions.',
        );
      }
    } else if (action == 'revoke_challenge') {
      if (p['reason'] is! String ||
          (p['reason'] as String).trim().isEmpty ||
          (p['reason'] as String).length > 500) {
        throw const FieldSalesFailure(
          'VALIDATION_ERROR',
          'Add a revocation reason.',
        );
      }
      p['reason'] = (p['reason'] as String).trim();
    }
    final command = FieldConfirmationCompanyCommand({
      'actor': actor,
      ...scope.params.map((k, v) => MapEntry(k.substring(2), v)),
      'command_id': const Uuid().v4(),
      'key': const Uuid().v4(),
      'at': now().toUtc().toIso8601String(),
      'action': action,
      'expected_version': expectedVersion,
      'payload': p,
    });
    await repository.save(
      id: _id(actor, scope),
      tenantId: scope.tenantId,
      entityType: entityType,
      payload: command.json,
      localVersion: 1,
    );
    return command;
  });
  Future<void> complete(FieldConfirmationCompanyCommand command) =>
      _locked(_id(command.actor, command.scope), () async {
        final saved = await _load(command.actor, command.scope);
        if (saved?.commandId != command.commandId) {
          throw const FieldSalesFailure(
            'RECOVERY_CHANGED',
            'The protected original request changed.',
          );
        }
        await repository.delete(_id(command.actor, command.scope));
      });
}

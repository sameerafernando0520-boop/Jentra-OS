import 'dart:convert';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart' show DomainError;
import '../draft_repository.dart';
import 'reviewed_model_gateway.dart';

/// Original identities and bounded parameters only; no results or credentials.
final class Wave5CommandStore {
  Wave5CommandStore(this.drafts, this.authorize, {required this.namespace}) {
    if (!{
      'pipeline',
      'proposal',
      'model',
      'subscription',
      'integration',
      'cash_dates_payroll_obligation',
      'cash_dates_payroll_correction',
      'cash_dates_project_reimbursement',
    }.contains(namespace)) {
      throw const FormatException('Unknown command recovery namespace.');
    }
  }
  final EncryptedDraftRepository drafts;
  final Future<void> Function(ProcessMetricScope, String) authorize;
  final String namespace;
  String _key(ProcessMetricScope scope, String actor) {
    ProcessMetricScope(tenantId: actor, legalEntityId: actor);
    return 'w5:$namespace:command:${base64Url.encode(utf8.encode(jsonEncode([actor, scope.tenantId, scope.legalEntityId, scope.branchId])))}';
  }

  void validate(Map<String, Object?> envelope) {
    try {
      _validateWire(envelope);
    } on DomainError {
      throw const FormatException(
        'Invalid recovery identifiers or UTC parameters.',
      );
    }
  }

  void _validateWire(Map<String, Object?> envelope) {
    if (namespace == 'model') {
      ReviewedModelRequest.validateEnvelope(envelope);
      return;
    }
    if (envelope.length != 5 ||
        !envelope.keys.toSet().containsAll({
          'commandId',
          'idempotencyKey',
          'clientTimestamp',
          'action',
          'payload',
        }) ||
        envelope['commandId'] is! String ||
        envelope['idempotencyKey'] is! String ||
        envelope['clientTimestamp'] is! String ||
        envelope['payload'] is! Map<String, Object?> ||
        utf8.encode(jsonEncode(envelope)).length > 8192) {
      throw const FormatException('Invalid recovery envelope.');
    }
    ProcessMetricScope(
      tenantId: envelope['commandId'] as String,
      legalEntityId: envelope['idempotencyKey'] as String,
    );
    parseProcessMetricUtc(envelope['clientTimestamp'] as String);
    final payload = envelope['payload'] as Map<String, Object?>;
    final allowed = namespace.startsWith('cash_dates_')
        ? {
            'prepare': {
              'id',
              'sourceKind',
              'sourceId',
              'sourceHash',
              'dueDate',
              'reasonCode',
              'expectedVersion',
            },
            'approve': {'id', 'proposalHash'},
            'reject': {'id', 'proposalHash'},
          }
        : namespace == 'pipeline'
        ? {
            'freeze': {'horizonStart', 'horizonEnd'},
          }
        : namespace == 'integration'
        ? {
            'register': {'id', 'url', 'keyRef', 'expectedVersion'},
            'rotate': {'id', 'keyRef', 'expectedVersion'},
            'revoke': {'id', 'expectedVersion'},
            'review': {'deliveryId', 'decision', 'reason'},
            'credential_register': {'id', 'tokenHash', 'startsAt', 'expiresAt'},
            'credential_revoke': {'id'},
          }
        : namespace == 'subscription'
        ? {
            'schedule': {
              'expectedVersion',
              'plan',
              'seats',
              'trialStart',
              'trialEnd',
            },
          }
        : {
            'create': {'sourceId', 'expiresAt'},
            'decide': {'proposalId', 'parametersHash', 'decision'},
            'execute': {'proposalId'},
          };
    final fields = allowed[envelope['action']];
    if (fields == null ||
        payload.length != fields.length ||
        !payload.keys.toSet().containsAll(fields) ||
        payload.values.any((v) => v is! String)) {
      throw const FormatException('Unsupported recovered command parameters.');
    }
    for (final key in ['sourceId', 'proposalId', 'id', 'deliveryId']) {
      if (payload.containsKey(key)) {
        final id = payload[key] as String;
        ProcessMetricScope(tenantId: id, legalEntityId: id);
      }
    }
    if (payload.containsKey('expiresAt')) {
      parseProcessMetricUtc(payload['expiresAt'] as String);
    }
    if (payload.containsKey('parametersHash') &&
        !RegExp(
          r'^[0-9a-f]{64}$',
        ).hasMatch(payload['parametersHash'] as String)) {
      throw const FormatException('Invalid recovered approval hash.');
    }
    if (namespace.startsWith('cash_dates_')) {
      for (final key in ['sourceHash', 'proposalHash']) {
        if (payload.containsKey(key) &&
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(payload[key] as String)) {
          throw const FormatException(
            'Invalid payment-date recovery fingerprint.',
          );
        }
      }
      if (envelope['action'] == 'prepare') {
        if (payload['sourceKind'] !=
                namespace.substring('cash_dates_'.length) ||
            !{
              'payroll_calendar',
              'payment_terms',
              'reviewed_reschedule',
              'correction_recovery',
            }.contains(payload['reasonCode']) ||
            !RegExp(
              r'^(0|[1-9][0-9]{0,15})$',
            ).hasMatch(payload['expectedVersion'] as String) ||
            BigInt.parse(payload['expectedVersion'] as String) >
                BigInt.parse('9007199254740990') ||
            !RegExp(
              r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$',
            ).hasMatch(payload['dueDate'] as String)) {
          throw const FormatException(
            'Invalid payment-date recovery parameters.',
          );
        }
        parseProcessMetricUtc('${payload['dueDate']}T00:00:00Z');
      }
    }
    if (payload.containsKey('decision') &&
        !(namespace == 'integration'
                ? {'replay', 'acknowledged', 'not_sent'}
                : {'approved', 'rejected'})
            .contains(payload['decision'])) {
      throw const FormatException('Invalid recovered decision.');
    }
    if (namespace == 'integration') {
      if (payload.containsKey('tokenHash') &&
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(payload['tokenHash'] as String)) {
        throw const FormatException(
          'Only a reviewed server credential digest is accepted.',
        );
      }
      if (payload.containsKey('startsAt')) {
        final start = parseProcessMetricUtc(payload['startsAt'] as String),
            end = parseProcessMetricUtc(payload['expiresAt'] as String);
        if (!end.isAfter(start) ||
            end.difference(start) > const Duration(days: 366)) {
          throw const FormatException('Invalid credential effective dates.');
        }
      }
      if ((payload.containsKey('keyRef') &&
              !RegExp(
                r'^[a-zA-Z0-9_/-]{1,180}$',
              ).hasMatch(payload['keyRef'] as String)) ||
          (payload.containsKey('url') &&
              (!RegExp(
                    r'^https://[^/@:#?]+(:443)?(/[^#]*)?$',
                  ).hasMatch(payload['url'] as String) ||
                  (payload['url'] as String).length > 2048)) ||
          (payload.containsKey('expectedVersion') &&
              !RegExp(
                r'^(0|[1-9][0-9]{0,18})$',
              ).hasMatch(payload['expectedVersion'] as String)) ||
          (payload.containsKey('reason') &&
              ((payload['reason'] as String).trim().length < 8 ||
                  (payload['reason'] as String).length > 500))) {
        throw const FormatException(
          'Invalid recovered integration parameters.',
        );
      }
    }
    if (namespace == 'subscription') {
      if (!RegExp(
            r'^[1-9][0-9]{0,18}$',
          ).hasMatch(payload['expectedVersion'] as String) ||
          BigInt.parse(payload['expectedVersion'] as String) >
              BigInt.parse('9223372036854775807') ||
          !RegExp(
            r'^[a-z][a-z0-9_]{0,63}$',
          ).hasMatch(payload['plan'] as String) ||
          !RegExp(r'^[1-9][0-9]{0,4}$').hasMatch(payload['seats'] as String) ||
          int.parse(payload['seats'] as String) > 10000) {
        throw const FormatException(
          'Invalid recovered subscription parameters.',
        );
      }
      final start = parseProcessMetricUtc(payload['trialStart'] as String),
          end = parseProcessMetricUtc(payload['trialEnd'] as String);
      if (!end.isAfter(start) ||
          end.difference(start) > const Duration(days: 366)) {
        throw const FormatException('Invalid recovered trial.');
      }
    }
    if (namespace == 'pipeline') {
      final start = parseProcessMetricUtc(
            '${payload['horizonStart']}T00:00:00Z',
          ),
          end = parseProcessMetricUtc('${payload['horizonEnd']}T00:00:00Z');
      if (!end.isAfter(start) ||
          end.difference(start) > const Duration(days: 366)) {
        throw const FormatException('Invalid recovered forecast horizon.');
      }
    }
  }

  Future<void> save(
    ProcessMetricScope scope,
    String actor,
    Map<String, Object?> envelope,
  ) async {
    validate(envelope);
    await authorize(scope, actor);
    await drafts.save(
      id: _key(scope, actor),
      tenantId: scope.tenantId,
      entityType: 'wave5_${namespace}_command',
      payload: envelope,
      localVersion: 1,
    );
  }

  Future<Map<String, Object?>?> restore(
    ProcessMetricScope scope,
    String actor,
  ) async {
    final key = _key(scope, actor);
    await authorize(scope, actor);
    final found = await drafts.find(key);
    await authorize(scope, actor);
    if (found == null) return null;
    if (found.tenantId != scope.tenantId ||
        found.entityType != 'wave5_${namespace}_command') {
      throw const FormatException('Recovery context changed.');
    }
    validate(found.payload);
    return Map.unmodifiable(found.payload);
  }

  Future<void> remove(
    ProcessMetricScope scope,
    String actor, {
    bool Function()? isCurrent,
  }) async {
    await authorize(scope, actor);
    if (isCurrent != null && !isCurrent()) return;
    await drafts.delete(_key(scope, actor));
  }
}

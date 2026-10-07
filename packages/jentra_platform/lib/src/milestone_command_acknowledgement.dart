import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_milestones.dart';
import 'scoped_command_draft_store.dart';
import 'local_draft_storage_failure.dart';

final class MilestoneCommandAcknowledgements {
  const MilestoneCommandAcknowledgements(this.store);
  final ScopedCommandDraftStore store;
  String _key(ScopedPendingCommand r) =>
      'milestone.ack:${base64Url.encode(utf8.encode(jsonEncode(r.envelope.context.toJson())))}:${r.envelope.commandId}';
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

  Future<void> save(ScopedPendingCommand r, Map<String, Object?> result) async {
    final c = r.envelope;
    milestoneReceipt(
      result,
      c.context,
      c.payload['project_id'] as String,
      request: c,
    );
    try {
      await store.repository.save(
        id: _key(r),
        tenantId: c.context.tenantId,
        entityType: 'projects.milestone.acknowledgement',
        payload: {
          'scope': c.context.toJson(),
          'action': r.action,
          'command_id': c.commandId,
          'idempotency_key': c.idempotencyKey,
          'entity_id': c.payload['id'],
          'version': c.expectedEntityVersion! + 1,
          'request_digest': await _digest(r),
        },
        localVersion: 1,
        serverVersion: c.expectedEntityVersion! + 1,
        syncState: DraftSyncState.localOnly,
      );
    } catch (e) {
      throw localDraftStorageFailure(e);
    }
  }

  Future<bool> contains(ScopedPendingCommand r) async {
    final c = r.envelope, row = await store.repository.find(_key(r));
    if (row == null) return false;
    final p = row.payload;
    if (row.tenantId != c.context.tenantId ||
        row.entityType != 'projects.milestone.acknowledgement' ||
        p.length != 7 ||
        TenantContext.fromJson(Map<String, Object?>.from(p['scope'] as Map)) !=
            c.context ||
        p['action'] != r.action ||
        p['command_id'] != c.commandId ||
        p['idempotency_key'] != c.idempotencyKey ||
        p['entity_id'] != c.payload['id'] ||
        p['version'] != c.expectedEntityVersion! + 1 ||
        p['request_digest'] != await _digest(r)) {
      throw const DomainError(
        code: 'DRAFT_SCOPE_MISMATCH',
        message: 'The saved confirmation belongs to another milestone request.',
      );
    }
    return true;
  }
}

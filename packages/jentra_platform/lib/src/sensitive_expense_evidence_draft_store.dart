import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_expense_evidence.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:uuid/uuid.dart';
import 'draft_repository.dart';
import 'scoped_command_draft_store.dart';

final class SensitiveExpenseEvidenceDraft {
  SensitiveExpenseEvidenceDraft(Map<String, Object?> row)
    : _wire = jsonEncode(row);
  final String _wire;
  Map<String, Object?> get data => workforceMap(jsonDecode(_wire));
  Map<String, Object?> get payload => workforceMap(data['payload']);
  DateTime get expiresAt =>
      DateTime.parse(data['expires_at'] as String).toUtc();
  int get version => data['expected_version'] as int;
  ScopedPendingCommand? get pending => data['pending'] == null
      ? null
      : ScopedPendingCommand.fromJson(workforceMap(data['pending']));
}

/// File bytes, filenames and URLs are never persisted. Private metadata has a
/// fixed 24-hour expiry; the encrypted minimal receipt survives uncertain expiry.
final class SensitiveExpenseEvidenceDraftStore {
  SensitiveExpenseEvidenceDraftStore(
    this.repository,
    this.authorize, {
    DateTime Function()? clock,
  }) : clock = clock ?? (() => DateTime.now().toUtc());
  final EncryptedDraftRepository repository;
  final Future<void> Function(TenantContext, String?, String?, String)
  authorize;
  final DateTime Function() clock;
  static const _uuid = Uuid();
  static final _queues = <String, Future<void>>{};
  static const _body = 'sensitive_expense_evidence',
      _receipt = 'sensitive_expense_evidence_receipt';
  String _key(
    TenantContext scope,
    String? project,
    String? expense,
    String id,
    String capability,
  ) {
    if (!scope.hasOperationalScope ||
        (project == null) != (expense == null) ||
        !{
          expenseEvidenceManage,
          expenseEvidenceRetention,
        }.contains(capability)) {
      throw const FormatException('Evidence recovery scope is invalid.');
    }
    calendarUuid(id);
    if (project != null) {
      calendarUuid(project);
      calendarUuid(expense);
    }
    return 'expense-evidence-v1:${base64Url.encode(utf8.encode(jsonEncode(scope.toJson())))}:$project:$expense:$capability:$id';
  }

  String _type(String key, bool receipt) =>
      '${receipt ? _receipt : _body}:${key.substring(0, key.lastIndexOf(':'))}';

  Future<List<String>> recoveryIds(
    TenantContext s,
    String? p,
    String? x,
    String cap,
  ) async {
    final sample = _key(s, p, x, '00000000-0000-4000-8000-000000000000', cap);
    await authorize(s, p, x, cap);
    final ids = <String>{};
    for (final receipt in [true, false]) {
      final rows = await repository.pageIds(
        tenantId: s.tenantId,
        entityType: _type(sample, receipt),
        limit: 50,
      );
      for (final key in rows) {
        final base = receipt
            ? key.substring(0, key.length - ':receipt'.length)
            : key;
        final id = base.substring(base.lastIndexOf(':') + 1);
        calendarUuid(id);
        ids.add(id);
      }
    }
    return List.unmodifiable(ids.toList()..sort());
  }

  Future<T> _locked<T>(String key, Future<T> Function() work) async {
    final previous = _queues[key] ?? Future<void>.value();
    final done = Completer<void>();
    _queues[key] = done.future;
    try {
      await previous;
      return await work();
    } finally {
      done.complete();
      if (identical(_queues[key], done.future)) _queues.remove(key);
    }
  }

  Future<SensitiveExpenseEvidenceDraft?> _read(
    TenantContext s,
    String key,
  ) async {
    final row = await repository.find(key);
    if (row == null) return null;
    if (row.tenantId != s.tenantId || row.entityType != _type(key, false)) {
      throw const FormatException(
        'Evidence recovery belongs to another scope.',
      );
    }
    final draft = SensitiveExpenseEvidenceDraft(row.payload);
    if (!clock().toUtc().isBefore(draft.expiresAt)) {
      await repository.delete(key);
      return null;
    }
    final payload = ExpenseEvidenceCommands.validate(draft.payload);
    if (_key(
          s,
          payload['project_id'] as String?,
          payload['expense_id'] as String?,
          payload['id'] as String,
          ExpenseEvidenceCommands.capability(payload['action'] as String),
        ) !=
        key) {
      throw const FormatException(
        'Evidence recovery payload belongs to another scope.',
      );
    }
    final pending = draft.pending;
    if (pending != null &&
        (jsonEncode(pending.envelope.context.toJson()) !=
                jsonEncode(s.toJson()) ||
            jsonEncode(pending.envelope.payload) != jsonEncode(payload) ||
            pending.envelope.expectedEntityVersion != draft.version ||
            pending.action != payload['action'])) {
      throw const FormatException(
        'Sealed evidence recovery does not match its draft.',
      );
    }
    return draft;
  }

  Future<SensitiveExpenseEvidenceDraft?> read(
    TenantContext s,
    String? p,
    String? x,
    String id,
    String cap,
  ) async {
    final key = _key(s, p, x, id, cap);
    await authorize(s, p, x, cap);
    return _locked(key, () => _read(s, key));
  }

  Future<Map<String, Object?>?> receipt(
    TenantContext s,
    String? p,
    String? x,
    String id,
    String cap,
  ) async {
    final key = _key(s, p, x, id, cap);
    await authorize(s, p, x, cap);
    return _locked(key, () async {
      final row = await repository.find('$key:receipt');
      if (row == null) return null;
      if (row.tenantId != s.tenantId || row.entityType != _type(key, true)) {
        throw const FormatException('Evidence receipt scope is invalid.');
      }
      calendarFields(row.payload, {
        'command_id',
        'action',
        'id',
        'expected_version',
        'payload_digest',
      });
      calendarUuid(row.payload['command_id']);
      calendarUuid(row.payload['id']);
      expenseEvidenceDigest(row.payload['payload_digest']);
      if (row.payload['id'] != id ||
          ExpenseEvidenceCommands.capability(row.payload['action'] as String) !=
              cap) {
        throw const FormatException('Evidence receipt identity is invalid.');
      }
      return row.payload;
    });
  }

  Future<void> save(
    TenantContext s,
    Map<String, Object?> raw,
    int version,
  ) async {
    final payload = ExpenseEvidenceCommands.validate(raw);
    final cap = ExpenseEvidenceCommands.capability(payload['action'] as String);
    final p = payload['project_id'] as String?,
        x = payload['expense_id'] as String?,
        id = payload['id'] as String;
    if (version < 0 || version >= 9007199254740991) {
      throw const FormatException('Evidence recovery version is invalid.');
    }
    final key = _key(s, p, x, id, cap);
    await authorize(s, p, x, cap);
    await _locked(key, () async {
      final old = await _read(s, key);
      if (old?.pending != null ||
          await repository.find('$key:receipt') != null) {
        throw const DomainError(
          code: 'PENDING_COMMAND',
          message:
              'Resolve the exact saved evidence request before changing it.',
        );
      }
      await repository.save(
        id: key,
        tenantId: s.tenantId,
        entityType: _type(key, false),
        payload: {
          'expires_at':
              (old?.expiresAt ?? clock().toUtc().add(const Duration(hours: 24)))
                  .toIso8601String(),
          'payload': payload,
          'expected_version': version,
          'pending': null,
        },
        localVersion: 1,
        serverVersion: version,
      );
    });
  }

  Future<ScopedPendingCommand> seal(
    TenantContext s,
    String? p,
    String? x,
    String id,
    String cap,
  ) async {
    final key = _key(s, p, x, id, cap);
    await authorize(s, p, x, cap);
    return _locked(key, () async {
      final draft = await _read(s, key);
      if (draft == null) {
        throw const DomainError(
          code: 'DRAFT_EXPIRED',
          message:
              'Private evidence metadata expired. Check the saved receipt before creating a new request.',
        );
      }
      if (draft.pending != null) return draft.pending!;
      if (await repository.find('$key:receipt') != null) {
        throw const DomainError(
          code: 'PENDING_COMMAND',
          message: 'An unresolved evidence receipt already exists.',
        );
      }
      final payload = ExpenseEvidenceCommands.validate(draft.payload);
      if (payload['id'] != id ||
          payload['project_id'] != p ||
          payload['expense_id'] != x ||
          ExpenseEvidenceCommands.capability(payload['action'] as String) !=
              cap) {
        throw const FormatException('Evidence draft scope is invalid.');
      }
      final pending = ScopedPendingCommand(
        payload['action'] as String,
        CommandEnvelope<Map<String, Object?>>(
          commandId: _uuid.v4(),
          idempotencyKey: _uuid.v4(),
          context: s,
          payload: payload,
          clientTimestamp: clock().toUtc(),
          expectedEntityVersion: draft.version,
        ),
      );
      final digest = (await Sha256().hash(
        utf8.encode(jsonEncode(payload)),
      )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      await repository.transaction(() async {
        await repository.save(
          id: key,
          tenantId: s.tenantId,
          entityType: _type(key, false),
          payload: {...draft.data, 'pending': pending.toJson()},
          localVersion: 2,
          serverVersion: draft.version,
          syncState: DraftSyncState.queued,
        );
        await repository.save(
          id: '$key:receipt',
          tenantId: s.tenantId,
          entityType: _type(key, true),
          payload: {
            'command_id': pending.envelope.commandId,
            'action': payload['action'],
            'id': id,
            'expected_version': draft.version,
            'payload_digest': digest,
          },
          localVersion: 1,
          serverVersion: draft.version,
          syncState: DraftSyncState.queued,
        );
      });
      return pending;
    });
  }

  Future<void> acknowledge(
    TenantContext s,
    String? p,
    String? x,
    String id,
    String cap,
    ExpenseEvidenceConfirmation confirmation,
  ) async {
    final key = _key(s, p, x, id, cap);
    await authorize(s, p, x, cap);
    await _locked(key, () async {
      final row = await repository.find('$key:receipt');
      if (row == null) {
        throw const FormatException('Evidence receipt is missing.');
      }
      final e = confirmation.entity;
      if (confirmation.commandId != row.payload['command_id'] ||
          e['id'] != id ||
          e['action'] != row.payload['action'] ||
          e['tenant_id'] != s.tenantId ||
          e['legal_entity_id'] != s.legalEntityId ||
          e['branch_id'] != s.branchId ||
          e['project_id'] != p ||
          e['expense_id'] != x ||
          confirmation.recordVersion !=
              (row.payload['expected_version'] as int) + 1) {
        throw const FormatException(
          'Evidence confirmation does not match the pending receipt.',
        );
      }
      await repository.transaction(() async {
        await repository.delete(key);
        await repository.delete('$key:receipt');
      });
    });
  }

  Future<void> discard(
    TenantContext s,
    String? p,
    String? x,
    String id,
    String cap,
  ) async {
    final key = _key(s, p, x, id, cap);
    await authorize(s, p, x, cap);
    await _locked(key, () async {
      if (await repository.find('$key:receipt') != null) {
        throw const DomainError(
          code: 'PENDING_COMMAND',
          message: 'Resolve the evidence outcome before discarding its draft.',
        );
      }
      await repository.delete(key);
    });
  }

  Future<void> releaseRejected(
    TenantContext s,
    String? p,
    String? x,
    String id,
    String cap,
    DomainError error,
  ) async {
    if (!{
      'VERSION_CONFLICT',
      'VALIDATION_ERROR',
      'EVIDENCE_UNAVAILABLE',
      'EVIDENCE_CONTENT_UNAVAILABLE',
      'FINANCIAL_RETENTION_REQUIRED',
      'EVIDENCE_VERIFICATION_REQUIRED',
    }.contains(error.code)) {
      return;
    }
    final key = _key(s, p, x, id, cap);
    await authorize(s, p, x, cap);
    await _locked(key, () async {
      final draft = await _read(s, key);
      if (draft == null) return;
      await repository.transaction(() async {
        await repository.save(
          id: key,
          tenantId: s.tenantId,
          entityType: _type(key, false),
          payload: {...draft.data, 'pending': null},
          localVersion: 3,
          serverVersion: draft.version,
          syncState: DraftSyncState.conflicted,
        );
        await repository.delete('$key:receipt');
      });
    });
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:uuid/uuid.dart';

import 'draft_repository.dart';

final class CalendarPendingCommand {
  CalendarPendingCommand(Map<String, Object?> json) : _wire = jsonEncode(json);
  final String _wire;
  Map<String, Object?> toJson() =>
      Map<String, Object?>.from(jsonDecode(_wire) as Map);
  String get action => toJson()['action'] as String;
  CommandEnvelope<Map<String, Object?>> get envelope {
    final raw = Map<String, Object?>.from(toJson()['envelope'] as Map);
    return CommandEnvelope<Map<String, Object?>>(
      commandId: raw['command_id'] as String,
      idempotencyKey: raw['idempotency_key'] as String,
      context: TenantContext.fromJson(
        Map<String, Object?>.from(raw['context'] as Map),
      ),
      payload: Map<String, Object?>.from(raw['payload'] as Map),
      clientTimestamp: DateTime.parse(raw['client_timestamp'] as String),
      expectedEntityVersion: raw['expected_entity_version'] as int?,
    );
  }
}

final class CalendarDraft {
  const CalendarDraft({
    required this.form,
    required this.version,
    required this.localVersion,
    this.pending,
    this.errorCode,
  });
  final Map<String, Object?> form;
  final int version, localVersion;
  final CalendarPendingCommand? pending;
  final String? errorCode;
}

/// One actor/scope/slot owns each encrypted calendar editor and sealed retry.
final class CalendarDraftStore {
  CalendarDraftStore(this._repository);
  final EncryptedDraftRepository _repository;
  static const _uuid = Uuid();
  static final _queues = <String, Future<void>>{};
  static const entityType = 'people.calendar';

  String _key(TenantContext scope, String slot) =>
      'calendar:${base64Url.encode(utf8.encode(jsonEncode([scope.toJson(), slot])))}';

  Future<T> _locked<T>(String key, Future<T> Function() work) async {
    final previous = _queues[key] ?? Future<void>.value();
    final done = Completer<void>();
    final current = done.future;
    _queues[key] = current;
    await previous;
    try {
      return await work();
    } finally {
      done.complete();
      if (identical(_queues[key], current)) _queues.remove(key);
    }
  }

  Future<CalendarDraft?> load(TenantContext scope, String slot) async {
    final row = await _repository.find(_key(scope, slot));
    if (row == null) return null;
    final data = row.payload;
    if (row.tenantId != scope.tenantId ||
        row.entityType != entityType ||
        data['slot'] != slot ||
        TenantContext.fromJson(
              Map<String, Object?>.from(data['scope'] as Map),
            ) !=
            scope) {
      throw const DomainError(
        code: 'DRAFT_SCOPE_MISMATCH',
        message: 'This calendar draft belongs to another business scope.',
      );
    }
    if (data['pending'] != null) {
      final pending = CalendarPendingCommand(
        Map<String, Object?>.from(data['pending'] as Map),
      );
      if (pending.envelope.context != scope) {
        throw const DomainError(
          code: 'DRAFT_SCOPE_MISMATCH',
          message: 'The saved calendar request belongs to another scope.',
        );
      }
      validateCalendarPayload(pending.action, pending.envelope.payload);
    }
    return CalendarDraft(
      form: Map<String, Object?>.from(data['form'] as Map),
      version: row.serverVersion ?? 0,
      localVersion: row.localVersion,
      pending: data['pending'] == null
          ? null
          : CalendarPendingCommand(
              Map<String, Object?>.from(data['pending'] as Map),
            ),
      errorCode: data['error_code'] as String?,
    );
  }

  Future<void> _write(TenantContext scope, String slot, CalendarDraft draft) =>
      _repository.save(
        id: _key(scope, slot),
        tenantId: scope.tenantId,
        entityType: entityType,
        payload: {
          'scope': scope.toJson(),
          'slot': slot,
          'form': draft.form,
          'pending': draft.pending?.toJson(),
          'error_code': draft.errorCode,
        },
        localVersion: draft.localVersion,
        serverVersion: draft.version,
        syncState: draft.errorCode == 'VERSION_CONFLICT'
            ? DraftSyncState.conflicted
            : DraftSyncState.localOnly,
      );

  Future<void> save(
    TenantContext scope,
    String slot,
    Map<String, Object?> form, {
    required int version,
    bool resolveConflict = false,
  }) => _locked(_key(scope, slot), () async {
    final previous = await load(scope, slot);
    if (previous?.pending != null) {
      throw const DomainError(
        code: 'COMMAND_PENDING',
        message: 'Resolve the stored calendar request before editing.',
      );
    }
    if (previous?.errorCode == 'VERSION_CONFLICT' && !resolveConflict) {
      throw const DomainError(
        code: 'VERSION_CONFLICT',
        message: 'Compare the current calendar before replacing this draft.',
      );
    }
    await _write(
      scope,
      slot,
      CalendarDraft(
        form: Map<String, Object?>.from(form),
        version: version,
        localVersion: (previous?.localVersion ?? 0) + 1,
      ),
    );
  });

  Future<CalendarPendingCommand> prepare(
    TenantContext scope,
    String slot, {
    required String action,
    required Map<String, Object?> payload,
    required int version,
  }) => _locked(_key(scope, slot), () async {
    validateCalendarPayload(action, payload);
    if (version < 0 ||
        version >= calendarMaxVersion ||
        (action == 'create' ? version != 0 : version == 0)) {
      throw const FormatException('Calendar expected version is invalid.');
    }
    final previous = await load(scope, slot);
    if (previous?.errorCode == 'VERSION_CONFLICT') {
      throw const DomainError(
        code: 'VERSION_CONFLICT',
        message: 'Resolve the stale calendar draft before retrying.',
      );
    }
    if (previous?.pending != null) {
      final sealed = previous!.pending!;
      if (sealed.action == action &&
          sealed.envelope.expectedEntityVersion == version &&
          _canonical(sealed.envelope.payload) == _canonical(payload)) {
        return sealed;
      }
      throw const DomainError(
        code: 'COMMAND_PENDING',
        message: 'Retry the original calendar request before changing it.',
      );
    }
    if (previous != null && previous.version != version) {
      throw const DomainError(
        code: 'VERSION_CONFLICT',
        message: 'The saved calendar draft has a different server version.',
      );
    }
    final pending = CalendarPendingCommand({
      'action': action,
      'envelope': CommandEnvelope<Map<String, Object?>>(
        commandId: _uuid.v4(),
        idempotencyKey: _uuid.v4(),
        context: scope,
        payload: payload,
        expectedEntityVersion: version,
      ).toJson((value) => value),
    });
    await _write(
      scope,
      slot,
      CalendarDraft(
        form: previous?.form ?? payload,
        version: version,
        localVersion: (previous?.localVersion ?? 0) + 1,
        pending: pending,
      ),
    );
    return pending;
  });

  Future<void> recordFailure(
    TenantContext scope,
    String slot,
    DomainError error, {
    required String commandId,
  }) => _locked(_key(scope, slot), () async {
    final current = await load(scope, slot);
    if (current?.pending?.envelope.commandId != commandId) return;
    // Revocation or an unknown transport result may follow a committed command.
    final definite = {
      'VERSION_CONFLICT',
      'VALIDATION_ERROR',
      'CALENDAR_CODE_EXISTS',
      'CALENDAR_ID_EXISTS',
      'CALENDAR_OVERLAP',
      'CALENDAR_RETROACTIVE_CHANGE_REQUIRED',
    }.contains(error.code);
    await _write(
      scope,
      slot,
      CalendarDraft(
        form: current!.form,
        version: current.version,
        localVersion: current.localVersion + 1,
        pending: definite ? null : current.pending,
        errorCode: error.code,
      ),
    );
  });

  Future<void> complete(
    TenantContext scope,
    String slot,
    String commandId,
  ) => _locked(_key(scope, slot), () async {
    final current = await load(scope, slot);
    if (current?.pending?.envelope.commandId != commandId) {
      throw const DomainError(
        code: 'COMMAND_PENDING',
        message:
            'The confirmed calendar command does not match the local request.',
      );
    }
    await _repository.delete(_key(scope, slot));
  });

  Future<void> discard(TenantContext scope, String slot) => _locked(
    _key(scope, slot),
    () async {
      if ((await load(scope, slot))?.pending != null) {
        throw const DomainError(
          code: 'COMMAND_PENDING',
          message: 'Resolve the calendar request before discarding its draft.',
        );
      }
      await _repository.delete(_key(scope, slot));
    },
  );

  static String _canonical(Object? value) => jsonEncode(_sorted(value));
  static Object? _sorted(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _sorted(value[key])};
    }
    if (value is List) return value.map(_sorted).toList();
    return value;
  }
}

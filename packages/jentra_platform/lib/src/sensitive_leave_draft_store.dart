import 'dart:async';
import 'dart:convert';

import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:uuid/uuid.dart';

import 'draft_repository.dart';
import 'scoped_command_draft_store.dart';

final class SensitiveLeaveDraft {
  SensitiveLeaveDraft(this.expiresAt, Map<String, Object?> data)
    : _wire = jsonEncode(data);
  final DateTime expiresAt;
  final String _wire;
  Map<String, Object?> get data => workforceMap(jsonDecode(_wire));
  Map<String, Object?> get form => workforceMap(data['form']);
  String get id => data['id'] as String;
  String get employeeId => data['employee_id'] as String;
  String get action => data['action'] as String;
  int get version => data['version'] as int;
  String? get errorCode => data['error_code'] as String?;
  ScopedPendingCommand? get pending => data['pending'] == null
      ? null
      : ScopedPendingCommand.fromJson(workforceMap(data['pending']));
}

final class SensitiveLeaveRecovery {
  const SensitiveLeaveRecovery(
    this.employeeId,
    this.id,
    this.expiresAt, {
    required this.expired,
  });
  final String employeeId, id;
  final DateTime? expiresAt;
  final bool expired;
}

/// Leave reasons expire in 24 hours. The key carries only scope, identities and
/// expiry, so an expired body is deleted before any attempt to decrypt it.
final class SensitiveLeaveDraftStore {
  SensitiveLeaveDraftStore(
    this.repository,
    this.authorize, {
    DateTime Function()? clock,
  }) : clock = clock ?? (() => DateTime.now().toUtc());
  final EncryptedDraftRepository repository;
  final Future<void> Function(TenantContext, String) authorize;
  final DateTime Function() clock;
  static const _uuid = Uuid();
  static final _queues = <String, Future<void>>{};

  String _scope(TenantContext scope) =>
      base64Url.encode(utf8.encode(jsonEncode(scope.toJson())));
  String _base(TenantContext scope, String employeeId, String id) {
    calendarUuid(employeeId);
    calendarUuid(id);
    if (!scope.hasOperationalScope) {
      throw const FormatException(
        'Leave recovery requires an operational scope.',
      );
    }
    return 'w4:leave:${_scope(scope)}:$employeeId:$id:';
  }

  String _receiptKey(String base) => 'receipt:$base';

  /// No reason text or request body is decrypted to populate this index.
  Future<List<SensitiveLeaveRecovery>> recovery(TenantContext scope) async {
    final prefix = 'w4:leave:${_scope(scope)}:';
    final found = <String, SensitiveLeaveRecovery>{};
    var scanned = 0;
    for (final type in ['sensitive_leave', 'sensitive_leave_receipt']) {
      String? after;
      while (true) {
        final page = await repository.pageIds(
          tenantId: scope.tenantId,
          entityType: type,
          afterId: after,
          limit: 200,
        );
        for (final key in page) {
          final bodyKey =
              type == 'sensitive_leave_receipt' && key.startsWith('receipt:')
              ? key.substring(8)
              : key;
          if (!bodyKey.startsWith(prefix)) continue;
          final parts = bodyKey.substring(prefix.length).split(':');
          if (parts.length != 3) {
            throw const FormatException('Leave recovery identity is invalid.');
          }
          final employeeId = calendarUuid(parts[0]);
          final id = calendarUuid(parts[1]);
          final base = _base(scope, employeeId, id);
          DateTime? expiry;
          if (type == 'sensitive_leave') {
            expiry = _expiry(bodyKey, base);
            if (!expiry.isAfter(clock())) {
              await repository.delete(key);
              continue;
            }
          }
          await authorize(scope, employeeId);
          final prior = found[base];
          found[base] = SensitiveLeaveRecovery(
            employeeId,
            id,
            expiry ?? prior?.expiresAt,
            expired: expiry == null && prior?.expiresAt == null,
          );
        }
        scanned += page.length;
        if (page.length < 200) break;
        if (scanned >= 2000) {
          throw const DomainError(
            code: 'DRAFT_LIMIT',
            message: 'Leave recovery metadata exceeds its bounded scan.',
          );
        }
        after = page.last;
      }
    }
    return List.unmodifiable(found.values);
  }

  Future<T> _lock<T>(String key, Future<T> Function() work) async {
    final prior = _queues[key] ?? Future<void>.value();
    final completer = Completer<void>();
    _queues[key] = completer.future;
    await prior;
    try {
      return await work();
    } finally {
      completer.complete();
      if (identical(_queues[key], completer.future)) _queues.remove(key);
    }
  }

  Future<List<String>> _keys(TenantContext scope, String base) async {
    final matches = <String>[];
    String? after;
    var scanned = 0;
    while (true) {
      final page = await repository.pageIds(
        tenantId: scope.tenantId,
        entityType: 'sensitive_leave',
        afterId: after,
        limit: 200,
      );
      matches.addAll(page.where((id) => id.startsWith(base)));
      scanned += page.length;
      if (page.length < 200) break;
      if (scanned >= 2000) {
        throw const DomainError(
          code: 'DRAFT_LIMIT',
          message: 'Leave recovery metadata exceeds its bounded scan.',
        );
      }
      after = page.last;
    }
    if (matches.length > 1) {
      throw const DomainError(
        code: 'DRAFT_CONFLICT',
        message: 'Duplicate leave recovery bodies need comparison.',
      );
    }
    return matches;
  }

  DateTime _expiry(String key, String base) {
    final millis = int.tryParse(key.substring(base.length));
    if (millis == null) {
      throw const FormatException('Leave expiry metadata is invalid.');
    }
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  void _form(
    String action,
    Map<String, Object?> form,
    String employeeId,
    String id,
  ) {
    final fields =
        WorkforceCommands.fields[WorkforceCommandKind.leaveRequest]?[action];
    if (fields == null ||
        form['action'] != action ||
        form['id'] != id ||
        form['employee_id'] != employeeId ||
        form.keys.any((key) => !fields.contains(key)) ||
        utf8.encode(jsonEncode(form)).length > 64 * 1024) {
      throw const FormatException(
        'Leave draft fields or identity are invalid.',
      );
    }
  }

  Future<Map<String, Object?>?> receipt(
    TenantContext scope,
    String employeeId,
    String id,
  ) async {
    await authorize(scope, employeeId);
    final row = await repository.find(
      _receiptKey(_base(scope, employeeId, id)),
    );
    if (row == null) return null;
    final data = row.payload;
    calendarFields(data, {
      'command_id',
      'employee_id',
      'id',
      'expected_version',
    });
    if (row.tenantId != scope.tenantId ||
        row.entityType != 'sensitive_leave_receipt' ||
        data['employee_id'] != employeeId ||
        data['id'] != id) {
      throw const FormatException('Leave receipt scope changed.');
    }
    calendarUuid(data['command_id']);
    workforceInteger(data['expected_version']);
    await authorize(scope, employeeId);
    return Map.unmodifiable(data);
  }

  Future<SensitiveLeaveDraft?> _load(
    TenantContext scope,
    String employeeId,
    String id,
  ) async {
    await authorize(scope, employeeId);
    final base = _base(scope, employeeId, id);
    final keys = await _keys(scope, base);
    if (keys.isEmpty) return null;
    final expiry = _expiry(keys.single, base);
    if (!expiry.isAfter(clock())) {
      await repository.delete(keys.single);
      return null;
    }
    final row = await repository.find(keys.single);
    if (row == null) return null;
    final data = row.payload;
    calendarFields(data, {
      'scope',
      'employee_id',
      'id',
      'action',
      'form',
      'version',
      'pending',
      'error_code',
    });
    if (row.tenantId != scope.tenantId ||
        row.entityType != 'sensitive_leave' ||
        TenantContext.fromJson(workforceMap(data['scope'])) != scope ||
        data['employee_id'] != employeeId ||
        data['id'] != id ||
        row.serverVersion != data['version']) {
      throw const DomainError(
        code: 'DRAFT_SCOPE_MISMATCH',
        message: 'The saved leave request belongs to another scope.',
      );
    }
    final draft = SensitiveLeaveDraft(expiry, data);
    _form(draft.action, draft.form, employeeId, id);
    final pending = draft.pending;
    if (pending != null) {
      final command = pending.envelope;
      WorkforceCommands.validate(
        WorkforceCommandKind.leaveRequest,
        pending.action,
        command.payload,
      );
      if (pending.action != draft.action ||
          command.context != scope ||
          command.payload['employee_id'] != employeeId ||
          command.payload['id'] != id ||
          command.expectedEntityVersion != draft.version) {
        throw const DomainError(
          code: 'DRAFT_SCOPE_MISMATCH',
          message: 'The sealed leave request changed scope or version.',
        );
      }
    }
    await authorize(scope, employeeId);
    return draft;
  }

  Future<SensitiveLeaveDraft?> load(
    TenantContext scope,
    String employeeId,
    String id,
  ) => _lock(_base(scope, employeeId, id), () => _load(scope, employeeId, id));

  Future<void> _write(
    TenantContext scope,
    String employeeId,
    String id,
    String action,
    Map<String, Object?> form,
    int version,
    DateTime expiresAt, {
    ScopedPendingCommand? pending,
    String? errorCode,
  }) => repository.save(
    id:
        _base(scope, employeeId, id) +
        expiresAt.millisecondsSinceEpoch.toString(),
    tenantId: scope.tenantId,
    entityType: 'sensitive_leave',
    payload: {
      'scope': scope.toJson(),
      'employee_id': employeeId,
      'id': id,
      'action': action,
      'form': form,
      'version': version,
      'pending': pending?.toJson(),
      'error_code': errorCode,
    },
    localVersion: 1,
    serverVersion: version,
  );

  Future<void> save(
    TenantContext scope,
    String employeeId,
    String id,
    String action,
    Map<String, Object?> input,
    int version, {
    bool compared = false,
  }) {
    final form = workforceMap(jsonDecode(jsonEncode(input)));
    _form(action, form, employeeId, id);
    workforceInteger(version);
    return _lock(_base(scope, employeeId, id), () async {
      final old = await _load(scope, employeeId, id);
      if (old?.pending != null ||
          old == null && await receipt(scope, employeeId, id) != null) {
        throw const DomainError(
          code: 'COMMAND_PENDING',
          message: 'Resolve the original saved leave request first.',
        );
      }
      if (old?.errorCode == 'VERSION_CONFLICT' && !compared) {
        throw const DomainError(
          code: 'VERSION_CONFLICT',
          message: 'Compare the current leave version first.',
        );
      }
      await _write(
        scope,
        employeeId,
        id,
        action,
        form,
        version,
        old?.expiresAt ?? clock().add(const Duration(hours: 24)),
      );
    });
  }

  Future<ScopedPendingCommand> prepare(
    TenantContext scope,
    String employeeId,
    String id,
    String action,
    Map<String, Object?> input,
    int version,
  ) {
    final form = workforceMap(jsonDecode(jsonEncode(input)));
    _form(action, form, employeeId, id);
    WorkforceCommands.validate(WorkforceCommandKind.leaveRequest, action, form);
    workforceInteger(version);
    if (version >= maxExactWorkInteger) {
      throw const FormatException('Leave expected version exceeds its bound.');
    }
    return _lock(_base(scope, employeeId, id), () async {
      final old = await _load(scope, employeeId, id);
      final previous = old?.pending;
      if (previous != null) {
        if (previous.action == action &&
            previous.envelope.expectedEntityVersion == version &&
            _canonical(previous.envelope.payload) == _canonical(form)) {
          return previous;
        }
        throw const DomainError(
          code: 'COMMAND_PENDING',
          message: 'Retry the exact original leave request.',
        );
      }
      if (old?.errorCode == 'VERSION_CONFLICT' ||
          old != null && old.version != version) {
        throw const DomainError(
          code: 'VERSION_CONFLICT',
          message: 'Compare the current leave version first.',
        );
      }
      if (old == null && await receipt(scope, employeeId, id) != null) {
        throw const DomainError(
          code: 'PRIVATE_DRAFT_EXPIRED',
          message: 'The private text expired. Reconcile its minimal receipt.',
        );
      }
      final pending = ScopedPendingCommand(
        action,
        CommandEnvelope(
          commandId: _uuid.v4(),
          idempotencyKey: _uuid.v4(),
          context: scope,
          payload: form,
          expectedEntityVersion: version,
          clientTimestamp: clock(),
        ),
      );
      final base = _base(scope, employeeId, id);
      await repository.transaction(() async {
        await repository.save(
          id: _receiptKey(base),
          tenantId: scope.tenantId,
          entityType: 'sensitive_leave_receipt',
          payload: {
            'command_id': pending.envelope.commandId,
            'employee_id': employeeId,
            'id': id,
            'expected_version': version,
          },
          localVersion: 1,
          serverVersion: version,
        );
        await _write(
          scope,
          employeeId,
          id,
          action,
          old?.form ?? form,
          version,
          old?.expiresAt ?? clock().add(const Duration(hours: 24)),
          pending: pending,
        );
      });
      return pending;
    });
  }

  Future<void> failure(
    TenantContext scope,
    String employeeId,
    String id,
    String commandId,
    DomainError error,
  ) => _lock(_base(scope, employeeId, id), () async {
    final old = await _load(scope, employeeId, id);
    if (old?.pending?.envelope.commandId != commandId) return;
    final definite = {
      'VERSION_CONFLICT',
      'VALIDATION_ERROR',
      'IDEMPOTENCY_MISMATCH',
      'WORK_INTERVAL_CONFLICT',
      'LEAVE_BALANCE_INSUFFICIENT',
      'STATE_CONFLICT',
      'IDENTITY_EXISTS',
    }.contains(error.code);
    await repository.transaction(() async {
      await _write(
        scope,
        employeeId,
        id,
        old!.action,
        old.form,
        old.version,
        old.expiresAt,
        pending: definite ? null : old.pending,
        errorCode: error.code,
      );
      if (definite) {
        await repository.delete(_receiptKey(_base(scope, employeeId, id)));
      }
    });
  });

  Future<void> complete(
    TenantContext scope,
    String employeeId,
    String id,
    String commandId,
  ) => _lock(_base(scope, employeeId, id), () async {
    final minimal = await receipt(scope, employeeId, id);
    if (minimal?['command_id'] != commandId) {
      throw const DomainError(
        code: 'COMMAND_PENDING',
        message: 'Leave confirmation does not match the saved request.',
      );
    }
    final base = _base(scope, employeeId, id);
    final keys = await _keys(scope, base);
    await repository.transaction(() async {
      for (final key in keys) {
        await repository.delete(key);
      }
      await repository.delete(_receiptKey(base));
    });
  });

  Future<bool> reconcileExpired(
    TenantContext scope,
    String employeeId,
    String id,
    WorkforceRepository server,
  ) async {
    final minimal = await receipt(scope, employeeId, id);
    if (minimal == null) return false;
    final result = await server.leaveOwnReceipt(
      scope,
      minimal['command_id'] as String,
    );
    if (result == null) return false;
    if (result['id'] != id ||
        result['employee_id'] != employeeId ||
        result['version'] != (minimal['expected_version'] as int) + 1) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'The remote leave receipt differs from local recovery.',
      );
    }
    await complete(scope, employeeId, id, minimal['command_id'] as String);
    return true;
  }

  Future<void> discard(TenantContext scope, String employeeId, String id) =>
      _lock(_base(scope, employeeId, id), () async {
        final old = await _load(scope, employeeId, id);
        if (old?.pending != null ||
            await receipt(scope, employeeId, id) != null) {
          throw const DomainError(
            code: 'COMMAND_PENDING',
            message:
                'Resolve the saved or expired leave request before discarding.',
          );
        }
        for (final key in await _keys(scope, _base(scope, employeeId, id))) {
          await repository.delete(key);
        }
      });

  static String _canonical(Object? value) => jsonEncode(_sort(value));
  static Object? _sort(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _sort(value[key])};
    }
    if (value is List) return value.map(_sort).toList();
    return value;
  }
}

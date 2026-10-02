import 'dart:async';
import 'dart:convert';

import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_payroll.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:uuid/uuid.dart';

import 'draft_repository.dart';
import 'scoped_command_draft_store.dart';

final class SensitivePayrollCorrectionDraft {
  SensitivePayrollCorrectionDraft(this.expiresAt, Map<String, Object?> data)
    : _wire = jsonEncode(data);
  final DateTime expiresAt;
  final String _wire;
  Map<String, Object?> get data => workforceMap(jsonDecode(_wire));
  Map<String, Object?> get form => workforceMap(data['form']);
  String get id => data['id'] as String;
  PayrollCorrectionCommandKind get kind =>
      PayrollCorrectionCommandKind.values.byName(data['kind'] as String);
  String get action => data['action'] as String;
  String get capability => PayrollCorrectionCommands.capability(kind, action);
  int get version => data['version'] as int;
  String? get errorCode => data['error_code'] as String?;
  ScopedPendingCommand? get pending => data['pending'] == null
      ? null
      : ScopedPendingCommand.fromJson(workforceMap(data['pending']));
}

final class SensitivePayrollCorrectionRecovery {
  const SensitivePayrollCorrectionRecovery(
    this.kind,
    this.id,
    this.capability,
    this.expiresAt,
  );
  final PayrollCorrectionCommandKind kind;
  final String id, capability;
  final DateTime? expiresAt;
  bool get expired => expiresAt == null;
}

/// Only identity, action capability and fixed expiry appear in the index.
/// Private payroll bodies expire in 24 hours; an uncertain command keeps an
/// encrypted minimal receipt until its matching server outcome is confirmed.
final class SensitivePayrollCorrectionDraftStore {
  SensitivePayrollCorrectionDraftStore(
    this.repository,
    this.authorize, {
    DateTime Function()? clock,
  }) : clock = clock ?? (() => DateTime.now().toUtc());
  final EncryptedDraftRepository repository;
  final Future<void> Function(TenantContext, String) authorize;
  final DateTime Function() clock;
  static const _uuid = Uuid();
  static final _queues = <String, Future<void>>{};
  static const _bodyType = 'sensitive_payroll_correction',
      _receiptType = 'sensitive_payroll_correction_receipt';
  static const _comparison = {
    'VERSION_CONFLICT',
    'PAYROLL_INPUTS_CHANGED',
    'PAYROLL_RULES_CHANGED',
  };
  static const _definite = {
    ..._comparison,
    'VALIDATION_ERROR',
    'IDEMPOTENCY_MISMATCH',
    'STATE_CONFLICT',
    'PERIOD_CLOSED',
    'PAYROLL_SOURCE_CONSUMED',
    'PAYROLL_PERIOD_CONSUMED',
    'PAYROLL_NEGATIVE_NET',
    'PAYROLL_SEPARATE_CONTROL_REQUIRED',
    'PAYROLL_SETTLEMENT_EXISTS',
    'PAYROLL_OVERPAYMENT',
    'PAYROLL_INDEPENDENT_APPROVAL_REQUIRED',
    'PAYROLL_ACTIVE_SETTLEMENT',
    'PAYROLL_SETTLEMENT_EXCEEDS_DUE',
    'PROVIDER_UNAVAILABLE',
    'IDENTITY_EXISTS',
    'PAYROLL_PROVIDER_UNAVAILABLE',
    'PAYROLL_RULE_COVERAGE_REQUIRED',
    'PAYROLL_CALENDAR_COVERAGE_REQUIRED',
  };

  String _prefix(TenantContext scope) {
    if (!scope.hasOperationalScope) {
      throw const FormatException(
        'Payroll recovery needs an operational scope.',
      );
    }
    return 'w4:payroll-correction:${base64Url.encode(utf8.encode(jsonEncode(scope.toJson())))}:';
  }

  String _base(
    TenantContext scope,
    PayrollCorrectionCommandKind kind,
    String id,
  ) => '${_prefix(scope)}${kind.name}:${calendarUuid(id)}:';
  String _cap(PayrollCorrectionCommandKind kind, String action) {
    if (PayrollCorrectionCommands.fields[kind]?[action] == null) {
      throw const FormatException('Payroll draft action is invalid.');
    }
    return PayrollCorrectionCommands.capability(kind, action);
  }

  void _validCap(PayrollCorrectionCommandKind kind, String cap) {
    if (!PayrollCorrectionCommands.fields[kind]!.keys.any(
      (a) => _cap(kind, a) == cap,
    )) {
      throw const FormatException('Payroll recovery capability changed.');
    }
  }

  Future<T> _lock<T>(String base, Future<T> Function() work) async {
    final prior = _queues[base] ?? Future<void>.value(),
        done = Completer<void>();
    _queues[base] = done.future;
    await prior;
    try {
      return await work();
    } finally {
      done.complete();
      if (identical(_queues[base], done.future)) _queues.remove(base);
    }
  }

  Future<List<String>> _keys(
    TenantContext scope,
    String type, {
    String? base,
  }) async {
    String? after;
    final found = <String>[];
    var count = 0;
    while (true) {
      final page = await repository.pageIds(
        tenantId: scope.tenantId,
        entityType: type,
        afterId: after,
        limit: 200,
      );
      found.addAll(page.where((key) => key.startsWith(base ?? _prefix(scope))));
      count += page.length;
      if (page.length < 200) break;
      if (count >= 2000) {
        throw const DomainError(
          code: 'DRAFT_LIMIT',
          message: 'Payroll recovery exceeds its bounded metadata scan.',
        );
      }
      after = page.last;
    }
    if (base != null && found.length > 1) {
      throw const DomainError(
        code: 'DRAFT_CONFLICT',
        message: 'Duplicate payroll recovery entries need comparison.',
      );
    }
    return found;
  }

  SensitivePayrollCorrectionRecovery _metadata(
    TenantContext scope,
    String key,
    bool body,
  ) {
    final parts = key.substring(_prefix(scope).length).split(':');
    if (parts.length != (body ? 4 : 3)) {
      throw const FormatException('Payroll recovery index is invalid.');
    }
    final kind = PayrollCorrectionCommandKind.values.byName(parts[0]),
        id = calendarUuid(parts[1]),
        cap = parts[2];
    _validCap(kind, cap);
    DateTime? expiry;
    if (body) {
      final millis = int.tryParse(parts[3]);
      if (millis == null) {
        throw const FormatException('Payroll expiry metadata is invalid.');
      }
      expiry = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    }
    return SensitivePayrollCorrectionRecovery(kind, id, cap, expiry);
  }

  Future<List<SensitivePayrollCorrectionRecovery>> recovery(
    TenantContext scope,
  ) async {
    final found = <String, SensitivePayrollCorrectionRecovery>{};
    for (final type in [_bodyType, _receiptType]) {
      for (final key in await _keys(scope, type)) {
        final meta = _metadata(scope, key, type == _bodyType),
            base = _base(scope, meta.kind, meta.id);
        if (meta.expiresAt != null && !meta.expiresAt!.isAfter(clock())) {
          await repository.delete(key);
          continue;
        }
        await authorize(scope, meta.capability);
        final prior = found[base];
        if (prior != null && prior.capability != meta.capability) {
          throw const FormatException(
            'Payroll body and receipt capability differ.',
          );
        }
        found[base] = prior ?? meta;
      }
    }
    return List.unmodifiable(found.values);
  }

  void _form(
    PayrollCorrectionCommandKind kind,
    String id,
    String action,
    Map<String, Object?> form,
  ) {
    final fields = PayrollCorrectionCommands.fields[kind]?[action];
    if (fields == null ||
        form['id'] != id ||
        form['action'] != action ||
        form.keys.any((k) => !fields.contains(k)) ||
        utf8.encode(jsonEncode(form)).length > 256 * 1024) {
      throw const FormatException(
        'Payroll draft fields or identity are invalid.',
      );
    }
  }

  Future<Map<String, Object?>?> receipt(
    TenantContext scope,
    PayrollCorrectionCommandKind kind,
    String id,
  ) async {
    final keys = await _keys(scope, _receiptType, base: _base(scope, kind, id));
    if (keys.isEmpty) return null;
    final meta = _metadata(scope, keys.single, false);
    await authorize(scope, meta.capability);
    final row = await repository.find(keys.single);
    if (row == null) return null;
    final data = row.payload;
    calendarFields(data, {
      'command_id',
      'kind',
      'id',
      'capability',
      'expected_version',
    });
    if (row.tenantId != scope.tenantId ||
        row.entityType != _receiptType ||
        data['kind'] != kind.name ||
        data['id'] != id ||
        data['capability'] != meta.capability ||
        row.serverVersion != data['expected_version']) {
      throw const FormatException('Payroll receipt scope changed.');
    }
    calendarUuid(data['command_id']);
    workforceInteger(data['expected_version']);
    await authorize(scope, meta.capability);
    return Map.unmodifiable(data);
  }

  Future<SensitivePayrollCorrectionDraft?> _load(
    TenantContext scope,
    PayrollCorrectionCommandKind kind,
    String id,
  ) async {
    final keys = await _keys(scope, _bodyType, base: _base(scope, kind, id));
    if (keys.isEmpty) return null;
    final meta = _metadata(scope, keys.single, true);
    if (!meta.expiresAt!.isAfter(clock())) {
      await repository.delete(keys.single);
      return null;
    }
    await authorize(scope, meta.capability);
    final row = await repository.find(keys.single);
    if (row == null) return null;
    final data = row.payload;
    calendarFields(data, {
      'scope',
      'kind',
      'id',
      'action',
      'version',
      'form',
      'pending',
      'error_code',
    });
    if (row.tenantId != scope.tenantId ||
        row.entityType != _bodyType ||
        TenantContext.fromJson(workforceMap(data['scope'])) != scope ||
        data['kind'] != kind.name ||
        data['id'] != id ||
        row.serverVersion != data['version']) {
      throw const DomainError(
        code: 'DRAFT_SCOPE_MISMATCH',
        message: 'Saved payroll belongs to another scope.',
      );
    }
    final draft = SensitivePayrollCorrectionDraft(meta.expiresAt!, data);
    workforceInteger(draft.version);
    _form(kind, id, draft.action, draft.form);
    if (draft.capability != meta.capability) {
      throw const FormatException('Payroll draft capability changed.');
    }
    final pending = draft.pending;
    if (pending != null) {
      PayrollCorrectionCommands.validate(
        kind,
        pending.envelope.payload,
        draft.version,
      );
      if (pending.action != draft.action ||
          pending.envelope.context != scope ||
          pending.envelope.payload['id'] != id ||
          pending.envelope.expectedEntityVersion != draft.version ||
          _canonical(pending.envelope.payload) != _canonical(draft.form)) {
        throw const DomainError(
          code: 'DRAFT_SCOPE_MISMATCH',
          message: 'Sealed payroll changed identity, scope or version.',
        );
      }
    }
    await authorize(scope, meta.capability);
    return draft;
  }

  Future<SensitivePayrollCorrectionDraft?> load(
    TenantContext scope,
    PayrollCorrectionCommandKind kind,
    String id,
  ) => _lock(_base(scope, kind, id), () => _load(scope, kind, id));
  Future<void> _write(
    TenantContext scope,
    PayrollCorrectionCommandKind kind,
    String id,
    String action,
    Map<String, Object?> form,
    int version,
    DateTime expiry, {
    ScopedPendingCommand? pending,
    String? errorCode,
  }) async {
    final base = _base(scope, kind, id), cap = _cap(kind, action);
    final key = '$base$cap:${expiry.millisecondsSinceEpoch}';
    // Callers hold the aggregate queue and repository transaction when replacing.
    for (final old in await _keys(scope, _bodyType, base: base)) {
      if (old != key) await repository.delete(old);
    }
    await repository.save(
      id: key,
      tenantId: scope.tenantId,
      entityType: _bodyType,
      payload: {
        'scope': scope.toJson(),
        'kind': kind.name,
        'id': id,
        'action': action,
        'version': version,
        'form': form,
        'pending': pending?.toJson(),
        'error_code': errorCode,
      },
      localVersion: 1,
      serverVersion: version,
    );
  }

  Future<void> save(
    TenantContext scope,
    PayrollCorrectionCommandKind kind,
    String id,
    String action,
    Map<String, Object?> input,
    int version, {
    bool compared = false,
  }) {
    final form = workforceMap(jsonDecode(jsonEncode(input)));
    _form(kind, id, action, form);
    workforceInteger(version);
    return _lock(_base(scope, kind, id), () async {
      await authorize(scope, _cap(kind, action));
      final old = await _load(scope, kind, id);
      if (old?.pending != null || await receipt(scope, kind, id) != null) {
        throw const DomainError(
          code: 'COMMAND_PENDING',
          message: 'Resolve the original payroll request first.',
        );
      }
      if ((old != null && old.version != version ||
              _comparison.contains(old?.errorCode)) &&
          !compared) {
        throw const DomainError(
          code: 'VERSION_CONFLICT',
          message: 'Compare the current payroll inputs and version first.',
        );
      }
      await repository.transaction(
        () => _write(
          scope,
          kind,
          id,
          action,
          form,
          version,
          old?.expiresAt ?? clock().add(const Duration(hours: 24)),
        ),
      );
    });
  }

  Future<ScopedPendingCommand> prepare(
    TenantContext scope,
    PayrollCorrectionCommandKind kind,
    String id,
    String action,
    Map<String, Object?> input,
    int version,
  ) {
    final form = workforceMap(jsonDecode(jsonEncode(input)));
    _form(kind, id, action, form);
    PayrollCorrectionCommands.validate(kind, form, version);
    return _lock(_base(scope, kind, id), () async {
      final cap = _cap(kind, action);
      await authorize(scope, cap);
      final old = await _load(scope, kind, id), previous = old?.pending;
      if (previous != null) {
        if (previous.action == action &&
            previous.envelope.expectedEntityVersion == version &&
            _canonical(previous.envelope.payload) == _canonical(form)) {
          return previous;
        }
        throw const DomainError(
          code: 'COMMAND_PENDING',
          message: 'Retry the exact original payroll request.',
        );
      }
      if (old != null &&
          (old.version != version || _comparison.contains(old.errorCode))) {
        throw const DomainError(
          code: 'VERSION_CONFLICT',
          message: 'Compare the current payroll inputs and version first.',
        );
      }
      if (await receipt(scope, kind, id) != null) {
        throw const DomainError(
          code: 'PRIVATE_DRAFT_EXPIRED',
          message:
              'Private payroll fields expired. Reconcile the minimal receipt.',
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
      await repository.transaction(() async {
        await repository.save(
          id: '${_base(scope, kind, id)}$cap',
          tenantId: scope.tenantId,
          entityType: _receiptType,
          payload: {
            'command_id': pending.envelope.commandId,
            'kind': kind.name,
            'id': id,
            'capability': cap,
            'expected_version': version,
          },
          localVersion: 1,
          serverVersion: version,
        );
        await _write(
          scope,
          kind,
          id,
          action,
          form,
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
    PayrollCorrectionCommandKind kind,
    String id,
    String commandId,
    DomainError error,
  ) => _lock(_base(scope, kind, id), () async {
    final old = await _load(scope, kind, id);
    if (old?.pending?.envelope.commandId != commandId) return;
    final definite = _definite.contains(error.code);
    await repository.transaction(() async {
      await _write(
        scope,
        kind,
        id,
        old!.action,
        old.form,
        old.version,
        old.expiresAt,
        pending: definite ? null : old.pending,
        errorCode: error.code,
      );
      if (definite) {
        for (final key in await _keys(
          scope,
          _receiptType,
          base: _base(scope, kind, id),
        )) {
          await repository.delete(key);
        }
      }
    });
  });
  Future<void> complete(
    TenantContext scope,
    PayrollCorrectionCommandKind kind,
    String id,
    String commandId,
    Map<String, Object?> response,
  ) => _lock(_base(scope, kind, id), () async {
    final minimal = await receipt(scope, kind, id),
        entity = workforceMap(response['entity']);
    if (minimal == null ||
        minimal['command_id'] != commandId ||
        response['command_id'] != commandId ||
        entity['id'] != id ||
        entity['version'] != (minimal['expected_version'] as int) + 1) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Payroll confirmation differs from the saved request.',
      );
    }
    assertPayrollScope(entity, scope);
    await repository.transaction(() async {
      final base = _base(scope, kind, id);
      for (final type in [_bodyType, _receiptType]) {
        for (final key in await _keys(scope, type, base: base)) {
          await repository.delete(key);
        }
      }
    });
  });
  Future<bool> reconcileExpired(
    TenantContext scope,
    PayrollCorrectionCommandKind kind,
    String id,
    PayrollCorrectionRepository server,
  ) async {
    final minimal = await receipt(scope, kind, id);
    if (minimal == null) return false;
    final result = await server.ownReceipt(
      scope,
      minimal['command_id'] as String,
      minimal['capability'] as String,
    );
    if (result == null) return false;
    await complete(scope, kind, id, minimal['command_id'] as String, result);
    return true;
  }

  Future<void> discard(
    TenantContext scope,
    PayrollCorrectionCommandKind kind,
    String id,
  ) => _lock(_base(scope, kind, id), () async {
    final old = await _load(scope, kind, id);
    if (old?.pending != null || await receipt(scope, kind, id) != null) {
      throw const DomainError(
        code: 'COMMAND_PENDING',
        message: 'Resolve saved payroll before discarding it.',
      );
    }
    for (final key in await _keys(
      scope,
      _bodyType,
      base: _base(scope, kind, id),
    )) {
      await repository.delete(key);
    }
  });
  static String _canonical(Object? value) => jsonEncode(_sort(value));
  static Object? _sort(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final k in keys) k: _sort(value[k])};
    }
    if (value is List) return value.map(_sort).toList();
    return value;
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:uuid/uuid.dart';
import 'draft_repository.dart';
import 'scoped_command_draft_store.dart';

final class PrivateHrDraft {
  PrivateHrDraft(this.expiresAt, Map<String, Object?> row)
    : _wire = jsonEncode(row);
  final DateTime expiresAt;
  final String _wire;
  Map<String, Object?> get row => hrMap(jsonDecode(_wire));
  String get action => row['action'] as String;
  String get aggregateId => row['id'] as String;
  Map<String, Object?> get form => hrMap(row['form']);
  int get version => row['version'] as int;
  String? get errorCode => row['error_code'] as String?;
  ScopedPendingCommand? get pending => row['pending'] == null
      ? null
      : ScopedPendingCommand.fromJson(hrMap(row['pending']));
}

final class PrivateHrRecovery {
  const PrivateHrRecovery({
    required this.employeeId,
    required this.aggregateId,
    required this.capability,
    required this.actionHint,
    this.expiresAt,
  });
  final String? employeeId;
  final String aggregateId, capability, actionHint;
  final DateTime? expiresAt;
}

/// Expiry is non-content metadata and does not extend on edits. Expired rows
/// are removed before decryption; document drafts contain metadata only.
final class PrivateHrDraftStore {
  PrivateHrDraftStore(
    this.repository,
    this.authorize, {
    DateTime Function()? clock,
  }) : clock = clock ?? (() => DateTime.now().toUtc());
  final EncryptedDraftRepository repository;
  final Future<void> Function(TenantContext, String?, String) authorize;
  final DateTime Function() clock;
  static const _uuid = Uuid();
  static final _queues = <String, Future<void>>{};
  String _base(
    TenantContext scope,
    String? employee,
    String id,
    String action,
  ) =>
      'w4:private:${base64Url.encode(utf8.encode(jsonEncode(scope.toJson())))}:${employee ?? 'entity'}:${HrCommands.capability(action)}:$id:';
  String _receipt(String base) => 'receipt:$base';

  /// Metadata only: no draft or contact text is decrypted to build this index.
  Future<List<PrivateHrRecovery>> recovery(
    TenantContext scope,
    Set<String> capabilities,
  ) async {
    final prefix =
        'w4:private:${base64Url.encode(utf8.encode(jsonEncode(scope.toJson())))}:';
    final found = <String, PrivateHrRecovery>{};
    var scanned = 0;
    for (final type in {'private_hr', 'private_hr_receipt'}) {
      String? after;
      while (true) {
        final keys = await repository.pageIds(
          tenantId: scope.tenantId,
          entityType: type,
          afterId: after,
          limit: 200,
        );
        for (final key in keys) {
          final bodyKey =
              type == 'private_hr_receipt' && key.startsWith('receipt:')
              ? key.substring(8)
              : key;
          if (!bodyKey.startsWith(prefix)) continue;
          final parts = bodyKey.substring(prefix.length).split(':');
          if (parts.length != 4 || !capabilities.contains(parts[1])) continue;
          final employee = parts[0] == 'entity' ? null : calendarUuid(parts[0]);
          final id = calendarUuid(parts[2]);
          final action = HrCommands.fields.keys
              .where((a) => HrCommands.capability(a) == parts[1])
              .firstOrNull;
          if (action == null) continue;
          await authorize(scope, null, parts[1]);
          final base = _base(scope, employee, id, action);
          DateTime? expiry;
          if (type == 'private_hr') {
            expiry = _expiry(key, base);
            if (!expiry.isAfter(clock())) {
              await repository.delete(key);
              continue;
            }
          }
          final old = found[base];
          found[base] = PrivateHrRecovery(
            employeeId: employee,
            aggregateId: id,
            capability: parts[1],
            actionHint: action,
            expiresAt: expiry ?? old?.expiresAt,
          );
        }
        scanned += keys.length;
        if (keys.length < 200) break;
        if (scanned >= 2000) {
          throw const DomainError(
            code: 'DRAFT_LIMIT',
            message: 'Private recovery metadata exceeds its bounded scan.',
          );
        }
        after = keys.last;
      }
    }
    return List.unmodifiable(found.values);
  }

  Future<T> _lock<T>(String key, Future<T> Function() work) async {
    final previous = _queues[key] ?? Future<void>.value();
    final done = Completer<void>();
    _queues[key] = done.future;
    await previous;
    try {
      return await work();
    } finally {
      done.complete();
      if (identical(_queues[key], done.future)) _queues.remove(key);
    }
  }

  Future<List<String>> _keys(TenantContext scope, String base) async {
    final found = <String>[];
    String? after;
    var scanned = 0;
    while (true) {
      final page = await repository.pageIds(
        tenantId: scope.tenantId,
        entityType: 'private_hr',
        afterId: after,
        limit: 200,
      );
      found.addAll(page.where((key) => key.startsWith(base)));
      scanned += page.length;
      if (page.length < 200) break;
      if (scanned >= 2000) {
        throw const DomainError(
          code: 'DRAFT_LIMIT',
          message: 'Private recovery metadata exceeds its bounded scan.',
        );
      }
      after = page.last;
    }
    if (found.length > 1) {
      throw const DomainError(
        code: 'DRAFT_CONFLICT',
        message:
            'Compare duplicate private recovery entries before proceeding.',
      );
    }
    return found;
  }

  DateTime _expiry(String key, String base) {
    final millis = int.tryParse(key.substring(base.length));
    if (millis == null) {
      throw const FormatException('Private draft expiry is invalid.');
    }
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  Future<PrivateHrDraft?> _load(
    TenantContext scope,
    String? employee,
    String id,
    String action,
  ) async {
    await authorize(scope, employee, HrCommands.capability(action));
    final base = _base(scope, employee, id, action);
    final keys = await _keys(scope, base);
    if (keys.isEmpty) return null;
    final expires = _expiry(keys.single, base);
    if (!expires.isAfter(clock())) {
      await repository.delete(keys.single);
      return null;
    }
    final saved = await repository.find(keys.single);
    if (saved == null) return null;
    final data = saved.payload;
    if (saved.entityType != 'private_hr' ||
        saved.tenantId != scope.tenantId ||
        data['id'] != id ||
        data['employee_id'] != employee ||
        TenantContext.fromJson(hrMap(data['scope'])) != scope ||
        HrCommands.capability(data['action'] as String) !=
            HrCommands.capability(action)) {
      throw const DomainError(
        code: 'DRAFT_SCOPE_MISMATCH',
        message: 'Private recovery belongs to another scope or capability.',
      );
    }
    final draft = PrivateHrDraft(expires, data);
    _form(draft.action, draft.form, id, employee);
    if (draft.pending != null) {
      final pending = draft.pending!;
      final command = pending.envelope;
      HrCommands.validate(pending.action, command.payload);
      if (command.context != scope ||
          command.payload['id'] != id ||
          command.payload['employee_id'] != employee ||
          command.expectedEntityVersion != draft.version ||
          pending.action != draft.action) {
        throw const DomainError(
          code: 'DRAFT_SCOPE_MISMATCH',
          message: 'The private sealed request is inconsistent.',
        );
      }
    }
    await authorize(scope, employee, HrCommands.capability(action));
    return draft;
  }

  Future<PrivateHrDraft?> load(
    TenantContext scope,
    String? employee,
    String id,
    String action,
  ) => _lock(
    _base(scope, employee, id, action),
    () => _load(scope, employee, id, action),
  );
  void _form(
    String action,
    Map<String, Object?> form,
    String id,
    String? employee,
  ) {
    final allowed = HrCommands.fields[action];
    if (allowed == null ||
        form['action'] != action ||
        form['id'] != id ||
        form['employee_id'] != employee ||
        form.keys.any((k) => !allowed.contains(k)) ||
        utf8.encode(jsonEncode(form)).length > 64 * 1024) {
      throw const FormatException(
        'Private draft fields or identity are invalid.',
      );
    }
    if (action == 'profile_save' &&
        form['body'] != null &&
        hrMap(form['body']).keys.any((k) => !hrContactFields.contains(k))) {
      throw const FormatException(
        'Private contact draft contains unsupported fields.',
      );
    }
    if ({'review_create', 'review_revise'}.contains(action) &&
        form['body'] != null &&
        hrMap(
          form['body'],
        ).keys.any((k) => !{'objectives', 'comments'}.contains(k))) {
      throw const FormatException('Review draft contains unsupported fields.');
    }
  }

  Future<void> _write(
    TenantContext scope,
    String? employee,
    String id,
    String action,
    Map<String, Object?> form,
    int version,
    DateTime expires, {
    ScopedPendingCommand? pending,
    String? errorCode,
  }) async {
    final base = _base(scope, employee, id, action);
    await repository.save(
      id: base + expires.millisecondsSinceEpoch.toString(),
      tenantId: scope.tenantId,
      entityType: 'private_hr',
      payload: {
        'scope': scope.toJson(),
        'employee_id': employee,
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
  }

  Future<Map<String, Object?>?> expiredReceipt(
    TenantContext scope,
    String? employee,
    String id,
    String action,
  ) async {
    await authorize(scope, null, HrCommands.capability(action));
    final row = await repository.find(
      _receipt(_base(scope, employee, id, action)),
    );
    if (row == null) return null;
    if (row.entityType != 'private_hr_receipt' ||
        row.tenantId != scope.tenantId) {
      throw const FormatException('Minimal private receipt scope is invalid.');
    }
    calendarFields(row.payload, {
      'command_id',
      'action',
      'id',
      'employee_id',
      'expected_version',
    });
    calendarUuid(row.payload['command_id']);
    if (row.payload['id'] != id ||
        row.payload['employee_id'] != employee ||
        HrCommands.capability(row.payload['action'] as String) !=
            HrCommands.capability(action)) {
      throw const FormatException(
        'Minimal private receipt identity is invalid.',
      );
    }
    await authorize(scope, null, HrCommands.capability(action));
    return Map.unmodifiable(row.payload);
  }

  Future<void> save(
    TenantContext scope,
    String? employee,
    String id,
    String action,
    Map<String, Object?> input,
    int version, {
    bool compared = false,
  }) {
    final form = hrMap(jsonDecode(jsonEncode(input)));
    _form(action, form, id, employee);
    return _lock(_base(scope, employee, id, action), () async {
      final old = await _load(scope, employee, id, action);
      if (old?.pending != null) {
        throw const DomainError(
          code: 'COMMAND_PENDING',
          message: 'Retry the exact private request before editing.',
        );
      }
      if (old?.errorCode == 'VERSION_CONFLICT' && !compared) {
        throw const DomainError(
          code: 'VERSION_CONFLICT',
          message: 'Compare the current private version first.',
        );
      }
      if (old == null &&
          await expiredReceipt(scope, employee, id, action) != null) {
        throw const DomainError(
          code: 'PRIVATE_DRAFT_EXPIRED',
          message:
              'Private text expired. Resolve the minimal command receipt first.',
        );
      }
      await _write(
        scope,
        employee,
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
    String? employee,
    String id,
    String action,
    Map<String, Object?> input,
    int version,
  ) {
    final form = hrMap(jsonDecode(jsonEncode(input)));
    _form(action, form, id, employee);
    HrCommands.validate(action, form);
    if (version < 0 || version >= 9007199254740991) {
      throw const FormatException('Private expected version is invalid.');
    }
    return _lock(_base(scope, employee, id, action), () async {
      final old = await _load(scope, employee, id, action);
      if (old?.pending != null) {
        final pending = old!.pending!;
        if (pending.action != action ||
            pending.envelope.expectedEntityVersion != version ||
            _canonical(pending.envelope.payload) != _canonical(form)) {
          throw const DomainError(
            code: 'COMMAND_PENDING',
            message: 'Preserve the exact original private request.',
          );
        }
        return pending;
      }
      if (old?.errorCode == 'VERSION_CONFLICT' ||
          old != null && old.version != version) {
        throw const DomainError(
          code: 'VERSION_CONFLICT',
          message: 'Compare the current private version first.',
        );
      }
      if (old == null &&
          await expiredReceipt(scope, employee, id, action) != null) {
        throw const DomainError(
          code: 'PRIVATE_DRAFT_EXPIRED',
          message:
              'Resolve the minimal receipt of the expired private request.',
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
      final base = _base(scope, employee, id, action);
      await repository.transaction(() async {
        await repository.save(
          id: _receipt(base),
          tenantId: scope.tenantId,
          entityType: 'private_hr_receipt',
          payload: {
            'command_id': pending.envelope.commandId,
            'action': action,
            'id': id,
            'employee_id': employee,
            'expected_version': version,
          },
          localVersion: 1,
          serverVersion: version,
        );
        await _write(
          scope,
          employee,
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
    String? employee,
    String id,
    String action,
    String commandId,
    DomainError error,
  ) => _lock(_base(scope, employee, id, action), () async {
    final old = await _load(scope, employee, id, action);
    if (old?.pending?.envelope.commandId != commandId) return;
    final definite = {
      'VERSION_CONFLICT',
      'VALIDATION_ERROR',
      'IDEMPOTENCY_MISMATCH',
      'HR_LEGAL_HOLD',
      'HR_LINK_ALREADY_EXISTS',
      'HR_PURGE_ALREADY_STARTED',
      'HR_UPLOAD_VERIFICATION_REQUIRED',
    }.contains(error.code);
    await repository.transaction(() async {
      await _write(
        scope,
        employee,
        id,
        old!.action,
        old.form,
        old.version,
        old.expiresAt,
        pending: definite ? null : old.pending,
        errorCode: error.code,
      );
      if (definite) {
        await repository.delete(_receipt(_base(scope, employee, id, action)));
      }
    });
  });
  Future<void> complete(
    TenantContext scope,
    String? employee,
    String id,
    String action,
    String commandId,
  ) => _lock(_base(scope, employee, id, action), () async {
    final stub = await expiredReceipt(scope, employee, id, action);
    if (stub?['command_id'] != commandId) {
      throw const DomainError(
        code: 'COMMAND_PENDING',
        message: 'Private confirmation does not match recovery metadata.',
      );
    }
    final base = _base(scope, employee, id, action);
    final keys = await _keys(scope, base);
    await repository.transaction(() async {
      for (final key in keys) {
        await repository.delete(key);
      }
      await repository.delete(_receipt(base));
    });
  });
  Future<void> discard(
    TenantContext scope,
    String? employee,
    String id,
    String action,
  ) => _lock(_base(scope, employee, id, action), () async {
    final old = await _load(scope, employee, id, action);
    if (old?.pending != null ||
        await expiredReceipt(scope, employee, id, action) != null) {
      throw const DomainError(
        code: 'COMMAND_PENDING',
        message:
            'Resolve the sealed or expired private request before discarding.',
      );
    }
    for (final key in await _keys(scope, _base(scope, employee, id, action))) {
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

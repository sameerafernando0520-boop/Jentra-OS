import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'data/employee_gateway.dart';
import 'data/employee_self_service.dart';
import 'data/employee_storage.dart';
import 'data/employee_document_export.dart';

final class _DocumentExportLease {
  _DocumentExportLease(this.owner, this.startedAt);
  final String owner;
  final DateTime startedAt;
  bool revoked = false;
  Completer<void> changed = Completer<void>();
  void signal() {
    final previous = changed;
    changed = Completer<void>();
    if (!previous.isCompleted) previous.complete();
  }
}

/// A durable, immutable request is sealed before dispatch. Uncertain transport
/// results retain the same command and target IDs, including across restarts.
final class EmployeeSelfPending {
  EmployeeSelfPending({
    required this.owner,
    required this.rpc,
    required Map<String, Object?> parameters,
    required this.createdAt,
    this.receiptOnly = false,
  }) : parameters = selfImmutableMap(parameters);
  final String owner, rpc;
  final Map<String, Object?> parameters;
  final DateTime createdAt;
  final bool receiptOnly;
  String get commandId => selfUuid(parameters['p_command_id']);
  String get requestId => selfUuid(
    parameters['p_request_id'] ?? selfMap(parameters['p_payload'])['id'],
  );
  EmployeeSelfPending redacted() => EmployeeSelfPending(
    owner: owner,
    rpc: rpc,
    parameters: {'p_command_id': commandId, 'p_request_id': requestId},
    createdAt: createdAt,
    receiptOnly: true,
  );
  Map<String, Object?> toJson() => {
    'owner': owner,
    'rpc': rpc,
    'parameters': parameters,
    'created_at': createdAt.toIso8601String(),
    'receipt_only': receiptOnly,
    'schema': 2,
  };
  factory EmployeeSelfPending.parse(String wire, EmployeeIdentity identity) =>
      EmployeeSelfPending.forOwner(wire, identity.key);
  factory EmployeeSelfPending.forOwner(String wire, String owner) {
    if (wire.length > 24000) throw const FormatException('Oversized request.');
    final json = selfMap(jsonDecode(wire));
    if (!((json['schema'] == 1 && json.length == 5) ||
            (json['schema'] == 2 &&
                json.length == 6 &&
                json['receipt_only'] is bool)) ||
        json['owner'] != owner ||
        !employeeSelfCommandRpcs.contains(json['rpc'])) {
      throw const FormatException('Saved request owner mismatch.');
    }
    final params = selfMap(json['parameters']);
    selfUuid(params['p_command_id']);
    if (params.keys.any(
      (key) => {
        'p_tenant_id',
        'p_legal_entity_id',
        'p_branch_id',
        'p_employee_id',
        'employee_id',
      }.contains(key),
    )) {
      throw const FormatException('Unexpected authority selector.');
    }
    final receiptOnly = json['receipt_only'] == true;
    if (receiptOnly) {
      if (params.length != 2 ||
          params.keys.any(
            (key) => !{'p_command_id', 'p_request_id'}.contains(key),
          )) {
        throw const FormatException('Invalid receipt-only request.');
      }
      selfUuid(params['p_request_id']);
    } else {
      validateEmployeeCommandParameters(json['rpc']! as String, params);
      selfUuid(params['p_request_id'] ?? selfMap(params['p_payload'])['id']);
    }
    final created = DateTime.tryParse(selfText(json['created_at'], max: 40));
    if (created == null || !created.isUtc) {
      throw const FormatException('Invalid request timestamp.');
    }
    return EmployeeSelfPending(
      owner: owner,
      rpc: json['rpc']! as String,
      parameters: params,
      createdAt: created,
      receiptOnly: receiptOnly,
    );
  }
}

final class EmployeeSelfServiceController extends ChangeNotifier {
  EmployeeSelfServiceController({
    required this.gateway,
    required this.store,
    required this.currentIdentity,
    this.documentExporter,
    DateTime Function()? now,
    this.exportReturnTimeout = const Duration(minutes: 2),
  }) : _now = now ?? DateTime.now {
    if (exportReturnTimeout <= Duration.zero ||
        exportReturnTimeout > const Duration(minutes: 2)) {
      throw ArgumentError.value(exportReturnTimeout, 'exportReturnTimeout');
    }
  }
  final EmployeeSelfServiceGateway? gateway;
  final EmployeeKeyValueStore store;
  final EmployeeDocumentExporter? documentExporter;
  final EmployeeIdentity? Function() currentIdentity;
  final DateTime Function() _now;
  Future<void> _storageTail = Future<void>.value();
  static const _indexKey = 'jentra.employee.self.pending.index.v1';
  final _retentionTimers = <String, Timer>{};
  final Duration exportReturnTimeout;
  _DocumentExportLease? _exportLease;
  String? _exportReturnOwner;
  bool get exportBusy => _exportLease != null;
  bool exportSaved = false;
  final pages = <EmployeeService, EmployeeServicePage>{};
  final errors = <EmployeeService, EmployeeFailure>{};
  final loading = <EmployeeService>{};
  final balances = <String, EmployeeLeaveBalance>{};
  final details = <String, EmployeeServiceRecord>{};
  String _detailKey(EmployeeService service, String id) =>
      '${service.name}/$id';
  EmployeeServiceRecord? detailFor(EmployeeService service, String id) =>
      details[_detailKey(service, id)];
  final _balanceReads = <String, int>{};
  final _detailReads = <String, int>{};
  int _readSequence = 0;
  EmployeeFailure? actionError;
  EmployeeSelfPending? pending;
  bool actionBusy = false;
  bool confirmed = false;
  bool notApplied = false;
  String? _owner;
  int _epoch = 0;
  bool _disposed = false;

  void synchronize() {
    final owner = currentIdentity()?.key;
    if (owner == _owner) return;
    final export = _exportLease;
    if (export != null) {
      if (owner != null && owner != export.owner) invalidateExports();
      export.signal();
    }
    _owner = owner;
    _epoch++;
    pages.clear();
    errors.clear();
    loading.clear();
    balances.clear();
    details.clear();
    _balanceReads.clear();
    _detailReads.clear();
    pending = null;
    actionError = null;
    actionBusy = false;
    confirmed = false;
    notApplied = false;
    exportSaved = false;
    _emit();
  }

  /// A system save chooser may mask the app temporarily. Explicit account,
  /// workspace, manual-lock and logout changes revoke its independent lease.
  void invalidateExports() {
    final export = _exportLease;
    if (export != null) {
      export.revoked = true;
      export.signal();
    }
    _exportReturnOwner = null;
  }

  bool consumeDocumentReturn() {
    if (_exportReturnOwner == null ||
        _exportReturnOwner != currentIdentity()?.key) {
      return false;
    }
    _exportReturnOwner = null;
    return true;
  }

  bool _exportValid(_DocumentExportLease lease) {
    final now = _now().toUtc();
    return !_disposed &&
        identical(_exportLease, lease) &&
        !lease.revoked &&
        !now.isBefore(lease.startedAt) &&
        now.difference(lease.startedAt) < exportReturnTimeout;
  }

  Future<EmployeeIdentity?> _exportIdentity(_DocumentExportLease lease) async {
    try {
      return await (() async {
        while (_exportValid(lease)) {
          synchronize();
          final identity = currentIdentity();
          if (identity != null) {
            return identity.key == lease.owner ? identity : null;
          }
          final changed = lease.changed.future;
          if (!_exportValid(lease)) return null;
          await changed;
        }
        return null;
      })().timeout(exportReturnTimeout);
    } on TimeoutException {
      return null;
    }
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  bool _valid(EmployeeIdentity identity, int epoch) =>
      !_disposed && epoch == _epoch && currentIdentity()?.key == identity.key;
  EmployeeIdentity? _identity() {
    synchronize();
    return currentIdentity();
  }

  EmployeeSelfServiceGateway get _gateway =>
      gateway ??
      (throw const EmployeeFailure(
        'FEATURE_NOT_INSTALLED',
        'This employee service is unavailable in the connected environment.',
      ));
  String _pendingKey(EmployeeIdentity identity) =>
      'jentra.employee.self.pending.v1.${identity.key}';

  Future<T> _storage<T>(Future<T> Function() work) {
    final result = _storageTail.then((_) => work());
    _storageTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<Set<String>> _pendingOwners() async {
    final wire = await store.read(_indexKey);
    if (wire == null) return <String>{};
    if (wire.length > 24000) {
      throw const FormatException('Invalid recovery index.');
    }
    final value = jsonDecode(wire);
    if (value is! List ||
        value.length > 100 ||
        value.any(
          (owner) =>
              owner is! String ||
              owner.split('/').length != 5 ||
              owner.split('/').any((part) {
                try {
                  selfUuid(part);
                  return false;
                } on FormatException {
                  return true;
                }
              }),
        )) {
      throw const FormatException('Invalid recovery index.');
    }
    return value.cast<String>().toSet();
  }

  Future<void> _writeOwners(Set<String> owners) async {
    if (owners.length > 100) {
      throw const EmployeeFailure(
        'STORAGE_UNAVAILABLE',
        'Saved request recovery needs support.',
      );
    }
    final wire = jsonEncode(owners.toList()..sort());
    await store.write(_indexKey, wire);
    if (await store.read(_indexKey) != wire) {
      throw const EmployeeFailure(
        'STORAGE_UNAVAILABLE',
        'Saved request recovery could not be verified.',
      );
    }
  }

  Future<void> _persist(EmployeeSelfPending saved) async {
    if (!saved.receiptOnly && _expired(saved)) saved = saved.redacted();
    final owners = (await _pendingOwners())..add(saved.owner);
    // Index first: a crash cannot leave an undiscoverable sensitive body.
    await _writeOwners(owners);
    final key = 'jentra.employee.self.pending.v1.${saved.owner}';
    final wire = jsonEncode(saved.toJson());
    await store.write(key, wire);
    if (await store.read(key) != wire) {
      throw const EmployeeFailure(
        'STORAGE_UNAVAILABLE',
        'Saved request recovery could not be verified.',
      );
    }
    _retentionTimers.remove(saved.owner)?.cancel();
    if (!saved.receiptOnly) {
      final remaining = saved.createdAt
          .add(const Duration(hours: 23))
          .difference(_now().toUtc());
      _retentionTimers[saved.owner] = Timer(
        remaining.isNegative ? Duration.zero : remaining,
        () {
          unawaited(
            _storage(() => _redactOwners(expiredOnly: true))
                .then((_) {
                  if (!_disposed && currentIdentity()?.key == saved.owner) {
                    unawaited(restorePending());
                  }
                })
                .catchError((Object _) {
                  if (!_disposed && currentIdentity()?.key == saved.owner) {
                    actionError = const EmployeeFailure(
                      'STORAGE_UNAVAILABLE',
                      'Saved request privacy could not be confirmed.',
                    );
                    _emit();
                  }
                }),
          );
        },
      );
    }
  }

  bool _expired(EmployeeSelfPending saved) {
    final now = _now().toUtc();
    return now.isBefore(saved.createdAt) ||
        now.difference(saved.createdAt) >= const Duration(hours: 23);
  }

  Future<void> _redactOwners({required bool expiredOnly}) async {
    for (final owner in await _pendingOwners()) {
      final wire = await store.read('jentra.employee.self.pending.v1.$owner');
      if (wire == null) continue;
      final saved = EmployeeSelfPending.forOwner(wire, owner);
      if (!saved.receiptOnly && (!expiredOnly || _expired(saved))) {
        await _persist(saved.redacted());
      }
    }
  }

  /// Clears sensitive request bodies across all local workspaces/accounts,
  /// retaining only opaque IDs needed to reconcile their uncertain outcomes.
  Future<void> protectPendingForIdentityChange() =>
      _storage(() => _redactOwners(expiredOnly: false));

  Future<EmployeeSelfPending?> _readPending(EmployeeIdentity identity) =>
      _storage(() async {
        await _redactOwners(expiredOnly: true);
        final wire = await store.read(_pendingKey(identity));
        if (wire == null) return null;
        var saved = EmployeeSelfPending.parse(wire, identity);
        if (!saved.receiptOnly && _expired(saved)) saved = saved.redacted();
        // Also adopts any pre-index development record and restores its timer.
        await _persist(saved);
        return saved;
      });

  Future<void> _removePending(EmployeeIdentity identity) => _storage(() async {
    await store.delete(_pendingKey(identity));
    if (await store.read(_pendingKey(identity)) != null) {
      throw const EmployeeFailure(
        'STORAGE_UNAVAILABLE',
        'Saved request recovery could not be cleared.',
      );
    }
    final owners = (await _pendingOwners())..remove(identity.key);
    await _writeOwners(owners);
    _retentionTimers.remove(identity.key)?.cancel();
  });

  Future<void> load(EmployeeService service, {bool more = false}) async {
    final identity = _identity();
    if (identity == null) return;
    if (loading.contains(service)) return;
    final epoch = _epoch;
    final after = more ? pages[service]?.nextCursor : null;
    if (more && after == null) return;
    loading.add(service);
    errors.remove(service);
    _emit();
    try {
      final page = await _gateway.page(identity, service, after: after);
      if (!_valid(identity, epoch)) return;
      final merged = after == null
          ? page.items
          : [...?pages[service]?.items, ...page.items];
      if (merged.map((row) => row.id).toSet().length != merged.length ||
          after != null && page.nextCursor == after) {
        throw const FormatException('Inconsistent employee page.');
      }
      pages[service] = EmployeeServicePage(
        List.unmodifiable(merged),
        page.nextCursor,
      );
    } on Object catch (error) {
      if (_valid(identity, epoch)) {
        errors[service] = employeeFailure(error);
        if (!more) pages.remove(service);
      }
    } finally {
      if (_valid(identity, epoch)) {
        loading.remove(service);
        _emit();
      }
    }
  }

  Future<EmployeeLeaveBalance?> loadBalance(
    String policyId,
    String asOf,
  ) async {
    final identity = _identity();
    if (identity == null) return null;
    final epoch = _epoch;
    final read = ++_readSequence;
    _balanceReads[policyId] = read;
    try {
      final result = await _gateway.balance(identity, policyId, asOf);
      if (!_valid(identity, epoch) || _balanceReads[policyId] != read) {
        return null;
      }
      balances[policyId] = result;
      actionError = null;
      _emit();
      return result;
    } on Object catch (error) {
      if (_valid(identity, epoch) && _balanceReads[policyId] == read) {
        actionError = employeeFailure(error);
        _emit();
      }
      return null;
    }
  }

  Future<EmployeeServiceRecord?> loadDetail(
    EmployeeService service,
    String id,
  ) async {
    final identity = _identity();
    if (identity == null) return null;
    final epoch = _epoch;
    final key = _detailKey(service, id);
    final read = ++_readSequence;
    _detailReads[key] = read;
    details.remove(key);
    actionError = null;
    _emit();
    try {
      final result = await _gateway.detail(identity, service, id);
      if (!_valid(identity, epoch) || _detailReads[key] != read) return null;
      validateEmployeeServiceRecord(result, service, identity, detail: true);
      details[key] = result;
      _emit();
      return result;
    } on Object catch (error) {
      if (_valid(identity, epoch) && _detailReads[key] == read) {
        actionError = employeeFailure(error);
        _emit();
      }
      return null;
    }
  }

  Future<void> restorePending() async {
    final identity = _identity();
    if (identity == null) return;
    final epoch = _epoch;
    try {
      final saved = await _readPending(identity);
      if (!_valid(identity, epoch)) return;
      pending = saved;
      _emit();
    } on Object {
      if (_valid(identity, epoch)) {
        actionError = const EmployeeFailure(
          'STORAGE_UNAVAILABLE',
          'Saved request recovery is unavailable.',
        );
        _emit();
      }
    }
  }

  Future<bool> submit(String rpc, Map<String, Object?> parameters) async {
    final identity = _identity();
    if (identity == null || actionBusy) return false;
    final epoch = _epoch;
    actionBusy = true;
    actionError = null;
    confirmed = false;
    notApplied = false;
    _emit();
    try {
      if (parameters.containsKey('p_command_id')) {
        throw const FormatException(
          'Command identity is generated by the app.',
        );
      }
      final existing = await _readPending(identity);
      if (!_valid(identity, epoch)) return false;
      if (existing != null) {
        pending = existing;
        throw const EmployeeFailure(
          'PENDING_REQUEST',
          'Check the earlier saved request before creating another.',
        );
      }
      final sealed = EmployeeSelfPending(
        owner: identity.key,
        rpc: rpc,
        parameters: Map.unmodifiable({
          'p_command_id': const Uuid().v4(),
          ...parameters,
        }),
        createdAt: _now().toUtc(),
      );
      final checked = EmployeeSelfPending.parse(
        jsonEncode(sealed.toJson()),
        identity,
      );
      await _storage(() async {
        if (!_valid(identity, epoch)) return;
        await _persist(checked);
      });
      if (!_valid(identity, epoch)) return false;
      pending = checked;
      return await _dispatch(identity, epoch, checked, freshAttempt: true);
    } on Object catch (error) {
      if (_valid(identity, epoch)) actionError = employeeFailure(error);
      return false;
    } finally {
      if (_valid(identity, epoch)) {
        actionBusy = false;
        _emit();
      }
    }
  }

  Future<bool> reconcile() async {
    final identity = _identity();
    if (identity == null || actionBusy) return false;
    final epoch = _epoch;
    actionBusy = true;
    actionError = null;
    confirmed = false;
    notApplied = false;
    _emit();
    try {
      final saved = await _readPending(identity);
      if (!_valid(identity, epoch)) return false;
      if (saved == null) {
        pending = null;
        return false;
      }
      pending = saved;
      if (saved.receiptOnly) {
        final receipt = await _gateway.receipt(
          identity,
          saved.rpc,
          saved.commandId,
          saved.requestId,
          stillAuthorized: () => _valid(identity, epoch),
        );
        if (!_valid(identity, epoch)) return false;
        if (receipt.receipt == null && !receipt.abandoned) {
          throw const EmployeeFailure(
            'PENDING_EXPIRED',
            'The saved request needs support reconciliation. Do not submit a replacement.',
          );
        }
        await _removePending(identity);
        if (!_valid(identity, epoch)) return false;
        pending = null;
        confirmed = receipt.receipt != null;
        notApplied = receipt.abandoned;
        return confirmed;
      }
      return await _dispatch(identity, epoch, saved);
    } on Object catch (error) {
      if (_valid(identity, epoch)) actionError = employeeFailure(error);
      return false;
    } finally {
      if (_valid(identity, epoch)) {
        actionBusy = false;
        _emit();
      }
    }
  }

  Future<bool> _dispatch(
    EmployeeIdentity identity,
    int epoch,
    EmployeeSelfPending saved, {
    bool freshAttempt = false,
  }) async {
    final now = _now().toUtc();
    if (now.isBefore(saved.createdAt) ||
        now.difference(saved.createdAt) >= const Duration(hours: 23)) {
      throw const EmployeeFailure(
        'PENDING_EXPIRED',
        'The saved request needs support reconciliation. Do not submit a replacement.',
      );
    }
    try {
      final receipt = await _gateway.command(
        identity,
        saved.rpc,
        saved.parameters,
        stillAuthorized: () => _valid(identity, epoch),
      );
      validateEmployeeCommandReceipt(
        receipt,
        identity,
        saved.rpc,
        saved.parameters,
      );
    } on EmployeeFailure catch (error) {
      // A transactional rejection confirms no command took effect. Transport,
      // receipt mismatch and unknown failures always retain the original IDs.
      // A rejection on reconciliation does not establish the outcome of the
      // original uncertain attempt (the endpoint may have been changed/removed).
      if (freshAttempt &&
          {
            'VERSION_CONFLICT',
            'VALIDATION_ERROR',
            'FEATURE_NOT_INSTALLED',
          }.contains(error.code) &&
          _valid(identity, epoch)) {
        await _removePending(identity);
        if (_valid(identity, epoch)) pending = null;
      }
      rethrow;
    }
    if (!_valid(identity, epoch)) return false;
    await _removePending(identity);
    if (!_valid(identity, epoch)) return false;
    pending = null;
    confirmed = true;
    return true;
  }

  Future<void> markRead(EmployeeServiceRecord notice) async {
    final identity = _identity();
    if (identity == null) return;
    final epoch = _epoch;
    if (actionBusy) return;
    actionBusy = true;
    actionError = null;
    _emit();
    try {
      await _gateway.markNoticeRead(
        identity,
        notice,
        const Uuid().v4(),
        stillAuthorized: () => _valid(identity, epoch),
      );
      if (_valid(identity, epoch)) await load(EmployeeService.inbox);
    } on Object catch (error) {
      if (_valid(identity, epoch)) actionError = employeeFailure(error);
    } finally {
      if (_valid(identity, epoch)) {
        actionBusy = false;
        _emit();
      }
    }
  }

  Future<EmployeePrivateDocument?> download(
    EmployeeServiceRecord document,
  ) async {
    final identity = _identity();
    if (identity == null) return null;
    final epoch = _epoch;
    if (actionBusy) return null;
    actionBusy = true;
    actionError = null;
    _emit();
    try {
      final data = await _gateway.document(identity, document);
      return _valid(identity, epoch) ? data : null;
    } on Object catch (error) {
      if (_valid(identity, epoch)) actionError = employeeFailure(error);
      return null;
    } finally {
      if (_valid(identity, epoch)) {
        actionBusy = false;
        _emit();
      }
    }
  }

  Future<bool> saveDocument(EmployeeServiceRecord document) async {
    final identity = _identity();
    if (identity == null) return false;
    final epoch = _epoch;
    if (_exportLease != null) return false;
    final exporter = documentExporter;
    if (exporter == null || !exporter.supported) {
      actionError = const EmployeeFailure(
        'DOCUMENT_EXPORT_UNAVAILABLE',
        'Private document saving is unavailable on this device.',
      );
      _emit();
      return false;
    }
    final data = await download(document);
    if (data == null || !_valid(identity, epoch)) return false;
    final lease = _DocumentExportLease(identity.key, _now().toUtc());
    _exportLease = lease;
    _exportReturnOwner = identity.key;
    exportSaved = false;
    _emit();
    try {
      final saved = await exporter.save(
        bytes: data.bytes,
        mimeType: data.mime,
        stillAuthorized: () =>
            _exportValid(lease) && currentIdentity()?.key == lease.owner,
        reauthorize: () async {
          final returnedIdentity = await _exportIdentity(lease);
          if (returnedIdentity == null || !_exportValid(lease)) return false;
          // Fresh server-derived subject and publication checks after the chooser.
          // Walk pages rather than trusting a previously cached visible row.
          String? after;
          final seen = <String>{};
          do {
            final page = await _gateway.page(
              returnedIdentity,
              EmployeeService.documents,
              after: after,
            );
            if (!_exportValid(lease) || currentIdentity()?.key != lease.owner) {
              return false;
            }
            for (final row in page.items) {
              if (row.id == document.id) {
                return row.version == document.version &&
                    row.values['publication_version'] ==
                        document.values['publication_version'] &&
                    row.values['checksum'] == document.values['checksum'] &&
                    row.values['byte_size'] == data.bytes.length &&
                    row.values['mime'] == data.mime;
              }
            }
            after = page.nextCursor;
            if (after != null && !seen.add(after)) return false;
          } while (after != null && seen.length < 100);
          return false;
        },
      );
      if (_exportValid(lease) && currentIdentity()?.key == lease.owner) {
        exportSaved = saved;
      }
      return saved;
    } on Object catch (error) {
      if (_exportValid(lease) && currentIdentity()?.key == lease.owner) {
        actionError = employeeFailure(error);
      }
      return false;
    } finally {
      lease.revoked = true;
      lease.signal();
      if (identical(_exportLease, lease)) _exportLease = null;
      _exportReturnOwner = null;
      _emit();
    }
  }

  @override
  void dispose() {
    invalidateExports();
    _disposed = true;
    _epoch++;
    for (final timer in _retentionTimers.values) {
      timer.cancel();
    }
    _retentionTimers.clear();
    pages.clear();
    balances.clear();
    details.clear();
    pending = null;
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_platform/count_partitions.dart';
import 'package:jentra_domain/count_partitions.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import '../operations/operational_read_access.dart';
import '../operations/inventory_recovery_inputs.dart';

final stockCountGatewayProvider = Provider<StockCountGateway?>((ref) => null);
final countPartitionGatewayProvider = Provider<CountPartitionGateway?>(
  (ref) => null,
);
final stockCountControllerProvider =
    Provider.autoDispose<StockCountController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider),
          gateway = ref.watch(stockCountGatewayProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      final permissions = caps.value ?? <String>{};
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          caps.isLoading ||
          caps.hasError ||
          !permissions.contains('inventory.cost.view') ||
          ![
            'inventory.adjustments.post',
            'workflow.approvals.decide',
          ].any(permissions.contains)) {
        return null;
      }
      final c = StockCountController(
        scope: scope,
        gateway: gateway,
        partitionGateway: ref.watch(countPartitionGatewayProvider),
        drafts: QuotationDraftStore(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
        permissions: permissions,
      );
      ref.listen(
        connectivityStateProvider,
        (_, s) => c.setOnline(s.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

final class StockCountController extends ChangeNotifier
    implements OperationalReadAccess {
  StockCountController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.online,
    required this.permissions,
    this.partitionGateway,
  });
  final TenantContext scope;
  final StockCountGateway gateway;
  final CountPartitionGateway? partitionGateway;
  final QuotationDraftStore drafts;
  final Set<String> permissions;
  static const slot = 'stock-count-editor';
  bool online, busy = false, _disposed = false, accessDenied = false;
  int _epoch = 0;
  @override
  int get readAccessEpoch => _epoch;
  @override
  bool currentRead(int value) =>
      !_disposed && online && !accessDenied && value == _epoch;
  @override
  void denyReadAccess() {
    if (_disposed) return;
    accessDenied = true;
    _epoch++;
    items = [];
    cursor = null;
    partitionProgress = null;
    clearValueEvidence();
    emit();
  }

  String? error, message, cursor;
  Map<String, Object?>? form;
  QuotationLocalDraft? local;
  QuotationLocalDraft? partitionLocal;
  CountPartitionProgress? partitionProgress;
  CountPartitionCaptureService? get partitionService => partitionGateway == null
      ? null
      : CountPartitionCaptureService(
          scope: scope,
          gateway: partitionGateway!,
          drafts: drafts,
        );
  bool get partitionPending => partitionLocal?.pending != null;
  List<Map<String, Object?>> items = [];
  bool get locked =>
      busy ||
      _disposed ||
      accessDenied ||
      local?.pending != null ||
      partitionPending;
  bool get canManage => permissions.contains('inventory.adjustments.post');
  bool get editable => !locked && canManage && (form?['status'] == 'draft');
  bool get canReloadEvidence =>
      !locked && online && form?['version'] != null && form?['_dirty'] != true;
  void clearValueEvidence() {
    if (form != null) form = inventoryRecoveryInputs(form!);
  }

  void emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    items = [];
    partitionProgress = null;
    form = null;
    notifyListeners();
    super.dispose();
  }

  void setOnline(bool value) {
    if (online != value) {
      online = value;
      _epoch++;
      partitionProgress = null;
      items = [];
      cursor = null;
      clearValueEvidence();
    }
    emit();
  }

  Future<void> run(Future<void> Function() work) async {
    if (busy || _disposed) return;
    final access = _epoch;
    busy = true;
    error = null;
    emit();
    try {
      await work();
    } catch (e) {
      if (_disposed || access != _epoch) return;
      if (e is DomainError &&
          const {
            'PERMISSION_DENIED',
            'ACCESS_DENIED',
            'MFA_REQUIRED',
            'AUTHENTICATION_REQUIRED',
          }.contains(e.code)) {
        accessDenied = true;
        _epoch++;
        items = [];
        partitionProgress = null;
        cursor = null;
        clearValueEvidence();
      }
      error = e is DomainError
          ? e.message
          : e is FormatException
          ? e.message
          : 'Unable to complete this action. Saved work is retained.';
    } finally {
      busy = false;
      emit();
    }
  }

  Future<void> initialize() => run(() async {
    local = await drafts.load(scope, slot);
    if (_disposed) return;
    form = local == null ? null : inventoryRecoveryInputs(local!.form);
    partitionLocal = await partitionService?.restore();
    if (_disposed) return;
    if (online && partitionLocal?.form['confirmed_group_id'] is String) {
      final epoch = _epoch;
      final progress = await partitionGateway!.page(
        scope,
        partitionLocal!.form['confirmed_group_id'] as String,
      );
      if (!_disposed && online && epoch == _epoch) partitionProgress = progress;
      if (_disposed) return;
    }
    if (online) await _refresh();
  });
  Future<void> capturePartitions() => run(() async {
    if (!online ||
        accessDenied ||
        !canManage ||
        partitionService == null ||
        local?.pending != null) {
      return;
    }
    final service = partitionService!;
    final epoch = _epoch;
    if (partitionLocal?.form['confirmed_group_id'] is String) {
      throw const FormatException(
        'Capture is already confirmed. Refresh group progress to reopen its counts.',
      );
    }
    if (!partitionPending) {
      if (form == null ||
          form!['version'] != null ||
          (form!['lines'] as List).length != 1) {
        throw const FormatException(
          'Choose one tracked product for a shared cutoff capture.',
        );
      }
      await _save();
      await service.saveDraft({
        'id': form!['id'],
        'warehouse_id': form!['warehouse_id'],
        'product_id': (form!['lines'] as List).single['product_id'],
        'offset_account_id': form!['offset_account_id'],
        'document_date': form!['document_date'],
        'reason': form!['reason'],
      });
    }
    partitionLocal = await service.restore();
    emit();
    try {
      final captured = await service.capture();
      if (_disposed) return;
      partitionLocal = await service.restore();
      await drafts.discard(scope, slot);
      form = null;
      local = null;
      message = 'Captured independent count documents at one cutoff. Open each partition to count and approve it.';
      final progress = online && epoch == _epoch
          ? await partitionGateway!.page(scope, captured.id)
          : null;
      if (_disposed) return;
      if (online && epoch == _epoch) partitionProgress = progress;
      if (online && epoch == _epoch) await _refresh();
    } finally {
      partitionLocal = await service.restore();
    }
  });
  Future<void> refreshPartitions() => run(() async {
    if (!online ||
        accessDenied ||
        partitionGateway == null ||
        partitionLocal?.form['confirmed_group_id'] is! String) {
      return;
    }
    final epoch = _epoch;
    final progress = await partitionGateway!.page(
      scope,
      partitionLocal!.form['confirmed_group_id'] as String,
    );
    if (!_disposed && online && epoch == _epoch) partitionProgress = progress;
  });
  Future<void> closePartitions() => run(() async {
    if (partitionPending) return;
    await partitionService?.discardDraft();
    partitionLocal = null;
    partitionProgress = null;
  });
  Future<void> _refresh({bool more = false}) async {
    final epoch = _epoch;
    final r = await gateway.page(scope, after: more ? cursor : null);
    if (_disposed || !online || epoch != _epoch) return;
    items = [
      if (more) ...items,
      for (final x in r['items'] as List) (x as Map).cast<String, Object?>(),
    ];
    cursor = r['next_cursor'] as String?;
    accessDenied = false;
  }

  Future<void> refresh({bool more = false}) => run(() async {
    if (online) await _refresh(more: more);
  });
  Future<void> reloadEvidence() => run(() async {
    // run sets busy before invoking work; check the remaining locks here.
    if (!currentRead(_epoch) ||
        local?.pending != null ||
        partitionPending ||
        form?['version'] == null ||
        form?['_dirty'] == true) {
      return;
    }
    final epoch = _epoch;
    final original = form!;
    final detail = await gateway.detail(scope, original['id'] as String);
    if (!currentRead(epoch) ||
        !identical(form, original) ||
        local?.pending != null) {
      return;
    }
    form = {...detail};
    await _save();
  });
  Future<void> create() => run(() async {
    if (!canManage || accessDenied || form != null || partitionPending) return;
    form = {
      'id': const Uuid().v4(),
      'document_date': DateTime.now().toUtc().toIso8601String().substring(
        0,
        10,
      ),
      'status': 'draft',
      'reason': '',
      'lines': <Map<String, Object?>>[],
    };
    await _save();
  });
  Future<void> open(Map<String, Object?> row) => run(() async {
    if (form != null || accessDenied) return;
    if (row['lines'] is! List && !online) {
      throw const FormatException(
        'Connect to load the selected count. Local drafts remain available offline.',
      );
    }
    final epoch = _epoch;
    final detail = row['lines'] is List
        ? row
        : await gateway.detail(scope, row['id'] as String);
    if (_disposed || !online || epoch != _epoch) return;
    form = {...detail};
    await _save();
  });
  Future<void> correct() => run(() async {
    final original = form;
    if (!canManage ||
        accessDenied ||
        !online ||
        original?['status'] != 'posted' ||
        local?.pending != null) {
      return;
    }
    await drafts.discard(scope, slot);
    form = {
      'id': const Uuid().v4(),
      'corrects_count_id': original!['id'],
      'warehouse_id': original['warehouse_id'],
      'warehouse_name': original['warehouse_name'],
      'offset_account_id': original['offset_account_id'],
      'offset_account_name': original['offset_account_name'],
      'document_date': DateTime.now().toUtc().toIso8601String().substring(
        0,
        10,
      ),
      'status': 'draft',
      'reason': '',
      'lines': [
        for (final raw in original['lines'] as List)
          {
            'line_id': const Uuid().v4(),
            'product_id': (raw as Map)['product_id'],
            'product_name': raw['product_name'],
            'counted_quantity': raw['counted_quantity'],
            'empty_unit_cost': raw['empty_unit_cost'],
          },
      ],
    };
    local = null;
    await _save();
  });
  Future<void> _save() async {
    if (_disposed || form == null) return;
    await drafts.save(
      scope,
      slot,
      inventoryRecoveryInputs(form!),
      expectedVersion: form!['version'] as int?,
    );
    local = await drafts.load(scope, slot);
  }

  Future<void> saveLocal() => run(_save);
  Future<bool> canLeave() async {
    if (busy) return false;
    if (form == null || local?.pending != null) return true;
    var ok = false;
    await run(() async {
      await _save();
      ok = true;
    });
    return ok;
  }

  void update(String key, Object? value) {
    if (!editable) return;
    form = {...form!, key: value, '_dirty': true};
    emit();
  }

  void updateLine(int i, String key, Object? value) {
    if (!editable || form?['version'] == null) return;
    final lines = [...form!['lines'] as List];
    lines[i] = {...lines[i] as Map, key: value};
    update('lines', lines);
  }

  void addProduct(Map<String, Object?> p) {
    if (!editable || form?['version'] != null) return;
    if ((form!['lines'] as List).any(
      (l) => (l as Map)['product_id'] == p['id'],
    )) {
      return;
    }
    update('lines', [
      ...form!['lines'] as List,
      {
        'line_id': const Uuid().v4(),
        'product_id': p['id'],
        'product_name': p['name'],
        'counted_quantity': p['on_hand_quantity'],
        'empty_unit_cost': '0',
      },
    ]);
  }

  void updateIdentity(int lineIndex, int identityIndex, String value) {
    if (!editable || form?['version'] == null) return;
    final lines = [...form!['lines'] as List];
    final line = {...lines[lineIndex] as Map};
    final identities = [...line['identities'] as List];
    identities[identityIndex] = {
      ...identities[identityIndex] as Map,
      'counted_quantity': value,
    };
    line['identities'] = identities;
    try {
      line['counted_quantity'] = stockCountIdentityTotal(
        identities.cast<Map>(),
        serial: line['tracking_mode'] == 'serial',
      );
    } on FormatException {
      line['counted_quantity'] = '';
    }
    lines[lineIndex] = line;
    update('lines', lines);
  }

  Future<void> close() => run(() async {
    if (local?.pending != null) {
      throw const FormatException('Resolve the pending command first.');
    }
    await drafts.discard(scope, slot);
    form = null;
    local = null;
  });
  Future<void> act(String verb, {String note = ''}) => run(() async {
    if (!currentRead(_epoch) || form == null) return;
    final epoch = _epoch;
    var pending = local?.pending;
    if (pending == null) {
      final f = form!;
      if (verb != 'save' && (f['_dirty'] == true || f['version'] == null)) {
        throw const FormatException(
          'Save the count changes before submitting another action.',
        );
      }
      if (verb == 'save') {
        if (!canManage || f['status'] != 'draft') return;
        final date = f['document_date'] as String? ?? '';
        final parsed = DateTime.tryParse(date);
        if (parsed == null ||
            parsed.toIso8601String().substring(0, 10) != date) {
          throw const FormatException('Enter a valid YYYY-MM-DD date.');
        }
        if ((f['reason'] as String? ?? '').trim().length < 3 ||
            f['warehouse_id'] == null ||
            f['offset_account_id'] == null ||
            (f['lines'] as List).isEmpty) {
          throw const FormatException(
            'Select warehouse, variance account and products; enter a reason.',
          );
        }
        for (final raw in f['lines'] as List) {
          final l = raw as Map;
          if (l['identities'] is List) {
            stockCountIdentityTotal(
              (l['identities'] as List).cast<Map>(),
              serial: l['tracking_mode'] == 'serial',
            );
          }
          for (final key in ['counted_quantity', 'empty_unit_cost']) {
            final value = l[key];
            if (value is! String ||
                !RegExp(r'^\d{1,14}(\.\d{1,6})?$').hasMatch(value)) {
              throw const FormatException(
                'Use nonnegative decimal strings with at most six decimal places.',
              );
            }
          }
        }
      } else if (verb == 'approve' || verb == 'reject') {
        if (!permissions.contains('workflow.approvals.decide')) return;
      } else if (!canManage) {
        return;
      }
      if (['recall', 'cancel', 'reject'].contains(verb) &&
          note.trim().isEmpty) {
        throw const FormatException('Enter a reason for this action.');
      }
      final payload = verb == 'save'
          ? <String, Object?>{
              for (final key in [
                'id',
                'document_date',
                'reason',
                'warehouse_id',
                'offset_account_id',
                'corrects_count_id',
              ])
                key: f[key],
              'capture_only': f['version'] == null,
              'lines': [
                for (final raw in f['lines'] as List)
                  {
                    for (final key in [
                      'line_id',
                      'product_id',
                      'counted_quantity',
                      'empty_unit_cost',
                    ])
                      key: (raw as Map)[key],
                    if ((raw as Map)['identities'] is List)
                      'identities': [
                        for (final identity in raw['identities'] as List)
                          {
                            'id': (identity as Map)['id'],
                            'counted_quantity': identity['counted_quantity'],
                          },
                      ],
                  },
              ],
            }
          : <String, Object?>{
              'document_id': f['id'],
              if (verb == 'approve' || verb == 'reject')
                'decision': verb == 'approve' ? 'approved' : 'rejected'
              else if (verb != 'post')
                'action': verb,
              'reason': note,
              'note': note,
            };
      await _save();
      pending = await drafts.prepare(
        scope,
        slot,
        verb: verb == 'post' ? 'accept' : verb,
        payload: payload,
        expectedVersion: f['version'] as int?,
      );
      local = await drafts.load(scope, slot);
    }
    if (!currentRead(epoch)) return;
    Map<String, Object?> result;
    try {
      result = await gateway.execute(
        pending.verb == 'accept' ? 'post' : pending.verb,
        pending.envelope,
      );
      await drafts.confirm(
        scope,
        slot,
        pending.envelope.commandId,
        form: inventoryRecoveryInputs(result),
        expectedVersion: result['version'] as int?,
      );
    } on DomainError catch (e) {
      await drafts.recordFailure(
        scope,
        slot,
        e,
        commandId: pending.envelope.commandId,
      );
      local = await drafts.load(scope, slot);
      rethrow;
    }
    if (_disposed) return;
    local = null;
    message = 'Count action confirmed.';
    if (!online || epoch != _epoch) {
      form = null;
      return;
    }
    form = result;
    // The server receipt is authoritative even if local persistence or refresh fails.
    try {
      await _save();
      await _refresh();
    } catch (_) {
      error = 'Action confirmed. Retry local save or refresh before leaving.';
    }
  });
}

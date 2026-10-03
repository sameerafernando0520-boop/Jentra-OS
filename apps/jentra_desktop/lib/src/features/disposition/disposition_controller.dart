import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_platform/disposition.dart';
import 'package:jentra_domain/disposition.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import '../operations/operational_read_access.dart';
import '../operations/inventory_recovery_inputs.dart';

final dispositionGatewayProvider = Provider<DispositionGateway?>((ref) => null);
final dispositionControllerProvider =
    Provider.autoDispose<DispositionController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider),
          gateway = ref.watch(dispositionGatewayProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      final permissions = caps.value ?? <String>{};
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          caps.isLoading ||
          caps.hasError ||
          !permissions.contains('inventory.cost.view') ||
          ![
            'inventory.dispositions.post',
            'workflow.approvals.decide',
          ].any(permissions.contains)) {
        return null;
      }
      final connection = ref.read(connectivityStateProvider);
      final c = DispositionController(
        scope: scope,
        gateway: gateway,
        drafts: QuotationDraftStore(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        online:
            !connection.isLoading &&
            !connection.hasError &&
            connection.value == ConnectivityState.online,
        permissions: permissions,
      );
      ref.listen(
        connectivityStateProvider,
        (_, s) => c.setOnline(
          !s.isLoading && !s.hasError && s.value == ConnectivityState.online,
        ),
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

final class DispositionController extends ChangeNotifier
    implements OperationalReadAccess {
  DispositionController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.online,
    required this.permissions,
  });
  final TenantContext scope;
  final DispositionGateway gateway;
  final QuotationDraftStore drafts;
  final Set<String> permissions;
  static const slot = 'stock-disposition-editor';
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
    clearValueEvidence();
    emit();
  }

  String? error, message, cursor;
  Map<String, Object?>? form;
  QuotationLocalDraft? local;
  List<Map<String, Object?>> items = [];
  bool get locked =>
      busy || _disposed || accessDenied || local?.pending != null;
  bool get canManage => permissions.contains('inventory.dispositions.post');
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
    form = null;
    notifyListeners();
    super.dispose();
  }

  void setOnline(bool value) {
    if (online != value) {
      online = value;
      _epoch++;
      items = [];
      cursor = null;
      if (form?['status'] == 'posted') form = null;
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
    if (!online && form?['status'] == 'posted') form = null;
    if (online) await _refresh();
  });
  Future<void> _refresh({bool more = false}) async {
    final epoch = _epoch;
    final r = await gateway.page(scope, after: more ? cursor : null);
    if (!isCurrent(epoch)) return;
    items = [
      if (more) ...items,
      for (final x in r['items'] as List) (x as Map).cast<String, Object?>(),
    ];
    cursor = r['next_cursor'] as String?;
    accessDenied = false;
  }

  int get accessEpoch => _epoch;
  bool isCurrent(int epoch) => !_disposed && online && epoch == _epoch;
  void denyAccess() {
    accessDenied = true;
    _epoch++;
    items = [];
    cursor = null;
    clearValueEvidence();
    emit();
  }

  Future<void> refresh({bool more = false}) => run(() async {
    if (online) await _refresh(more: more);
  });
  Future<void> reloadEvidence() => run(() async {
    if (!currentRead(_epoch) ||
        local?.pending != null ||
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
    if (!canManage || accessDenied || form != null) return;
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
        'Connect to load the selected disposition. Local drafts remain available offline.',
      );
    }
    final epoch = _epoch;
    final detail = row['lines'] is List
        ? row
        : await gateway.detail(scope, row['id'] as String);
    if (!isCurrent(epoch)) return;
    form = {...detail};
    await _save();
  });
  Future<void> correct({bool reverse = false}) => run(() async {
    final original = form;
    if (!canManage ||
        accessDenied ||
        !online ||
        original?['status'] != 'posted' ||
        local?.pending != null) {
      return;
    }
    if (reverse &&
        (original!['lines'] as List).any(
          (row) => (row as Map)['tracking_mode'] == 'serial',
        )) {
      throw const FormatException(
        'Disposed serial identities cannot be restored.',
      );
    }
    await drafts.discard(scope, slot);
    form = {
      'id': const Uuid().v4(),
      if (reverse)
        'reverses_disposition_id': original!['id']
      else
        'corrects_disposition_id': original!['id'],
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
      'lines': <Map<String, Object?>>[],
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
    if (!editable || form?['reverses_disposition_id'] != null) return;
    final lines = [...form!['lines'] as List];
    lines[i] = {...lines[i] as Map, key: value};
    update('lines', lines);
  }

  void removeLine(int i) {
    if (!editable) return;
    update('lines', [...form!['lines'] as List]..removeAt(i));
  }

  void addProduct(Map<String, Object?> p) {
    if (!editable ||
        form?['reverses_disposition_id'] != null ||
        (form!['lines'] as List).length >= 100) {
      return;
    }
    update('lines', [
      ...form!['lines'] as List,
      {
        'line_id': const Uuid().v4(),
        'product_id': p['id'],
        'product_name': p['name'],
        'unit_id': p['base_unit_id'],
        'tracking_mode': p['tracking_mode'],
        'quantity': '1',
        'conversion_numerator': '1',
        'conversion_denominator': '1',
        'serial_ids': <String>[],
      },
    ]);
  }

  void setLot(int i, Map<String, Object?> lot) {
    if (!editable) return;
    final lines = [...form!['lines'] as List];
    lines[i] = {
      ...lines[i] as Map,
      'lot_id': lot['id'],
      'lot_code': lot['code'],
    };
    update('lines', lines);
  }

  void setSerials(int i, List<Map<String, Object?>> serials) {
    if (!editable) return;
    final lots = serials.map((s) => s['lot_id']).toSet();
    if (lots.length > 1) {
      error = 'Select serials from the same lot on one line.';
      emit();
      return;
    }
    final lines = [...form!['lines'] as List];
    lines[i] = {
      ...lines[i] as Map,
      'serial_ids': serials.map((s) => s['id']).toList(),
      'serial_codes': serials.map((s) => s['code']).toList(),
      'lot_id': lots.isEmpty ? null : lots.single,
      'quantity': serials.length.toString(),
    };
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
          'Save the disposition changes before submitting another action.',
        );
      }
      if (verb == 'save') {
        if (!canManage || f['status'] != 'draft') return;
        dispositionSavePayload(f);
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
          ? dispositionSavePayload(f)
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
    message = 'Disposition action confirmed.';
    if (!isCurrent(epoch)) {
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

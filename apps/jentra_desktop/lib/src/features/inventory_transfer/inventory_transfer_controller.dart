import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import '../operations/operational_read_access.dart';
import '../operations/inventory_recovery_inputs.dart';

final inventoryTransferGatewayProvider = Provider<InventoryTransferGateway?>(
  (ref) => null,
);
final inventoryTransferControllerProvider =
    Provider.autoDispose<InventoryTransferController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      final gateway = ref.watch(inventoryTransferGatewayProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          caps.isLoading ||
          caps.hasError ||
          !(caps.value?.contains('inventory.transfers.post') ?? false)) {
        return null;
      }
      final c = InventoryTransferController(
        scope: scope,
        gateway: gateway,
        drafts: QuotationDraftStore(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
      );
      ref.listen(
        connectivityStateProvider,
        (_, value) => c.setOnline(value.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

final class InventoryTransferController extends ChangeNotifier
    implements OperationalReadAccess {
  InventoryTransferController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.online,
  });
  final TenantContext scope;
  final InventoryTransferGateway gateway;
  // Reuses the existing encrypted envelope store in a unique slot. No shared store change.
  final QuotationDraftStore drafts;
  static const slot = 'inventory-transfer-editor';
  bool online, busy = false, _disposed = false, accessDenied = false;
  int _epoch = 0, _operationEpoch = 0;
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
    clearServer();
    emit();
  }

  bool get currentServer => !_disposed && online && _operationEpoch == _epoch;
  void clearServer() {
    items = [];
    holdings = [];
    cursor = null;
    holdingsCursor = null;
    loadedHoldingsDate = null;
    if (form != null) form = inventoryRecoveryInputs(form!);
  }

  String? error, message, cursor;
  Map<String, Object?>? form;
  QuotationLocalDraft? local;
  List<Map<String, Object?>> items = [];
  List<Map<String, Object?>> holdings = [];
  String holdingsDate = DateTime.now().toUtc().toIso8601String().substring(
    0,
    10,
  );
  String? holdingsCursor, loadedHoldingsDate;
  Future<void> loadHoldings({bool more = false}) => run(() async {
    if (!online) return;
    final date = more ? loadedHoldingsDate! : holdingsDate;
    final parsed = DateTime.tryParse(date);
    if (parsed == null || parsed.toIso8601String().substring(0, 10) != date) {
      throw const FormatException('Enter a valid YYYY-MM-DD report date.');
    }
    final result = await gateway.holdings(
      scope,
      date,
      after: more ? holdingsCursor : null,
    );
    if (!currentServer) return;
    holdings = [
      if (more) ...holdings,
      for (final raw in result['items'] as List)
        (raw as Map).cast<String, Object?>(),
    ];
    holdingsCursor = result['next_cursor'] as String?;
    loadedHoldingsDate = date;
  });
  bool get locked =>
      busy || _disposed || accessDenied || local?.pending != null;
  void emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    clearServer();
    form = null;
    notifyListeners();
    super.dispose();
  }

  void setOnline(bool value) {
    if (online != value) {
      online = value;
      _epoch++;
      clearServer();
    }
    emit();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    _operationEpoch = _epoch;
    emit();
    try {
      await action();
    } catch (e) {
      if (!_disposed &&
          _operationEpoch == _epoch &&
          e is DomainError &&
          const {
            'PERMISSION_DENIED',
            'ACCESS_DENIED',
            'MFA_REQUIRED',
            'AUTHENTICATION_REQUIRED',
          }.contains(e.code)) {
        accessDenied = true;
        _epoch++;
        clearServer();
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
    if (online) await _refresh();
  });
  Future<void> _refresh({bool more = false}) async {
    final result = await gateway.page(scope, after: more ? cursor : null);
    if (!currentServer) return;
    items = [
      if (more) ...items,
      for (final x in result['items'] as List)
        (x as Map).cast<String, Object?>(),
    ];
    cursor = result['next_cursor'] as String?;
    accessDenied = false;
  }

  Future<void> refresh({bool more = false}) => run(() async {
    if (online) await _refresh(more: more);
  });
  Future<void> create() => run(() async {
    if (form != null || local != null) return;
    form = {
      'id': const Uuid().v4(),
      'operation': 'dispatch',
      'document_date': DateTime.now().toUtc().toIso8601String().substring(
        0,
        10,
      ),
      'reason': '',
      'reference': '',
      'lines': <Map<String, Object?>>[],
    };
    await _save();
  });
  Future<void> prepare(Map<String, Object?> transfer, String operation) =>
      run(() async {
        if (form != null || !['receive', 'reverse'].contains(operation)) return;
        form = {
          ...inventoryRecoveryInputs(transfer),
          'operation': operation,
          'document_date': DateTime.now().toUtc().toIso8601String().substring(
            0,
            10,
          ),
          'reason': '',
        };
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

  Future<void> save() => run(_save);
  Future<bool> canLeave() async {
    if (busy) return false;
    if (form == null || local?.pending != null) return true;
    var saved = false;
    await run(() async {
      await _save();
      saved = true;
    });
    return saved;
  }

  void update(String key, Object? value) {
    if (locked || form == null) return;
    form = {...form!, key: value};
    emit();
  }

  void addProduct(Map<String, Object?> product) {
    if (locked || form == null) return;
    update('lines', [
      ...form!['lines'] as List,
      {
        'line_id': const Uuid().v4(),
        'product_id': product['id'],
        'product_name': product['name'],
        'tracking_mode': product['tracking_mode'],
        'unit_id': product['base_unit_id'],
        'units': product['units'],
        'quantity': '1',
        'conversion_numerator': '1',
        'conversion_denominator': '1',
        'serial_ids': <String>[],
      },
    ]);
  }

  void updateLine(int index, String key, Object? value) {
    if (locked || form == null) return;
    final lines = [...form!['lines'] as List];
    lines[index] = {...lines[index] as Map, key: value};
    update('lines', lines);
  }

  Future<void> discard() => run(() async {
    if (local?.pending != null) {
      throw const FormatException(
        'Resolve the pending command before discarding.',
      );
    }
    await drafts.discard(scope, slot);
    form = null;
    local = null;
  });
  Future<void> submit() => run(() async {
    if (!currentServer || accessDenied || form == null) return;
    var pending = local?.pending;
    if (pending == null) {
      final f = form!;
      final date = f['document_date'] as String? ?? '';
      final parsed = DateTime.tryParse(date);
      if (parsed == null || parsed.toIso8601String().substring(0, 10) != date) {
        throw const FormatException('Enter a valid YYYY-MM-DD posting date.');
      }
      for (final key in ['reason', 'reference']) {
        final value = (f[key] as String? ?? '').trim();
        if (value.isEmpty || value.length > (key == 'reason' ? 1000 : 140)) {
          throw const FormatException(
            'Enter a reason and reference within their limits.',
          );
        }
      }
      final dispatch = ['dispatch', 'immediate'].contains(f['operation']);
      final lines = <Map<String, Object?>>[];
      if (dispatch) {
        if (f['source_warehouse_id'] == null ||
            f['destination_warehouse_id'] == null ||
            f['source_warehouse_id'] == f['destination_warehouse_id']) {
          throw const FormatException(
            'Select different source and destination warehouses.',
          );
        }
        for (final raw in f['lines'] as List) {
          final line = raw as Map;
          final quantity = InventoryTransferQuantity(
            line['quantity'],
            line['conversion_numerator'],
            line['conversion_denominator'],
          );
          if (line['tracking_mode'] == 'serial') {
            final serials = (line['serial_ids'] as List).cast<String>();
            quantity.validateSerialCount(serials.toSet().length);
          }
          if (line['tracking_mode'] == 'lot' && line['lot_id'] == null) {
            throw const FormatException(
              'Select a lot for each lot-tracked line.',
            );
          }
          lines.add({
            for (final k in [
              'line_id',
              'product_id',
              'unit_id',
              'quantity',
              'conversion_numerator',
              'conversion_denominator',
              'lot_id',
              'serial_ids',
            ])
              k: line[k],
          });
        }
        if (lines.isEmpty || lines.length > 500) {
          throw const FormatException('Add 1 to 500 transfer lines.');
        }
      }
      await _save();
      pending = await drafts.prepare(
        scope,
        slot,
        verb: 'submit',
        expectedVersion: f['version'] as int?,
        payload: {
          for (final k in [
            'id',
            'operation',
            'document_date',
            'reason',
            'reference',
          ])
            k: f[k],
          if (dispatch) ...{
            'source_warehouse_id': f['source_warehouse_id'],
            'destination_warehouse_id': f['destination_warehouse_id'],
            'lines': lines,
          },
        },
      );
      local = await drafts.load(scope, slot);
    }
    if (!currentServer || accessDenied) return;
    try {
      await gateway.execute(pending.envelope);
      await drafts.complete(scope, slot, pending.envelope.commandId);
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
    form = null;
    local = null;
    message = 'Transfer action posted. Movement history is retained.';
    if (!currentServer) return;
    try {
      await _refresh();
    } catch (_) {
      error = 'Posted successfully. Refresh the register when the connection returns.';
    }
  });
}

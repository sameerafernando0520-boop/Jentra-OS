import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';

import '../../app_providers.dart';

final receiptTraceGatewayProvider = Provider<ReceiptTraceGateway?>(
  (ref) => null,
);
final receiptTraceControllerProvider =
    Provider.autoDispose<ReceiptTraceController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider);
      final gateway = ref.watch(receiptTraceGatewayProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          caps.isLoading ||
          caps.hasError ||
          !(caps.value?.contains('inventory.valuation.post') ?? false) ||
          !(caps.value?.contains('inventory.cost.view') ?? false)) {
        return null;
      }
      final c = ReceiptTraceController(
        scope: scope,
        gateway: gateway,
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
      );
      ref.listen(
        connectivityStateProvider,
        (_, state) => c.setOnline(state.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      unawaited(c.refresh());
      return c;
    });

final class ReceiptTraceController extends ChangeNotifier {
  ReceiptTraceController({
    required this.scope,
    required this.gateway,
    required this.online,
  });
  final TenantContext scope;
  final ReceiptTraceGateway gateway;
  bool online, busy = false, _disposed = false;
  String? error, cursor, historyCursor;
  List<Map<String, Object?>> rows = [], history = [];
  Map<String, Object?>? selected, detail;
  void emit() {
    if (!_disposed) notifyListeners();
  }

  void setOnline(bool value) {
    online = value;
    emit();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> run(Future<void> Function() work) async {
    if (_disposed || busy || !online) return;
    busy = true;
    error = null;
    emit();
    try {
      await work();
    } catch (e) {
      if (e is DomainError && e.code == 'PERMISSION_DENIED') {
        rows = [];
        history = [];
        selected = null;
        detail = null;
        cursor = null;
        historyCursor = null;
      }
      error = e is DomainError
          ? e.message
          : 'Receipt trace could not be verified. Refresh to try again.';
    } finally {
      busy = false;
      emit();
    }
  }

  Future<void> refresh({bool more = false}) => run(() async {
    final result = await gateway.page(scope, after: more ? cursor : null);
    if (_disposed) return;
    rows = [
      if (more) ...rows,
      for (final row in result['items'] as List)
        (row as Map).cast<String, Object?>(),
    ];
    cursor = result['next_cursor'] as String?;
  });
  Future<void> open(Map<String, Object?> row) => run(() async {
    // Clear old detail before loading a different identity; a failed read cannot relabel it.
    selected = row;
    detail = null;
    history = [];
    historyCursor = null;
    emit();
    await readDetail(more: false);
  });
  Future<void> refreshDetail({bool more = false}) =>
      run(() => readDetail(more: more));
  Future<void> readDetail({required bool more}) async {
    if (selected == null) return;
    final result = await gateway.detail(
      scope,
      selected!['id'] as String,
      after: more ? historyCursor : null,
    );
    if (_disposed) return;
    detail = result;
    history = [
      if (more) ...history,
      for (final row in result['items'] as List)
        (row as Map).cast<String, Object?>(),
    ];
    historyCursor = result['next_cursor'] as String?;
  }

  void close() {
    if (busy) return;
    selected = null;
    detail = null;
    history = [];
    historyCursor = null;
    error = null;
    emit();
  }
}

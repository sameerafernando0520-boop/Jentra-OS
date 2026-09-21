import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import '../../app_providers.dart';

final inventoryValuationGatewayProvider = Provider<InventoryValuationGateway?>(
  (ref) => null,
);
final inventoryValuationControllerProvider =
    Provider.autoDispose<InventoryValuationController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider),
          gateway = ref.watch(inventoryValuationGatewayProvider),
          caps = ref.watch(businessCapabilitiesProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          caps.isLoading ||
          caps.hasError ||
          ![
            'inventory.stock.view',
            'inventory.cost.view',
            'finance.view',
          ].every((p) => caps.value?.contains(p) ?? false)) {
        return null;
      }
      final c = InventoryValuationController(
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
        (_, s) => c.setOnline(s.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

final class InventoryValuationController extends ChangeNotifier {
  InventoryValuationController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.online,
  });
  final TenantContext scope;
  final InventoryValuationGateway gateway;
  final QuotationDraftStore drafts;
  static const slot = 'inventory-valuation-report';
  bool online, busy = false, _disposed = false, accessDenied = false;
  String? error, message, cursor, evidenceKey;
  String section = 'stock';
  Map<String, Object?> form = {}, summary = {};
  QuotationLocalDraft? local;
  List<Map<String, Object?>> accounts = [], reports = [], rows = [];
  String? accountCursor, reportCursor;
  bool get locked =>
      busy ||
      accessDenied ||
      local?.pending != null ||
      form['status'] == 'generated';
  List<String> get selectedAccounts =>
      (form['account_ids'] as List? ?? []).cast<String>();
  void emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void setOnline(bool v) {
    online = v;
    emit();
  }

  void deny(Object e) {
    if (e is DomainError && e.code == 'PERMISSION_DENIED') {
      accessDenied = true;
      summary = {};
      rows = [];
      accounts = [];
      reports = [];
      cursor = null;
      evidenceKey = null;
    }
  }

  Future<void> run(Future<void> Function() work) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    emit();
    try {
      await work();
    } catch (e) {
      deny(e);
      error = e is DomainError
          ? e.message
          : e is FormatException
          ? e.message
          : 'Unable to load the report. Saved work is retained.';
    } finally {
      busy = false;
      emit();
    }
  }

  Future<void> persist() async {
    await drafts.save(scope, slot, form, expectedVersion: 0);
    local = await drafts.load(scope, slot);
  }

  Future<void> initialize() => run(() async {
    local = await drafts.load(scope, slot);
    if (_disposed) return;
    form =
        local?.form ??
        {
          'id': const Uuid().v4(),
          'as_of': DateTime.now().toUtc().toIso8601String().substring(0, 10),
          'account_ids': <String>[],
          'status': 'local',
        };
    if (online) {
      await loadOptions('accounts');
      await loadOptions('reports');
      accessDenied = false;
      if (form['status'] == 'generated') {
        summary = Map<String, Object?>.from(form['summary'] as Map);
        await readPage();
      }
    }
  });
  Future<void> loadOptions(String resource, {bool more = false}) async {
    if (!online) return;
    final r = await gateway.options(
      scope,
      resource,
      after: more
          ? (resource == 'accounts' ? accountCursor : reportCursor)
          : null,
    );
    if (_disposed) return;
    final items = [
      for (final x in r['items'] as List) (x as Map).cast<String, Object?>(),
    ];
    if (resource == 'accounts') {
      accounts = [if (more) ...accounts, ...items];
      accountCursor = r['next_cursor'] as String?;
    } else {
      reports = [if (more) ...reports, ...items];
      reportCursor = r['next_cursor'] as String?;
    }
  }

  Future<void> refresh(String resource, {bool more = false}) =>
      run(() => loadOptions(resource, more: more));
  void date(String value) {
    if (locked) return;
    form = {...form, 'as_of': value.trim()};
    emit();
  }

  void account(String id, bool selected) {
    if (locked) return;
    final ids = selectedAccounts.toSet();
    selected ? ids.add(id) : ids.remove(id);
    form = {...form, 'account_ids': ids.toList()..sort()};
    emit();
  }

  Future<void> save() => run(persist);
  Future<bool> canLeave() async {
    if (busy) return false;
    if (accessDenied || local?.pending != null) return true;
    await save();
    return error == null;
  }

  Future<void> newReport() => run(() async {
    if (local?.pending != null) {
      throw const FormatException(
        'Resolve the saved request before starting another report.',
      );
    }
    await drafts.discard(scope, slot);
    form = {
      'id': const Uuid().v4(),
      'as_of':
          form['as_of'] ??
          DateTime.now().toUtc().toIso8601String().substring(0, 10),
      'account_ids': selectedAccounts,
      'status': 'local',
    };
    summary = {};
    rows = [];
    cursor = null;
    evidenceKey = null;
    message = null;
    await persist();
  });
  Future<void> generate() => run(() async {
    if (!online || accessDenied || form['status'] == 'generated') return;
    var pending = local?.pending;
    if (pending == null) {
      if (selectedAccounts.isEmpty || selectedAccounts.length > 50) {
        throw const FormatException('Select 1–50 inventory control accounts.');
      }
      await persist();
      pending = await drafts.prepare(
        scope,
        slot,
        verb: 'accept',
        expectedVersion: 0,
        payload: {
          'id': form['id'],
          'as_of': form['as_of'],
          'account_ids': selectedAccounts,
        },
      );
      local = await drafts.load(scope, slot);
    }
    Map<String, Object?> result;
    try {
      result = await gateway.generate(pending.envelope);
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
    summary = result;
    form = {...form, 'status': 'generated', 'summary': result};
    local = null;
    message = 'Report saved. Later postings will not change this snapshot.';
    try {
      await persist();
      section = 'stock';
      evidenceKey = null;
      rows = [];
      cursor = null;
      await readPage();
      await loadOptions('reports');
    } catch (e) {
      deny(e);
      error =
          'Report generation confirmed. Refresh to load its saved evidence.';
    }
  });
  Future<void> open(Map<String, Object?> report) => run(() async {
    if (!online || local?.pending != null) return;
    summary = report;
    section = 'stock';
    evidenceKey = null;
    rows = [];
    cursor = null;
    emit();
    await readPage();
    // Reviewing a saved report does not replace the user's unsubmitted inputs.
    await persist();
  });
  Future<void> selectSection(String value) => run(() async {
    if (!online || summary.isEmpty) return;
    section = value;
    if (!['movements', 'journals', 'transit'].contains(value)) {
      evidenceKey = null;
    }
    rows = [];
    cursor = null;
    emit();
    await readPage();
  });
  Future<void> sources(String? key) => run(() async {
    if (!online || summary.isEmpty) return;
    evidenceKey = key;
    section = key == null ? 'differences' : 'movements';
    rows = [];
    cursor = null;
    emit();
    await readPage();
  });
  Future<void> refreshPage({bool more = false}) =>
      run(() => readPage(more: more));
  Future<void> readPage({bool more = false}) async {
    if (!online || summary.isEmpty) return;
    final r = await gateway.page(
      scope,
      summary['id'] as String,
      section,
      after: more ? cursor : null,
      evidenceKey: evidenceKey,
    );
    if (_disposed) return;
    summary = (r['summary'] as Map).cast<String, Object?>();
    rows = [
      if (more) ...rows,
      for (final x in r['items'] as List) (x as Map).cast<String, Object?>(),
    ];
    cursor = r['next_cursor'] as String?;
  }
}

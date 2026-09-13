import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:uuid/uuid.dart';
import '../../app_providers.dart';
import 'procurement_controller.dart';

final purchaseOrderControllerProvider =
    Provider.autoDispose<PurchaseOrderController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider);
      final gateway = ref.watch(procurementGatewayProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway is! PurchaseOrderGateway ||
          caps.isLoading ||
          caps.hasError ||
          !(caps.value?.contains('procurement.orders.manage') ?? false)) {
        return null;
      }
      final c = PurchaseOrderController(
        scope: scope,
        gateway: gateway as PurchaseOrderGateway,
        references: gateway!,
        drafts: QuotationDraftStore.procurement(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        canApprove: caps.value?.contains('workflow.approvals.decide') ?? false,
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
      );
      ref.listen(
        connectivityStateProvider,
        (_, v) => c.setOnline(v.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

final class PurchaseOrderController extends ChangeNotifier {
  PurchaseOrderController({
    required this.scope,
    required this.gateway,
    required this.references,
    required this.drafts,
    required this.online,
    this.canApprove = false,
  });
  final TenantContext scope;
  final PurchaseOrderGateway gateway;
  final ProcurementGateway references;
  final QuotationDraftStore drafts;
  final bool canApprove;
  static const slot = 'purchase-order-editor';
  bool online, busy = false, _disposed = false;
  String? error, message;
  Map<String, Object?>? form, selected;
  QuotationLocalDraft? local;
  int? version;
  CursorPage<Map<String, Object?>> page = CursorPage(items: [], limit: 50);
  bool get locked =>
      _disposed ||
      busy ||
      local?.pending != null ||
      local?.errorCode == 'VERSION_CONFLICT';
  bool get ownOrder =>
      selected != null &&
      [
        'created_by',
        'commercial_editor_id',
        'submitted_by',
      ].any((k) => selected![k] == scope.actorId);
  void emit() {
    if (!_disposed) {
      notifyListeners();
    }
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

  Future<void> run(Future<void> Function() work) async {
    if (busy || _disposed) {
      return;
    }
    busy = true;
    error = null;
    emit();
    try {
      await work();
    } catch (e) {
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
    if (_disposed) {
      return;
    }
    form = local?.form;
    version = local?.expectedVersion;
    if (online) {
      page = await gateway.orders(scope);
    }
  });
  Future<void> refresh({bool more = false}) => run(() async {
    if (!online) {
      return;
    }
    final result = await gateway.orders(
      scope,
      after: more ? page.nextCursor : null,
    );
    if (_disposed) {
      return;
    }
    page = CursorPage(
      items: [if (more) ...page.items, ...result.items],
      limit: 50,
      nextCursor: result.nextCursor,
    );
    if (selected != null) {
      selected =
          page.items.where((r) => r['id'] == selected!['id']).firstOrNull ??
          selected;
    }
  });
  void select(Map<String, Object?> row) {
    if (locked || form != null) {
      return;
    }
    selected = row;
    emit();
  }

  Future<void> create(Map<String, Object?> rfq) => run(() async {
    if (form != null || local != null || rfq['status'] != 'selected') {
      return;
    }
    final quote = (rfq['quotes'] as List)
        .cast<Map>()
        .where((q) => q['id'] == rfq['selected_quote_id'])
        .single;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    form = {
      'id': const Uuid().v4(),
      'source_rfq_id': rfq['id'],
      'source_rfq_version': rfq['version'],
      'source_quote_id': quote['id'],
      'source_quote_version': quote['version'],
      'document_date': today,
      'promised_date': today,
      'warehouse_id': null,
      '_source_number': rfq['document_number'],
      '_supplier_name': quote['supplier_name'],
      '_source_total': '${quote['currency_code']} ${quote['total']}',
      '_source_lines': quote['lines'],
    };
    version = null;
    await drafts.save(scope, slot, form!);
  });
  Future<void> edit(Map<String, Object?> row) => run(() async {
    if (form != null || local != null || row['status'] != 'draft') {
      return;
    }
    form = Map<String, Object?>.from(row);
    version = row['version'] as int;
    await drafts.save(scope, slot, form!, expectedVersion: version);
  });
  Future<void> createFromRequisition(Map<String, Object?> source) =>
      run(() async {
        if (form != null || local != null || source['status'] != 'approved') {
          return;
        }
        final today = DateTime.now().toIso8601String().substring(0, 10);
        form = {
          'id': const Uuid().v4(),
          'source_requisition_id': source['id'],
          'source_requisition_version': source['version'],
          '_source_number': source['document_number'],
          'document_date': today,
          'promised_date': source['need_by'],
          'supplier_id': null,
          'warehouse_id': null,
          'currency_code': source['currency_code'],
          'exchange_rate': '1',
          'exchange_rate_id': null,
          'rate_date': today,
          'payment_terms': '',
          'delivery_terms': '',
          'lines': (source['lines'] as List).map((raw) {
            final l = raw as Map;
            return <String, Object?>{
              'line_id': const Uuid().v4(),
              'source_line_id': l['line_id'],
              'product_id': l['product_id'],
              'unit_id': l['unit_id'],
              'description': l['description'],
              'quantity': l['quantity'],
              'unit_price': l['estimated_unit_price'],
              'discount_percent': '0',
              'tax_definition_id': null,
              'received_quantity': '0',
              'billed_quantity': '0',
            };
          }).toList(),
        };
        version = null;
        await drafts.save(scope, slot, form!);
      });
  Future<void> useBaseCurrency() => run(() async {
    if (!online ||
        form == null ||
        local?.pending != null ||
        local?.errorCode == 'VERSION_CONFLICT') {
      return;
    }
    final result = await references.references(scope, 'units');
    if (_disposed || form == null) {
      return;
    }
    form = {
      ...form!,
      'currency_code': result['base_currency'],
      'exchange_rate': '1',
      'exchange_rate_id': null,
    };
  });
  void update(String key, Object? value) {
    if (locked ||
        form == null ||
        (form?['status'] != null && form?['status'] != 'draft')) {
      return;
    }
    form = {...form!, key: value};
    emit();
  }

  Future<void> saveLocal() => run(() async {
    if (form == null ||
        local?.pending != null ||
        local?.errorCode == 'VERSION_CONFLICT') {
      return;
    }
    await drafts.save(scope, slot, form!, expectedVersion: version);
    message = 'Saved securely on this device.';
  });
  Future<bool> canLeave() async {
    if (busy) {
      return false;
    }
    if (form == null ||
        local?.pending != null ||
        local?.errorCode == 'VERSION_CONFLICT') {
      return true;
    }
    var saved = false;
    await run(() async {
      await drafts.save(scope, slot, form!, expectedVersion: version);
      saved = true;
    });
    return saved;
  }

  Future<void> discard() => run(() async {
    await drafts.discard(scope, slot);
    form = null;
    local = null;
    version = null;
  });
  Future<void> transition(String action, {String? reason}) => run(() async {
    if (!online || selected == null || form != null || local != null) {
      return;
    }
    if (['approve', 'reject'].contains(action) && (!canApprove || ownOrder)) {
      return;
    }
    final payload = <String, Object?>{
      'document_id': selected!['id'],
      if (action == 'approve' || action == 'reject')
        'decision': action == 'approve' ? 'approved' : 'rejected'
      else
        'action': action,
      'reason': ?reason,
    };
    // The draft store's established verbs distinguish commands from editable saves.
    final verb = action == 'revise' ? 'recall' : action;
    await drafts.save(
      scope,
      slot,
      selected!,
      expectedVersion: selected!['version'] as int,
    );
    final pending = await drafts.prepare(
      scope,
      slot,
      verb: verb,
      payload: payload,
      expectedVersion: selected!['version'] as int,
    );
    local = await drafts.load(scope, slot);
    form = selected;
    version = selected!['version'] as int;
    await send(pending);
  });
  Future<void> saveServer() => run(() async {
    if (!online || form == null) {
      return;
    }
    var pending = local?.pending;
    if (pending == null) {
      if (form?['status'] != null && form?['status'] != 'draft') {
        throw const FormatException('Reload this order from the register.');
      }
      for (final key in ['document_date', 'promised_date']) {
        final date = form![key];
        final parsed = date is String ? DateTime.tryParse(date) : null;
        if (parsed == null ||
            parsed.toIso8601String().substring(0, 10) != date) {
          throw FormatException('Enter a valid $key.');
        }
      }
      if (form!['warehouse_id'] == null) {
        throw const FormatException('Choose a receiving warehouse.');
      }
      final payload = <String, Object?>{
        for (final key in const [
          'id',
          'source_rfq_id',
          'source_rfq_version',
          'source_quote_id',
          'source_quote_version',
          'source_requisition_id',
          'source_requisition_version',
          'supplier_id',
          'warehouse_id',
          'document_date',
          'promised_date',
          'currency_code',
          'exchange_rate_id',
          'exchange_rate',
          'rate_date',
          'payment_terms',
          'delivery_terms',
        ])
          if (form!.containsKey(key)) key: form![key],
        if (form!['lines'] case final List lines)
          'lines': [
            for (final line in lines)
              {
                for (final key in const [
                  'line_id',
                  'source_line_id',
                  'product_id',
                  'unit_id',
                  'description',
                  'quantity',
                  'unit_price',
                  'discount_percent',
                  'tax_definition_id',
                ])
                  key: (line as Map)[key],
              },
          ],
      };
      await drafts.save(scope, slot, form!, expectedVersion: version);
      pending = await drafts.prepare(
        scope,
        slot,
        verb: 'save',
        payload: payload,
        expectedVersion: version,
      );
      local = await drafts.load(scope, slot);
    }
    await send(pending);
  });
  Future<void> send(QuotationPendingCommand pending) async {
    if (_disposed || !online) {
      return;
    }
    late final Map<String, Object?> result;
    try {
      result = pending.verb == 'save'
          ? await gateway.saveOrder(pending.envelope)
          : await gateway.transitionOrder(pending.envelope);
      await drafts.complete(scope, slot, pending.envelope.commandId);
    } on DomainError catch (e) {
      await drafts.recordFailure(
        scope,
        slot,
        e,
        commandId: pending.envelope.commandId,
      );
      local = await drafts.load(scope, slot);
      if (pending.verb != 'save' &&
          local?.pending == null &&
          e.code != 'VERSION_CONFLICT') {
        await drafts.discard(scope, slot);
        form = null;
        local = null;
        version = null;
      }
      rethrow;
    }
    if (_disposed) {
      return;
    }
    form = null;
    local = null;
    version = null;
    selected = result;
    message =
        'Purchase order ${result['status']} · revision ${result['revision']}';
    try {
      page = await gateway.orders(scope);
    } catch (_) {
      error =
          'Saved successfully. The register could not refresh; use Refresh to reload it.';
    }
  }
}

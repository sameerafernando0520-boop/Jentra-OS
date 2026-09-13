import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:uuid/uuid.dart';
import '../../app_providers.dart';
import 'procurement_controller.dart';

final supplierBillControllerProvider =
    Provider.autoDispose<SupplierBillController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider),
          gateway = ref.watch(procurementGatewayProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway is! SupplierBillGateway ||
          caps.isLoading ||
          caps.hasError ||
          ![
            'procurement.bills.view',
            'procurement.bills.manage',
            'procurement.bills.post',
            'finance.setup.manage',
          ].any((p) => caps.value?.contains(p) ?? false)) {
        return null;
      }
      final c = SupplierBillController(
        scope: scope,
        gateway: gateway as SupplierBillGateway,
        references: gateway!,
        drafts: QuotationDraftStore.procurement(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
        canManage: caps.value?.contains('procurement.bills.manage') ?? false,
        canPost: caps.value?.contains('procurement.bills.post') ?? false,
        canApprove: caps.value?.contains('workflow.approvals.decide') ?? false,
        canSetup: caps.value?.contains('finance.setup.manage') ?? false,
      );
      ref.listen(
        connectivityStateProvider,
        (_, v) => c.setOnline(v.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

final class SupplierBillController extends ChangeNotifier {
  SupplierBillController({
    required this.scope,
    required this.gateway,
    required this.references,
    required this.drafts,
    required this.online,
    this.canManage = true,
    this.canPost = false,
    this.canApprove = false,
    this.canSetup = false,
  });
  final TenantContext scope;
  final SupplierBillGateway gateway;
  final ProcurementGateway references;
  final QuotationDraftStore drafts;
  final bool canManage, canPost, canApprove, canSetup;
  static const slot = 'supplier-bill-editor';
  bool online, busy = false, _disposed = false;
  String? error, message, baseCurrency;
  Map<String, Object?>? form, selected;
  QuotationLocalDraft? local;
  int? version;
  CursorPage<Map<String, Object?>> page = CursorPage(items: [], limit: 50);
  bool get locked =>
      _disposed ||
      busy ||
      local?.pending != null ||
      local?.errorCode == 'VERSION_CONFLICT';
  bool get ownBill =>
      selected != null &&
      ['created_by', 'updated_by'].any((k) => selected![k] == scope.actorId);
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

  Future<void> run(Future<void> Function() action) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    emit();
    try {
      await action();
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
    if (_disposed) return;
    form = local?.form;
    version = local?.expectedVersion;
    if (online) page = await gateway.bills(scope);
  });
  Future<void> refresh({bool more = false}) => run(() async {
    if (!online) return;
    final result = await gateway.bills(
      scope,
      after: more ? page.nextCursor : null,
    );
    if (_disposed) return;
    page = CursorPage(
      items: [if (more) ...page.items, ...result.items],
      limit: 50,
      nextCursor: result.nextCursor,
    );
  });
  void select(Map<String, Object?> row) {
    if (!locked && form == null) {
      selected = row;
      emit();
    }
  }

  Future<void> create({Map<String, Object?>? receipt}) => run(() async {
    if (!canManage ||
        form != null ||
        local != null ||
        (!canPost && receipt == null)) {
      return;
    }
    final meta = await references.references(scope, 'bill_suppliers');
    if (_disposed) return;
    baseCurrency = meta['base_currency'] as String;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    form = {
      'id': const Uuid().v4(),
      '_mode': 'bill',
      'document_date': today,
      'due_date': today,
      'supplier_reference': '',
      'supplier_id': receipt?['supplier_id'],
      'currency_code': receipt?['currency_code'] ?? baseCurrency,
      'exchange_rate_id': receipt?['exchange_rate_id'],
      '_base_currency': baseCurrency,
      'lines': <Map<String, Object?>>[
        if (receipt != null) _receiptLine(receipt),
      ],
    };
    version = null;
    await drafts.save(scope, slot, form!);
  });
  Map<String, Object?> _receiptLine(Map<String, Object?> r) {
    final source = (r['source_snapshot'] as Map).cast<String, Object?>();
    return {
      'line_id': const Uuid().v4(),
      'receipt_line_id': r['receipt_line_id'],
      'description': r['description'],
      '_receipt_number': r['_receipt_number'],
      'quantity': r['available_quantity'],
      'unit_price': source['unit_price'],
      'discount_percent': source['discount_percent'],
      'tax_definition_id': source['tax_definition_id'],
      '_tax_name': source['tax_definition_id'] == null
          ? 'No tax'
          : 'Source tax',
    };
  }

  void addReceipt(Map<String, Object?> row) {
    if (locked || form == null) return;
    if (row['supplier_id'] != form!['supplier_id']) {
      error = 'Choose a receipt for the same supplier.';
      emit();
      return;
    }
    update('lines', [...form!['lines'] as List, _receiptLine(row)]);
  }

  void addDirect() {
    if (locked || !canPost || form == null) return;
    update('lines', [
      ...form!['lines'] as List,
      {
        'line_id': const Uuid().v4(),
        'description': '',
        'quantity': '1',
        'unit_price': '0',
        'discount_percent': '0',
        'tax_definition_id': null,
        'expense_account_id': null,
      },
    ]);
  }

  Future<void> edit(Map<String, Object?> row) => run(() async {
    if (!canManage ||
        form != null ||
        local != null ||
        row['status'] != 'draft') {
      return;
    }
    form = {...row, '_mode': 'bill'};
    version = row['version'] as int;
    await drafts.save(scope, slot, form!, expectedVersion: version);
  });
  Future<void> configure() => run(() async {
    if (!canSetup || !online || form != null || local != null) return;
    final result = await references.references(scope, 'bill_controls');
    if (_disposed) return;
    final items = result['items'] as List;
    final current = items.isEmpty
        ? <String, Object?>{}
        : (items.first as Map).cast<String, Object?>();
    form = {
      ...current,
      'id': scope.legalEntityId,
      '_mode': 'controls',
      'amount_tolerance': current['amount_tolerance'] ?? '0',
      'price_percent_tolerance': current['price_percent_tolerance'] ?? '0',
    };
    version = current['version'] as int?;
    await drafts.save(scope, slot, form!, expectedVersion: version);
  });
  void update(String key, Object? value) {
    if (!locked && form != null) {
      form = {...form!, key: value};
      emit();
    }
  }

  void updateLine(String id, String key, Object? value) {
    if (locked || form?['lines'] is! List) return;
    update('lines', [
      for (final raw in form!['lines'] as List)
        {
          ...(raw as Map).cast<String, Object?>(),
          if (raw['line_id'] == id) key: value,
        },
    ]);
  }

  void removeLine(String id) {
    if (!locked && form?['lines'] is List) {
      update('lines', [
        for (final raw in form!['lines'] as List)
          if ((raw as Map)['line_id'] != id) raw,
      ]);
    }
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
    if (busy) return false;
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
  Future<void> action(String action, {String? reason}) => run(() async {
    if (!online ||
        selected == null ||
        form != null ||
        local != null ||
        selected!['status'] != 'draft') {
      return;
    }
    if (action == 'approve' && (!canApprove || !canPost || ownBill)) return;
    if (action == 'post' && !canPost || action == 'cancel' && !canManage) {
      return;
    }
    form = {...selected!, '_mode': 'action'};
    version = selected!['version'] as int;
    await drafts.save(scope, slot, form!, expectedVersion: version);
    final pending = await drafts.prepare(
      scope,
      slot,
      verb: action == 'post' ? 'submit' : action,
      payload: {'document_id': selected!['id'], 'reason': ?reason},
      expectedVersion: version,
    );
    local = await drafts.load(scope, slot);
    await send(pending);
  });
  Future<void> saveServer() => run(() async {
    if (!online || form == null || local?.errorCode == 'VERSION_CONFLICT') {
      return;
    }
    var pending = local?.pending;
    if (pending == null) {
      final controls = form!['_mode'] == 'controls';
      if (controls ? !canSetup : !canManage) return;
      if (form!['_mode'] == 'action') {
        throw const FormatException(
          'Discard this rejected action and reload the bill to continue.',
        );
      }
      final payload = <String, Object?>{'id': form!['id']};
      if (controls) {
        for (final key in [
          'payable_account_id',
          'input_tax_account_id',
          'variance_account_id',
        ]) {
          if (form![key] == null) {
            throw const FormatException('Choose all three posting accounts.');
          }
          payload[key] = form![key];
        }
        for (final key in ['amount_tolerance', 'price_percent_tolerance']) {
          GoodsReceiptQuantity.decimal(form![key]);
          payload[key] = form![key];
        }
      } else {
        for (final key in ['document_date', 'due_date']) {
          final v = form![key];
          final parsed = v is String ? DateTime.tryParse(v) : null;
          if (parsed == null ||
              parsed.toIso8601String().substring(0, 10) != v) {
            throw const FormatException('Enter valid posting and due dates.');
          }
        }
        if (form!['supplier_id'] == null ||
            (form!['supplier_reference'] as String? ?? '').trim().isEmpty) {
          throw const FormatException(
            'Choose a supplier and enter its invoice reference.',
          );
        }
        for (final key in [
          'supplier_id',
          'supplier_reference',
          'document_date',
          'due_date',
          'currency_code',
          'exchange_rate_id',
        ]) {
          payload[key] = form![key];
        }
        final lines = form!['lines'] as List;
        if (lines.isEmpty || lines.length > 500) {
          throw const FormatException('Add 1 to 500 bill lines.');
        }
        payload['lines'] = [
          for (final raw in lines)
            {
              for (final key in [
                'line_id',
                'receipt_line_id',
                'product_id',
                'description',
                'quantity',
                'unit_price',
                'discount_percent',
                'tax_definition_id',
                'expense_account_id',
              ])
                key: (raw as Map)[key],
            },
        ];
        for (final raw in lines) {
          final line = raw as Map;
          if (!GoodsReceiptQuantity.decimal(line['quantity']).isPositive) {
            throw const FormatException('Bill quantities must be positive.');
          }
          GoodsReceiptQuantity.decimal(line['unit_price']);
          if (GoodsReceiptQuantity.decimal(
                line['discount_percent'],
              ).compareTo(GoodsReceiptQuantity.decimal('100')) >
              0) {
            throw const FormatException('Discount must be from 0 to 100.');
          }
        }
      }
      await drafts.save(scope, slot, form!, expectedVersion: version);
      pending = await drafts.prepare(
        scope,
        slot,
        verb: controls ? 'accept' : 'save',
        payload: payload,
        expectedVersion: version,
      );
      local = await drafts.load(scope, slot);
    }
    await send(pending);
  });
  Future<void> send(QuotationPendingCommand pending) async {
    if (_disposed || !online) return;
    late Map<String, Object?> result;
    try {
      result = switch (pending.verb) {
        'save' => await gateway.saveBill(pending.envelope),
        'accept' => await gateway.saveBillControls(pending.envelope),
        'submit' => await gateway.billAction('post', pending.envelope),
        'approve' ||
        'cancel' => await gateway.billAction(pending.verb, pending.envelope),
        _ => throw const FormatException('Unknown saved bill command.'),
      };
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
    version = null;
    if (pending.verb != 'accept') selected = result;
    message = pending.verb == 'accept'
        ? 'Supplier bill controls saved.'
        : pending.verb == 'approve'
        ? 'Match decision recorded.'
        : 'Supplier bill ${result['status']}.';
    try {
      page = await gateway.bills(scope);
    } catch (_) {
      error =
          'Saved successfully. Refresh the register when the connection returns.';
    }
  }
}

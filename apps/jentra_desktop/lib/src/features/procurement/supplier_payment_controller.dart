import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:uuid/uuid.dart';
import '../../app_providers.dart';
import 'procurement_controller.dart';

final supplierPaymentControllerProvider =
    Provider.autoDispose<SupplierPaymentController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider),
          gateway = ref.watch(procurementGatewayProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway is! SupplierPaymentGateway ||
          caps.isLoading ||
          caps.hasError ||
          ![
            'finance.payments.manage',
            'finance.payments.post',
            'finance.payments.allocate',
            'finance.payments.reverse',
          ].any((p) => caps.value?.contains(p) ?? false)) {
        return null;
      }
      final c = SupplierPaymentController(
        scope: scope,
        gateway: gateway as SupplierPaymentGateway,
        references: gateway!,
        drafts: QuotationDraftStore.procurement(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
        canManage: caps.value?.contains('finance.payments.manage') ?? false,
        canPost: caps.value?.contains('finance.payments.post') ?? false,
        canAllocate: caps.value?.contains('finance.payments.allocate') ?? false,
        canReverse: caps.value?.contains('finance.payments.reverse') ?? false,
        canApprove: caps.value?.contains('workflow.approvals.decide') ?? false,
      );
      ref.listen(
        connectivityStateProvider,
        (_, v) => c.setOnline(v.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

final class SupplierPaymentController extends ChangeNotifier {
  SupplierPaymentController({
    required this.scope,
    required this.gateway,
    required this.references,
    required this.drafts,
    required this.online,
    this.canManage = true,
    this.canPost = false,
    this.canApprove = false,
    this.canAllocate = false,
    this.canReverse = false,
  });
  final TenantContext scope;
  final SupplierPaymentGateway gateway;
  final ProcurementGateway references;
  final QuotationDraftStore drafts;
  final bool canManage, canPost, canApprove;
  final bool canAllocate, canReverse;
  Map<String, Object?>? itemDetail;
  List<Map<String, Object?>> allocationTargets = [];
  String? targetCursor;
  List<Map<String, Object?>> allocationRates = [];
  String? rateCursor;
  Future<void> loadAllocationRates({bool more = false}) => run(() async {
    if (!online || form?['_mode'] != 'allocation' || local?.pending != null) {
      return;
    }
    final result = await gateway.allocationRates(
      scope,
      form!,
      after: more ? rateCursor : null,
    );
    if (_disposed) return;
    allocationRates = [
      if (more) ...allocationRates,
      for (final raw in result['items'] as List)
        (raw as Map).cast<String, Object?>(),
    ];
    rateCursor = result['next_cursor'] as String?;
  });
  Future<void> inspectItem(String id, {bool more = false}) => run(() async {
    if (!online || form != null) return;
    final detail = await gateway.itemDetail(
      scope,
      id,
      after: more ? (itemDetail?['next_cursor'] as String?) : null,
    );
    if (_disposed) return;
    itemDetail = {
      ...detail,
      'allocations': [
        if (more) ...itemDetail!['allocations'] as List,
        ...detail['allocations'] as List,
      ],
    };
  });
  Future<void> beginAllocation() => run(() async {
    if (!canAllocate || itemDetail == null || form != null || local != null) {
      return;
    }
    final item = (itemDetail!['item'] as Map).cast<String, Object?>();
    if (!ExactDecimal.parse(item['amount'] as String, scale: 6).isNegative) {
      return;
    }
    form = {
      'id': const Uuid().v4(),
      '_mode': 'allocation',
      'source_open_item_id': item['id'],
      '_source_number': item['document_number'],
      '_currency': item['currency_code'],
      'source_amount': (item['amount'] as String).substring(1),
      'transaction_amount': '',
      'posting_date': DateTime.now().toIso8601String().substring(0, 10),
      'reason': '',
    };
    version = null;
    allocationTargets = [];
    targetCursor = null;
    await drafts.save(scope, slot, form!);
  });
  Future<void> loadAllocationTargets({bool more = false}) => run(() async {
    if (!online || form?['_mode'] != 'allocation' || local?.pending != null) {
      return;
    }
    final result = await gateway.allocationTargets(
      scope,
      form!['source_open_item_id'] as String,
      after: more ? targetCursor : null,
    );
    if (_disposed) return;
    allocationTargets = [
      if (more) ...allocationTargets,
      for (final row in result['items'] as List)
        (row as Map).cast<String, Object?>(),
    ];
    targetCursor = result['next_cursor'] as String?;
  });
  Future<void> reverseAllocation(
    Map<String, Object?> allocation, {
    required String date,
    required String reason,
  }) => run(() async {
    if (!canReverse ||
        !online ||
        form != null ||
        local != null ||
        allocation['reversal'] != null) {
      return;
    }
    form = {
      'id': const Uuid().v4(),
      '_mode': 'correction',
      '_correction_action': 'reverse',
      'allocation_id': allocation['id'],
      'posting_date': date,
      'reason': reason,
    };
    version = null;
    await drafts.save(scope, slot, form!);
  });
  Future<void> prepareCorrection() async {
    final f = form!, reverse = form!['_correction_action'] == 'reverse';
    if (reverse ? !canReverse : !canAllocate) return;
    final date = f['posting_date'] as String?,
        parsed = DateTime.tryParse(f['posting_date'] as String? ?? '');
    if (parsed == null || parsed.toIso8601String().substring(0, 10) != date) {
      throw const FormatException('Enter a valid allocation posting date.');
    }
    final reason = (f['reason'] as String? ?? '').trim();
    if (reason.isEmpty || reason.length > 1000) {
      throw const FormatException('Enter a reason of up to 1000 characters.');
    }
    final payload = <String, Object?>{'posting_date': date, 'reason': reason};
    if (reverse) {
      payload['allocation_id'] = f['allocation_id'];
    } else {
      if (f['target_open_item_id'] == null) {
        throw const FormatException('Choose a bill to allocate.');
      }
      for (final key in ['source_amount', 'transaction_amount']) {
        if (!GoodsReceiptQuantity.decimal(f[key]).isPositive) {
          throw const FormatException('Allocation amounts must be positive.');
        }
      }
      payload['source_open_item_id'] = f['source_open_item_id'];
      payload['allocations'] = [
        {
          for (final key in [
            'target_open_item_id',
            'source_amount',
            'transaction_amount',
            'exchange_rate_id',
          ])
            key: f[key],
        },
      ];
    }
    await drafts.save(scope, slot, form!);
    final pending = await drafts.prepare(
      scope,
      slot,
      verb: 'expire',
      payload: payload,
    );
    local = await drafts.load(scope, slot);
    await send(pending);
  }

  static const slot = 'supplier-payment-editor';
  bool online, busy = false, _disposed = false, showingPayments = false;
  String? error, message, itemCursor;
  Map<String, Object?>? form, selected;
  Map<String, Object?>? statementReport;
  Future<void> loadStatement({
    required String supplierId,
    String? supplierName,
    required String currency,
    required String asOf,
    required List<int> buckets,
  }) => run(() async {
    if (!online ||
        !(canManage || canPost || canAllocate || canReverse) ||
        form != null) {
      return;
    }
    statementReport = await gateway.statement(
      scope,
      supplierId: supplierId,
      currency: currency,
      asOf: asOf,
      buckets: buckets,
    );
    statementReport = {
      ...statementReport!,
      'supplier_name': supplierName ?? supplierId,
    };
  });
  QuotationLocalDraft? local;
  int? version;
  List<Map<String, Object?>> eligible = [];
  CursorPage<Map<String, Object?>> page = CursorPage(items: [], limit: 50);
  bool get locked =>
      _disposed ||
      busy ||
      local?.pending != null ||
      local?.errorCode == 'VERSION_CONFLICT';
  bool get ownProposal =>
      selected != null &&
      [
        'created_by',
        'prepared_by',
        'submitted_by',
      ].any((k) => selected![k] == scope.actorId);
  String get proposedTotal {
    try {
      var total = ExactDecimal.zero(scale: 6);
      for (final raw in form?['lines'] as List? ?? []) {
        final row = raw as Map,
            amount = GoodsReceiptQuantity.decimal(raw['amount']);
        total = row['kind'] == 'credit' ? total - amount : total + amount;
      }
      return total.toDecimalString();
    } on FormatException {
      return 'Enter valid amounts';
    }
  }

  void emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void setOnline(bool value) {
    online = value;
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

  Future<CursorPage<Map<String, Object?>>> fetch({String? after}) =>
      showingPayments
      ? gateway.payments(scope, after: after)
      : gateway.proposals(scope, after: after);
  Future<void> initialize() => run(() async {
    local = await drafts.load(scope, slot);
    if (_disposed) return;
    form = local?.form;
    version = local?.expectedVersion;
    if (online) page = await fetch();
  });
  Future<void> refresh({bool more = false, bool? payments}) => run(() async {
    if (!online || form != null) return;
    if (payments != null) {
      showingPayments = payments;
      selected = null;
    }
    final result = await fetch(after: more ? page.nextCursor : null);
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

  Future<void> create() => run(() async {
    if (!canManage || form != null || local != null) return;
    form = {
      'id': const Uuid().v4(),
      '_mode': 'proposal',
      'document_date': DateTime.now().toIso8601String().substring(0, 10),
      'lines': <Map<String, Object?>>[],
    };
    version = null;
    eligible = [];
    itemCursor = null;
    await drafts.save(scope, slot, form!);
  });
  Future<void> edit(Map<String, Object?> row) => run(() async {
    if (!canManage ||
        form != null ||
        local != null ||
        row['status'] != 'draft') {
      return;
    }
    form = {...row, '_mode': 'proposal'};
    version = row['version'] as int;
    eligible = [];
    itemCursor = null;
    await drafts.save(scope, slot, form!, expectedVersion: version);
  });
  void update(String key, Object? value) {
    if (locked || form == null) return;
    form = {...form!, key: value};
    if (['_target_currency', 'posting_date'].contains(key)) {
      allocationRates = [];
      rateCursor = null;
      form = {...form!, 'exchange_rate_id': null};
    }
    if ([
      'supplier_id',
      'cash_bank_account_id',
      'document_date',
    ].contains(key)) {
      eligible = [];
      itemCursor = null;
    }
    emit();
  }

  void chooseSupplier(Map<String, Object?> row) {
    if (locked || form == null) return;
    update('supplier_id', row['id']);
    update('_supplier_name', row['name']);
    update('lines', <Map<String, Object?>>[]);
  }

  void chooseBank(Map<String, Object?> row) {
    if (locked || form == null) return;
    update('cash_bank_account_id', row['id']);
    update('_bank_name', row['name']);
    update('currency_code', row['currency_code']);
    update('exchange_rate_id', null);
    update('_rate_name', null);
    update('lines', <Map<String, Object?>>[]);
  }

  void validateDate() {
    final value = form?['document_date'];
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
      throw const FormatException('Enter a valid payment date (YYYY-MM-DD).');
    }
  }

  Future<void> loadItems({bool more = false}) => run(() async {
    if (!online ||
        form == null ||
        local?.pending != null ||
        local?.errorCode == 'VERSION_CONFLICT') {
      return;
    }
    validateDate();
    if (form!['supplier_id'] == null || form!['cash_bank_account_id'] == null) {
      throw const FormatException(
        'Choose the supplier and payment bank first.',
      );
    }
    final result = await gateway.payableItems(
      scope,
      form!,
      after: more ? itemCursor : null,
    );
    if (_disposed) return;
    eligible = [
      if (more) ...eligible,
      for (final raw in result['items'] as List)
        (raw as Map).cast<String, Object?>(),
    ];
    itemCursor = result['next_cursor'] as String?;
    message = eligible.isEmpty
        ? 'No eligible open items for these filters.'
        : null;
  });
  void addItem(Map<String, Object?> row) {
    if (locked || form == null || row['claimed'] == true) return;
    final lines = form!['lines'] as List;
    if (lines.any((x) => (x as Map)['open_item_id'] == row['id'])) return;
    final residual = (row['residual'] as Map)['amount'] as String;
    update('lines', [
      ...lines,
      {
        'open_item_id': row['id'],
        'document_number': row['document_number'],
        'due_date': row['due_date'],
        'kind': row['kind'],
        'currency_code': row['currency_code'],
        'amount': residual.startsWith('-') ? residual.substring(1) : residual,
      },
    ]);
  }

  void amount(String id, String value) => update('lines', [
    for (final raw in form?['lines'] as List? ?? [])
      {
        ...(raw as Map).cast<String, Object?>(),
        if (raw['open_item_id'] == id) 'amount': value,
      },
  ]);
  void remove(String id) => update('lines', [
    for (final raw in form?['lines'] as List? ?? [])
      if ((raw as Map)['open_item_id'] != id) raw,
  ]);
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
    eligible = [];
  });
  Future<void> saveServer() => run(() async {
    if (!online || form == null || local?.errorCode == 'VERSION_CONFLICT') {
      return;
    }
    var pending = local?.pending;
    if (pending == null) {
      if (['allocation', 'correction'].contains(form!['_mode'])) {
        await prepareCorrection();
        return;
      }
      if (!canManage) return;
      if (form!['_mode'] != 'proposal') {
        throw const FormatException(
          'Discard this rejected action and reload the proposal to continue.',
        );
      }
      validateDate();
      if (form!['supplier_id'] == null ||
          form!['cash_bank_account_id'] == null) {
        throw const FormatException('Choose the supplier and payment bank.');
      }
      final lines = form!['lines'] as List;
      if (lines.isEmpty || lines.length > 500) {
        throw const FormatException('Select 1 to 500 payable items.');
      }
      for (final raw in lines) {
        if (!GoodsReceiptQuantity.decimal((raw as Map)['amount']).isPositive) {
          throw const FormatException('Each selected amount must be positive.');
        }
      }
      if (!ExactDecimal.parse(proposedTotal, scale: 6).isPositive) {
        throw const FormatException(
          'Bills less credits must leave a positive payment.',
        );
      }
      final payload = <String, Object?>{
        for (final key in [
          'id',
          'supplier_id',
          'cash_bank_account_id',
          'document_date',
          'exchange_rate_id',
        ])
          key: form![key],
        'lines': [
          for (final raw in lines)
            {
              'open_item_id': (raw as Map)['open_item_id'],
              'amount': raw['amount'],
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
  Future<void> action(String action, {String? reason, String? reference}) =>
      run(() async {
        if (!online ||
            selected == null ||
            form != null ||
            local != null ||
            showingPayments) {
          return;
        }
        final status = selected!['status'];
        if (action == 'post' ? !canPost || status != 'approved' : !canManage) {
          return;
        }
        if (['approve', 'reject'].contains(action) &&
            (!canApprove || ownProposal || status != 'pending_approval')) {
          return;
        }
        if (action == 'submit' && status != 'draft') return;
        if (['recall', 'reject', 'cancel'].contains(action) &&
            (reason == null || reason.trim().isEmpty)) {
          throw const FormatException('Enter the reason for this decision.');
        }
        if (action == 'post' &&
            (reference == null || reference.trim().isEmpty)) {
          throw const FormatException('Enter the recorded payment reference.');
        }
        if (![
          'submit',
          'approve',
          'reject',
          'recall',
          'cancel',
          'post',
        ].contains(action)) {
          throw const FormatException('Unknown payment action.');
        }
        form = {...selected!, '_mode': 'action'};
        version = selected!['version'] as int;
        await drafts.save(scope, slot, form!, expectedVersion: version);
        final payload = <String, Object?>{
          'document_id': selected!['id'],
          if (action == 'post')
            'reference': reference!.trim()
          else if (action == 'approve' || action == 'reject')
            'decision': action == 'approve' ? 'approved' : 'rejected'
          else
            'action': action,
          'reason': ?reason,
        };
        final pending = await drafts.prepare(
          scope,
          slot,
          verb: action == 'post' ? 'accept' : action,
          payload: payload,
          expectedVersion: version,
        );
        local = await drafts.load(scope, slot);
        await send(pending);
      });
  Future<void> send(QuotationPendingCommand pending) async {
    if (_disposed || !online) return;
    late Map<String, Object?> result;
    try {
      result = switch (pending.verb) {
        'save' => await gateway.saveProposal(pending.envelope),
        'accept' => await gateway.postPayment(pending.envelope),
        'expire' => await gateway.correctAllocation(
          pending.envelope.payload.containsKey('allocation_id')
              ? 'reverse'
              : 'allocate',
          pending.envelope,
        ),
        'submit' ||
        'approve' ||
        'reject' ||
        'recall' ||
        'cancel' => await gateway.transitionProposal(pending.envelope),
        _ => throw const FormatException('Unknown saved payment command.'),
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
    eligible = [];
    selected = result;
    if (pending.verb == 'expire') {
      selected = null;
      itemDetail = null;
      statementReport = null;
    }
    if (pending.verb == 'accept') showingPayments = true;
    message = pending.verb == 'expire'
        ? 'Allocation correction recorded. Reload the statement to see current balances.'
        : pending.verb == 'accept'
        ? 'Supplier payment recorded. Awaiting bank reconciliation.'
        : 'Payment proposal ${result['status']}.';
    try {
      page = await fetch();
    } catch (_) {
      error =
          'Saved successfully. Refresh the register when the connection returns.';
    }
  }
}

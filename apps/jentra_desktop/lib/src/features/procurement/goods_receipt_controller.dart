import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import '../operations/operational_read_access.dart';
import 'procurement_controller.dart';

final goodsReceiptControllerProvider =
    Provider.autoDispose<GoodsReceiptController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider);
      final gateway = ref.watch(procurementGatewayProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway is! GoodsReceiptGateway ||
          caps.isLoading ||
          caps.hasError ||
          !((caps.value?.contains('procurement.receipts.post') ?? false) ||
              (caps.value?.contains('finance.setup.manage') ?? false))) {
        return null;
      }
      final c = GoodsReceiptController(
        scope: scope,
        gateway: gateway as GoodsReceiptGateway,
        references: gateway!,
        drafts: QuotationDraftStore.procurement(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
        canPost: caps.value?.contains('procurement.receipts.post') ?? false,
        canSetup: caps.value?.contains('finance.setup.manage') ?? false,
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

final class GoodsReceiptController extends ChangeNotifier
    implements OperationalReadAccess {
  GoodsReceiptController({
    required this.scope,
    required this.gateway,
    required this.references,
    required this.drafts,
    required this.online,
    this.canPost = true,
    this.canSetup = false,
    this.canApprove = false,
  });
  final TenantContext scope;
  final GoodsReceiptGateway gateway;
  final ProcurementGateway references;
  final QuotationDraftStore drafts;
  final bool canPost, canSetup, canApprove;
  bool get canAllow =>
      canPost && canApprove && gateway is ReceiptAllowanceGateway;
  static const slot = 'goods-receipt-editor';
  bool online, busy = false, _disposed = false, accessDenied = false;
  int _epoch = 0, _operationEpoch = 0;
  @override
  int get readAccessEpoch => _epoch;
  @override
  bool currentRead(int epoch) =>
      !_disposed && online && !accessDenied && epoch == _epoch;
  @override
  void denyReadAccess() {
    if (_disposed) return;
    accessDenied = true;
    _epoch++;
    clearServer();
    emit();
  }

  bool get currentServer => !_disposed && online && _operationEpoch == _epoch;
  void confirmedReadFailure(Object failure, int epoch, String fallback) {
    if (_disposed || epoch != _epoch) return;
    if (failure is DomainError &&
        const {
          'PERMISSION_DENIED',
          'ACCESS_DENIED',
          'MFA_REQUIRED',
          'AUTHENTICATION_REQUIRED',
        }.contains(failure.code)) {
      accessDenied = true;
      _epoch++;
      clearServer();
      error = failure.message;
      return;
    }
    error = fallback;
  }

  void clearServer() {
    page = CursorPage(items: [], limit: 50);
    selected = null;
  }

  String? error, message;
  Map<String, Object?>? form, selected;
  QuotationLocalDraft? local;
  int? version;
  CursorPage<Map<String, Object?>> page = CursorPage(items: [], limit: 50);
  bool get locked =>
      _disposed ||
      accessDenied ||
      busy ||
      local?.pending != null ||
      local?.errorCode == 'VERSION_CONFLICT';
  void emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    clearServer();
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
    if (_disposed || busy) return;
    busy = true;
    error = null;
    _operationEpoch = _epoch;
    emit();
    try {
      await action();
    } catch (e) {
      if (_disposed || _operationEpoch != _epoch) return;
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
    form = local?.form;
    version = local?.expectedVersion;
    if (online && canPost) {
      final result = await gateway.receipts(scope);
      if (currentServer) {
        page = result;
        accessDenied = false;
      }
    }
  });
  Future<void> refresh({bool more = false}) => run(() async {
    if (!online || !canPost) return;
    final result = await gateway.receipts(
      scope,
      after: more ? page.nextCursor : null,
    );
    if (!currentServer) return;
    page = CursorPage(
      items: [if (more) ...page.items, ...result.items],
      limit: 50,
      nextCursor: result.nextCursor,
    );
    accessDenied = false;
  });
  void select(Map<String, Object?> row) {
    if (!locked && form == null) {
      selected = row;
      emit();
    }
  }

  Future<void> create(Map<String, Object?> order) => run(() async {
    if (!canPost ||
        form != null ||
        local != null ||
        order['status'] != 'approved') {
      return;
    }
    form = {
      'id': const Uuid().v4(),
      '_mode': 'receipt',
      'order_id': order['id'],
      '_order_number': order['document_number'],
      'warehouse_id': order['warehouse_id'],
      'document_date': DateTime.now().toIso8601String().substring(0, 10),
      'reference': '',
      'lines': [
        for (final raw in order['lines'] as List)
          {
            ...(raw as Map).cast<String, Object?>(),
            'order_line_id': raw['line_id'],
            'line_id': const Uuid().v4(),
            'accepted_quantity': '0',
            'rejected_quantity': '0',
            'rejection_reason': '',
            'lot_code': null,
            'manufacture_date': null,
            'expiry_date': null,
            'serial_codes': <String>[],
          },
      ],
    };
    version = order['version'] as int;
    await drafts.save(scope, slot, form!, expectedVersion: version);
  });
  Future<void> configure() => run(() async {
    if (!canSetup || !online || form != null || local != null) return;
    final result = await references.references(scope, 'receipt_controls');
    if (!currentServer || accessDenied) return;
    final rows = result['items'] as List;
    final current = rows.isEmpty
        ? <String, Object?>{}
        : (rows.first as Map).cast<String, Object?>();
    form = {...current, 'id': scope.legalEntityId, '_mode': 'controls'};
    version = current['version'] as int?;
    await drafts.save(scope, slot, form!, expectedVersion: version);
  });
  Future<void> createAllowance(Map<String, Object?> order) => run(() async {
    if (!canAllow ||
        form != null ||
        local != null ||
        order['status'] != 'approved') {
      return;
    }
    if ([
      'created_by',
      'commercial_editor_id',
      'submitted_by',
    ].any((key) => order[key] == scope.actorId)) {
      throw const FormatException(
        'An independent approver must approve extra quantities on this order.',
      );
    }
    form = {
      'id': const Uuid().v4(),
      '_mode': 'allowance',
      'order_id': order['id'],
      '_order_number': order['document_number'],
      '_source_lines': order['lines'],
      'order_line_id': null,
      'extra_quantity': '0',
      'reason': '',
    };
    version = order['version'] as int;
    await drafts.save(scope, slot, form!, expectedVersion: version);
  });
  void update(String key, Object? value) {
    if (locked || form == null) return;
    form = {...form!, key: value};
    emit();
  }

  void updateLine(String id, String key, Object? value) {
    if (locked || form == null || form!['lines'] is! List) return;
    final lines = [
      for (final raw in form!['lines'] as List)
        {
          ...(raw as Map).cast<String, Object?>(),
          if (raw['line_id'] == id) key: value,
        },
    ];
    update('lines', lines);
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
  void date(Object? value) {
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
      throw const FormatException('Enter a valid date as YYYY-MM-DD.');
    }
  }

  Future<void> reverse(String postingDate, String reason) => run(() async {
    if (!online ||
        !canPost ||
        form != null ||
        local != null ||
        selected?['status'] != 'posted') {
      return;
    }
    date(postingDate);
    if (reason.trim().isEmpty) {
      throw const FormatException('Enter a reversal reason.');
    }
    form = {
      ...selected!,
      '_mode': 'reversal',
      'document_date': postingDate,
      'reason': reason,
    };
    final documentId = selected!['id'];
    version = selected!['version'] as int;
    await drafts.save(scope, slot, form!, expectedVersion: version);
    final pending = await drafts.prepare(
      scope,
      slot,
      verb: 'cancel',
      expectedVersion: version,
      payload: {
        'document_id': documentId,
        'document_date': postingDate,
        'reason': reason,
      },
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
      final allowance = form!['_mode'] == 'allowance';
      if (controls ? !canSetup : !canPost) return;
      final payload = <String, Object?>{'id': form!['id']};
      if (controls) {
        for (final key in ['grni_account_id', 'expense_account_id']) {
          if (form![key] == null) {
            throw const FormatException('Choose both posting accounts.');
          }
          payload[key] = form![key];
        }
        final percent = form!['maximum_over_receipt_percent'] ?? '0';
        if (GoodsReceiptQuantity.decimal(percent)
                .compareTo(GoodsReceiptQuantity.decimal('100')) >
            0) {
          throw const FormatException(
            'Enter a maximum percentage from 0 to 100.',
          );
        }
        payload['maximum_over_receipt_percent'] = percent;
      } else if (allowance) {
        if (!canAllow) return;
        if (form!['order_line_id'] == null ||
            (form!['reason'] as String? ?? '').trim().isEmpty ||
            !GoodsReceiptQuantity.decimal(form!['extra_quantity']).isPositive) {
          throw const FormatException(
            'Choose a line, positive extra quantity and reason.',
          );
        }
        for (final key in [
          'order_id',
          'order_line_id',
          'extra_quantity',
          'reason',
        ]) {
          payload[key] = form![key];
        }
      } else {
        if (form!['_mode'] != 'receipt') {
          throw const FormatException(
            'Reload the receipt before reversing it.',
          );
        }
        date(form!['document_date']);
        if ((form!['reference'] as String? ?? '').trim().isEmpty) {
          throw const FormatException('Enter the supplier delivery reference.');
        }
        for (final key in [
          'order_id',
          'warehouse_id',
          'document_date',
          'reference',
        ]) {
          payload[key] = form![key];
        }
        final lines = <Map<String, Object?>>[];
        for (final raw in form!['lines'] as List) {
          final l = (raw as Map).cast<String, Object?>();
          final q = GoodsReceiptQuantity(
            accepted: l['accepted_quantity'],
            rejected: l['rejected_quantity'],
            numerator: l['conversion_numerator'],
            denominator: l['conversion_denominator'],
          );
          if (q.empty) continue;
          var maximum = GoodsReceiptQuantity.decimal(l['remaining_quantity']);
          if (l['_allowance'] case final Map allowance) {
            if (allowance['approved_by'] != scope.actorId) {
              maximum =
                  GoodsReceiptQuantity.decimal(
                    allowance['maximum_received_quantity'],
                  ) -
                  GoodsReceiptQuantity.decimal(l['received_quantity']);
            }
          }
          if (q.acceptedQuantity.compareTo(maximum) > 0) {
            throw const FormatException(
              'Accepted quantity exceeds this order line’s remaining quantity.',
            );
          }
          if (!q.rejectedQuantity.isZero &&
              (l['rejection_reason'] as String? ?? '').trim().isEmpty) {
            throw const FormatException('Explain each rejected quantity.');
          }
          lines.add({
            for (final key in [
              'line_id',
              'order_line_id',
              'accepted_quantity',
              'rejected_quantity',
              'rejection_reason',
              'lot_code',
              'manufacture_date',
              'expiry_date',
              'serial_codes',
            ])
              key: l[key],
          });
        }
        if (lines.isEmpty || lines.length > 500) {
          throw const FormatException(
            'Enter quantities on 1 to 500 receipt lines.',
          );
        }
        payload['lines'] = lines;
      }
      await drafts.save(scope, slot, form!, expectedVersion: version);
      pending = await drafts.prepare(
        scope,
        slot,
        verb: controls
            ? 'save'
            : allowance
            ? 'approve'
            : 'submit',
        payload: payload,
        expectedVersion: version,
      );
      local = await drafts.load(scope, slot);
    }
    await send(pending);
  });
  Future<void> send(QuotationPendingCommand pending) async {
    if (!currentServer || accessDenied) return;
    late Map<String, Object?> result;
    try {
      result = switch (pending.verb) {
        'submit' => await gateway.postReceipt(pending.envelope),
        'cancel' => await gateway.reverseReceipt(pending.envelope),
        'save' => await gateway.saveReceiptControls(pending.envelope),
        'approve' =>
          await (gateway as ReceiptAllowanceGateway).approveReceiptAllowance(
            pending.envelope,
          ),
        _ => throw const FormatException('Unknown saved receipt command.'),
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
    message = 'Goods receipt action confirmed.';
    if (!currentServer) return;
    if (pending.verb != 'save' && pending.verb != 'approve') selected = result;
    message = pending.verb == 'save'
        ? 'Receipt posting accounts saved.'
        : pending.verb == 'approve'
        ? 'Receipt allowance approved. A different poster can reload this order and receive within the allowance.'
        : 'Goods receipt ${result['status']}.';
    if (canPost) {
      final refreshEpoch = _epoch;
      try {
        final refreshed = await gateway.receipts(scope);
        if (currentServer) page = refreshed;
      } catch (failure) {
        confirmedReadFailure(
          failure,
          refreshEpoch,
          'Saved successfully. Refresh the register when the connection returns.',
        );
      }
    }
  }
}

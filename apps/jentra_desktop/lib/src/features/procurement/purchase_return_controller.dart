import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:uuid/uuid.dart';
import '../../app_providers.dart';
import 'procurement_controller.dart';

final purchaseReturnControllerProvider =
    Provider.autoDispose<PurchaseReturnController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider);
      final gateway = ref.watch(procurementGatewayProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway is! PurchaseReturnGateway ||
          caps.isLoading ||
          caps.hasError ||
          !(caps.value?.contains('procurement.returns.post') ?? false)) {
        return null;
      }
      final c = PurchaseReturnController(
        scope: scope,
        gateway: gateway as PurchaseReturnGateway,
        drafts: QuotationDraftStore.procurement(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
      );
      ref.listen(
        connectivityStateProvider,
        (_, state) => c.setOnline(state.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

final class PurchaseReturnController extends ChangeNotifier {
  PurchaseReturnController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.online,
  });
  final TenantContext scope;
  final PurchaseReturnGateway gateway;
  final QuotationDraftStore drafts;
  static const slot = 'purchase-return-editor';
  bool online, busy = false, _disposed = false;
  String? error, message, sourceKind, sourceCursor;
  String sourceSearch = '';
  Map<String, Object?>? form, selected;
  QuotationLocalDraft? local;
  List<Map<String, Object?>> sources = [];
  CursorPage<Map<String, Object?>> page = CursorPage(items: [], limit: 50);
  bool get locked => _disposed || busy || local?.pending != null;
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
    if (_disposed || busy) return;
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
    if (online) page = await gateway.returns(scope);
  });
  Future<void> refresh({bool more = false}) => run(() async {
    if (!online) return;
    final result = await gateway.returns(
      scope,
      after: more ? page.nextCursor : null,
    );
    if (!_disposed) {
      page = CursorPage(
        items: [if (more) ...page.items, ...result.items],
        limit: 50,
        nextCursor: result.nextCursor,
      );
    }
  });
  Future<void> findSources(
    String kind, {
    bool more = false,
    String search = '',
  }) => run(() async {
    if (!online || form != null || !['bill', 'receipt'].contains(kind)) return;
    final result = await gateway.returnSources(
      scope,
      kind,
      after: more ? sourceCursor : null,
      search: more ? sourceSearch : search,
    );
    if (_disposed) return;
    sourceKind = kind;
    if (!more) sourceSearch = search;
    sources = [
      if (more) ...sources,
      for (final raw in result['items'] as List)
        (raw as Map).cast<String, Object?>(),
    ];
    sourceCursor = result['next_cursor'] as String?;
  });
  Future<void> create(String kind, String sourceId) => run(() async {
    if (!online || form != null || local != null) return;
    final source = await gateway.returnSource(scope, kind, sourceId);
    if (_disposed) return;
    form = {
      'id': const Uuid().v4(),
      'source_kind': kind,
      'source_id': sourceId,
      '_source_number': source['document_number'],
      '_supplier_name': source['supplier_name'],
      'currency_code': source['currency_code'],
      '_rounding_scale': source['rounding_scale'],
      'document_date': DateTime.now().toUtc().toIso8601String().substring(
        0,
        10,
      ),
      'reason': '',
      'reference': '',
      'lines': [
        for (final raw in source['lines'] as List)
          {
            ...(raw as Map).cast<String, Object?>(),
            'line_id': const Uuid().v4(),
            '_original_quantity': raw['quantity'] ?? raw['accepted_quantity'],
            'quantity': '0',
            'serial_ids': <String>[],
          },
      ],
    };
    selected = null;
    sourceKind = null;
    sources = [];
    await drafts.save(scope, slot, form!);
    local = await drafts.load(scope, slot);
  });
  void update(String key, Object? value) {
    if (locked || form == null) return;
    form = {...form!, key: value};
    emit();
  }

  ({String total, String tax}) get preview {
    final f = form!;
    final scale = f['_rounding_scale'];
    if (scale is! int) {
      throw const FormatException(
        'Reload the source to obtain its currency precision.',
      );
    }
    var total = ExactDecimal.zero(scale: 6), tax = ExactDecimal.zero(scale: 6);
    for (final raw in f['lines'] as List) {
      final l = raw as Map;
      if (GoodsReceiptQuantity.decimal(l['quantity']).isZero) continue;
      final amount = PurchaseReturnAmount(
        originalQuantity: l['_original_quantity'],
        consumedQuantity: l['returned_quantity'],
        returnQuantity: l['quantity'],
        netAmount: l['net_amount'],
        taxAmount: l['tax_amount'] ?? '0',
        roundingScale: scale,
      );
      total = total + amount.total;
      tax = tax + amount.tax;
    }
    return (
      total: total.rescale(scale).toString(),
      tax: tax.rescale(scale).toString(),
    );
  }

  void line(int index, String key, Object? value) {
    if (locked || form == null) return;
    final lines = [...form!['lines'] as List];
    lines[index] = {
      ...(lines[index] as Map).cast<String, Object?>(),
      key: value,
    };
    form = {...form!, 'lines': lines};
    emit();
  }

  Future<void> saveLocal() => run(() async {
    if (form == null || local?.pending != null) return;
    await drafts.save(scope, slot, form!);
    local = await drafts.load(scope, slot);
    message = 'Return draft saved securely on this device.';
  });
  Future<bool> canLeave() async {
    if (busy) return false;
    if (form == null || local?.pending != null) return true;
    var saved = false;
    await run(() async {
      await drafts.save(scope, slot, form!);
      saved = true;
    });
    return saved;
  }

  Future<void> discard() => run(() async {
    await drafts.discard(scope, slot);
    form = null;
    local = null;
  });
  Future<void> post() => run(() async {
    if (!online || form == null) return;
    var pending = local?.pending;
    if (pending == null) {
      final f = form!;
      preview; // Fail closed if the frozen-source financial preview is invalid.
      final date = f['document_date'] as String? ?? '';
      final parsed = DateTime.tryParse(date);
      if (parsed == null || parsed.toIso8601String().substring(0, 10) != date) {
        throw const FormatException('Enter a valid date as YYYY-MM-DD.');
      }
      for (final key in ['reason', 'reference']) {
        final text = (f[key] as String? ?? '').trim();
        if (text.isEmpty || text.length > (key == 'reason' ? 1000 : 140)) {
          throw const FormatException(
            'Enter a return reason and supplier reference within their limits.',
          );
        }
      }
      final lines = <Map<String, Object?>>[];
      for (final raw in f['lines'] as List) {
        final l = (raw as Map).cast<String, Object?>();
        final quantity = GoodsReceiptQuantity(
          accepted: l['quantity'],
          rejected: '0',
          numerator: l['conversion_numerator'],
          denominator: l['conversion_denominator'],
        );
        if (quantity.empty) continue;
        if (quantity.acceptedQuantity.compareTo(
              GoodsReceiptQuantity.decimal(l['eligible_quantity']),
            ) >
            0) {
          throw const FormatException(
            'Return quantity exceeds the source line’s remaining eligibility.',
          );
        }
        final serials = (l['serial_ids'] as List).cast<String>();
        if ((l['serial_options'] as List).isNotEmpty &&
            quantity.baseQuantity.compareTo(
                  GoodsReceiptQuantity.decimal(serials.length.toString()),
                ) !=
                0) {
          throw const FormatException(
            'Select one original serial for each returned base unit.',
          );
        }
        lines.add({
          for (final key in [
            'line_id',
            'source_line_id',
            'quantity',
            'serial_ids',
          ])
            key: l[key],
        });
      }
      if (lines.isEmpty || lines.length > 500) {
        throw const FormatException(
          'Enter positive quantities on 1 to 500 lines.',
        );
      }
      await drafts.save(scope, slot, f);
      pending = await drafts.prepare(
        scope,
        slot,
        verb: 'submit',
        payload: {
          for (final key in [
            'id',
            'source_kind',
            'source_id',
            'document_date',
            'reason',
            'reference',
          ])
            key: f[key],
          'lines': lines,
        },
      );
      local = await drafts.load(scope, slot);
    }
    if (pending.verb != 'submit') {
      throw const FormatException('Unknown saved return command.');
    }
    Map<String, Object?> result;
    try {
      result = await gateway.postReturn(pending.envelope);
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
    selected = result;
    form = null;
    local = null;
    message =
        'Purchase return posted. Source documents and posting evidence are retained.';
    try {
      page = await gateway.returns(scope);
    } catch (_) {
      error =
          'Posted successfully. Refresh the register when the connection returns.';
    }
  });
}

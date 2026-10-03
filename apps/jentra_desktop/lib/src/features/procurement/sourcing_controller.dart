import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import '../operations/operational_read_access.dart';
import 'procurement_controller.dart';

final sourcingControllerProvider = Provider.autoDispose<SourcingController?>((
  ref,
) {
  final scope = ref.watch(activeTenantContextProvider),
      gateway = ref.watch(procurementGatewayProvider);
  final caps = ref.watch(businessCapabilitiesProvider);
  if (scope == null ||
      !scope.hasOperationalScope ||
      gateway == null ||
      caps.isLoading ||
      caps.hasError ||
      !(caps.value?.contains('procurement.rfq.manage') ?? false)) {
    return null;
  }
  final controller = SourcingController(
    scope: scope,
    gateway: gateway,
    drafts: QuotationDraftStore.procurement(
      ref.watch(encryptedDraftRepositoryProvider),
    ),
    online: procurementVerifiedOnline(ref.read(connectivityStateProvider)),
  );
  ref.listen(
    connectivityStateProvider,
    (_, v) => controller.setOnline(procurementVerifiedOnline(v)),
  );
  ref.onDispose(controller.dispose);
  unawaited(controller.initialize());
  return controller;
});

final class SourcingController extends ChangeNotifier
    implements OperationalReadAccess {
  SourcingController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.online,
  });
  final TenantContext scope;
  final ProcurementGateway gateway;
  final QuotationDraftStore drafts;
  static const slot = 'rfq-editor';
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
    baseCurrency = null;
  }

  String? error, message, baseCurrency;
  Map<String, Object?>? form, selected;
  int? version;
  QuotationLocalDraft? local;
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

  void setOnline(bool v) {
    if (online != v) {
      online = v;
      _epoch++;
      clearServer();
    }
    emit();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    clearServer();
    notifyListeners();
    super.dispose();
  }

  Future<void> run(Future<void> Function() work) async {
    if (busy || _disposed) return;
    busy = true;
    _operationEpoch = _epoch;
    error = null;
    emit();
    try {
      await work();
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
          : 'Unable to complete the action. Saved work is retained.';
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
    if (online) {
      final refs = await gateway.references(scope, 'suppliers');
      if (!currentServer) return;
      if (_disposed) return;
      baseCurrency = refs['base_currency'] as String;
      final result = await gateway.rfqs(scope);
      if (currentServer) {
        page = result;
        accessDenied = false;
      }
    }
  });
  Future<void> refresh({bool more = false}) => run(() async {
    if (!online) return;
    final result = await gateway.rfqs(
      scope,
      after: more ? page.nextCursor : null,
    );
    if (!currentServer) return;
    accessDenied = false;
    page = CursorPage(
      items: [if (more) ...page.items, ...result.items],
      limit: 50,
      nextCursor: result.nextCursor,
    );
  });
  void select(Map<String, Object?> row) {
    if (locked || form != null) return;
    selected = row;
    emit();
  }

  Future<void> issue(Map<String, Object?> requisition) => run(() async {
    if (form != null || local != null) return;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    form = {
      'id': const Uuid().v4(),
      'operation': 'issue',
      'title': requisition['justification'],
      'requisition_id': requisition['id'],
      'requisition_version': requisition['version'],
      'source_line_ids': (requisition['lines'] as List)
          .map((l) => (l as Map)['line_id'])
          .toList(),
      '_source_lines': requisition['lines'],
      'document_date': today,
      'close_date': today,
      'invited_supplier_ids': <String>[],
      '_supplier_labels': <Map<String, Object?>>[],
      '_source_number': requisition['document_number'],
    };
    version = null;
    await drafts.save(scope, slot, form!);
  });
  Future<void> quote(Map<String, Object?> supplier) => run(() async {
    if (form != null || local != null || selected?['status'] != 'issued') {
      return;
    }
    final existing = (selected!['quotes'] as List)
        .cast<Map>()
        .where((q) => q['supplier_id'] == supplier['id'])
        .firstOrNull;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    form = {
      'id': selected!['id'],
      'operation': 'record_quote',
      'quote_id': existing?['id'] ?? const Uuid().v4(),
      'supplier_id': supplier['id'],
      '_supplier_name': supplier['name'],
      'quote_date': existing?['quote_date'] ?? today,
      'valid_until': existing?['valid_until'] ?? today,
      'currency_code': existing?['currency_code'] ?? baseCurrency,
      'exchange_rate': existing?['exchange_rate'] ?? '1',
      'exchange_rate_id': existing?['exchange_rate_id'],
      'rate_date': existing?['rate_date'] ?? today,
      'payment_terms': existing?['payment_terms'] ?? '',
      'delivery_terms': existing?['delivery_terms'] ?? '',
      'lines':
          existing?['lines'] ??
          (selected!['lines'] as List).map((x) {
            final l = x as Map;
            return <String, Object?>{
              'source_line_id': l['source_line_id'],
              'description': l['description'],
              'quantity': l['quantity'],
              'unit_price': '0',
              'discount_percent': '0',
              'tax_definition_id': null,
            };
          }).toList(),
    };
    version = selected!['version'] as int;
    await drafts.save(scope, slot, form!, expectedVersion: version);
  });
  Future<void> choose(Map<String, Object?> quote, String reason) =>
      run(() async {
        if (form != null ||
            local != null ||
            selected?['status'] != 'issued' ||
            quote['complete'] != true) {
          return;
        }
        form = {
          'id': selected!['id'],
          'operation': 'select',
          'quote_id': quote['id'],
          'selection_reason': reason,
          '_supplier_name': quote['supplier_name'],
        };
        version = selected!['version'] as int;
        await drafts.save(scope, slot, form!, expectedVersion: version);
        await send();
      });
  void update(String key, Object? value) {
    if (locked || form == null) return;
    form = {...form!, key: value};
    emit();
  }

  Future<void> saveLocal() => run(() async {
    if (locked && local?.pending != null) return;
    if (form != null) {
      await drafts.save(scope, slot, form!, expectedVersion: version);
      message = 'Saved securely on this device.';
    }
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
  Future<void> saveServer() => run(send);
  Future<void> send() async {
    if (!online || _disposed || form == null) return;
    var pending = local?.pending;
    if (pending == null) {
      if (form!['operation'] == 'record_quote') {
        for (final line in form!['lines'] as List) {
          for (final key in ['quantity', 'unit_price', 'discount_percent']) {
            final value = (line as Map)[key];
            if (value is! String ||
                !RegExp(r'^\d+(\.\d{1,6})?$').hasMatch(value)) {
              throw FormatException(
                'Enter an exact $key value with up to six decimal places.',
              );
            }
          }
        }
      }
      await drafts.save(scope, slot, form!, expectedVersion: version);
      pending = await drafts.prepare(
        scope,
        slot,
        verb: 'save',
        payload: {
          for (final e in form!.entries)
            if (!e.key.startsWith('_') && e.key != 'lines') e.key: e.value,
          if (form!['lines'] case final List lines)
            'lines': [
              for (final line in lines)
                {
                  for (final key in const [
                    'source_line_id',
                    'quantity',
                    'unit_price',
                    'discount_percent',
                    'tax_definition_id',
                  ])
                    key: (line as Map)[key],
                },
            ],
        },
        expectedVersion: version,
      );
      local = await drafts.load(scope, slot);
    }
    if (!currentServer || accessDenied) return;
    late final Map<String, Object?> result;
    try {
      result = await gateway.source(pending.envelope);
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
    if (!currentServer) {
      message = 'Action confirmed. Refresh after reconnecting.';
      return;
    }
    selected = result;
    message = 'Sourcing record saved · ${result['status']}';
    final refreshEpoch = _epoch;
    try {
      final refreshed = await gateway.rfqs(scope);
      if (currentServer) page = refreshed;
    } catch (failure) {
      confirmedReadFailure(
        failure,
        refreshEpoch,
        'Saved successfully. The register could not refresh; use Refresh to reload it.',
      );
    }
  }
}

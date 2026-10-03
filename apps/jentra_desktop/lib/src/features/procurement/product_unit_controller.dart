import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import '../operations/operational_read_access.dart';
import 'procurement_controller.dart';

final productUnitControllerProvider =
    Provider.autoDispose<ProductUnitController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider);
      final g = ref.watch(procurementGatewayProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          g is! ProductUnitGateway ||
          caps.isLoading ||
          caps.hasError ||
          !(caps.value?.contains('inventory.catalog.manage') ?? false)) {
        return null;
      }
      final c = ProductUnitController(
        scope: scope,
        gateway: g as ProductUnitGateway,
        references: g!,
        drafts: QuotationDraftStore.procurement(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        online: procurementVerifiedOnline(ref.read(connectivityStateProvider)),
      );
      ref.listen(
        connectivityStateProvider,
        (_, v) => c.setOnline(procurementVerifiedOnline(v)),
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

final class ProductUnitController extends ChangeNotifier
    implements OperationalReadAccess {
  ProductUnitController({
    required this.scope,
    required this.gateway,
    required this.references,
    required this.drafts,
    required this.online,
  });
  final TenantContext scope;
  final ProductUnitGateway gateway;
  final ProcurementGateway references;
  final QuotationDraftStore drafts;
  static const slot = 'product-unit-editor';
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
  }

  String? error, message;
  Map<String, Object?>? form;
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
    if (!_disposed) {
      notifyListeners();
    }
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

  Future<void> run(Future<void> Function() work) async {
    if (busy || _disposed) {
      return;
    }
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
      await loadPage();
    }
  });
  Future<void> loadPage({bool more = false}) async {
    final r = await references.references(
      scope,
      'unit_conversions',
      after: more ? page.nextCursor : null,
    );
    if (!currentServer) {
      return;
    }
    accessDenied = false;
    page = CursorPage(
      items: [
        if (more) ...page.items,
        ...(r['items'] as List).map(
          (x) => ((x as Map)['detail'] as Map).cast<String, Object?>(),
        ),
      ],
      limit: 50,
      nextCursor: r['next_cursor'] as String?,
    );
  }

  Future<void> refresh({bool more = false}) => run(() async {
    if (online) {
      await loadPage(more: more);
    }
  });
  Future<void> edit([Map<String, Object?>? row]) => run(() async {
    if (form != null || local != null) {
      return;
    }
    form = row == null
        ? {
            'id': const Uuid().v4(),
            'product_id': null,
            'unit_id': null,
            'numerator': '1',
            'denominator': '1',
            'status': 'active',
          }
        : Map<String, Object?>.from(row);
    version = row?['version'] as int?;
    await drafts.save(scope, slot, form!, expectedVersion: version);
  });
  void update(String key, Object? value) {
    if (locked || form == null) {
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
  Future<void> saveServer() => run(() async {
    if (!online || form == null) {
      return;
    }
    var pending = local?.pending;
    if (pending == null) {
      for (final k in ['numerator', 'denominator']) {
        final v = form![k];
        if (v is! String || !RegExp(r'^[1-9]\d{0,17}$').hasMatch(v)) {
          throw FormatException(
            'Enter $k as a positive integer of up to 18 digits.',
          );
        }
      }
      if (form!['product_id'] == null || form!['unit_id'] == null) {
        throw const FormatException('Choose a product and transaction unit.');
      }
      await drafts.save(scope, slot, form!, expectedVersion: version);
      pending = await drafts.prepare(
        scope,
        slot,
        verb: 'save',
        payload: {
          for (final k in [
            'id',
            'product_id',
            'unit_id',
            'numerator',
            'denominator',
            'status',
          ])
            k: form![k],
        },
        expectedVersion: version,
      );
      local = await drafts.load(scope, slot);
    }
    if (!currentServer || accessDenied) {
      return;
    }
    late final Map<String, Object?> result;
    try {
      result = await gateway.saveProductUnit(pending.envelope);
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
    if (_disposed) {
      return;
    }
    form = null;
    local = null;
    version = null;
    message = 'Product unit saved · version ${result['version']}';
    if (!currentServer) return;
    final refreshEpoch = _epoch;
    try {
      await loadPage();
    } catch (failure) {
      confirmedReadFailure(
        failure,
        refreshEpoch,
        'Saved successfully. Refresh the register to reload it.',
      );
    }
  });
}

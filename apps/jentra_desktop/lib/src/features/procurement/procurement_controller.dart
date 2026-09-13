import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:uuid/uuid.dart';
import '../../app_providers.dart';

final procurementGatewayProvider = Provider<ProcurementGateway?>((ref) => null);
final procurementControllerProvider =
    Provider.autoDispose<ProcurementController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      final gateway = ref.watch(procurementGatewayProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          caps.isLoading ||
          caps.hasError ||
          !(caps.value?.contains('procurement.requisitions.manage') ?? false) ||
          gateway == null) {
        return null;
      }
      final controller = ProcurementController(
        scope: scope,
        gateway: gateway,
        canApprove: caps.value!.contains('workflow.approvals.decide'),
        store: QuotationDraftStore.procurement(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
      );
      ref.listen(
        connectivityStateProvider,
        (_, next) =>
            controller.setOnline(next.value == ConnectivityState.online),
      );
      ref.onDispose(controller.dispose);
      unawaited(controller.initialize());
      return controller;
    });

final class ProcurementController extends ChangeNotifier {
  ProcurementController({
    required this.scope,
    required this.gateway,
    required this.store,
    required this.online,
    this.canApprove = false,
  });
  final TenantContext scope;
  final ProcurementGateway gateway;
  final QuotationDraftStore store;
  final bool canApprove;
  static const slot = 'requisition-editor';
  bool online, busy = false, _disposed = false;
  String? error, message;
  String? baseCurrency;
  Map<String, Object?>? form;
  Map<String, Object?>? selected;
  int? version;
  QuotationLocalDraft? recovery;
  List<Map<String, Object?>> units = [];
  CursorPage<Map<String, Object?>> page = CursorPage(items: [], limit: 50);
  bool get locked =>
      _disposed ||
      busy ||
      recovery?.pending != null ||
      recovery?.errorCode == 'VERSION_CONFLICT' ||
      (form?['status'] != null && form?['status'] != 'draft');
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void setOnline(bool value) {
    online = value;
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    _emit();
    try {
      await work();
    } catch (e) {
      error = e is DomainError
          ? e.message
          : 'Unable to complete this action. Your draft is retained.';
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> initialize() => _run(() async {
    recovery = await store.load(scope, slot);
    if (_disposed) return;
    form = recovery?.form;
    version = recovery?.expectedVersion;
    if (online) {
      final refs = await gateway.references(scope, 'units');
      baseCurrency = refs['base_currency'] as String;
      units = (refs['items'] as List)
          .map((r) => (r as Map).cast<String, Object?>())
          .toList();
      if (_disposed) return;
      page = await gateway.page(scope);
    }
  });
  Future<void> refresh({bool more = false}) => _run(() async {
    if (!online) return;
    final refs = await gateway.references(scope, 'units');
    baseCurrency = refs['base_currency'] as String;
    units = (refs['items'] as List)
        .map((r) => (r as Map).cast<String, Object?>())
        .toList();
    if (_disposed) return;
    final next = await gateway.page(
      scope,
      after: more ? page.nextCursor : null,
    );
    if (_disposed) return;
    page = CursorPage(
      items: [if (more) ...page.items, ...next.items],
      limit: 50,
      nextCursor: next.nextCursor,
    );
  });
  Future<void> create(String currency) => _run(() async {
    if (form != null || recovery != null) return;
    form = {
      'id': const Uuid().v4(),
      'need_by': DateTime.now().toIso8601String().substring(0, 10),
      'currency_code': currency,
      'justification': '',
      'lines': <Map<String, Object?>>[],
    };
    version = null;
    await store.save(scope, slot, form!, expectedVersion: null);
  });
  Future<void> edit(Map<String, Object?> document) => _run(() async {
    if (form != null || recovery != null || document['status'] != 'draft') {
      return;
    }
    form = {
      ...document,
      'lines': (document['lines'] as List)
          .map((l) => (l as Map).cast<String, Object?>())
          .toList(),
    };
    version = document['version'] as int;
    await store.save(scope, slot, form!, expectedVersion: version);
  });
  void update(String field, Object? value) {
    if (!locked && form != null) {
      form = {...form!, field: value};
      _emit();
    }
  }

  Future<void> saveLocal() => _run(() async {
    if (form == null || recovery?.pending != null) return;
    await store.save(scope, slot, form!, expectedVersion: version);
    message = 'Draft saved securely on this device.';
  });
  Future<bool> canLeave() async {
    if (busy) return false;
    if (form == null ||
        recovery?.pending != null ||
        recovery?.errorCode == 'VERSION_CONFLICT') {
      return true;
    }
    var saved = false;
    await _run(() async {
      await store.save(scope, slot, form!, expectedVersion: version);
      saved = true;
    });
    return saved;
  }

  Future<void> discard() => _run(() async {
    await store.discard(scope, slot);
    form = null;
    recovery = null;
    version = null;
    selected = null;
  });
  void select(Map<String, Object?> document) {
    if (busy || form != null || recovery != null) return;
    selected = document;
    _emit();
  }

  bool get ownRequest =>
      selected != null &&
      [
        'requester_id',
        'created_by',
        'updated_by',
        'submitted_by',
      ].any((key) => selected![key] == scope.actorId);
  bool get canDecide =>
      canApprove && !ownRequest && selected?['status'] == 'pending_approval';
  Future<void> transition(String verb, {String? reason}) => _run(() async {
    if (!online || selected == null || form != null || recovery != null) return;
    if ((verb == 'approve' || verb == 'reject') && !canDecide) return;
    final payload = <String, Object?>{
      'document_id': selected!['id'],
      if (verb == 'approve' || verb == 'reject')
        'decision': verb == 'approve' ? 'approved' : 'rejected'
      else
        'action': verb,
      'reason': ?reason,
    };
    await store.save(
      scope,
      slot,
      selected!,
      expectedVersion: selected!['version'] as int,
    );
    final pending = await store.prepare(
      scope,
      slot,
      verb: verb,
      payload: payload,
      expectedVersion: selected!['version'] as int,
    );
    recovery = await store.load(scope, slot);
    form = selected;
    version = selected!['version'] as int;
    await _send(pending);
  });
  Future<void> saveServer() => _run(() async {
    if (!online || form == null) return;
    QuotationPendingCommand? pending = recovery?.pending;
    if (pending == null) {
      if (form?['status'] != null && form?['status'] != 'draft') {
        throw const DomainError(
          code: 'INVALID_DOCUMENT_STATE',
          message:
              'Reload this requisition from the register before continuing.',
        );
      }
      final date = form!['need_by'];
      final parsed = date is String ? DateTime.tryParse(date) : null;
      if (date is! String ||
          parsed == null ||
          parsed.toIso8601String().substring(0, 10) != date ||
          '${form!['justification'] ?? ''}'.trim().isEmpty) {
        throw const DomainError(
          code: 'VALIDATION_ERROR',
          message: 'Enter a valid need-by date and justification.',
        );
      }
      final raw = form!['lines'];
      if (raw is! List || raw.isEmpty || raw.length > 500) {
        throw const DomainError(
          code: 'VALIDATION_ERROR',
          message: 'Add between 1 and 500 lines.',
        );
      }
      final ids = <String>{};
      final lines = raw
          .map(
            (l) => ProcurementLine.fromJson((l as Map).cast<String, Object?>()),
          )
          .toList();
      for (final line in lines) {
        if (!ids.add(line.lineId)) {
          throw const FormatException('Duplicate line identity.');
        }
      }
      await store.save(scope, slot, form!, expectedVersion: version);
      pending = await store.prepare(
        scope,
        slot,
        verb: 'save',
        payload: {...form!, 'lines': lines.map((l) => l.toJson()).toList()},
        expectedVersion: version,
      );
      recovery = await store.load(scope, slot);
    }
    await _send(pending);
  });
  Future<void> _send(QuotationPendingCommand pending) async {
    if (_disposed || !online) return;
    late final Map<String, Object?> result;
    try {
      result = pending.verb == 'save'
          ? await gateway.save(pending.envelope)
          : await gateway.transition(pending.envelope);
      await store.complete(scope, slot, pending.envelope.commandId);
    } on DomainError catch (e) {
      await store.recordFailure(
        scope,
        slot,
        e,
        commandId: pending.envelope.commandId,
      );
      recovery = await store.load(scope, slot);
      if (pending.verb != 'save' &&
          recovery?.pending == null &&
          e.code != 'VERSION_CONFLICT') {
        await store.discard(scope, slot);
        recovery = null;
        form = null;
        version = null;
      }
      rethrow;
    }
    if (_disposed) return;
    form = null;
    recovery = null;
    version = null;
    selected = result;
    message = 'Requisition ${result['status']} · version ${result['version']}';
    try {
      page = await gateway.page(scope);
    } catch (_) {
      error =
          'Saved successfully. The register could not refresh; use Refresh to reload it.';
    }
  }
}

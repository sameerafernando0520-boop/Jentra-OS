import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import '../../app_providers.dart';

final landedValueGatewayProvider = Provider<LandedValueGateway?>((ref) => null);
final landedValueControllerProvider =
    Provider.autoDispose<LandedValueController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider),
          gateway = ref.watch(landedValueGatewayProvider);
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
      final c = LandedValueController(
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

final class LandedValueController extends ChangeNotifier {
  LandedValueController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.online,
  });
  final TenantContext scope;
  final LandedValueGateway gateway;
  final QuotationDraftStore drafts;
  static const slot = 'landed-value-editor';
  bool online, busy = false, _disposed = false;
  bool accessDenied = false;
  String? error, message;
  Map<String, Object?>? form, preview;
  QuotationLocalDraft? local;
  final options = <String, List<Map<String, Object?>>>{};
  final cursors = <String, String?>{};
  bool get locked =>
      busy ||
      accessDenied ||
      local?.pending != null ||
      form?['status'] == 'posted';
  void clearDeniedAccess(Object e) {
    if (e is DomainError && e.code == 'PERMISSION_DENIED') {
      accessDenied = true;
      options.clear();
      cursors.clear();
      preview = null;
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

  Future<void> run(Future<void> Function() work) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    emit();
    try {
      await work();
    } catch (e) {
      clearDeniedAccess(e);
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

  Future<void> load(String resource, {bool more = false}) async {
    if (!online) return;
    final r = await gateway.options(
      scope,
      resource,
      after: more ? cursors[resource] : null,
    );
    if (_disposed) return;
    options[resource] = [
      if (more) ...?options[resource],
      for (final x in r['items'] as List) (x as Map).cast<String, Object?>(),
    ];
    cursors[resource] = r['next_cursor'] as String?;
  }

  Future<void> refresh(String resource, {bool more = false}) =>
      run(() => load(resource, more: more));
  Future<void> references() => run(() async {
    await load('receipts');
    await load('accounts');
  });
  Future<void> initialize() => run(() async {
    local = await drafts.load(scope, slot);
    if (_disposed) return;
    form = local?.form;
    preview = (form?['preview'] as Map?)?.cast<String, Object?>();
    if (local?.errorCode == 'VERSION_CONFLICT') preview = null;
    if (online) {
      for (final r in ['receipts', 'accounts', 'posted']) {
        await load(r);
      }
      accessDenied = false;
    }
  });
  Future<void> create() => run(() async {
    if (form != null) return;
    message = null;
    preview = null;
    form = {
      'id': const Uuid().v4(),
      'document_date': DateTime.now().toUtc().toIso8601String().substring(
        0,
        10,
      ),
      'amount': '',
      'reason': '',
      'reference': '',
      'status': 'local',
    };
    await persist();
  });
  Future<void> openPosted(Map<String, Object?> row) => run(() async {
    if (form != null) return;
    message = null;
    form = {...row, 'status': 'posted'};
    preview = row;
    await persist();
  });
  void update(String key, String value) {
    if (locked || form == null) return;
    if (![
      'amount',
      'reason',
      'reference',
      'document_date',
      'receipt_line_id',
      'offset_account_id',
      'variance_account_id',
    ].contains(key)) {
      return;
    }
    form = {...form!, key: value};
    if (form!['reverse_of'] == null) {
      preview = null;
      form!.remove('preview');
    }
    emit();
  }

  Future<void> persist({bool resolveConflict = false}) async {
    if (form == null) return;
    final saved = {...form!}..remove('preview');
    if (preview != null) saved['preview'] = preview;
    await drafts.save(
      scope,
      slot,
      saved,
      expectedVersion: form!['reverse_of'] == null ? 0 : 1,
      resolveConflict: resolveConflict,
    );
    local = await drafts.load(scope, slot);
  }

  Future<void> save() => run(persist);
  Future<bool> canLeave() async {
    if (busy) return false;
    if (accessDenied) return true;
    if (local?.pending != null || form == null) return true;
    await save();
    return error == null;
  }

  Future<void> close() => run(() async {
    if (local?.pending != null) {
      throw const FormatException('Resolve the saved command before closing.');
    }
    await drafts.discard(scope, slot);
    form = null;
    preview = null;
    local = null;
    message = null;
  });
  Future<void> calculate() => run(() async {
    if (!online ||
        form == null ||
        local?.pending != null ||
        form!['status'] == 'posted') {
      return;
    }
    preview = await gateway.preview(scope, form!);
    await persist(resolveConflict: true);
  });
  Future<void> reverse() => run(() async {
    if (form?['status'] != 'posted' ||
        form?['reverse_of'] != null ||
        form?['reversed'] == true) {
      return;
    }
    preview = {...form!};
    form = {
      'id': const Uuid().v4(),
      'reverse_of': form!['id'],
      'status': 'local',
      'reference': 'Correction ${form!['reference']}',
      'reason': '',
      'document_date': DateTime.now().toUtc().toIso8601String().substring(
        0,
        10,
      ),
      'preview': preview,
    };
    message = null;
    await persist();
  });
  Future<void> post() => run(() async {
    if (!online || accessDenied || form == null || form!['status'] == 'posted') {
      return;
    }
    var pending = local?.pending;
    if (pending == null) {
      final reason = (form!['reason'] as String? ?? '').trim(),
          reference = (form!['reference'] as String? ?? '').trim();
      if (reason.length < 3 ||
          reason.length > 1000 ||
          reference.isEmpty ||
          reference.length > 140) {
        throw const FormatException(
          'Enter a reference and a reason of 3–1000 characters.',
        );
      }
      if (form!['reverse_of'] == null && preview == null) {
        throw const FormatException(
          'Refresh the exact allocation preview first.',
        );
      }
      await persist();
      final payload = {
        for (final k in [
          'id',
          'reverse_of',
          'receipt_line_id',
          'amount',
          'offset_account_id',
          'variance_account_id',
          'document_date',
        ])
          if (form!.containsKey(k)) k: form![k],
        'reason': reason,
        'reference': reference,
        if (form!['reverse_of'] == null) 'basis_hash': preview!['basis_hash'],
      };
      pending = await drafts.prepare(
        scope,
        slot,
        verb: 'accept',
        payload: payload,
        expectedVersion: form!['reverse_of'] == null ? 0 : 1,
      );
      local = await drafts.load(scope, slot);
    }
    Map<String, Object?> result;
    try {
      result = await gateway.post(pending.envelope);
      await drafts.complete(scope, slot, pending.envelope.commandId);
    } on DomainError catch (e) {
      await drafts.recordFailure(
        scope,
        slot,
        e,
        commandId: pending.envelope.commandId,
      );
      local = await drafts.load(scope, slot);
      if (e.code == 'VERSION_CONFLICT') {
        preview = null;
      }
      rethrow;
    }
    if (_disposed) return;
    form = result;
    preview = result;
    local = null;
    message = 'Landed-value posting confirmed.';
    try {
      await persist();
      await load('posted');
    } catch (e) {
      clearDeniedAccess(e);
      error =
          'Posting confirmed. Retry save or register refresh before leaving.';
    }
  });
}

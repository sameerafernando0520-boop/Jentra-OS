import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';

import '../../app_providers.dart';
import '../operations/operational_read_access.dart';

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

final class LandedValueController extends ChangeNotifier
    implements OperationalReadAccess {
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
  int _epoch = 0;
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

  void clearServer() {
    options.clear();
    cursors.clear();
    preview = null;
    if (form?['status'] == 'posted') form = null;
  }

  Map<String, Object?> recoveryInputs(Map<String, Object?> source) => {
    for (final key in [
      'id',
      'status',
      'reverse_of',
      'receipt_line_id',
      'offset_account_id',
      'variance_account_id',
      'amount',
      'document_date',
      'reference',
      'reason',
    ])
      if (source.containsKey(key)) key: source[key],
  };
  bool accessDenied = false;
  String? error, message;
  Map<String, Object?>? form, preview;
  QuotationLocalDraft? local;
  final options = <String, List<Map<String, Object?>>>{};
  final cursors = <String, String?>{};
  bool get locked =>
      busy ||
      _disposed ||
      accessDenied ||
      local?.pending != null ||
      form?['status'] == 'posted';
  void clearDeniedAccess(Object e) {
    if (e is DomainError &&
        const {
          'PERMISSION_DENIED',
          'ACCESS_DENIED',
          'MFA_REQUIRED',
          'AUTHENTICATION_REQUIRED',
        }.contains(e.code)) {
      denyReadAccess();
    }
  }

  void emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    clearServer();
    form = null;
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
    if (busy || _disposed) return;
    busy = true;
    final epoch = _epoch;
    error = null;
    emit();
    try {
      await work();
    } catch (e) {
      if (_disposed || epoch != _epoch) return;
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
    final epoch = _epoch;
    final r = await gateway.options(
      scope,
      resource,
      after: more ? cursors[resource] : null,
    );
    if (_disposed || !online || epoch != _epoch) return;
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
    form = local == null || local!.form['status'] == 'posted'
        ? null
        : recoveryInputs(local!.form);
    preview = null;
    if (form == null && local?.pending == null) local = null;
    if (online) {
      final epoch = _epoch;
      for (final r in ['receipts', 'accounts', 'posted']) {
        await load(r);
      }
      if (!_disposed && online && epoch == _epoch) accessDenied = false;
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
    if (form != null ||
        !online ||
        accessDenied ||
        !(options['posted'] ?? []).contains(row)) {
      return;
    }
    message = null;
    form = {...row, 'status': 'posted'};
    preview = row;
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
    if (_disposed || form!['status'] == 'posted') return;
    final saved = recoveryInputs(form!);
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
        accessDenied ||
        form == null ||
        local?.pending != null ||
        form!['status'] == 'posted') {
      return;
    }
    final epoch = _epoch;
    final original = form!;
    final result = await gateway.preview(scope, original);
    if (!currentRead(epoch) || !identical(form, original)) return;
    preview = result;
    await persist(resolveConflict: true);
  });
  Future<void> reverse() => run(() async {
    if (!online ||
        accessDenied ||
        form?['status'] != 'posted' ||
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
    };
    message = null;
    await persist();
  });
  Future<void> post() => run(() async {
    if (!online ||
        accessDenied ||
        form == null ||
        form!['status'] == 'posted') {
      return;
    }
    final epoch = _epoch;
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
      final expectedVersion = form!['reverse_of'] == null ? 0 : 1;
      await persist();
      pending = await drafts.prepare(
        scope,
        slot,
        verb: 'accept',
        payload: payload,
        expectedVersion: expectedVersion,
      );
      local = await drafts.load(scope, slot);
    }
    Map<String, Object?> result;
    if (!currentRead(epoch)) return;
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
      if (currentRead(epoch) && e.code == 'VERSION_CONFLICT') {
        preview = null;
      }
      rethrow;
    }
    if (_disposed) return;
    local = null;
    message = 'Landed-value posting confirmed.';
    if (!currentRead(epoch)) {
      form = null;
      preview = null;
      return;
    }
    form = result;
    preview = result;
    try {
      await load('posted');
    } catch (e) {
      if (!currentRead(epoch)) return;
      clearDeniedAccess(e);
      error =
          'Posting confirmed. Retry the register refresh to view its evidence.';
    }
  });
}

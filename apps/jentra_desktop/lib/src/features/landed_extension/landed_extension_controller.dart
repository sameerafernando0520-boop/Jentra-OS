import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/landed_extension.dart';
import 'package:jentra_platform/landed_extension_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';

final landedExtensionGatewayProvider = Provider<LandedExtensionGateway?>(
  (ref) => null,
);
final landedExtensionControllerProvider =
    Provider.autoDispose<LandedExtensionController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider),
          gateway = ref.watch(landedExtensionGatewayProvider);
      final capabilities = ref.watch(businessCapabilitiesProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          capabilities.isLoading ||
          capabilities.hasError ||
          !(capabilities.value?.contains('inventory.valuation.post') ??
              false) ||
          !(capabilities.value?.contains('inventory.cost.view') ?? false)) {
        return null;
      }
      final controller = LandedExtensionController(
        scope: scope,
        gateway: gateway,
        drafts: LandedExtensionDraftStore(
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

final class LandedExtensionController extends ChangeNotifier {
  LandedExtensionController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.online,
  });
  final TenantContext scope;
  final LandedExtensionGateway gateway;
  final LandedExtensionDraftStore drafts;
  bool online, busy = false, accessDenied = false, _disposed = false;
  int _epoch = 0;
  String? error, message;
  Map<String, Object?>? form, preview, posted;
  ScopedCommandDraft? local;
  final options = <String, List<Map<String, Object?>>>{};
  final cursors = <String, String?>{};
  List<ScopedCommandDraft> recovered = [];
  String? recoveryCursor;
  bool get locked =>
      busy ||
      _disposed ||
      accessDenied ||
      local?.pending != null ||
      posted != null;
  bool get correcting => form?['correction_of'] != null;
  int get version => correcting ? 1 : 0;
  String get id => form!['id'] as String;
  void emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    preview = null;
    options.clear();
    cursors.clear();
    posted = null;
    form = null;
    super.dispose();
  }

  void setOnline(bool value) {
    if (online != value) {
      online = value;
      _epoch++;
      preview = null;
      posted = null;
      options.clear();
      cursors.clear();
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
      if (e is DomainError &&
          const {
            'PERMISSION_DENIED',
            'ACCESS_DENIED',
            'MFA_REQUIRED',
            'AUTHENTICATION_REQUIRED',
          }.contains(e.code)) {
        accessDenied = true;
        _epoch++;
        preview = null;
        posted = null;
        options.clear();
        cursors.clear();
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

  Future<void> load(String resource, {bool more = false}) async {
    if (!online) return;
    final epoch = _epoch;
    try {
      final result = await gateway.options(
        scope,
        resource,
        after: more ? cursors[resource] : null,
      );
      if (_disposed || epoch != _epoch) return;
      options[resource] = [
        if (more) ...?options[resource],
        for (final row in result['items'] as List)
          (row as Map).cast<String, Object?>(),
      ];
      cursors[resource] = result['next_cursor'] as String?;
    } catch (e) {
      if (_disposed || epoch != _epoch) return;
      rethrow;
    }
  }

  Future<void> recover({bool more = false}) async {
    final page = await drafts.store.page(
      scope,
      after: more ? recoveryCursor : null,
    );
    if (_disposed) return;
    recovered = [if (more) ...recovered, ...page.items];
    recoveryCursor = page.nextCursor;
  }

  Future<void> initialize() => run(() async {
    final epoch = _epoch;
    await recover();
    if (!online) return;
    for (final resource in ['receipts', 'accounts', 'posted']) {
      await load(resource);
    }
    if (!_disposed && online && epoch == _epoch) accessDenied = false;
  });
  Future<void> refresh(String resource, {bool more = false}) =>
      run(() => load(resource, more: more));
  Future<void> moreRecovery() => run(() => recover(more: true));
  Future<void> restore(ScopedCommandDraft draft) => run(() async {
    if (form != null || posted != null) return;
    local = await drafts.store.load(scope, draft.aggregateId);
    if (_disposed || local == null) return;
    form = Map.from(local!.form);
    preview = null;
    message = null;
  });
  Future<void> create() => run(() async {
    if (form != null || posted != null) return;
    form = {
      'id': const Uuid().v4(),
      'document_date': DateTime.now().toUtc().toIso8601String().substring(
        0,
        10,
      ),
      'reference': '',
      'reason': '',
      'total_amount': '',
      'basis_mode': 'quantity',
      'receipts': <Map<String, Object?>>[],
    };
    message = null;
    await persist();
  });
  Future<void> openPosted(Map<String, Object?> row) => run(() async {
    if (form != null ||
        !online ||
        accessDenied ||
        !(options['posted'] ?? []).contains(row)) {
      return;
    }
    posted = Map.from(row);
    preview = posted;
  });
  Future<void> correction() => run(() async {
    if (posted == null ||
        posted!['has_correction'] == true ||
        !online ||
        accessDenied) {
      return;
    }
    final parent = posted!;
    form = {
      'id': const Uuid().v4(),
      'correction_of': parent['id'],
      'document_date': DateTime.now().toUtc().toIso8601String().substring(
        0,
        10,
      ),
      'reference': '',
      'reason': '',
      'total_amount': parent['total_amount'],
    };
    posted = null;
    preview = null;
    await persist();
  });
  void update(String key, String value) {
    if (locked ||
        form == null ||
        !const {
          'document_date',
          'reference',
          'reason',
          'total_amount',
          'basis_mode',
          'offset_account_id',
          'variance_account_id',
        }.contains(key)) {
      return;
    }
    if (correcting &&
        const {
          'basis_mode',
          'offset_account_id',
          'variance_account_id',
        }.contains(key)) {
      return;
    }
    if (key.endsWith('account_id') &&
        !(options['accounts'] ?? []).any((row) => row['id'] == value)) {
      return;
    }
    form = {...form!, key: value};
    form!.remove('basis_hash');
    preview = null;
    emit();
  }

  void selectReceipt(Map<String, Object?> row, bool selected) {
    if (locked ||
        form == null ||
        correcting ||
        !(options['receipts'] ?? []).contains(row)) {
      return;
    }
    final lines = [
      for (final line in form!['receipts'] as List)
        Map<String, Object?>.from(line as Map),
    ];
    lines.removeWhere((line) => line['receipt_line_id'] == row['id']);
    if (selected) {
      if (lines.length >= 50) return;
      lines.add({'receipt_line_id': row['id'], 'weight': '1'});
    }
    form = {...form!, 'receipts': lines};
    form!.remove('basis_hash');
    preview = null;
    emit();
  }

  void weight(String receipt, String value) {
    if (locked || form == null || correcting) return;
    final lines = [
      for (final line in form!['receipts'] as List)
        {
          ...Map<String, Object?>.from(line as Map),
          if (line['receipt_line_id'] == receipt) 'weight': value,
        },
    ];
    form = {...form!, 'receipts': lines};
    form!.remove('basis_hash');
    preview = null;
    emit();
  }

  Future<void> persist({bool resolve = false}) async {
    if (form == null || _disposed) return;
    final aggregate = id;
    await drafts.store.save(
      scope,
      aggregate,
      'post',
      LandedExtensionProtocol.payload(form!),
      version,
      resolveConflict: resolve,
    );
    local = await drafts.store.load(scope, aggregate);
  }

  Future<void> save() => run(persist);
  Future<bool> canLeave() async {
    if (busy) return false;
    if (local?.pending != null || form == null) return true;
    await save();
    return error == null;
  }

  Future<void> close() => run(() async {
    if (local?.pending != null) {
      throw const FormatException(
        'Resolve the original saved command before closing.',
      );
    }
    if (form != null) await drafts.store.discard(scope, id);
    form = null;
    local = null;
    preview = null;
    posted = null;
    await recover();
  });
  Future<void> calculate() => run(() async {
    if (!online || accessDenied || form == null || local?.pending != null) {
      return;
    }
    final epoch = _epoch;
    final result = await gateway.preview(
      scope,
      LandedExtensionProtocol.payload(form!),
    );
    if (_disposed || epoch != _epoch || !online) return;
    preview = result;
    form = {...form!, 'basis_hash': result['basis_hash']};
    await persist(resolve: true);
  });
  Future<void> post() => run(() async {
    if (!online || accessDenied || form == null || posted != null) return;
    final epoch = _epoch, aggregate = id, expectedVersion = version;
    final payload = LandedExtensionProtocol.payload(form!);
    var pending = local?.pending;
    if (pending == null) {
      if (preview == null) {
        throw const FormatException(
          'Refresh the exact allocation preview first.',
        );
      }
      await persist();
      pending = await drafts.store.prepare(
        scope,
        aggregate,
        'post',
        payload,
        expectedVersion,
      );
      local = await drafts.store.load(scope, aggregate);
    }
    if (_disposed || !online || accessDenied || epoch != _epoch) return;
    Map<String, Object?> result;
    try {
      result = await gateway.post(pending.envelope);
      // Confirmation is durable even after this route has been disposed.
      await drafts.store.complete(scope, aggregate, pending.envelope.commandId);
    } on DomainError catch (e) {
      await drafts.store.recordFailure(
        scope,
        aggregate,
        pending.envelope.commandId,
        e,
      );
      if (!_disposed) {
        local = await drafts.store.load(scope, aggregate);
        if (local?.pending == null) {
          preview = null;
          form?.remove('basis_hash');
        }
      }
      rethrow;
    }
    if (_disposed) return;
    form = null;
    local = null;
    message = 'Landed value posting confirmed.';
    if (online && !accessDenied && epoch == _epoch) {
      posted = result;
      preview = result;
    }
    // A refresh failure cannot recreate or resend this confirmed envelope.
    await recover();
    if (online && !accessDenied && epoch == _epoch) await load('posted');
  });
}

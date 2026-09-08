import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_receivables.dart';
import 'package:jentra_platform/jentra_receivables_platform.dart';
import 'package:uuid/uuid.dart';
import '../../app_providers.dart';

final receivablesRepositoryProvider = Provider<ReceivablesRepository?>(
  (ref) => null,
);
final receivablesControllerProvider =
    Provider.autoDispose<ReceivablesController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      final repository = ref.watch(receivablesRepositoryProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          caps.isLoading ||
          caps.hasError ||
          repository == null) {
        return null;
      }
      final controller = ReceivablesController(
        scope: scope,
        capabilities: caps.value!,
        repository: repository,
        drafts: ReceivableDraftStore(
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
      unawaited(controller.refresh());
      return controller;
    });

final class ReceivablesController extends ChangeNotifier {
  ReceivablesController({
    required this.scope,
    required Set<String> capabilities,
    required this.repository,
    required this.drafts,
    required this.online,
  }) : capabilities = Set.unmodifiable(capabilities) {
    kind =
        ReceivableKind.values
            .where((k) => k.canRead(capabilities))
            .firstOrNull ??
        ReceivableKind.invoice;
  }
  final TenantContext scope;
  final Set<String> capabilities;
  final ReceivablesRepository repository;
  final ReceivableDraftStore drafts;
  late ReceivableKind kind;
  bool online, busy = false, _disposed = false;
  String? error, message, statusFilter, slot;
  ReceivableDocument? document;
  Map<String, Object?>? form;
  ReceivableLocalDraft? local;
  CursorPage<ReceivableDocument> page = CursorPage(items: [], limit: 50);
  int epoch = 0;
  Future<void> _saveTail = Future<void>.value();
  bool saving = false;
  bool localSaveFailed = false;
  bool get canManage => capabilities.contains(kind.managePermission);
  bool get active => !_disposed;
  bool get pending => local?.pending == true;
  bool get conflict => local?.error == 'VERSION_CONFLICT';
  bool get canEdit =>
      canManage && !busy && !pending && !conflict && form != null;
  bool get canAct =>
      online && !busy && local == null && form == null && document != null;
  bool get canPost =>
      canAct &&
      capabilities.contains(kind.postPermission) &&
      ['submitted', 'approved'].contains(document!.status);
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
    notifyListeners();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    _emit();
    try {
      await _saveTail;
      if (_disposed) return;
      await work();
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> refresh({bool more = false}) => _run(() async {
    if (!online || !kind.canRead(capabilities)) return;
    final next = await repository.page(
      scope,
      kind,
      cursor: more ? page.nextCursor : null,
      status: statusFilter,
    );
    if (_disposed) return;
    page = more
        ? CursorPage(
            items: [...page.items, ...next.items],
            limit: 50,
            nextCursor: next.nextCursor,
          )
        : next;
  });
  Future<void> selectKind(ReceivableKind value) async {
    if (busy || form != null || pending || !value.canRead(capabilities)) return;
    kind = value;
    document = null;
    local = null;
    slot = null;
    page = CursorPage(items: [], limit: 50);
    statusFilter = null;
    _emit();
    await refresh();
  }

  Future<void> open(ReceivableDocument value) => _run(() async {
    if (form != null || pending) return;
    kind = value.kind;
    slot = '${kind.wire}:${value.id}';
    document = online ? await repository.find(scope, kind, value.id) : value;
    local = await drafts.load(scope, slot!);
    form = local?.form;
    epoch++;
  });
  Future<void> create() => _run(() async {
    if (!canManage || form != null || pending) return;
    final id = const Uuid().v4();
    slot = '${kind.wire}:$id';
    document = null;
    form = {
      'id': id,
      'document_type': kind.wire,
      'document_date': DateTime.now().toIso8601String().substring(0, 10),
      'currency_code': 'LKR',
      'lines': <Object?>[],
    };
    await drafts.save(scope, slot!, form!, null);
    local = await drafts.load(scope, slot!);
    epoch++;
  });
  Future<void> edit() => _run(() async {
    if (!canManage || document?.editable != true || local != null) return;
    form = document!.toDraft();
    await drafts.save(scope, slot!, form!, document!.version);
    local = await drafts.load(scope, slot!);
    epoch++;
  });
  // Serialize field snapshots through the draft store; the UI awaits this before
  // changing records or sending a command, so no unpersisted edit is abandoned.
  Future<void> saveLocal(Map<String, Object?> value) async {
    if (!canEdit) return;
    final snapshot = receivableMap(jsonDecode(jsonEncode(value))),
        savedSlot = slot!,
        version = local?.version ?? document?.version;
    form = snapshot;
    saving = true;
    error = null;
    final job = _saveTail.then((_) async {
      await drafts.save(scope, savedSlot, snapshot, version);
      final saved = await drafts.load(scope, savedSlot);
      localSaveFailed = false;
      if (!_disposed) local = saved;
    });
    _saveTail = job.catchError((Object e) {
      localSaveFailed = true;
      error = 'Local save failed: $e';
    });
    _emit();
    await _saveTail;
    saving = false;
    _emit();
  }

  Future<void> closeEditor() => _run(() async {
    if (pending) return;
    if (localSaveFailed) {
      throw const ReceivableFailure(
        'LOCAL_SAVE_FAILED',
        'Keep this editor open and retry saving; the latest fields are not safely stored.',
      );
    }
    // Already encrypted locally. Closing is not discarding.
    form = null;
    document = null;
    local = null;
    slot = null;
    epoch++;
  });
  Future<void> discardAndReload() => _run(() async {
    if (slot == null || pending) return;
    await drafts.discard(scope, slot!);
    local = null;
    form = null;
    if (document != null && online) {
      document = await repository.find(scope, kind, document!.id);
    }
    epoch++;
  });
  Future<void> recover(String recoverySlot) => _run(() async {
    if (form != null || pending) return;
    final recovered = await drafts.load(scope, recoverySlot);
    if (recovered == null) return;
    final wire = recoverySlot.split(':').first;
    final selected = ReceivableKind.values.firstWhere((k) => k.wire == wire);
    if (!selected.canRead(capabilities)) {
      throw const ReceivableFailure(
        'PERMISSION_DENIED',
        'This draft is no longer available to your role.',
      );
    }
    kind = selected;
    slot = recoverySlot;
    local = recovered;
    form =
        recoverySlot.contains(':allocation-') ||
            recoverySlot.contains(':setup-')
        ? null
        : recovered.form;
    document = null;
    if (recovered.version != null && online) {
      try {
        document = await repository.find(
          scope,
          kind,
          recoverySlot.split(':').last,
        );
      } catch (_) {
        /* Recovery remains visible even if the read fails. */
      }
    }
    epoch++;
  });
  Future<void> saveServer() => _run(() async {
    if (!online || !canManage || pending || conflict || form == null) return;
    final validation = ReceivableDraft(kind, form!).validate();
    if (validation.isNotEmpty) {
      throw ReceivableFailure(
        'VALIDATION_ERROR',
        validation.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
        definite: true,
      );
    }
    await _send(
      'upsert_${kind.wire}',
      form!,
      local?.version ?? document?.version,
    );
  });
  Future<void> action(String verb, {String? reason}) => _run(() async {
    // busy is set by _run; check the other preconditions explicitly.
    if (!online || document == null || local != null || form != null) return;
    final decision = verb == 'approve' || verb == 'reject';
    final permission = verb == 'post'
        ? kind.postPermission
        : decision
        ? 'workflow.approvals.decide'
        : kind.managePermission;
    if (!capabilities.contains(permission)) {
      throw const ReceivableFailure(
        'PERMISSION_DENIED',
        'Your role cannot perform this action.',
        definite: true,
      );
    }
    final payload = <String, Object?>{
      'document_type': kind.wire,
      'document_id': document!.id,
      if (decision)
        'decision': verb == 'approve' ? 'approved' : 'rejected'
      else if (verb != 'post')
        'action': verb,
      if (reason != null) ...{'reason': reason, 'note': reason},
    };
    await _send(
      verb == 'post'
          ? 'post_${kind.wire}'
          : decision
          ? 'decide_operational_approval'
          : 'transition_operational_document',
      payload,
      document!.version,
    );
  });
  Future<void> retry() => _run(() async {
    if (!online || local?.pending != true) return;
    final rpc = local!.rpc;
    final required = rpc == 'upsert_receivables_setup'
        ? 'finance.setup.manage'
        : rpc.startsWith('upsert_')
        ? kind.managePermission
        : rpc.startsWith('post_')
        ? kind.postPermission
        : rpc == 'allocate_customer_receipt'
        ? 'finance.receipts.allocate'
        : rpc == 'decide_operational_approval'
        ? 'workflow.approvals.decide'
        : kind.managePermission;
    if (!capabilities.contains(required)) {
      throw const ReceivableFailure(
        'PERMISSION_DENIED',
        'Your current role cannot retry this command.',
        definite: true,
      );
    }
    await _dispatch(local!);
  });
  Future<void> allocate(Map<String, Object?> payload) => _run(() async {
    if (!online ||
        !capabilities.contains('finance.receipts.allocate') ||
        form != null ||
        pending) {
      return;
    }
    slot = '${ReceivableKind.receipt.wire}:allocation-${const Uuid().v4()}';
    await _send('allocate_customer_receipt', payload, null);
  });
  Future<void> _send(
    String rpc,
    Map<String, Object?> payload,
    int? version,
  ) async {
    if (local == null &&
        document != null &&
        rpc != 'allocate_customer_receipt' &&
        rpc != 'upsert_receivables_setup') {
      await drafts.save(scope, slot!, document!.toDraft(), version);
    }
    local = await drafts.prepare(scope, slot!, rpc, payload, version);
    await _dispatch(local!);
  }

  Future<void> _dispatch(ReceivableLocalDraft saved) async {
    if (_disposed) return;
    final savedSlot = slot!, envelope = saved.envelope;
    try {
      final result = await repository.command(saved.rpc, envelope);
      // Parse before deleting recovery: malformed success may follow a commit.
      final next =
          {
            'allocate_customer_receipt',
            'upsert_receivables_setup',
          }.contains(saved.rpc)
          ? null
          : ReceivableDocument(receivableMap(result['entity']));
      await drafts.complete(scope, savedSlot, envelope.commandId);
      if (_disposed) return;
      document = next;
      local = null;
      form = null;
      epoch++;
      message = 'Confirmed · request ${result['request_id']}';
      try {
        page = await repository.page(scope, kind, status: statusFilter);
      } catch (_) {
        message = '$message · refresh the register when connected';
      }
    } catch (e) {
      final failure = e is ReceivableFailure
          ? e
          : const ReceivableFailure(
              'UNCERTAIN_RESULT',
              'Could not verify the result. Retry the saved command.',
            );
      await drafts.failure(scope, savedSlot, envelope.commandId, failure);
      if (!_disposed) {
        local = await drafts.load(scope, savedSlot);
        error = failure.toString();
      }
    }
  }

  Future<void> setup(Map<String, Object?> payload, int? version) =>
      _run(() async {
        if (!online ||
            !capabilities.contains('finance.setup.manage') ||
            form != null ||
            pending) {
          return;
        }
        slot = '${ReceivableKind.receipt.wire}:setup-${const Uuid().v4()}';
        await _send('upsert_receivables_setup', payload, version);
      });
}

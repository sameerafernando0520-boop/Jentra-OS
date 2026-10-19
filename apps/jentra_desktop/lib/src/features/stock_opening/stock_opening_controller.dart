import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_stock_opening.dart';
import 'package:jentra_platform/jentra_stock_opening_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';

final stockOpeningRepositoryProvider = Provider<StockOpeningRepository?>(
  (ref) => null,
);
final stockOpeningControllerProvider =
    Provider.autoDispose<StockOpeningController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      final repository = ref.watch(stockOpeningRepositoryProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          caps.isLoading ||
          caps.hasError ||
          repository == null ||
          !canReadStockOpenings(caps.value!)) {
        return null;
      }
      final controller = StockOpeningController(
        scope: scope,
        capabilities: caps.value!,
        repository: repository,
        drafts: StockOpeningDraftStore(
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

final class StockOpeningController extends ChangeNotifier {
  StockOpeningController({
    required this.scope,
    required Set<String> capabilities,
    required this.repository,
    required this.drafts,
    required this.online,
  }) : capabilities = Set.unmodifiable(capabilities);
  final TenantContext scope;
  final Set<String> capabilities;
  final StockOpeningRepository repository;
  final StockOpeningDraftStore drafts;
  bool online, busy = false, _disposed = false;
  String? error, message, statusFilter, slot;
  final labels = <String, String>{};
  StockOpeningDocument? document;
  Map<String, Object?>? form;
  StockOpeningLocalDraft? local;
  CursorPage<StockOpeningDocument> page = CursorPage(items: [], limit: 50);
  int epoch = 0;
  Future<void> _saveTail = Future<void>.value();
  bool saving = false;
  bool localSaveFailed = false;
  bool get canManage =>
      active &&
      canReadStockOpenings(capabilities) &&
      capabilities.contains('inventory.adjustments.post');
  bool get active => !_disposed;
  bool get pending => local?.pending == true;
  bool get conflict => local?.error == 'VERSION_CONFLICT';
  bool get canEdit =>
      canManage && !busy && !pending && !conflict && form != null;
  bool get canAct =>
      online && !busy && local == null && form == null && document != null;
  bool get canPost => canAct && canManage && document!.status == 'approved';
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

  Future<void> loadLabels() async {
    if (!online || document == null) return;
    for (final entry in {
      'warehouses': 'warehouse_id',
      'accounts': 'offset_account_id',
    }.entries) {
      final id = document!.data[entry.value] as String;
      try {
        final rows = await repository.references(scope, entry.key, id: id);
        if (!_disposed && rows.items.isNotEmpty) {
          final row = rows.items.first;
          labels[id] = '${row['code'] ?? ''} · ${row['name'] ?? ''}';
        }
      } catch (_) {
        /* The scoped identifier remains visible if the master is unavailable. */
      }
    }
  }

  Future<void> refresh({bool more = false}) => _run(() async {
    if (!online || !canReadStockOpenings(capabilities)) return;
    final next = await repository.page(
      scope,
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
  Future<void> open(StockOpeningDocument value) => _run(() async {
    if (form != null || pending) return;
    slot = value.id;
    document = online ? await repository.find(scope, value.id) : value;
    local = await drafts.load(scope, slot!);
    form = _recoveryForm(local);
    await loadLabels();
    epoch++;
  });
  Future<void> create() => _run(() async {
    if (!canManage || form != null || pending) return;
    final id = const Uuid().v4();
    slot = id;
    document = null;
    form = {
      'id': id,
      'document_type': 'stock_opening',
      'document_date': DateTime.now().toIso8601String().substring(0, 10),
      'lines': <Object?>[],
    };
    if (online) {
      try {
        final entities = await repository.references(scope, 'legal_entities');
        if (entities.items.isNotEmpty) {
          form!['_currency_code'] = entities.items.first['currency_code'];
        }
      } catch (_) {
        /* Saving on the server will confirm the entity currency. */
      }
    }
    await _persistForm(slot!, form!, null);
    epoch++;
  });
  Future<void> edit() => _run(() async {
    if (!canManage || document?.editable != true || local != null) return;
    form = document!.toDraft();
    await _persistForm(slot!, form!, document!.version);
    epoch++;
  });
  Future<void> _persistForm(
    String savedSlot,
    Map<String, Object?> snapshot,
    int? version,
  ) async {
    try {
      await drafts.save(scope, savedSlot, snapshot, version);
      final saved = await drafts.load(scope, savedSlot);
      localSaveFailed = false;
      if (!_disposed) local = saved;
    } catch (_) {
      localSaveFailed = true;
      throw const StockOpeningFailure(
        'LOCAL_STORAGE_FULL',
        'Local storage could not save these edits. Keep this editor open and retry saving.',
        definite: true,
      );
    }
  }

  // Serialize field snapshots through the draft store; the UI awaits this before
  // changing records or sending a command, so no unpersisted edit is abandoned.
  Future<void> saveLocal(Map<String, Object?> value) async {
    if (!canEdit) return;
    final snapshot = openingMap(jsonDecode(jsonEncode(value))),
        savedSlot = slot!,
        version = local?.version ?? document?.version;
    form = snapshot;
    saving = true;
    error = null;
    final job = _saveTail.then(
      (_) => _persistForm(savedSlot, snapshot, version),
    );
    _saveTail = job.catchError((Object e) {
      localSaveFailed = true;
      error = 'Local save failed: $e';
    });
    _emit();
    await _saveTail;
    saving = false;
    _emit();
  }

  Future<bool> canLeave() async {
    await _saveTail;
    if (busy || localSaveFailed) {
      error = 'Keep this opening open until the current save completes successfully.';
      _emit();
      return false;
    }
    return true;
  }

  Future<void> closeEditor() => _run(() async {
    if (pending) return;
    if (localSaveFailed) {
      throw const StockOpeningFailure(
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
    localSaveFailed = false;
    local = null;
    form = null;
    if (document != null && online) {
      document = await repository.find(scope, document!.id);
    }
    epoch++;
  });
  Future<void> recover(String recoverySlot) => _run(() async {
    if (form != null || pending || !canReadStockOpenings(capabilities)) return;
    final recovered = await drafts.load(scope, recoverySlot);
    if (recovered == null) return;
    slot = recoverySlot;
    localSaveFailed = false;
    local = recovered;
    form = _recoveryForm(recovered);
    document = null;
    if (recovered.version != null && online) {
      try {
        document = await repository.find(scope, recoverySlot);
      } catch (_) {
        /* Recovery remains visible even if the read fails. */
      }
    }
    epoch++;
  });
  Map<String, Object?>? _recoveryForm(StockOpeningLocalDraft? saved) {
    final operation = saved?.data['operation'];
    // Lifecycle requests retain a server snapshot for recovery, not an edit form.
    return operation == null || operation == 'upsert_stock_opening'
        ? saved?.form
        : null;
  }

  Future<void> saveServer() => _run(() async {
    if (!online || !canManage || pending || conflict || form == null) return;
    final validation = StockOpeningDraft(form!).validate();
    if (validation.isNotEmpty) {
      throw StockOpeningFailure(
        'VALIDATION_ERROR',
        validation.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
        definite: true,
      );
    }
    await _send(
      'upsert_stock_opening',
      form!,
      local?.version ?? document?.version,
    );
  });
  bool allows(String verb) {
    if (document == null || !canReadStockOpenings(capabilities)) return false;
    final status = document!.status;
    if (verb == 'approve' || verb == 'reject') {
      return status == 'pending_approval' &&
          capabilities.contains('workflow.approvals.decide') &&
          !document!.preparedBy(scope.actorId);
    }
    if (!canManage) return false;
    if (verb == 'post') return status == 'approved';
    if (verb == 'submit') return status == 'draft';
    if (!{'recall', 'cancel'}.contains(verb) ||
        {'posted', 'cancelled'}.contains(status)) {
      return false;
    }
    final snapshot = document!.data['workflow_snapshot'];
    if (snapshot is! Map) return verb == 'cancel' && status == 'draft';
    final lifecycle = openingMap(snapshot)['lifecycle'];
    if (lifecycle is! Map) return false;
    final from = status == 'pending_approval' ? 'submitted' : status;
    final to = verb == 'recall' ? 'draft' : 'cancelled';
    return [
      ...?lifecycle['transitions'] as List?,
      ...?lifecycle['posting_transitions'] as List?,
    ].any((t) => t is List && t.length == 2 && t[0] == from && t[1] == to);
  }

  Future<void> action(String verb, {String? reason}) => _run(() async {
    if (!online || local != null || form != null || !allows(verb)) return;
    if ({'reject', 'recall', 'cancel'}.contains(verb) &&
        (reason == null || reason.trim().isEmpty)) {
      throw const StockOpeningFailure(
        'REASON_REQUIRED',
        'Explain this decision.',
        definite: true,
      );
    }
    final decision = verb == 'approve' || verb == 'reject';
    await _send(
      verb == 'post' ? 'post_stock_opening' : 'transition_stock_opening',
      {
        'document_type': 'stock_opening',
        'document_id': document!.id,
        if (decision)
          'decision': verb == 'approve' ? 'approved' : 'rejected'
        else if (verb != 'post')
          'action': verb,
        if (reason != null) ...{'reason': reason.trim(), 'note': reason.trim()},
      },
      document!.version,
    );
  });
  Future<void> retry() => _run(() async {
    if (!online || local?.pending != true) return;
    final required = local!.envelope.payload['decision'] != null
        ? 'workflow.approvals.decide'
        : 'inventory.adjustments.post';
    if (!canReadStockOpenings(capabilities) ||
        !capabilities.contains(required)) {
      throw const StockOpeningFailure(
        'PERMISSION_DENIED',
        'Your current role cannot retry this command.',
        definite: true,
      );
    }
    await _dispatch(local!);
  });
  Future<void> _send(
    String rpc,
    Map<String, Object?> payload,
    int? version,
  ) async {
    if (form != null) {
      // A failed autosave can leave an older encrypted form on disk. Persist
      // the current fields before preparing a retry envelope or dispatching.
      await _persistForm(slot!, form!, version);
    } else if (local == null && document != null) {
      await drafts.save(scope, slot!, document!.toDraft(), version);
    }
    local = await drafts.prepare(scope, slot!, rpc, payload, version);
    await _dispatch(local!);
  }

  Future<void> _dispatch(StockOpeningLocalDraft saved) async {
    if (_disposed) return;
    final savedSlot = slot!, envelope = saved.envelope;
    try {
      final result = await repository.command(saved.rpc, envelope);
      // Parse before deleting recovery: malformed success may follow a commit.
      final next = StockOpeningDocument(openingMap(result['entity']));
      await drafts.complete(scope, savedSlot, envelope.commandId);
      if (_disposed) return;
      document = next;
      local = null;
      form = null;
      epoch++;
      message = 'Confirmed · request ${result['request_id']}';
      try {
        page = await repository.page(scope, status: statusFilter);
      } catch (_) {
        message = '$message · refresh the register when connected';
      }
    } catch (e) {
      final failure = e is StockOpeningFailure
          ? e
          : const StockOpeningFailure(
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
}

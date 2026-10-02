import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

import '../../app_providers.dart';

final quotationWorkspaceProvider =
    AsyncNotifierProvider<
      QuotationWorkspaceController,
      QuotationWorkspaceState
    >(QuotationWorkspaceController.new, retry: (count, error) => null);
const _unset = Object();

bool canViewQuotations(Set<String> capabilities) => const {
  'sales.quotations.view',
  'sales.quotations.manage',
}.any(capabilities.contains);

final class QuotationWorkspaceState {
  const QuotationWorkspaceState({
    required this.context,
    required this.capabilities,
    required this.connectivity,
    required this.page,
    required this.query,
    this.detail,
    this.revisions = const [],
    this.decisions = const [],
    this.form,
    this.slot,
    this.localDraft,
    this.busy = false,
    this.loading = false,
    this.recovered = false,
    this.error,
    this.statusMessage,
    this.editorEpoch = 0,
    this.conflictDetail,
    this.savingLocal = false,
    this.moreRevisions = false,
    this.moreDecisions = false,
  });
  final TenantContext context;
  final Set<String> capabilities;
  final ConnectivityState connectivity;
  final CursorPage<SalesQuotation> page;
  final QuotationListQuery query;
  final QuotationDetail? detail, conflictDetail;
  final List<SalesQuotationRevision> revisions;
  final List<Map<String, Object?>> decisions;
  final Map<String, Object?>? form;
  final String? slot;
  final QuotationLocalDraft? localDraft;
  final bool busy,
      loading,
      recovered,
      savingLocal,
      moreRevisions,
      moreDecisions;
  final DomainError? error;
  final String? statusMessage;
  final int editorEpoch;
  bool get canManage => capabilities.contains('sales.quotations.manage');
  bool get canApprove => capabilities.contains('workflow.approvals.decide');
  bool get isOnline => connectivity == ConnectivityState.online;
  bool get canWrite =>
      isOnline && context.hasOperationalScope && !busy && !loading;
  QuotationPendingCommand? get pending => localDraft?.pending;
  bool get conflict => localDraft?.errorCode == 'VERSION_CONFLICT';
  bool get dirty =>
      localDraft != null ||
      savingLocal ||
      error?.code == 'DRAFT_SAVE_FAILED' ||
      (error != null && isLocalDraftStorageFailure(error!));
  bool get canEditForm =>
      canManage &&
      !busy &&
      !loading &&
      pending == null &&
      !conflict &&
      form != null &&
      (detail == null ||
          detail!.quotation.status == 'draft' ||
          form!['create_revision'] == true);
  bool get canRevise =>
      canManage &&
      !dirty &&
      !busy &&
      !loading &&
      const {
        'submitted',
        'approved',
        'rejected',
        'expired',
      }.contains(detail?.quotation.status);
  Set<String> get allowedActions {
    final quote = detail?.quotation;
    if (quote == null || dirty || busy || loading) return {};
    final expired = quote.validUntil.isBefore(
      DateTime.parse(
        '${DateTime.now().toUtc().toIso8601String().substring(0, 10)}T00:00:00Z',
      ),
    );
    final actions = <String>{
      if (canManage) ...{
        if (quote.status == 'draft') 'submit',
        if ({
          'submitted',
          'pending_approval',
          'approved',
        }.contains(quote.status))
          'recall',
        if ({'submitted', 'approved'}.contains(quote.status) && !expired)
          'accept',
        if ({
              'submitted',
              'pending_approval',
              'approved',
            }.contains(quote.status) &&
            expired)
          'expire',
        if (!{'cancelled', 'converted'}.contains(quote.status)) 'cancel',
      },
      if (canApprove && quote.status == 'pending_approval') ...{
        'approve',
        'reject',
      },
    };
    final revision = revisions
        .where((r) => r.revisionNumber == quote.currentRevision)
        .firstOrNull;
    final policy = revision?.snapshot['workflow_snapshot'];
    if (policy is Map && policy['lifecycle'] is Map) {
      final lifecycle = policy['lifecycle'] as Map;
      final edges = [
        ...(lifecycle['transitions'] as List? ?? []),
        ...(lifecycle['quotation_transitions'] as List? ?? []),
      ];
      final from = quote.status == 'pending_approval'
          ? 'submitted'
          : quote.status;
      actions.removeWhere((action) {
        final to = switch (action) {
          'recall' => 'draft',
          'approve' => 'approved',
          'reject' => 'rejected',
          'accept' => 'accepted',
          'expire' => 'expired',
          'cancel' => 'cancelled',
          _ => 'submitted',
        };
        return !edges.any(
          (edge) =>
              edge is List &&
              edge.length == 2 &&
              edge[0] == from &&
              edge[1] == to,
        );
      });
    }
    return actions;
  }

  QuotationWorkspaceState copyWith({
    CursorPage<SalesQuotation>? page,
    QuotationListQuery? query,
    ConnectivityState? connectivity,
    Object? detail = _unset,
    Object? conflictDetail = _unset,
    List<SalesQuotationRevision>? revisions,
    List<Map<String, Object?>>? decisions,
    Object? form = _unset,
    Object? slot = _unset,
    Object? localDraft = _unset,
    bool? busy,
    bool? loading,
    bool? recovered,
    bool? savingLocal,
    bool? moreRevisions,
    bool? moreDecisions,
    Object? error = _unset,
    Object? statusMessage = _unset,
    int? editorEpoch,
  }) => QuotationWorkspaceState(
    context: context,
    capabilities: capabilities,
    connectivity: connectivity ?? this.connectivity,
    page: page ?? this.page,
    query: query ?? this.query,
    detail: identical(detail, _unset)
        ? this.detail
        : detail as QuotationDetail?,
    conflictDetail: identical(conflictDetail, _unset)
        ? this.conflictDetail
        : conflictDetail as QuotationDetail?,
    revisions: revisions ?? this.revisions,
    decisions: decisions ?? this.decisions,
    form: identical(form, _unset) ? this.form : form as Map<String, Object?>?,
    slot: identical(slot, _unset) ? this.slot : slot as String?,
    localDraft: identical(localDraft, _unset)
        ? this.localDraft
        : localDraft as QuotationLocalDraft?,
    busy: busy ?? this.busy,
    loading: loading ?? this.loading,
    recovered: recovered ?? this.recovered,
    savingLocal: savingLocal ?? this.savingLocal,
    moreRevisions: moreRevisions ?? this.moreRevisions,
    moreDecisions: moreDecisions ?? this.moreDecisions,
    error: identical(error, _unset) ? this.error : error as DomainError?,
    statusMessage: identical(statusMessage, _unset)
        ? this.statusMessage
        : statusMessage as String?,
    editorEpoch: editorEpoch ?? this.editorEpoch,
  );
}

final class QuotationWorkspaceController
    extends AsyncNotifier<QuotationWorkspaceState> {
  int _generation = 0, _selection = 0, _read = 0, _edit = 0;
  bool _commandActive = false;
  Future<void> _edits = Future.value();
  final _failedEdits = <String>{};
  String _editKey(TenantContext context, String? slot) =>
      '${jsonEncode(context.toJson())}:$slot';
  bool _canLeave(QuotationWorkspaceState previous) {
    if (!_failedEdits.contains(_editKey(previous.context, previous.slot))) {
      return true;
    }
    final current = _current;
    if (current != null) {
      state = AsyncData(
        current.copyWith(
          error: _draftSaveError,
          loading: false,
          savingLocal: false,
        ),
      );
    }
    return false;
  }

  static const _draftSaveError = DomainError(
    code: 'DRAFT_SAVE_FAILED',
    message: 'This device could not save the encrypted draft. Keep this editor open and retry saving, or explicitly discard your edits.',
  );
  QuotationWorkspaceRepository get _reader =>
      ref.read(quotationWorkspaceRepositoryProvider) ??
      (throw const DomainError(
        code: 'BACKEND_UNAVAILABLE',
        message: 'Configure the development service to load quotations.',
      ));
  QuotationDraftStore get _store => ref.read(quotationDraftStoreProvider);

  @override
  Future<QuotationWorkspaceState> build() async {
    ++_generation;
    ++_selection;
    ++_read;
    final context = ref.watch(activeTenantContextProvider);
    // Also observe AsyncValue changes: a refreshed future may retain its identity
    // while the resolved capability set changes.
    ref.watch(businessCapabilitiesProvider);
    final capabilities = await ref.watch(businessCapabilitiesProvider.future);
    if (!canViewQuotations(capabilities)) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Your role cannot open quotations.',
      );
    }
    if (context == null || !context.hasOperationalScope) {
      throw const DomainError(
        code: 'BRANCH_REQUIRED',
        message: 'Choose a legal entity and branch to open quotations.',
      );
    }
    ref.watch(quotationWorkspaceRepositoryProvider);
    // Connectivity updates do not destroy in-progress fields or local recovery.
    ref.listen(connectivityStateProvider, (_, next) {
      final current = state.value;
      if (current != null && !state.isLoading) {
        state = AsyncData(
          current.copyWith(
            connectivity: next.value ?? ConnectivityState.offline,
          ),
        );
      }
    });
    final connectivity = await ref.read(connectivityStateProvider.future);
    final query = QuotationListQuery();
    var value = QuotationWorkspaceState(
      context: context,
      capabilities: Set.unmodifiable(capabilities),
      connectivity: connectivity,
      page: CursorPage(items: [], limit: 50),
      query: query,
    );
    try {
      if (connectivity == ConnectivityState.online) {
        value = value.copyWith(
          page: await _reader.pageQuotations(context: context, query: query),
        );
      }
    } on Object catch (error) {
      value = value.copyWith(error: _error(error));
    }
    return value;
  }

  bool _valid(int generation, TenantContext context) {
    if (!ref.mounted ||
        generation != _generation ||
        state.isLoading ||
        context != ref.read(activeTenantContextProvider)) {
      return false;
    }
    final current = ref.read(businessCapabilitiesProvider);
    final saved = state.value?.capabilities;
    return !current.isLoading &&
        !current.hasError &&
        current.value != null &&
        saved != null &&
        saved.length == current.value!.length &&
        current.value!.containsAll(saved);
  }

  QuotationWorkspaceState? get _current {
    if (!ref.mounted || state.isLoading) return null;
    final current = state.value;
    return current != null && _valid(_generation, current.context)
        ? current
        : null;
  }

  void _fail(Object error) {
    final current = _current;
    if (current != null) {
      state = AsyncData(
        current.copyWith(error: _error(error), busy: false, loading: false),
      );
    }
  }

  static Map<String, Object?> _clone(Map<String, Object?> raw) =>
      (jsonDecode(jsonEncode(raw)) as Map).cast<String, Object?>();

  Future<void> search(String text, {String? status}) async {
    final current = _current;
    if (current == null || current.busy) return;
    final generation = _generation, read = ++_read;
    try {
      final query = QuotationListQuery(search: text, status: status);
      state = AsyncData(current.copyWith(loading: true, error: null));
      final page = await _reader.pageQuotations(
        context: current.context,
        query: query,
      );
      if (_valid(generation, current.context) && read == _read) {
        state = AsyncData(
          state.requireValue.copyWith(page: page, query: query, loading: false),
        );
      }
    } on Object catch (error) {
      if (_valid(generation, current.context) && read == _read) _fail(error);
    }
  }

  Future<void> refresh() async {
    final current = _current;
    if (current != null) {
      await search(current.query.search, status: current.query.status);
    }
  }

  Future<void> loadMore() async {
    final current = _current;
    if (current == null ||
        current.loading ||
        current.busy ||
        !current.page.hasNextPage) {
      return;
    }
    final generation = _generation, read = ++_read;
    state = AsyncData(current.copyWith(loading: true, error: null));
    try {
      final page = await _reader.pageQuotations(
        context: current.context,
        query: QuotationListQuery(
          search: current.query.search,
          status: current.query.status,
          cursor: current.page.nextCursor,
        ),
      );
      if (_valid(generation, current.context) && read == _read) {
        state = AsyncData(
          state.requireValue.copyWith(
            page: CursorPage(
              items: [
                ...current.page.items,
                ...page.items.where(
                  (item) => !current.page.items.any((old) => old.id == item.id),
                ),
              ],
              limit: page.limit,
              nextCursor: page.nextCursor,
            ),
            loading: false,
          ),
        );
      }
    } on Object catch (error) {
      if (_valid(generation, current.context) && read == _read) _fail(error);
    }
  }

  Future<void> selectQuotation(String id) async {
    final current = _current;
    if (current == null || current.busy) return;
    final generation = _generation, selection = ++_selection;
    final store = _store;
    state = AsyncData(current.copyWith(loading: true, error: null));
    await _edits;
    if (!_valid(generation, current.context) || selection != _selection) return;
    if (!_canLeave(current)) return;
    try {
      final loaded = await Future.wait<Object?>([
        _reader.loadQuotationDetail(context: current.context, id: id),
        _reader.quotationRevisions(context: current.context, id: id),
        _reader.quotationDecisions(context: current.context, id: id),
        if (current.canManage)
          store.load(current.context, 'quotation:$id')
        else
          Future<QuotationLocalDraft?>.value(null),
      ]);
      if (!_valid(generation, current.context) || selection != _selection) {
        return;
      }
      final detail = loaded[0] as QuotationDetail?;
      if (detail == null) {
        throw const DomainError(
          code: 'NOT_FOUND',
          message: 'This quotation is no longer available in this scope.',
        );
      }
      final local = loaded[3] as QuotationLocalDraft?;
      final revisions = loaded[1] as List<SalesQuotationRevision>;
      final decisions = loaded[2] as List<Map<String, Object?>>;
      state = AsyncData(
        state.requireValue.copyWith(
          detail: detail,
          form: local?.form ?? detail.draft.toJson(),
          slot: 'quotation:$id',
          localDraft: local,
          revisions: revisions,
          decisions: decisions,
          moreRevisions: revisions.length == 100,
          moreDecisions: decisions.length == 100,
          loading: false,
          recovered: local != null,
          conflictDetail: null,
          statusMessage: null,
          editorEpoch: state.requireValue.editorEpoch + 1,
        ),
      );
    } on Object catch (error) {
      if (_valid(generation, current.context) && selection == _selection) {
        _fail(error);
      }
    }
  }

  Future<void> newDraft({String currencyCode = 'LKR'}) async {
    final current = _current;
    if (current == null || current.busy || !current.canManage) return;
    final generation = _generation, selection = ++_selection;
    final store = _store;
    await _edits;
    if (!_valid(generation, current.context) ||
        selection != _selection ||
        !_canLeave(current)) {
      return;
    }
    try {
      var local = await store.load(current.context, 'new');
      final recovered = local != null;
      final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
      final form =
          local?.form ??
          <String, Object?>{
            'customer_id': '',
            'quotation_date': today,
            'valid_until': today,
            'currency_code': currencyCode,
            'exchange_rate': '1.0000000000',
            'rate_date': today,
            'payment_terms_days': 0,
            'salesperson_id': current.context.actorId,
            'create_revision': false,
            'lines': <Object?>[],
          };
      if (!_valid(generation, current.context) || selection != _selection) {
        return;
      }
      if (local == null) {
        await store.save(current.context, 'new', form);
        local = await store.load(current.context, 'new');
      }
      if (!_valid(generation, current.context) || selection != _selection) {
        return;
      }
      state = AsyncData(
        state.requireValue.copyWith(
          detail: null,
          form: form,
          slot: 'new',
          localDraft: local,
          revisions: [],
          decisions: [],
          conflictDetail: null,
          loading: false,
          recovered: recovered,
          error: null,
          statusMessage: null,
          editorEpoch: state.requireValue.editorEpoch + 1,
        ),
      );
    } on Object catch (error) {
      if (_valid(generation, current.context) && selection == _selection) {
        _fail(error);
      }
    }
  }

  Future<void> recoverLocal(String slot) async {
    final current = _current;
    if (current == null || current.busy || !current.canManage) return;
    final generation = _generation, selection = ++_selection, store = _store;
    await _edits;
    if (!_valid(generation, current.context) ||
        selection != _selection ||
        !_canLeave(current)) {
      return;
    }
    try {
      final local = await store.load(current.context, slot);
      if (local == null) {
        throw const DomainError(
          code: 'NOT_FOUND',
          message: 'This local draft is no longer available.',
        );
      }
      if (!_valid(generation, current.context) || selection != _selection) {
        return;
      }
      // Recover without requiring a server read; retained version still guards writes.
      state = AsyncData(
        state.requireValue.copyWith(
          detail: null,
          form: local.form,
          slot: slot,
          localDraft: local,
          revisions: [],
          decisions: [],
          conflictDetail: null,
          recovered: true,
          loading: false,
          error: null,
          editorEpoch: state.requireValue.editorEpoch + 1,
          statusMessage: 'Recovered local fields. Server totals will be available after the quotation is refreshed.',
        ),
      );
      if (current.isOnline && local.form['id'] is String) {
        await selectQuotation(local.form['id']! as String);
      }
    } on Object catch (error) {
      if (_valid(generation, current.context) && selection == _selection) {
        _fail(error);
      }
    }
  }

  Future<void> updateForm(Map<String, Object?> form) {
    final current = _current;
    if (current == null || !current.canEditForm || current.slot == null) {
      return Future.value();
    }
    final raw = _clone(form),
        generation = _generation,
        selection = _selection,
        edit = ++_edit;
    final store = _store,
        slot = current.slot!,
        version =
            current.localDraft?.expectedVersion ??
            current.detail?.quotation.version;
    state = AsyncData(
      current.copyWith(
        form: raw,
        savingLocal: true,
        error: null,
        statusMessage: null,
      ),
    );
    // Capture the actor/scope, slot and complete fields before any asynchronous boundary.
    _edits = _edits.then((_) async {
      try {
        await store.save(current.context, slot, raw, expectedVersion: version);
        _failedEdits.remove(_editKey(current.context, slot));
        final local = await store.load(current.context, slot);
        if (_valid(generation, current.context) &&
            selection == _selection &&
            edit == _edit) {
          state = AsyncData(
            state.requireValue.copyWith(localDraft: local, savingLocal: false),
          );
        }
      } on Object catch (failure) {
        _failedEdits.add(_editKey(current.context, slot));
        if (_valid(generation, current.context) &&
            selection == _selection &&
            edit == _edit) {
          state = AsyncData(
            state.requireValue.copyWith(
              error: isLocalDraftStorageFailure(failure)
                  ? failure as DomainError
                  : _draftSaveError,
              savingLocal: false,
            ),
          );
        }
      }
    });
    return _edits;
  }

  Future<void> startRevision(String reason) async {
    final current = _current;
    if (current == null || !current.canRevise) return;
    if (reason.trim().isEmpty) {
      _fail(
        const DomainError(
          code: 'VALIDATION_ERROR',
          message: 'Enter a revision reason.',
        ),
      );
      return;
    }
    final raw = {
      ...current.detail!.draft.toJson(),
      'create_revision': true,
      'revision_reason': reason.trim(),
    };
    state = AsyncData(
      current.copyWith(form: raw, editorEpoch: current.editorEpoch + 1),
    );
    await updateForm(raw);
  }

  Future<void> save() => _command('save');
  Future<void> transition(String verb, {String? reason}) =>
      _command(verb, reason: reason);
  Future<void> decide({required bool approve, String? reason}) =>
      _command(approve ? 'approve' : 'reject', reason: reason);
  Future<void> retryPending() => _command('retry');

  Future<void> _command(String verb, {String? reason}) async {
    var current = _current;
    if (current == null || _commandActive || current.busy) return;
    if (!current.isOnline) {
      _fail(
        const DomainError(
          code: 'OFFLINE_COMMAND_BLOCKED',
          message: 'Reconnect before sending. Your draft is retained on this device.',
        ),
      );
      return;
    }
    final requiredApproval =
        (verb == 'retry' ? current.pending?.verb : verb) == 'approve' ||
        (verb == 'retry' ? current.pending?.verb : verb) == 'reject';
    if (!(requiredApproval ? current.canApprove : current.canManage)) {
      _fail(
        const DomainError(
          code: 'PERMISSION_DENIED',
          message: 'Your role cannot perform this action.',
        ),
      );
      return;
    }
    if (!current.context.hasOperationalScope || current.slot == null) return;
    if (current.conflict) {
      _fail(
        const DomainError(
          code: 'VERSION_CONFLICT',
          message: 'Compare the current server version and explicitly resolve your draft.',
        ),
      );
      return;
    }
    if (verb != 'retry' && current.pending != null) {
      _fail(
        const DomainError(
          code: 'COMMAND_PENDING',
          message: 'Retry the saved request before making other changes.',
        ),
      );
      return;
    }
    if (verb == 'save' && !current.canEditForm) return;
    if (verb != 'save' &&
        verb != 'retry' &&
        !current.allowedActions.contains(verb)) {
      _fail(
        const DomainError(
          code: 'INVALID_DOCUMENT_STATE',
          message: 'Save your edits or review the current workflow before this action.',
        ),
      );
      return;
    }
    final generation = _generation,
        selection = _selection,
        context = current.context,
        slot = current.slot!,
        store = _store;
    final repository = ref.read(leadToCashRepositoryProvider);
    if (repository == null) {
      _fail(
        const DomainError(
          code: 'BACKEND_UNAVAILABLE',
          message: 'The development service is unavailable.',
        ),
      );
      return;
    }
    _commandActive = true;
    state = AsyncData(
      current.copyWith(busy: true, error: null, statusMessage: null),
    );
    QuotationPendingCommand? pending;
    try {
      await _edits;
      if (!_valid(generation, context) || selection != _selection) return;
      current = state.requireValue;
      if (current.error != null) throw current.error!;
      if (verb == 'retry') {
        pending = (await store.load(context, slot))?.pending;
        if (pending == null) {
          throw const DomainError(
            code: 'COMMAND_PENDING',
            message: 'There is no saved request to retry.',
          );
        }
      } else {
        late Map<String, Object?> payload;
        if (verb == 'save') {
          final draft = QuotationDraftCodec.fromJson(current.form!);
          final validation = draft.validate();
          if (!validation.isValid) {
            throw DomainError(
              code: 'VALIDATION_ERROR',
              message: 'Review the quotation fields.',
              fieldDetails: {
                for (final issue in validation.issues)
                  issue.field: issue.message,
              },
            );
          }
          payload = draft.toJson();
        } else if (requiredApproval) {
          final decision = OperationalApprovalDecision(
            documentType: OperationalDocumentType.salesQuotation,
            documentId: current.detail!.quotation.id,
            decision: verb == 'approve'
                ? ApprovalDecision.approved
                : ApprovalDecision.rejected,
            note: reason,
          );
          if (!decision.validate().isValid) {
            throw const DomainError(
              code: 'VALIDATION_ERROR',
              message: 'A rejection reason is required.',
            );
          }
          payload = decision.toJson();
        } else {
          final transition = OperationalDocumentTransition(
            documentType: OperationalDocumentType.salesQuotation,
            documentId: current.detail!.quotation.id,
            action: OperationalDocumentAction.values.firstWhere(
              (a) => a.apiValue == verb,
            ),
            reason: reason,
          );
          if (!transition.validate().isValid) {
            throw const DomainError(
              code: 'VALIDATION_ERROR',
              message: 'A recall reason is required.',
            );
          }
          payload = transition.toJson();
        }
        final version =
            current.localDraft?.expectedVersion ??
            current.detail?.quotation.version;
        // Even lifecycle-only requests retain the current form and version before transport.
        await store.save(
          context,
          slot,
          current.form!,
          expectedVersion: version,
        );
        _failedEdits.remove(_editKey(context, slot));
        pending = await store.prepare(
          context,
          slot,
          verb: verb,
          payload: payload,
          expectedVersion: version,
        );
      }
      if (!_valid(generation, context) || selection != _selection) return;
      if (ref.read(connectivityStateProvider).value !=
          ConnectivityState.online) {
        throw const DomainError(
          code: 'NETWORK_ERROR',
          message: 'Connection changed before sending. Retry the saved request when online.',
          retryable: true,
        );
      }
      final envelope = pending.envelope;
      final payload = envelope.payload;
      final result = await switch (pending.verb) {
        'save' => repository.upsertQuotation(
          _typed(envelope, QuotationDraftCodec.fromJson(payload)),
        ),
        'approve' || 'reject' => repository.decideQuotationApproval(
          _typed(
            envelope,
            OperationalApprovalDecision(
              documentType: OperationalDocumentType.salesQuotation,
              documentId: payload['document_id']! as String,
              decision: payload['decision'] == 'approved'
                  ? ApprovalDecision.approved
                  : ApprovalDecision.rejected,
              note: payload['note'] as String?,
            ),
          ),
        ),
        _ => repository.transitionQuotation(
          _typed(
            envelope,
            OperationalDocumentTransition(
              documentType: OperationalDocumentType.salesQuotation,
              documentId: payload['document_id']! as String,
              action: OperationalDocumentAction.values.firstWhere(
                (a) => a.apiValue == payload['action'],
              ),
              reason: payload['reason'] as String?,
            ),
          ),
        ),
      };
      if (result.isFailure) throw result.error!;
      final entity = result.entity!;
      if (entity.tenantId != context.tenantId ||
          entity.legalEntityId != context.legalEntityId ||
          entity.branchId != context.branchId) {
        throw const DomainError(
          code: 'CONTRACT_ERROR',
          message: 'The returned quotation did not match the request scope.',
        );
      }
      await store.complete(context, slot, envelope.commandId);
      pending = null;
      if (!_valid(generation, context) || selection != _selection) return;
      state = AsyncData(
        state.requireValue.copyWith(
          localDraft: null,
          form: null,
          detail: null,
          slot: 'quotation:${entity.id}',
          page: CursorPage(
            items: [
              entity,
              ...state.requireValue.page.items.where(
                (item) => item.id != entity.id,
              ),
            ],
            limit: state.requireValue.page.limit,
            nextCursor: state.requireValue.page.nextCursor,
          ),
          busy: false,
          error: null,
          recovered: false,
        ),
      );
      await selectQuotation(entity.id);
      if (_valid(generation, context)) {
        state = AsyncData(
          state.requireValue.copyWith(
            statusMessage:
                '${verb == 'save' ? 'Quotation saved and recalculated' : 'Quotation action confirmed'}.',
            busy: false,
          ),
        );
      }
    } on Object catch (error) {
      final failure = _error(error);
      if (pending != null) {
        try {
          await store.recordFailure(
            context,
            slot,
            failure,
            commandId: pending.envelope.commandId,
          );
        } on Object {
          /* The persisted envelope remains available for exact replay. */
        }
      }
      if (_valid(generation, context) && selection == _selection) {
        QuotationLocalDraft? local;
        try {
          local = await store.load(context, slot);
        } on Object {
          /* Keep in-memory fields too. */
        }
        if (_valid(generation, context) && selection == _selection) {
          state = AsyncData(
            state.requireValue.copyWith(
              localDraft: local ?? state.requireValue.localDraft,
              busy: false,
              error: failure,
            ),
          );
        }
      }
    } finally {
      _commandActive = false;
      if (_valid(generation, context) && state.requireValue.busy) {
        state = AsyncData(state.requireValue.copyWith(busy: false));
      }
    }
  }

  static CommandEnvelope<T> _typed<T>(
    CommandEnvelope<Map<String, Object?>> wire,
    T payload,
  ) => CommandEnvelope(
    commandId: wire.commandId,
    idempotencyKey: wire.idempotencyKey,
    context: wire.context,
    payload: payload,
    clientTimestamp: wire.clientTimestamp,
    expectedEntityVersion: wire.expectedEntityVersion,
  );

  Future<void> inspectConflict() async {
    final current = _current;
    if (current == null ||
        !current.conflict ||
        current.detail == null ||
        !current.isOnline) {
      return;
    }
    final generation = _generation, selection = _selection;
    try {
      final latest = await _reader.loadQuotationDetail(
        context: current.context,
        id: current.detail!.quotation.id,
      );
      if (latest == null) {
        throw const DomainError(
          code: 'NOT_FOUND',
          message: 'The current quotation cannot be read in this scope.',
        );
      }
      if (_valid(generation, current.context) && selection == _selection) {
        state = AsyncData(state.requireValue.copyWith(conflictDetail: latest));
      }
    } on Object catch (error) {
      if (_valid(generation, current.context) && selection == _selection) {
        _fail(error);
      }
    }
  }

  Future<void> resolveConflict({required bool keepLocal}) async {
    final current = _current;
    if (current == null ||
        !current.conflict ||
        current.busy ||
        !current.canManage ||
        !current.isOnline) {
      return;
    }
    final generation = _generation, selection = _selection;
    // Resolve against the exact version the user compared. A later remote write
    // must produce another conflict, never silently become an overwrite target.
    if (current.conflictDetail == null) await inspectConflict();
    if (!_valid(generation, current.context) || selection != _selection) return;
    final latest = state.requireValue.conflictDetail;
    if (latest == null) return;
    if (keepLocal && latest.quotation.status != 'draft') {
      _fail(
        const DomainError(
          code: 'INVALID_DOCUMENT_STATE',
          message: 'The server quotation is no longer a draft. Use its version, then recall or create a revision.',
        ),
      );
      return;
    }
    try {
      final raw = keepLocal
          ? {...current.form!, 'create_revision': false}
          : latest.draft.toJson();
      final store = _store;
      if (keepLocal) {
        await store.save(
          current.context,
          current.slot!,
          raw,
          expectedVersion: latest.quotation.version,
          resolveConflict: true,
        );
      } else {
        await store.discard(current.context, current.slot!);
      }
      final local = await store.load(current.context, current.slot!);
      if (_valid(generation, current.context) && selection == _selection) {
        state = AsyncData(
          state.requireValue.copyWith(
            detail: latest,
            form: raw,
            localDraft: local,
            conflictDetail: null,
            error: null,
            recovered: false,
            editorEpoch: state.requireValue.editorEpoch + 1,
            statusMessage: keepLocal
                ? 'Local edits retained against the current version. Review and save when ready.'
                : 'Current server version loaded.',
          ),
        );
      }
    } on Object catch (error) {
      if (_valid(generation, current.context) && selection == _selection) {
        _fail(error);
      }
    }
  }

  Future<void> discardEdits() async {
    final current = _current;
    if (current == null ||
        current.busy ||
        current.pending != null ||
        !current.canManage) {
      return;
    }
    final generation = _generation, selection = _selection, store = _store;
    await _edits;
    try {
      await store.discard(current.context, current.slot!);
      _failedEdits.remove(_editKey(current.context, current.slot));
      if (_valid(generation, current.context) && selection == _selection) {
        state = AsyncData(
          state.requireValue.copyWith(
            form: current.detail?.draft.toJson(),
            localDraft: null,
            slot: current.detail == null ? null : current.slot,
            recovered: false,
            error: null,
            conflictDetail: null,
            editorEpoch: current.editorEpoch + 1,
          ),
        );
      }
    } on Object catch (error) {
      if (_valid(generation, current.context) && selection == _selection) {
        _fail(error);
      }
    }
  }

  Future<void> loadMoreRevisions() => _moreHistory(true);
  Future<void> loadMoreDecisions() => _moreHistory(false);
  Future<void> _moreHistory(bool revisions) async {
    final current = _current;
    if (current == null ||
        current.detail == null ||
        current.loading ||
        current.busy ||
        !(revisions ? current.moreRevisions : current.moreDecisions)) {
      return;
    }
    final generation = _generation, selection = _selection;
    state = AsyncData(current.copyWith(loading: true));
    try {
      if (revisions) {
        final next = await _reader.quotationRevisions(
          context: current.context,
          id: current.detail!.quotation.id,
          beforeRevision: current.revisions.last.revisionNumber,
        );
        if (_valid(generation, current.context) && selection == _selection) {
          state = AsyncData(
            state.requireValue.copyWith(
              revisions: [...current.revisions, ...next],
              moreRevisions: next.length == 100,
              loading: false,
            ),
          );
        }
      } else {
        final next = await _reader.quotationDecisions(
          context: current.context,
          id: current.detail!.quotation.id,
          beforeId: current.decisions.last['id']! as String,
        );
        if (_valid(generation, current.context) && selection == _selection) {
          state = AsyncData(
            state.requireValue.copyWith(
              decisions: [...current.decisions, ...next],
              moreDecisions: next.length == 100,
              loading: false,
            ),
          );
        }
      }
    } on Object catch (error) {
      if (_valid(generation, current.context) && selection == _selection) {
        _fail(error);
      }
    }
  }

  static DomainError _error(Object error) => error is DomainError
      ? error
      : error is FormatException
      ? DomainError(code: 'VALIDATION_ERROR', message: error.message)
      : const DomainError(
          code: 'NETWORK_ERROR',
          message: 'The request could not be confirmed. Your local fields and any pending request are retained.',
          retryable: true,
        );
}

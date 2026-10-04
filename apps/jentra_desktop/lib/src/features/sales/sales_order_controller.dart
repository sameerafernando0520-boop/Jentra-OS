import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

import '../../app_providers.dart';

final salesOrderProvider =
    AsyncNotifierProvider<SalesOrderController, SalesOrderState>(
      SalesOrderController.new,
      retry: (count, error) => null,
    );
const _unset = Object();
bool canViewOrders(Set<String> caps) =>
    const {'sales.orders.view', 'sales.orders.manage'}.any(caps.contains);

final class SalesOrderState {
  const SalesOrderState({
    required this.context,
    required this.capabilities,
    required this.connectivity,
    required this.page,
    required this.query,
    this.detail,
    this.conflictDetail,
    this.form,
    this.slot,
    this.localDraft,
    this.busy = false,
    this.loading = false,
    this.recovered = false,
    this.savingLocal = false,
    this.error,
    this.statusMessage,
    this.editorEpoch = 0,
    this.decisions = const [],
    this.reservations = const [],
    this.moreDecisions = false,
    this.moreReservations = false,
    this.credit,
    this.conflictQuote,
  });
  final TenantContext context;
  final Set<String> capabilities;
  final ConnectivityState connectivity;
  final CursorPage<SalesOrder> page;
  final SalesOrderListQuery query;
  final SalesOrderDetail? detail, conflictDetail;
  final QuotationDetail? conflictQuote;
  final Map<String, Object?>? form;
  final String? slot, statusMessage;
  final QuotationLocalDraft? localDraft;
  final bool busy,
      loading,
      recovered,
      savingLocal,
      moreDecisions,
      moreReservations;
  final DomainError? error;
  final int editorEpoch;
  final List<Map<String, Object?>> decisions, reservations;
  final SalesOrderCreditPreview? credit;
  bool get canManage => capabilities.contains('sales.orders.manage');
  bool get canReserve => capabilities.contains('inventory.reservations.manage');
  bool get canViewStock =>
      canReserve || capabilities.contains('inventory.stock.view');
  bool get canOverride =>
      canManage && capabilities.contains('sales.credit.override');
  bool get isOnline => connectivity == ConnectivityState.online;
  QuotationPendingCommand? get pending => localDraft?.pending;
  bool get conflict => localDraft?.errorCode == 'VERSION_CONFLICT';
  bool get dirty =>
      localDraft != null ||
      savingLocal ||
      error?.code == 'DRAFT_SAVE_FAILED' ||
      (error != null && isLocalDraftStorageFailure(error!));
  bool get conversion => form?['_conversion'] == true;
  bool get converted =>
      detail?.converted == true || form?['_source_quotation_id'] != null;
  bool get canEditForm =>
      canManage &&
      !busy &&
      !loading &&
      pending == null &&
      !conflict &&
      form != null &&
      (detail == null || detail!.canEdit);
  bool get canAct => !busy && !loading && !dirty && isOnline && detail != null;
  bool get canConfirm => canManage && canAct && detail!.canEdit;
  bool get canCancel =>
      canManage &&
      canAct &&
      !{
        'cancelled',
        'delivered',
        'partially_delivered',
      }.contains(detail!.order.status);
  bool get canReserveNow =>
      canReserve &&
      canAct &&
      {
        'confirmed',
        'partially_reserved',
        'reserved',
      }.contains(detail!.order.status);
  SalesOrderState copyWith({
    CursorPage<SalesOrder>? page,
    SalesOrderListQuery? query,
    ConnectivityState? connectivity,
    Object? detail = _unset,
    Object? conflictDetail = _unset,
    Object? conflictQuote = _unset,
    Object? form = _unset,
    Object? slot = _unset,
    Object? localDraft = _unset,
    Object? credit = _unset,
    Object? error = _unset,
    Object? statusMessage = _unset,
    bool? busy,
    bool? loading,
    bool? recovered,
    bool? savingLocal,
    bool? moreDecisions,
    bool? moreReservations,
    int? editorEpoch,
    List<Map<String, Object?>>? decisions,
    List<Map<String, Object?>>? reservations,
  }) => SalesOrderState(
    context: context,
    capabilities: capabilities,
    connectivity: connectivity ?? this.connectivity,
    page: page ?? this.page,
    query: query ?? this.query,
    detail: identical(detail, _unset)
        ? this.detail
        : detail as SalesOrderDetail?,
    conflictDetail: identical(conflictDetail, _unset)
        ? this.conflictDetail
        : conflictDetail as SalesOrderDetail?,
    conflictQuote: identical(conflictQuote, _unset)
        ? this.conflictQuote
        : conflictQuote as QuotationDetail?,
    form: identical(form, _unset) ? this.form : form as Map<String, Object?>?,
    slot: identical(slot, _unset) ? this.slot : slot as String?,
    localDraft: identical(localDraft, _unset)
        ? this.localDraft
        : localDraft as QuotationLocalDraft?,
    credit: identical(credit, _unset)
        ? this.credit
        : credit as SalesOrderCreditPreview?,
    error: identical(error, _unset) ? this.error : error as DomainError?,
    statusMessage: identical(statusMessage, _unset)
        ? this.statusMessage
        : statusMessage as String?,
    busy: busy ?? this.busy,
    loading: loading ?? this.loading,
    recovered: recovered ?? this.recovered,
    savingLocal: savingLocal ?? this.savingLocal,
    moreDecisions: moreDecisions ?? this.moreDecisions,
    moreReservations: moreReservations ?? this.moreReservations,
    editorEpoch: editorEpoch ?? this.editorEpoch,
    decisions: decisions ?? this.decisions,
    reservations: reservations ?? this.reservations,
  );
}

final class SalesOrderController extends AsyncNotifier<SalesOrderState> {
  int _generation = 0, _selection = 0, _read = 0, _edit = 0;
  bool _commandActive = false;
  Future<void> _edits = Future.value();
  final _failedEdits = <String>{};
  String _editKey(TenantContext context, String? slot) =>
      '${jsonEncode(context.toJson())}:$slot';
  bool _canLeave(SalesOrderState previous) {
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
  SalesOrderWorkspaceRepository get _reader =>
      ref.read(salesOrderRepositoryProvider) ??
      (throw const DomainError(
        code: 'BACKEND_UNAVAILABLE',
        message: 'Configure the development service to load sales orders.',
      ));
  QuotationDraftStore get _store => ref.read(salesOrderDraftStoreProvider);

  @override
  Future<SalesOrderState> build() async {
    ++_generation;
    ++_selection;
    ++_read;
    final context = ref.watch(activeTenantContextProvider);
    // Also observe AsyncValue changes: a refreshed future may retain its identity
    // while the resolved capability set changes.
    ref.watch(businessCapabilitiesProvider);
    final capabilities = await ref.watch(businessCapabilitiesProvider.future);
    if (!canViewOrders(capabilities)) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Your role cannot open sales orders.',
      );
    }
    if (context == null || !context.hasOperationalScope) {
      throw const DomainError(
        code: 'BRANCH_REQUIRED',
        message: 'Choose a legal entity and branch to open sales orders.',
      );
    }
    ref.watch(salesOrderRepositoryProvider);
    // Connectivity updates do not destroy in-progress fields or local recovery.
    ref.listen(connectivityStateProvider, (_, next) {
      final current = state.value;
      if (current != null && !state.isLoading) {
        state = AsyncData(
          current.copyWith(
            connectivity: !next.isLoading && !next.hasError
                ? next.value ?? ConnectivityState.offline
                : ConnectivityState.offline,
          ),
        );
      }
    });
    final connectivity = await ref.read(connectivityStateProvider.future);
    final query = SalesOrderListQuery();
    var value = SalesOrderState(
      context: context,
      capabilities: Set.unmodifiable(capabilities),
      connectivity: connectivity,
      page: CursorPage(items: [], limit: 50),
      query: query,
    );
    try {
      if (connectivity == ConnectivityState.online) {
        value = value.copyWith(
          page: await _reader.pageOrders(context: context, query: query),
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

  SalesOrderState? get _current {
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
    if (current == null || current.busy || !current.isOnline) return;
    final generation = _generation, read = ++_read;
    try {
      final query = SalesOrderListQuery(search: text, status: status);
      state = AsyncData(current.copyWith(loading: true, error: null));
      final page = await _reader.pageOrders(
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
      if (current.detail != null &&
          !current.dirty &&
          _current?.detail?.order.id == current.detail!.order.id) {
        await selectOrder(current.detail!.order.id);
      }
    }
  }

  Future<void> loadMore() async {
    final current = _current;
    if (current == null ||
        current.loading ||
        current.busy ||
        !current.isOnline ||
        !current.page.hasNextPage) {
      return;
    }
    final generation = _generation, read = ++_read;
    state = AsyncData(current.copyWith(loading: true, error: null));
    try {
      final page = await _reader.pageOrders(
        context: current.context,
        query: SalesOrderListQuery(
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
            current.detail?.order.version;
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

  Map<String, Object?> _formFor(SalesOrderDetail detail) => {
    ...detail.draft.toJson(),
    '_document_number': detail.order.documentNumber,
    if (detail.converted)
      '_source_quotation_id': detail.order.sourceQuotationId,
  };
  Future<void> selectOrder(String id) async {
    final current = _current;
    if (current == null || current.busy || !current.isOnline) return;
    final generation = _generation, selection = ++_selection, store = _store;
    state = AsyncData(current.copyWith(loading: true, error: null));
    await _edits;
    if (!_valid(generation, current.context) ||
        selection != _selection ||
        !_canLeave(current)) {
      return;
    }
    try {
      final detail = await _reader.loadOrder(context: current.context, id: id);
      if (detail == null) {
        throw const DomainError(
          code: 'NOT_FOUND',
          message: 'This order is no longer available in this scope.',
        );
      }
      final local = current.canManage || current.canReserve
          ? await store.load(current.context, 'order:$id')
          : null;
      if (!_valid(generation, current.context) || selection != _selection) {
        return;
      }
      state = AsyncData(
        state.requireValue.copyWith(
          detail: detail,
          form: local?.form ?? _formFor(detail),
          slot: 'order:$id',
          localDraft: local,
          loading: false,
          recovered: local != null,
          conflictDetail: null,
          conflictQuote: null,
          credit: null,
          decisions: [],
          reservations: [],
          moreDecisions: false,
          moreReservations: false,
          error: null,
          statusMessage: null,
          editorEpoch: current.editorEpoch + 1,
        ),
      );
      await loadHistory();
    } on Object catch (error) {
      if (_valid(generation, current.context) && selection == _selection) {
        _fail(error);
      }
    }
  }

  Future<void> newDraft({String currencyCode = 'LKR'}) =>
      _openDraft('new', () async {
        final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
        return {
          'customer_id': '',
          'order_date': today,
          'promised_date': today,
          'currency_code': currencyCode,
          'exchange_rate': '1.0000000000',
          'rate_date': today,
          'payment_terms_days': 0,
          'warehouse_id': '',
          'ship_to': <String, Object?>{},
          'lines': <Object?>[],
        };
      });

  Future<void> openConvertedOrder(String quotationId) async {
    final current = _current;
    if (current == null || current.busy || !current.isOnline) return;
    final generation = _generation, selection = _selection;
    try {
      final page = await _reader.pageOrders(
        context: current.context,
        query: SalesOrderListQuery(sourceQuotationId: quotationId, limit: 2),
      );
      if (!_valid(generation, current.context) || selection != _selection) {
        return;
      }
      if (page.items.length != 1) {
        throw const DomainError(
          code: 'NOT_FOUND',
          message: 'The converted order is not available in this scope.',
        );
      }
      await selectOrder(page.items.single.id);
    } on Object catch (error) {
      if (_valid(generation, current.context) && selection == _selection) {
        _fail(error);
      }
    }
  }

  Future<void> startConversion(String quotationId) async {
    final current = _current;
    if (current == null || !current.canManage || !current.isOnline) return;
    await _openDraft('convert:$quotationId', () async {
      final reader = ref.read(quotationWorkspaceRepositoryProvider);
      final quote = await reader?.loadQuotationDetail(
        context: current.context,
        id: quotationId,
      );
      if (quote == null || quote.quotation.status != 'accepted') {
        throw const DomainError(
          code: 'INVALID_DOCUMENT_STATE',
          message: 'Open an accepted quotation to create its order.',
        );
      }
      return {
        '_conversion': true,
        'quotation_id': quotationId,
        'quotation_revision': quote.quotation.currentRevision,
        '_quote_version': quote.quotation.version,
        '_document_number': quote.quotation.documentNumber,
        'currency_code': quote.quotation.currencyCode,
        'promised_date': DateTime.now().toUtc().toIso8601String().substring(
          0,
          10,
        ),
        'warehouse_id': '',
        'ship_to': <String, Object?>{},
        '_source_total': quote.quotation.grandTotal.toDecimalString(),
      };
    });
  }

  Future<void> _openDraft(
    String slot,
    Future<Map<String, Object?>> Function() create,
  ) async {
    final current = _current;
    if (current == null || current.busy || !current.canManage) return;
    final generation = _generation, selection = ++_selection, store = _store;
    await _edits;
    if (!_valid(generation, current.context) ||
        selection != _selection ||
        !_canLeave(current)) {
      return;
    }
    state = AsyncData(current.copyWith(loading: true, error: null));
    try {
      var local = await store.load(current.context, slot);
      final recovered = local != null;
      final form = local?.form ?? await create();
      if (!_valid(generation, current.context) || selection != _selection) {
        return;
      }
      if (local == null) {
        await store.save(
          current.context,
          slot,
          form,
          expectedVersion: form['_quote_version'] as int?,
        );
        local = await store.load(current.context, slot);
      }
      if (!_valid(generation, current.context) || selection != _selection) {
        return;
      }
      state = AsyncData(
        state.requireValue.copyWith(
          detail: null,
          form: form,
          slot: slot,
          localDraft: local,
          recovered: recovered,
          loading: false,
          credit: null,
          decisions: [],
          reservations: [],
          conflictDetail: null,
          conflictQuote: null,
          editorEpoch: current.editorEpoch + 1,
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
    if (current == null ||
        current.busy ||
        !(current.canManage || current.canReserve)) {
      return;
    }
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
          message: 'The saved draft is no longer available.',
        );
      }
      if (!_valid(generation, current.context) || selection != _selection) {
        return;
      }
      state = AsyncData(
        current.copyWith(
          detail: null,
          form: local.form,
          slot: slot,
          localDraft: local,
          recovered: true,
          credit: null,
          decisions: [],
          reservations: [],
          conflictDetail: null,
          conflictQuote: null,
          error: null,
          editorEpoch: current.editorEpoch + 1,
        ),
      );
      if (current.isOnline && local.form['id'] is String) {
        await selectOrder(local.form['id']! as String);
      }
    } on Object catch (error) {
      if (_valid(generation, current.context) && selection == _selection) {
        _fail(error);
      }
    }
  }

  Future<void> loadHistory({
    bool moreDecisions = false,
    bool moreReservations = false,
  }) async {
    final current = _current;
    if (current == null ||
        current.detail == null ||
        current.busy ||
        !current.isOnline) {
      return;
    }
    final generation = _generation,
        selection = _selection,
        id = current.detail!.order.id;
    try {
      final decisions = moreReservations
          ? current.decisions
          : await _reader.creditDecisions(
              context: current.context,
              id: id,
              beforeId: moreDecisions
                  ? (current.decisions.isEmpty
                        ? null
                        : current.decisions.last['id'] as String?)
                  : null,
            );
      final reservations = !current.canViewStock || moreDecisions
          ? current.reservations
          : await _reader.reservations(
              context: current.context,
              id: id,
              afterId: moreReservations
                  ? (current.reservations.isEmpty
                        ? null
                        : current.reservations.last['id'] as String?)
                  : null,
            );
      if (!_valid(generation, current.context) || selection != _selection) {
        return;
      }
      state = AsyncData(
        state.requireValue.copyWith(
          decisions: moreDecisions
              ? [...current.decisions, ...decisions]
              : decisions,
          reservations: moreReservations
              ? [...current.reservations, ...reservations]
              : reservations,
          moreDecisions: moreReservations
              ? current.moreDecisions
              : decisions.length == 100,
          moreReservations: moreDecisions
              ? current.moreReservations
              : reservations.length == 100,
        ),
      );
    } on Object catch (error) {
      if (_valid(generation, current.context) && selection == _selection) {
        _fail(error);
      }
    }
  }

  Future<void> reviewCredit() async {
    final current = _current;
    if (current == null || !current.canConfirm) return;
    final generation = _generation, selection = _selection;
    state = AsyncData(
      current.copyWith(loading: true, credit: null, error: null),
    );
    try {
      final preview = await _reader.creditPreview(
        context: current.context,
        id: current.detail!.order.id,
      );
      if (preview.orderId != current.detail!.order.id ||
          preview.orderVersion != current.detail!.order.version) {
        throw const DomainError(
          code: 'STALE_PREVIEW',
          message: 'The order changed. Refresh it before reviewing credit.',
        );
      }
      if (_valid(generation, current.context) && selection == _selection) {
        state = AsyncData(
          state.requireValue.copyWith(credit: preview, loading: false),
        );
      }
    } on Object catch (error) {
      if (_valid(generation, current.context) && selection == _selection) {
        _fail(error);
      }
    }
  }

  Future<void> save() => _command(
    _current?.conversion == true
        ? 'convert'
        : _current?.converted == true
        ? 'fulfillment'
        : 'save',
  );
  Future<void> confirm({bool overrideCredit = false, String? reason}) =>
      _command(
        'confirm',
        extra: {'override_credit': overrideCredit, 'override_reason': ?reason},
      );
  Future<void> cancel(String reason) =>
      _command('cancel', extra: {'reason': reason});
  Future<void> reserve(StockReservationDraft draft) =>
      _command('reserve', extra: draft.toJson());
  Future<void> retryPending() => _command('retry');

  Future<void> _command(
    String verb, {
    Map<String, Object?> extra = const {},
  }) async {
    var current = _current;
    if (current == null ||
        current.busy ||
        current.loading ||
        _commandActive ||
        current.slot == null) {
      return;
    }
    final connection = ref.read(connectivityStateProvider);
    if (!current.isOnline ||
        connection.isLoading ||
        connection.hasError ||
        connection.value != ConnectivityState.online) {
      _fail(
        const DomainError(
          code: 'OFFLINE_COMMAND_BLOCKED',
          message: 'Reconnect to send this command. Your encrypted draft is retained.',
        ),
      );
      return;
    }
    final action = verb == 'retry' ? current.pending?.verb : verb;
    final payloadOverride = verb == 'retry'
        ? current.pending?.envelope.payload['override_credit'] == true
        : extra['override_credit'] == true;
    if (!(action == 'reserve' ? current.canReserve : current.canManage) ||
        (payloadOverride && !current.canOverride)) {
      _fail(
        const DomainError(
          code: 'PERMISSION_DENIED',
          message: 'Your current role cannot perform this action.',
        ),
      );
      return;
    }
    if (current.conflict) {
      _fail(
        const DomainError(
          code: 'VERSION_CONFLICT',
          message: 'Compare the current server version before continuing.',
        ),
      );
      return;
    }
    if (verb != 'retry' && current.pending != null) {
      _fail(
        const DomainError(
          code: 'COMMAND_PENDING',
          message: 'Retry the stored request first.',
        ),
      );
      return;
    }
    if (verb != 'retry' &&
        !(switch (verb) {
          'save' || 'convert' || 'fulfillment' => current.canEditForm,
          'confirm' => current.canConfirm,
          'cancel' => current.canCancel,
          'reserve' => current.canReserveNow,
          _ => false,
        })) {
      _fail(
        const DomainError(
          code: 'INVALID_DOCUMENT_STATE',
          message:
              'Save or discard your edits and review the current order state.',
        ),
      );
      return;
    }
    final generation = _generation,
        selection = _selection,
        context = current.context,
        slot = current.slot!,
        store = _store,
        reader = _reader;
    final capabilities = current.capabilities;
    var accessLost = false;
    void observeAccess() {
      if (accessLost) return;
      if (!ref.mounted) {
        accessLost = true;
        return;
      }
      final caps = ref.read(businessCapabilitiesProvider);
      final connectivity = ref.read(connectivityStateProvider);
      accessLost =
          ref.read(activeTenantContextProvider) != context ||
          caps.isLoading ||
          caps.hasError ||
          caps.value == null ||
          caps.value!.length != capabilities.length ||
          !caps.value!.containsAll(capabilities) ||
          connectivity.isLoading ||
          connectivity.hasError ||
          connectivity.value != ConnectivityState.online;
    }

    final scopes = ref.listen(
      activeTenantContextProvider,
      (_, _) => observeAccess(),
    );
    final permissions = ref.listen(
      businessCapabilitiesProvider,
      (_, _) => observeAccess(),
    );
    final connections = ref.listen(
      connectivityStateProvider,
      (_, _) => observeAccess(),
    );
    void checkPreparationAccess() {
      observeAccess();
      if (accessLost ||
          !_valid(generation, context) ||
          selection != _selection) {
        throw const DomainError(
          code: 'ACCESS_CHANGED',
          message: 'Business access or connection changed before sending. Your encrypted fields and any prepared request are retained. Review them and explicitly retry when authorized and online.',
          retryable: true,
        );
      }
    }

    _commandActive = true;
    state = AsyncData(
      current.copyWith(busy: true, error: null, statusMessage: null),
    );
    QuotationPendingCommand? pending;
    try {
      await _edits;
      checkPreparationAccess();
      current = state.requireValue;
      pending = (await store.load(context, slot))?.pending;
      checkPreparationAccess();
      if (verb == 'retry' && pending == null) {
        throw const DomainError(
          code: 'NOT_FOUND',
          message: 'There is no pending request.',
        );
      }
      if (pending == null) {
        final raw = current.form!;
        Map<String, Object?> payload;
        if (verb == 'save') {
          final draft = SalesOrderDraftCodec.fromJson(raw);
          _validate(draft.validate());
          payload = draft.toJson();
        } else if (verb == 'convert' || verb == 'fulfillment') {
          final promised = _date(raw['promised_date']);
          final warehouse = raw['warehouse_id'];
          if (warehouse is! String ||
              warehouse.trim().isEmpty ||
              raw['ship_to'] is! Map) {
            throw const FormatException(
              'Choose a warehouse and ship-to address.',
            );
          }
          payload = {
            'promised_date': promised,
            'warehouse_id': warehouse,
            'ship_to': raw['ship_to'],
            if (verb == 'convert') ...{
              'quotation_id': raw['quotation_id'],
              'quotation_revision': raw['quotation_revision'],
            } else
              'id': current.detail?.order.id ?? raw['id'],
          };
        } else if (verb == 'reserve') {
          if (extra['sales_order_id'] != current.detail!.order.id) {
            throw const FormatException(
              'Reservation must belong to this order.',
            );
          }
          final expires = DateTime.tryParse(
            extra['expires_at']?.toString() ?? '',
          );
          if (expires == null || !expires.isAfter(DateTime.now().toUtc())) {
            throw const FormatException(
              'Reservation expiry must be in the future.',
            );
          }
          final lines = extra['lines'];
          if (lines is! List || lines.isEmpty || lines.length > 500) {
            throw const FormatException('Choose at least one stocked line.');
          }
          final seen = <String>{};
          for (final row in lines) {
            final line = current.detail!.order.lines
                .where((l) => l.id == (row as Map)['sales_order_line_id'])
                .firstOrNull;
            final text = (row as Map)['requested_base_quantity'];
            if (line == null ||
                !seen.add(line.id) ||
                text is! String ||
                !RegExp(r'^[0-9]+(?:\.[0-9]{1,6})?$').hasMatch(text)) {
              throw const FormatException(
                'Review reservation lines and exact quantities.',
              );
            }
            final quantity = ExactDecimal.parse(text, scale: 6);
            if (!quantity.isPositive ||
                quantity.scaledValue > line.remainingToReserve.scaledValue) {
              throw const FormatException(
                'Reservation exceeds remaining demand.',
              );
            }
          }
          payload = extra;
        } else {
          final transition = OperationalDocumentTransition(
            documentType: OperationalDocumentType.salesOrder,
            documentId: current.detail!.order.id,
            action: verb == 'confirm'
                ? OperationalDocumentAction.confirm
                : OperationalDocumentAction.cancel,
            overrideCredit: payloadOverride,
            overrideReason: extra['override_reason'] as String?,
            reason: extra['reason'] as String?,
          );
          _validate(transition.validate());
          if (verb == 'cancel' &&
              (extra['reason'] as String? ?? '').trim().isEmpty) {
            throw const FormatException('Enter a cancellation reason.');
          }
          if (verb == 'confirm' &&
              current.credit?.orderVersion != current.detail!.order.version) {
            throw const FormatException('Review credit before confirming.');
          }
          payload = transition.toJson();
        }
        final version =
            current.localDraft?.expectedVersion ??
            current.detail?.order.version;
        await store.save(context, slot, raw, expectedVersion: version);
        _failedEdits.remove(_editKey(context, slot));
        checkPreparationAccess();
        pending = await store.prepare(
          context,
          slot,
          verb: verb,
          payload: payload,
          expectedVersion: version,
        );
      }
      checkPreparationAccess();
      final result = await reader.executeOrder(pending.verb, pending.envelope);
      if (result.isFailure) throw result.error!;
      final entity = result.entity!;
      if (entity.tenantId != context.tenantId ||
          entity.legalEntityId != context.legalEntityId ||
          entity.branchId != context.branchId) {
        throw const DomainError(
          code: 'CONTRACT_ERROR',
          message: 'Returned order does not match the requested scope.',
        );
      }
      await store.complete(context, slot, pending.envelope.commandId);
      pending = null;
      if (!_valid(generation, context) || selection != _selection) return;
      if (accessLost) {
        state = AsyncData(
          state.requireValue.copyWith(
            localDraft: null,
            form: null,
            detail: null,
            slot: null,
            credit: null,
            busy: false,
            recovered: false,
            error: const DomainError(
              code: 'ACCESS_CHANGED',
              message: 'The original request was acknowledged. Business access or connection changed while it was pending. Refresh the current workspace to review the result.',
            ),
          ),
        );
        return;
      }
      // Clear the committed form before follow-up reads, even if those reads fail.
      state = AsyncData(
        state.requireValue.copyWith(
          form: null,
          localDraft: null,
          detail: null,
          slot: 'order:${entity.id}',
          busy: false,
          credit: null,
          page: CursorPage(
            items: [
              entity,
              ...state.requireValue.page.items.where((o) => o.id != entity.id),
            ],
            limit: current.page.limit,
            nextCursor: current.page.nextCursor,
          ),
        ),
      );
      await selectOrder(entity.id);
      if (_valid(generation, context)) {
        state = AsyncData(
          state.requireValue.copyWith(
            statusMessage: entity.status == 'credit_hold'
                ? 'Credit limit exceeded. The order is on credit hold; the decision is recorded.'
                : 'Order action confirmed${result.warnings.isEmpty ? '.' : ': ${result.warnings.join(', ')}'}',
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
          /* Retain immutable retry. */
        }
      }
      QuotationLocalDraft? local;
      try {
        local = await store.load(context, slot);
      } on Object {
        /* Keep visible fields. */
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
    } finally {
      scopes.close();
      permissions.close();
      connections.close();
      _commandActive = false;
      if (_valid(generation, context) && state.requireValue.busy) {
        state = AsyncData(state.requireValue.copyWith(busy: false));
      }
    }
  }

  Future<void> inspectConflict() async {
    final current = _current;
    if (current == null || !current.conflict || !current.isOnline) return;
    final generation = _generation, selection = _selection;
    try {
      if (current.conversion) {
        final quote = await ref
            .read(quotationWorkspaceRepositoryProvider)
            ?.loadQuotationDetail(
              context: current.context,
              id: current.form!['quotation_id']! as String,
            );
        if (_valid(generation, current.context) && selection == _selection) {
          state = AsyncData(state.requireValue.copyWith(conflictQuote: quote));
        }
      } else {
        final detail = await _reader.loadOrder(
          context: current.context,
          id: current.form!['id']! as String,
        );
        if (detail == null) {
          throw const DomainError(
            code: 'NOT_FOUND',
            message: 'The current order is unavailable.',
          );
        }
        if (_valid(generation, current.context) && selection == _selection) {
          state = AsyncData(
            state.requireValue.copyWith(conflictDetail: detail),
          );
        }
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
        !current.isOnline ||
        !current.canManage) {
      return;
    }
    final latest = current.conflictDetail, quote = current.conflictQuote;
    if (current.conversion) {
      if (quote == null || quote.quotation.status != 'accepted') {
        _fail(
          const DomainError(
            code: 'INVALID_DOCUMENT_STATE',
            message: 'This quotation is no longer accepted. Discard this draft and inspect the quotation.',
          ),
        );
        return;
      }
    } else if (latest == null || (keepLocal && !latest.canEdit)) {
      _fail(
        const DomainError(
          code: 'INVALID_DOCUMENT_STATE',
          message: 'Inspect the latest version. Local edits can only be retained for an editable order.',
        ),
      );
      return;
    }
    final generation = _generation, selection = _selection, store = _store;
    try {
      final form = current.conversion
          ? {
              ...current.form!,
              'quotation_revision': quote!.quotation.currentRevision,
              '_quote_version': quote.quotation.version,
            }
          : keepLocal
          ? current.form!
          : _formFor(latest!);
      final version = current.conversion
          ? quote!.quotation.version
          : latest!.order.version;
      if (keepLocal || current.conversion) {
        await store.save(
          current.context,
          current.slot!,
          form,
          expectedVersion: version,
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
            form: form,
            localDraft: local,
            conflictDetail: null,
            conflictQuote: null,
            credit: null,
            error: null,
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

  Future<void> discardEdits() async {
    final current = _current;
    if (current == null ||
        current.busy ||
        current.pending != null ||
        !(current.canManage || current.canReserve) ||
        current.slot == null) {
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
            form: current.detail == null ? null : _formFor(current.detail!),
            localDraft: null,
            slot: current.detail == null ? null : current.slot,
            error: null,
            credit: null,
            conflictDetail: null,
            conflictQuote: null,
            recovered: false,
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

  static String _date(Object? raw) {
    if (raw is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
      throw const FormatException('Enter a date as YYYY-MM-DD.');
    }
    final date = DateTime.tryParse('${raw}T00:00:00Z');
    if (date == null || date.toIso8601String().substring(0, 10) != raw) {
      throw const FormatException('Enter a valid date.');
    }
    return raw;
  }

  static void _validate(ValidationResult validation) {
    if (!validation.isValid) {
      throw DomainError(
        code: 'VALIDATION_ERROR',
        message: validation.issues
            .map((i) => '${i.field}: ${i.message}')
            .join('\n'),
      );
    }
  }

  static DomainError _error(Object error) => error is DomainError
      ? error
      : error is FormatException
      ? DomainError(code: 'VALIDATION_ERROR', message: error.message)
      : const DomainError(
          code: 'NETWORK_ERROR',
          message: 'The request could not be confirmed. Local fields and any pending request are retained.',
          retryable: true,
        );
}

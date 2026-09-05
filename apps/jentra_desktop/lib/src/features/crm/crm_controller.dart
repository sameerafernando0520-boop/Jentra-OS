import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';

import '../../app_providers.dart';

final crmControllerProvider =
    AsyncNotifierProvider<CrmController, CrmWorkspaceState>(CrmController.new);

final class CrmWorkspaceState {
  const CrmWorkspaceState({
    required this.page,
    required this.summary,
    required this.query,
    required this.capabilities,
    required this.connectivity,
    required this.activities,
    this.selectedEntry,
    this.selectedLead,
    this.selectedOpportunity,
    this.detailLoading = false,
  });

  final CursorPage<CrmPipelineEntry> page;
  final CrmPipelineSummary summary;
  final CrmPipelineQuery query;
  final Set<String> capabilities;
  final ConnectivityState connectivity;
  final CrmPipelineEntry? selectedEntry;
  final CrmLead? selectedLead;
  final CrmOpportunity? selectedOpportunity;
  final List<CrmActivity> activities;
  final bool detailLoading;

  bool get canManageLeads => capabilities.contains('crm.leads.manage');
  bool get isOnline => connectivity == ConnectivityState.online;

  CrmWorkspaceState copyWith({
    CursorPage<CrmPipelineEntry>? page,
    CrmPipelineSummary? summary,
    CrmPipelineQuery? query,
    Set<String>? capabilities,
    ConnectivityState? connectivity,
    CrmPipelineEntry? selectedEntry,
    CrmLead? selectedLead,
    CrmOpportunity? selectedOpportunity,
    List<CrmActivity>? activities,
    bool? detailLoading,
    bool clearSelectedEntry = false,
    bool clearSelectedLead = false,
    bool clearSelectedOpportunity = false,
  }) => CrmWorkspaceState(
    page: page ?? this.page,
    summary: summary ?? this.summary,
    query: query ?? this.query,
    capabilities: capabilities ?? this.capabilities,
    connectivity: connectivity ?? this.connectivity,
    selectedEntry: clearSelectedEntry
        ? null
        : selectedEntry ?? this.selectedEntry,
    selectedLead: clearSelectedLead ? null : selectedLead ?? this.selectedLead,
    selectedOpportunity: clearSelectedOpportunity
        ? null
        : selectedOpportunity ?? this.selectedOpportunity,
    activities: activities ?? this.activities,
    detailLoading: detailLoading ?? this.detailLoading,
  );
}

final class CrmController extends AsyncNotifier<CrmWorkspaceState> {
  @override
  Future<CrmWorkspaceState> build() async {
    final capabilities = await ref.watch(businessCapabilitiesProvider.future);
    if (!_canViewCrm(capabilities)) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Your role cannot open CRM records.',
      );
    }
    final connectivity = await ref.watch(connectivityStateProvider.future);
    return _loadWorkspace(
      query: CrmPipelineQuery(),
      capabilities: capabilities,
      connectivity: connectivity,
    );
  }

  Future<void> applySearch(String search) async {
    final current = state.value;
    if (current == null) return;
    final query = current.query.copyWith(search: search, clearCursor: true);
    await _reload(current, query: query);
  }

  Future<void> refresh() async {
    final current = state.value;
    if (current == null) {
      ref.invalidateSelf();
      return;
    }
    await _reload(
      current,
      query: current.query.copyWith(clearCursor: true),
      preferredSelectionId: current.selectedEntry?.id,
    );
  }

  Future<void> selectEntry(CrmPipelineEntry entry) async {
    final current = state.value;
    if (current == null || current.selectedEntry?.id == entry.id) return;
    state = AsyncData(
      current.copyWith(
        selectedEntry: entry,
        activities: const [],
        detailLoading: true,
        clearSelectedLead: true,
        clearSelectedOpportunity: true,
      ),
    );
    try {
      final detail = await _loadSelection(_repository(), _context(), entry);
      final latest = state.value;
      if (latest == null || latest.selectedEntry?.id != entry.id) return;
      state = AsyncData(
        latest.copyWith(
          selectedLead: detail.lead,
          selectedOpportunity: detail.opportunity,
          activities: detail.activities,
          detailLoading: false,
          clearSelectedLead: detail.lead == null,
          clearSelectedOpportunity: detail.opportunity == null,
        ),
      );
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  Future<CommandResult<CrmLead>> createLead({
    required CrmLeadDraft draft,
    required String commandId,
    required String idempotencyKey,
  }) async {
    final current = state.value;
    if (current == null) {
      return _leadFailure(
        idempotencyKey,
        const DomainError(
          code: 'NOT_READY',
          message: 'CRM is still loading.',
          retryable: true,
        ),
      );
    }
    if (!current.canManageLeads) {
      return _leadFailure(
        idempotencyKey,
        const DomainError(
          code: 'PERMISSION_DENIED',
          message: 'Your role cannot create leads.',
        ),
      );
    }
    if (!current.isOnline) {
      return _leadFailure(
        idempotencyKey,
        const DomainError(
          code: 'OFFLINE_COMMAND_BLOCKED',
          message: 'Reconnect before creating a lead.',
          retryable: true,
        ),
      );
    }

    final result = await _repository().upsertLead(
      CommandEnvelope<CrmLeadDraft>(
        commandId: commandId,
        idempotencyKey: idempotencyKey,
        context: _context(),
        payload: draft,
      ),
    );
    if (result.isSuccess) await refresh();
    return result;
  }

  Future<void> _reload(
    CrmWorkspaceState current, {
    required CrmPipelineQuery query,
    String? preferredSelectionId,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _loadWorkspace(
        query: query,
        capabilities: current.capabilities,
        connectivity: current.connectivity,
        preferredSelectionId: preferredSelectionId,
      ),
    );
  }

  Future<CrmWorkspaceState> _loadWorkspace({
    required CrmPipelineQuery query,
    required Set<String> capabilities,
    required ConnectivityState connectivity,
    String? preferredSelectionId,
  }) async {
    final context = _context();
    final repository = _repository();
    final pipelineFuture = repository.listPipeline(
      context: context,
      query: query,
    );
    final summaryFuture = repository.getPipelineSummary(
      context: context,
      asOfDate: DateTime.now().toUtc(),
    );
    final loaded = await Future.wait<Object>([pipelineFuture, summaryFuture]);
    final page = loaded[0] as CursorPage<CrmPipelineEntry>;
    final summary = loaded[1] as CrmPipelineSummary;
    final selected = _preferredEntry(page.items, preferredSelectionId);
    final detail = selected == null
        ? const _SelectionDetail()
        : await _loadSelection(repository, context, selected);
    return CrmWorkspaceState(
      page: page,
      summary: summary,
      query: query,
      capabilities: capabilities,
      connectivity: connectivity,
      selectedEntry: selected,
      selectedLead: detail.lead,
      selectedOpportunity: detail.opportunity,
      activities: detail.activities,
    );
  }

  Future<_SelectionDetail> _loadSelection(
    CrmRepository repository,
    TenantContext context,
    CrmPipelineEntry entry,
  ) async {
    final aggregateType = switch (entry.entryType) {
      CrmEntryType.lead => CrmAggregateType.lead,
      CrmEntryType.opportunity => CrmAggregateType.opportunity,
    };
    final activityFuture = repository.listActivities(
      context: context,
      aggregateType: aggregateType,
      aggregateId: entry.id,
    );
    if (entry.entryType == CrmEntryType.lead) {
      final leadFuture = repository.findLead(context: context, id: entry.id);
      return _SelectionDetail(
        lead: await leadFuture,
        activities: await activityFuture,
      );
    }
    final opportunityFuture = repository.findOpportunity(
      context: context,
      id: entry.id,
    );
    return _SelectionDetail(
      opportunity: await opportunityFuture,
      activities: await activityFuture,
    );
  }

  TenantContext _context() {
    final context = ref.read(activeTenantContextProvider);
    if (context == null || !context.hasAccountingScope) {
      throw const DomainError(
        code: 'LEGAL_ENTITY_REQUIRED',
        message: 'Choose a legal entity before opening CRM.',
        fieldDetails: {'legal_entity_id': 'Required.'},
      );
    }
    return context;
  }

  CrmRepository _repository() {
    final repository = ref.read(crmRepositoryProvider);
    if (repository == null) {
      throw const DomainError(
        code: 'BACKEND_UNAVAILABLE',
        message: 'CRM requires a configured development service.',
      );
    }
    return repository;
  }

  static bool _canViewCrm(Set<String> capabilities) => const {
    'crm.leads.view',
    'crm.leads.manage',
    'crm.opportunities.view',
    'crm.opportunities.manage',
  }.any(capabilities.contains);

  static CrmPipelineEntry? _preferredEntry(
    List<CrmPipelineEntry> entries,
    String? preferredId,
  ) {
    if (preferredId != null) {
      for (final entry in entries) {
        if (entry.id == preferredId) return entry;
      }
    }
    return entries.firstOrNull;
  }

  static CommandResult<CrmLead> _leadFailure(
    String requestId,
    DomainError error,
  ) => CommandResult.failure(requestId: requestId, error: error);
}

final class _SelectionDetail {
  const _SelectionDetail({
    this.lead,
    this.opportunity,
    this.activities = const [],
  });

  final CrmLead? lead;
  final CrmOpportunity? opportunity;
  final List<CrmActivity> activities;
}

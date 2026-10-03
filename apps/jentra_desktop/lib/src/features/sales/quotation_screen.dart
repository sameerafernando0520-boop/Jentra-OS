import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

import '../../app_providers.dart';
import 'quotation_controller.dart';
import 'quotation_document_view.dart';
import 'quotation_editor.dart';
import 'quotation_recovery_dialog.dart';
import 'quotation_scope_guard.dart';
import 'sales_order_controller.dart';
import 'sales_order_screen.dart';

class QuotationScreen extends ConsumerWidget {
  const QuotationScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(businessCapabilitiesProvider)
      .when(
        skipLoadingOnRefresh: false,
        loading: () => const _Loading(),
        error: (error, _) => _Unavailable(
          error: error,
          onRetry: () => ref.invalidate(businessCapabilitiesProvider),
        ),
        data: (capabilities) {
          if (!canViewQuotations(capabilities)) {
            if (canViewOrders(capabilities)) return const SalesOrderScreen();
            return const Padding(
              padding: EdgeInsets.all(20),
              child: JentraPanel(
                child: JentraEmptyState(
                  icon: Icons.lock_outline,
                  title: 'Access is restricted',
                  description: 'Your role does not include permission to view quotations.',
                ),
              ),
            );
          }
          return ref
              .watch(quotationWorkspaceProvider)
              .when(
                skipLoadingOnRefresh: false,
                skipLoadingOnReload: false,
                loading: () => const _Loading(),
                error: (error, _) => _Unavailable(
                  error: error,
                  onRetry: () => ref.invalidate(quotationWorkspaceProvider),
                ),
                data: (state) =>
                    _Workspace(key: ValueKey(state.context), state: state),
              );
        },
      );
}

String _errorMessage(DomainError error) {
  final message = switch (error.code) {
    'WORKFLOW_CONFIGURATION_ERROR' => 'Quotation approval is not configured for this business scope. Configure its workflow and approval steps in Business setup, then retry.',
    'WORKFLOW_TRANSITION_INVALID' => 'The configured workflow does not permit this action from the current status.',
    'QUOTATION_RECALCULATION_REQUIRED' => 'Tax or reference data changed. Save and recalculate this draft before submitting.',
    'SEGREGATION_OF_DUTIES_VIOLATION' =>
      'This decision must be made by another authorized approver.',
    'PERMISSION_DENIED' => 'Your current role does not permit this action.',
    'QUOTATION_EXPIRED' =>
      'This quotation has expired. Create a new revision before acceptance.',
    _ => error.message,
  };
  final fields = error.fieldDetails.entries.where(
    (entry) => !entry.key.startsWith('_'),
  );
  return fields.isEmpty
      ? message
      : '$message\n${fields.map((entry) => '${quotationStatus(entry.key)}: ${entry.value}').join('\n')}';
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Center(
    child: CircularProgressIndicator(semanticsLabel: 'Loading quotations'),
  );
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: JentraPanel(
      child: JentraEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Quotations unavailable',
        description: error is DomainError
            ? (error as DomainError).message
            : 'Could not load quotations.',
        action: JentraPrimaryButton(label: 'Try again', onPressed: onRetry),
      ),
    ),
  );
}

class _Workspace extends ConsumerStatefulWidget {
  const _Workspace({required this.state, super.key});
  final QuotationWorkspaceState state;
  @override
  ConsumerState<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends ConsumerState<_Workspace> {
  final _search = TextEditingController();
  int _tab = 0;
  QuotationWorkspaceController get controller =>
      ref.read(quotationWorkspaceProvider.notifier);
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 1050 ||
              MediaQuery.textScalerOf(context).scale(1) >= 1.5;
          final header = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 20,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Quotations',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  if (canViewOrders(state.capabilities))
                    TextButton(
                      onPressed: state.busy
                          ? null
                          : () => context.go('/sales/orders'),
                      child: const Text('Sales orders'),
                    ),
                  if (state.detail?.quotation.status == 'converted' &&
                      canViewOrders(state.capabilities))
                    OutlinedButton(
                      onPressed: state.busy || state.loading || !state.isOnline
                          ? null
                          : () => context.go(
                              Uri(
                                path: '/sales/orders',
                                queryParameters: {
                                  'source': state.detail!.quotation.id,
                                },
                              ).toString(),
                            ),
                      child: const Text('Open converted order'),
                    ),
                  if (state.detail?.quotation.status == 'accepted' &&
                      state.capabilities.contains('sales.orders.manage'))
                    OutlinedButton(
                      onPressed:
                          state.busy ||
                              state.loading ||
                              state.dirty ||
                              !state.isOnline
                          ? null
                          : () => context.go(
                              Uri(
                                path: '/sales/orders',
                                queryParameters: {
                                  'quotation': state.detail!.quotation.id,
                                },
                              ).toString(),
                            ),
                      child: const Text('Convert to order'),
                    ),
                  JentraStatusBadge(
                    label: state.isOnline
                        ? 'Connected'
                        : 'Offline · local drafts available',
                    tone: state.isOnline
                        ? JentraStatusTone.success
                        : JentraStatusTone.warning,
                  ),
                  if (state.canManage)
                    JentraPrimaryButton(
                      label: 'New quotation',
                      icon: Icons.add,
                      onPressed: state.busy
                          ? null
                          : () {
                              setState(() => _tab = 0);
                              controller.newDraft(
                                currencyCode:
                                    ref
                                        .read(businessScopeProvider)
                                        .value
                                        ?.legalEntity
                                        ?.currencyCode ??
                                    'LKR',
                              );
                            },
                    ),
                  IconButton(
                    tooltip: 'Refresh quotations',
                    onPressed: state.busy || state.loading
                        ? null
                        : controller.refresh,
                    icon: const Icon(Icons.refresh),
                  ),
                  if (state.canManage)
                    OutlinedButton.icon(
                      onPressed: state.busy
                          ? null
                          : () async {
                              final scope = state.context;
                              final entry =
                                  await showDialog<QuotationRecoveryEntry>(
                                    context: context,
                                    builder: (_) =>
                                        QuotationRecoveryDialog(scope: scope),
                                  );
                              if (mounted &&
                                  entry != null &&
                                  scope == widget.state.context) {
                                setState(() => _tab = 0);
                                await controller.recoverLocal(entry.slot);
                              }
                            },
                      icon: const Icon(Icons.restore),
                      label: const Text('Recover local draft'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Prepare a clear offer. Keep every revision and decision in view.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: context.jentraColors.textSecondary),
              ),
              const SizedBox(height: 20),
            ],
          );
          final detail = _detail(context, state);
          if (stacked) {
            return ListView(
              key: const Key('quotation-workspace-scroll'),
              children: [
                header,
                SizedBox(height: 460, child: _list(context, state)),
                const SizedBox(height: 20),
                detail,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 290, child: _list(context, state)),
                    const SizedBox(width: 20),
                    Expanded(
                      child: ListView(
                        key: const Key('quotation-detail-scroll'),
                        children: [detail],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _list(
    BuildContext context,
    QuotationWorkspaceState state,
  ) => JentraPanel(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quotation register',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('quotation-search'),
          controller: _search,
          maxLength: 200,
          decoration: InputDecoration(
            labelText: 'Search document number',
            counterText: '',
            suffixIcon: IconButton(
              tooltip: 'Search quotations',
              onPressed: state.busy
                  ? null
                  : () => controller.search(
                      _search.text,
                      status: state.query.status,
                    ),
              icon: const Icon(Icons.search),
            ),
          ),
          onSubmitted: state.busy
              ? null
              : (text) => controller.search(text, status: state.query.status),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey(state.query.status),
          initialValue: state.query.status ?? '',
          decoration: const InputDecoration(labelText: 'Status'),
          items: [
            const DropdownMenuItem(value: '', child: Text('All statuses')),
            for (final status in const [
              'draft',
              'submitted',
              'pending_approval',
              'approved',
              'rejected',
              'accepted',
              'expired',
              'cancelled',
              'converted',
            ])
              DropdownMenuItem(
                value: status,
                child: Text(quotationStatus(status)),
              ),
          ],
          onChanged: state.busy
              ? null
              : (value) => controller.search(
                  _search.text,
                  status: value == '' ? null : value,
                ),
        ),
        const SizedBox(height: 12),
        if (state.loading)
          const LinearProgressIndicator(
            semanticsLabel: 'Loading quotation records',
          ),
        Expanded(
          child: state.page.items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('No quotations found.'),
                  ),
                )
              : ListView(
                  children: [
                    for (final quotation in state.page.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: state.detail?.quotation.id == quotation.id
                              ? context.jentraColors.infoSurface
                              : context.jentraColors.panel,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: context.jentraColors.border,
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: state.busy
                                ? null
                                : () {
                                    setState(() => _tab = 0);
                                    controller.selectQuotation(quotation.id);
                                  },
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    quotation.documentNumber ??
                                        'Draft quotation',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${quotation.currencyCode} ${quotation.grandTotal.toDecimalString()}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontFamily:
                                              JentraTypography.monoFamily,
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 6,
                                    children: [
                                      Text(quotationStatus(quotation.status)),
                                      Text(
                                        'Revision ${quotation.currentRevision}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (state.page.hasNextPage)
                      TextButton(
                        onPressed: state.loading ? null : controller.loadMore,
                        child: const Text('Load more quotations'),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 8),
        Text(
          '${state.page.items.length} loaded · totals shown per currency',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
  Widget _detail(BuildContext context, QuotationWorkspaceState state) {
    final quotation = state.detail?.quotation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.error != null)
          _notice(
            context,
            Icons.error_outline,
            _errorMessage(state.error!),
            danger: true,
          ),
        if (state.statusMessage != null)
          _notice(context, Icons.check_circle_outline, state.statusMessage!),
        if (state.pending != null)
          _notice(
            context,
            Icons.sync_problem,
            'Confirmation pending. Your original ${state.pending!.verb} request is stored securely. Retry it to learn the outcome.',
            action: TextButton(
              onPressed: state.canWrite ? controller.retryPending : null,
              child: const Text('Retry saved request'),
            ),
          ),
        if (state.conflict)
          _notice(
            context,
            Icons.compare_arrows,
            'This quotation changed on the server. Your local edits are preserved.',
            action: TextButton(
              onPressed: state.isOnline && !state.busy
                  ? () => _conflict(context)
                  : null,
              child: const Text('Compare & resolve'),
            ),
          ),
        if (state.recovered && state.pending == null && !state.conflict)
          _notice(
            context,
            Icons.restore,
            'Recovered your encrypted draft for this business scope. Review it before saving.',
          ),
        if (quotation == null && state.form == null)
          const JentraPanel(
            child: JentraEmptyState(
              icon: Icons.description_outlined,
              title: 'Choose a quotation',
              description: 'Open an offer to review its exact totals, terms and history, or create a quotation.',
            ),
          )
        else ...[
          JentraPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      quotation?.documentNumber ?? 'New quotation',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    JentraStatusBadge(
                      label: state.form?['create_revision'] == true
                          ? 'Revision draft'
                          : quotationStatus(quotation?.status ?? 'draft'),
                      tone:
                          quotation?.status == 'approved' ||
                              quotation?.status == 'accepted'
                          ? JentraStatusTone.success
                          : JentraStatusTone.info,
                    ),
                    if (quotation != null)
                      Text(
                        'Revision ${quotation.currentRevision} · Version ${quotation.version}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (state.canManage &&
                        (quotation == null ||
                            quotation.status == 'draft' ||
                            state.form?['create_revision'] == true))
                      JentraPrimaryButton(
                        label: 'Save & calculate',
                        icon: Icons.save_outlined,
                        loading: state.busy,
                        onPressed:
                            state.canWrite &&
                                state.pending == null &&
                                !state.conflict
                            ? controller.save
                            : null,
                      ),
                    if (state.dirty && state.pending == null && !state.conflict)
                      OutlinedButton(
                        onPressed: state.busy ? null : () => _discard(context),
                        child: const Text('Discard local edits'),
                      ),
                    if (state.canRevise)
                      OutlinedButton.icon(
                        onPressed: state.canWrite
                            ? () => _action(context, 'revision')
                            : null,
                        icon: const Icon(Icons.edit_note),
                        label: const Text('Create revision'),
                      ),
                    for (final action in state.allowedActions)
                      OutlinedButton(
                        onPressed: state.canWrite
                            ? () => _action(context, action)
                            : null,
                        child: Text(quotationStatus(action)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    state.savingLocal
                        ? 'Saving encrypted draft…'
                        : state.dirty
                        ? 'Local edits · last saved server totals remain unchanged'
                        : quotation == null
                        ? 'Draft on this device'
                        : 'Saved server version',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (!state.isOnline)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'You can edit locally. Reconnect to choose references or send commands.',
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (quotation != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(state.canEditForm ? 'Editor' : 'Quotation'),
                    selected: _tab == 0,
                    onSelected: (_) => setState(() => _tab = 0),
                  ),
                  ChoiceChip(
                    label: const Text('Revision & decision history'),
                    selected: _tab == 1,
                    onSelected: (_) => setState(() => _tab = 1),
                  ),
                  if (state.canEditForm)
                    ChoiceChip(
                      label: const Text('Saved totals'),
                      selected: _tab == 2,
                      onSelected: (_) => setState(() => _tab = 2),
                    ),
                ],
              ),
            ),
          if (_tab == 1 && quotation != null)
            _history(context, state)
          else if (_tab == 2 && state.detail != null)
            JentraPanel(
              child: QuotationDocumentView(
                snapshot: state.detail!.snapshot,
                labels: _labels(state),
              ),
            )
          else if (state.form != null &&
              state.canManage &&
              (quotation == null ||
                  quotation.status == 'draft' ||
                  state.form?['create_revision'] == true))
            QuotationEditor(
              key: ValueKey('${state.slot}:${state.editorEpoch}'),
              form: state.form!,
              enabled: state.canEditForm,
              online: state.isOnline,
              baseCurrency:
                  quotation?.baseCurrencyCode ??
                  ref
                      .watch(businessScopeProvider)
                      .value
                      ?.legalEntity
                      ?.currencyCode ??
                  'LKR',
              onChanged: controller.updateForm,
            )
          else if (state.detail != null)
            JentraPanel(
              child: QuotationDocumentView(
                snapshot: state.detail!.snapshot,
                labels: _labels(state),
              ),
            ),
        ],
      ],
    );
  }

  Map<String, Object?> _labels(QuotationWorkspaceState state) =>
      (state.form?['_labels'] as Map? ?? {}).cast<String, Object?>();
  Widget _notice(
    BuildContext context,
    IconData icon,
    String text, {
    Widget? action,
    bool danger = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: danger
              ? context.jentraColors.dangerSurface
              : context.jentraColors.infoSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: danger
                      ? context.jentraColors.danger
                      : context.jentraColors.info,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(text)),
              ],
            ),
            ?action,
          ],
        ),
      ),
    ),
  );
  Widget _history(
    BuildContext context,
    QuotationWorkspaceState state,
  ) => JentraPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Customer-facing revisions',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        if (state.revisions.isEmpty)
          const Text(
            'No published revisions yet. A submission preserves a customer-facing snapshot.',
          ),
        for (final revision in state.revisions)
          ExpansionTile(
            key: Key('quotation-revision-${revision.revisionNumber}'),
            tilePadding: EdgeInsets.zero,
            title: Text(
              'Revision ${revision.revisionNumber} · ${quotationStatus(revision.status)}',
            ),
            subtitle: Text(
              '${revision.reason ?? 'Submitted quotation'}\n${revision.createdAt.toUtc().toIso8601String()} · ${revision.createdBy}',
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: QuotationDocumentView(snapshot: revision.snapshot),
              ),
            ],
          ),
        if (state.moreRevisions)
          TextButton(
            onPressed: state.loading ? null : controller.loadMoreRevisions,
            child: const Text('Load older revisions'),
          ),
        const Divider(height: 36),
        Text(
          'Approval decisions',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        if (state.decisions.isEmpty)
          const Text('No approval decisions recorded.'),
        for (final decision in state.decisions)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: JentraPanel(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${quotationStatus(quotationLabel(decision['decision']))} · Revision ${decision['revision_number']}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Step ${decision['step_order']} · ${decision['actor_id']}',
                  ),
                  Text(
                    '${decision['currency_code']} ${decision['amount']}',
                    style: const TextStyle(
                      fontFamily: JentraTypography.monoFamily,
                    ),
                  ),
                  if (decision['note'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(quotationLabel(decision['note'])),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    quotationLabel(decision['decided_at']),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        if (state.moreDecisions)
          TextButton(
            onPressed: state.loading ? null : controller.loadMoreDecisions,
            child: const Text('Load older decisions'),
          ),
      ],
    ),
  );
  Future<void> _action(BuildContext context, String action) async {
    final origin = widget.state;
    final reason = await showScopedQuotationDialog<String>(
      context,
      scope: origin.context,
      capabilities: origin.capabilities,
      builder: (_) => _ActionDialog(action: action),
    );
    if (!mounted ||
        reason == null ||
        origin.context != widget.state.context ||
        origin.detail?.quotation.id != widget.state.detail?.quotation.id ||
        origin.detail?.quotation.version !=
            widget.state.detail?.quotation.version) {
      return;
    }
    if (action == 'revision') {
      await controller.startRevision(reason);
      setState(() => _tab = 0);
    } else if (action == 'approve' || action == 'reject') {
      await controller.decide(
        approve: action == 'approve',
        reason: reason.isEmpty ? null : reason,
      );
    } else {
      await controller.transition(
        action,
        reason: reason.isEmpty ? null : reason,
      );
    }
  }

  Future<void> _discard(BuildContext context) async {
    final origin = widget.state;
    final confirmed = await showScopedQuotationDialog<bool>(
      context,
      scope: origin.context,
      capabilities: origin.capabilities,
      requireOnline: false,
      builder: (context) => QuotationScopeGuard(
        scope: origin.context,
        capabilities: origin.capabilities,
        child: AlertDialog(
          title: const Text('Discard local edits?'),
          content: const Text(
            'The saved server quotation will remain available. Local changes in this editor will be removed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard local edits'),
            ),
          ],
        ),
      ),
    );
    if (mounted &&
        confirmed == true &&
        origin.context == widget.state.context &&
        origin.slot == widget.state.slot) {
      await controller.discardEdits();
    }
  }

  Future<void> _conflict(BuildContext context) async {
    final origin = widget.state;
    await controller.inspectConflict();
    if (!context.mounted ||
        !mounted ||
        origin.context != widget.state.context) {
      return;
    }
    final state = ref.read(quotationWorkspaceProvider).value;
    if (state?.conflictDetail == null) return;
    final keep = await showScopedQuotationDialog<bool>(
      context,
      scope: origin.context,
      capabilities: origin.capabilities,
      requireOnline: false,
      builder: (context) => QuotationScopeGuard(
        scope: origin.context,
        capabilities: origin.capabilities,
        child: AlertDialog(
          title: const Text('Resolve quotation conflict'),
          content: SizedBox(
            width: 1000,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your draft started at version ${state!.localDraft?.expectedVersion}. The server is at version ${state.conflictDetail!.quotation.version}. Choosing local edits prepares a new save for review.',
                  ),
                  const SizedBox(height: 20),
                  _Comparison(
                    local: state.form!,
                    server: state.conflictDetail!.draft.toJson(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Keep conflict unresolved'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Use server version'),
            ),
            FilledButton(
              onPressed: state.conflictDetail!.quotation.status == 'draft'
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('Keep local edits for review'),
            ),
          ],
        ),
      ),
    );
    if (mounted &&
        keep != null &&
        origin.context == widget.state.context &&
        origin.slot == widget.state.slot) {
      await controller.resolveConflict(keepLocal: keep);
    }
  }
}

class _ActionDialog extends StatefulWidget {
  const _ActionDialog({required this.action});
  final String action;
  @override
  State<_ActionDialog> createState() => _ActionDialogState();
}

class _ActionDialogState extends State<_ActionDialog> {
  final _reason = TextEditingController();
  bool get _required =>
      {'recall', 'reject', 'revision', 'cancel'}.contains(widget.action);
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${quotationStatus(widget.action)} quotation'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(switch (widget.action) {
            'submit' => 'Submit this saved version using the configured approval workflow.',
            'approve' => 'Record your decision for the current approval step.',
            'accept' => 'Record customer acceptance of this saved offer.',
            'revision' =>
              'Create a revised draft while preserving the published offer.',
            'recall' => 'Recall this offer into a new draft revision.',
            'expire' => 'Mark this offer expired after its validity date.',
            'cancel' =>
              'Cancel this offer if the configured workflow permits it.',
            _ => 'Record a rejection and explain what must change.',
          }),
          const SizedBox(height: 20),
          TextField(
            key: const Key('quotation-action-reason'),
            controller: _reason,
            autofocus: true,
            maxLength: 1000,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: _required ? 'Reason (required)' : 'Note (optional)',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Back'),
      ),
      FilledButton(
        onPressed: _required && _reason.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _reason.text.trim()),
        child: Text('Confirm ${widget.action}'),
      ),
    ],
  );
}

class _Comparison extends StatelessWidget {
  const _Comparison({required this.local, required this.server});
  final Map<String, Object?> local, server;
  Map<String, String> flatten(Map<String, Object?> form) {
    final rows = <String, String>{};
    for (final entry in form.entries) {
      if (entry.key.startsWith('_') ||
          entry.key == 'id' ||
          entry.key == 'lines') {
        continue;
      }
      rows[quotationStatus(entry.key)] = quotationLabel(entry.value);
    }
    final lines = form['lines'] as List? ?? [];
    for (var i = 0; i < lines.length; i++) {
      for (final entry in (lines[i] as Map).entries) {
        if (entry.key == 'line_id') continue;
        rows['Item ${i + 1} · ${quotationStatus(entry.key.toString())}'] =
            quotationLabel(entry.value);
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final a = flatten(local), b = flatten(server);
    final all = {...a.keys, ...b.keys};
    final changed = all.where((key) => a[key] != b[key]).toList();
    final unchanged = all.where((key) => a[key] == b[key]).toList();
    Widget row(String key) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: JentraPanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              key
                  .replaceAll(' Id', '')
                  .replaceAll('Create Revision', 'New revision'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked =
                    MediaQuery.textScalerOf(context).scale(1) >= 1.5 ||
                    constraints.maxWidth < 620;
                final local = QuotationFact('Your local value', a[key] ?? '—');
                final remote = QuotationFact(
                  'Current server value',
                  b[key] ?? '—',
                );
                return stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [local, const SizedBox(height: 12), remote],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: local),
                          Expanded(child: remote),
                        ],
                      );
              },
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${changed.length} differing ${changed.length == 1 ? 'field' : 'fields'}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        for (final key in changed) row(key),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('Show ${unchanged.length} unchanged fields'),
          children: [for (final key in unchanged) row(key)],
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

import '../../app_providers.dart';
import 'quotation_controller.dart';
import 'quotation_editor.dart';
import 'quotation_reference_picker.dart';
import 'quotation_reference_label.dart';
import 'quotation_recovery_dialog.dart';
import 'quotation_scope_guard.dart';
import 'sales_order_controller.dart';
import 'sales_order_dialogs.dart';

class SalesOrderScreen extends ConsumerStatefulWidget {
  const SalesOrderScreen({
    this.orderId,
    this.quotationId,
    this.sourceQuotationId,
    super.key,
  });
  final String? orderId, quotationId, sourceQuotationId;
  @override
  ConsumerState<SalesOrderScreen> createState() => _SalesOrderScreenState();
}

class _SalesOrderScreenState extends ConsumerState<SalesOrderScreen> {
  Object? _opened;
  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(businessCapabilitiesProvider);
    if (caps.isLoading) return const Center(child: CircularProgressIndicator());
    if (caps.hasError || !canViewOrders(caps.value ?? {})) {
      return const Center(
        child: Text('Your current role cannot open sales orders.'),
      );
    }
    return ref
        .watch(salesOrderProvider)
        .when(
          skipLoadingOnRefresh: false,
          skipLoadingOnReload: false,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  error is DomainError
                      ? error.message
                      : 'Orders could not be loaded.',
                ),
                TextButton(
                  onPressed: () => ref.invalidate(salesOrderProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
          data: (state) {
            final target = (
              state.context,
              widget.orderId,
              widget.quotationId,
              widget.sourceQuotationId,
            );
            if (_opened != target) {
              _opened = target;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final controller = ref.read(salesOrderProvider.notifier);
                if (widget.orderId != null) {
                  controller.selectOrder(widget.orderId!);
                } else if (widget.quotationId != null) {
                  controller.startConversion(widget.quotationId!);
                } else if (widget.sourceQuotationId != null) {
                  controller.openConvertedOrder(widget.sourceQuotationId!);
                }
              });
            }
            return _OrderWorkspace(key: ValueKey(state.context), state: state);
          },
        );
  }
}

class _OrderWorkspace extends ConsumerStatefulWidget {
  const _OrderWorkspace({required this.state, super.key});
  final SalesOrderState state;
  @override
  ConsumerState<_OrderWorkspace> createState() => _OrderWorkspaceState();
}

class _OrderWorkspaceState extends ConsumerState<_OrderWorkspace> {
  final _search = TextEditingController();
  final _creditAccess = <_CreditDialogAccess>{};
  int _tab = 0;
  SalesOrderController get controller => ref.read(salesOrderProvider.notifier);
  @override
  void dispose() {
    for (final access in _creditAccess) {
      access.invalidate();
    }
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Sales orders',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              JentraStatusBadge(
                label: s.isOnline ? 'Connected' : 'Offline · drafts available',
                tone: s.isOnline
                    ? JentraStatusTone.success
                    : JentraStatusTone.warning,
              ),
              if (s.canManage)
                FilledButton.icon(
                  onPressed: s.busy || s.loading
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
                  icon: const Icon(Icons.add),
                  label: const Text('New order'),
                ),
              IconButton(
                tooltip: 'Refresh orders',
                onPressed: s.busy || s.loading || !s.isOnline
                    ? null
                    : controller.refresh,
                icon: const Icon(Icons.refresh),
              ),
              if (s.canManage || s.canReserve)
                OutlinedButton.icon(
                  onPressed: s.busy
                      ? null
                      : () async {
                          final entry =
                              await showDialog<QuotationRecoveryEntry>(
                                context: context,
                                builder: (_) => QuotationScopeGuard(
                                  scope: s.context,
                                  capabilities: s.capabilities,
                                  child: QuotationRecoveryDialog(
                                    scope: s.context,
                                    orders: true,
                                  ),
                                ),
                              );
                          if (mounted &&
                              entry != null &&
                              widget.state.context == s.context) {
                            setState(() => _tab = 0);
                            await controller.recoverLocal(entry.slot);
                          }
                        },
                  icon: const Icon(Icons.restore),
                  label: const Text('Recover draft'),
                ),
              if (canViewQuotations(s.capabilities))
                TextButton(
                  onPressed: s.busy ? null : () => context.go('/sales'),
                  child: const Text('Quotations'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (s.error != null) _notice(s.error!.message, error: true),
          if (s.statusMessage != null) _notice(s.statusMessage!),
          if (s.loading || s.busy || s.savingLocal)
            const LinearProgressIndicator(
              semanticsLabel: 'Updating sales order',
            ),
          const SizedBox(height: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final stacked =
                    c.maxWidth < 1050 ||
                    MediaQuery.textScalerOf(context).scale(1) >= 1.5;
                return stacked
                    ? Column(
                        children: [
                          SizedBox(
                            height:
                                MediaQuery.textScalerOf(context).scale(1) >= 1.5
                                ? 350
                                : 230,
                            child: _register(s),
                          ),
                          const SizedBox(height: 16),
                          Expanded(child: _detail(s)),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 300, child: _register(s)),
                          const SizedBox(width: 20),
                          Expanded(child: _detail(s)),
                        ],
                      );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _notice(String text, {bool error = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Semantics(
      liveRegion: true,
      child: JentraPanel(
        child: Text(
          text,
          style: TextStyle(
            color: error ? Theme.of(context).colorScheme.error : null,
          ),
        ),
      ),
    ),
  );
  Widget _register(SalesOrderState s) => JentraPanel(
    child: Column(
      children: [
        TextField(
          controller: _search,
          enabled: !s.busy && s.isOnline,
          decoration: InputDecoration(
            labelText: 'Search order number',
            suffixIcon: IconButton(
              tooltip: 'Search orders',
              onPressed: s.busy || !s.isOnline
                  ? null
                  : () =>
                        controller.search(_search.text, status: s.query.status),
              icon: const Icon(Icons.search),
            ),
          ),
          onSubmitted: (text) =>
              controller.search(text, status: s.query.status),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: s.query.status ?? 'all',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Status'),
          items: [
            const DropdownMenuItem(value: 'all', child: Text('All statuses')),
            for (final status in SalesOrderListQuery.statuses)
              DropdownMenuItem(value: status, child: Text(orderStatus(status))),
          ],
          onChanged: s.busy || !s.isOnline
              ? null
              : (value) => controller.search(
                  _search.text,
                  status: value == 'all' ? null : value,
                ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            children: [
              if (s.page.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'No orders in this view. Create a draft or convert an accepted quotation.',
                  ),
                ),
              for (final order in s.page.items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  selected: s.detail?.order.id == order.id,
                  title: Text(order.documentNumber ?? 'Draft order'),
                  subtitle: Text(
                    '${orderStatus(order.status)}\n${order.currencyCode} ${order.grandTotal.toDecimalString()}',
                  ),
                  isThreeLine: true,
                  onTap: s.busy || !s.isOnline
                      ? null
                      : () {
                          setState(() => _tab = 0);
                          controller.selectOrder(order.id);
                        },
                ),
              if (s.page.hasNextPage)
                TextButton(
                  onPressed: s.busy || s.loading || !s.isOnline
                      ? null
                      : controller.loadMore,
                  child: const Text('Load more orders'),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _detail(SalesOrderState s) {
    final order = s.detail?.order;
    if (s.form == null) {
      return const JentraPanel(
        child: Center(
          child: Text(
            'Select an order to review commercial terms, credit and stock reservations.',
          ),
        ),
      );
    }
    return ListView(
      key: ValueKey('${s.slot}:$_tab'),
      children: [
        JentraPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    s.conversion
                        ? 'Convert accepted quotation'
                        : order?.documentNumber ?? 'New sales order',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (order != null)
                    JentraStatusBadge(
                      label: '${orderStatus(order.status)} · v${order.version}',
                      tone: order.status == 'credit_hold'
                          ? JentraStatusTone.warning
                          : JentraStatusTone.neutral,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (s.conversion)
                Text(
                  '${s.form!['_document_number'] ?? s.form!['quotation_id']} · revision ${s.form!['quotation_revision']} · ${s.form!['currency_code']} ${s.form!['_source_total'] ?? ''}',
                ),
              if (order?.sourceQuotationId != null)
                SelectableText(
                  'Source quotation ${order!.sourceQuotationId} · revision ${order.sourceQuotationRevision}',
                ),
              if (order != null)
                Text(
                  'Server total · ${order.currencyCode} ${order.grandTotal.toDecimalString()}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              if (s.converted)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Commercial terms and source lines are retained from the accepted quotation. Delivery details can be edited before confirmation.',
                  ),
                ),
              if (s.recovered || s.dirty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    s.pending != null
                        ? 'Confirmation pending. Retry sends the identical stored request.'
                        : s.savingLocal
                        ? 'Saving encrypted fields…'
                        : 'Local edits retained on this device.',
                  ),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (s.canManage && (s.detail == null || s.detail!.canEdit))
                    FilledButton(
                      onPressed: s.canEditForm && s.isOnline
                          ? controller.save
                          : null,
                      child: Text(
                        s.conversion
                            ? 'Convert to order'
                            : s.converted
                            ? 'Save delivery details'
                            : 'Save order',
                      ),
                    ),
                  if (s.pending != null)
                    FilledButton.icon(
                      onPressed: s.isOnline && !s.busy
                          ? controller.retryPending
                          : null,
                      icon: const Icon(Icons.replay),
                      label: const Text('Retry saved request'),
                    ),
                  if (s.dirty && s.pending == null)
                    TextButton(
                      onPressed: s.busy ? null : controller.discardEdits,
                      child: const Text('Discard local edits'),
                    ),
                  if (s.canManage && order != null && s.detail!.canEdit)
                    OutlinedButton(
                      onPressed: s.canConfirm ? () => _credit(s) : null,
                      child: const Text('Review credit & confirm'),
                    ),
                  if (s.canReserve && order != null)
                    OutlinedButton(
                      onPressed: s.canReserveNow ? () => _reserve(s) : null,
                      child: const Text('Reserve stock'),
                    ),
                  if (s.canManage &&
                      order != null &&
                      order.status != 'cancelled')
                    TextButton(
                      onPressed: s.canCancel ? () => _cancel(s) : null,
                      child: const Text('Cancel order'),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (s.conflict) ...[const SizedBox(height: 16), _conflict(s)],
        const SizedBox(height: 16),
        if (order != null)
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final (i, label) in [
                (0, 'Order details'),
                (1, 'Credit decisions'),
                (2, 'Reservations'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _tab == i,
                  onSelected: (_) => setState(() => _tab = i),
                ),
            ],
          ),
        const SizedBox(height: 16),
        if (_tab == 0 || order == null) ...[
          SalesOrderFulfillmentEditor(
            key: ValueKey('${s.slot}:${s.editorEpoch}:fulfillment'),
            form: s.form!,
            enabled: s.canEditForm,
            online: s.isOnline,
            onChanged: (patch) => controller.updateForm({
              ...ref.read(salesOrderProvider).requireValue.form!,
              ...patch,
            }),
          ),
          const SizedBox(height: 16),
          if (!s.conversion && !s.converted)
            QuotationEditor(
              key: ValueKey('${s.slot}:${s.editorEpoch}:commercial'),
              form: s.form!,
              enabled: s.canEditForm,
              online: s.isOnline,
              orderMode: true,
              baseCurrency:
                  ref
                      .read(businessScopeProvider)
                      .value
                      ?.legalEntity
                      ?.currencyCode ??
                  'LKR',
              onChanged: (raw) => controller.updateForm({
                ...raw,
                'promised_date': ref
                    .read(salesOrderProvider)
                    .requireValue
                    .form!['promised_date'],
                'warehouse_id': ref
                    .read(salesOrderProvider)
                    .requireValue
                    .form!['warehouse_id'],
                'ship_to': ref
                    .read(salesOrderProvider)
                    .requireValue
                    .form!['ship_to'],
              }),
            ),
          if (order != null) OrderLineSummary(detail: s.detail!),
          if (order != null && s.converted)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SavedOrderTerms(detail: s.detail!),
            ),
        ] else if (_tab == 1) ...[
          if (s.decisions.isEmpty)
            const JentraPanel(
              child: Text(
                'No credit decisions recorded. Confirmation records the authoritative exposure and decision.',
              ),
            ),
          for (final decision in s.decisions)
            CreditDecisionCard(decision: decision),
          if (s.moreDecisions)
            TextButton(
              onPressed: () => controller.loadHistory(moreDecisions: true),
              child: const Text('Load more decisions'),
            ),
        ] else ...[
          const JentraPanel(
            child: Text(
              'Reservations allocate available base quantities. Physical stock and accounting change at delivery.',
            ),
          ),
          if (!s.canViewStock)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Your role cannot view inventory reservation records.',
              ),
            ),
          if (s.canViewStock && s.reservations.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No reservation records for this order.'),
            ),
          for (final row in s.reservations)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: JentraPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${orderStatus(row['status']?.toString() ?? '')} · ${row['base_quantity']} base units',
                    ),
                    SelectableText('Order line ${row['sales_order_line_id']}'),
                    Text('Expires ${row['expires_at']}'),
                    if (row['release_reason'] != null)
                      Text('Release reason: ${row['release_reason']}'),
                  ],
                ),
              ),
            ),
          if (s.moreReservations)
            TextButton(
              onPressed: () => controller.loadHistory(moreReservations: true),
              child: const Text('Load more reservations'),
            ),
        ],
      ],
    );
  }

  Widget _conflict(SalesOrderState s) => JentraPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Order changed on the server',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          'Your local fields are retained at version ${s.localDraft?.expectedVersion}. Compare before choosing.',
        ),
        TextButton(
          onPressed: s.isOnline && !s.busy ? controller.inspectConflict : null,
          child: const Text('Inspect current server version'),
        ),
        if (s.conflictDetail != null) ...[
          Text(
            'Server v${s.conflictDetail!.order.version} · ${orderStatus(s.conflictDetail!.order.status)}',
          ),
          Text(
            'Server ship-to: ${s.conflictDetail!.order.shipTo}\nLocal ship-to: ${s.form!['ship_to']}',
          ),
          Text(
            'Server promise: ${s.conflictDetail!.draft.toJson()['promised_date']} · Local promise: ${s.form!['promised_date']}',
          ),
          Text(
            'Server total: ${s.conflictDetail!.order.currencyCode} ${s.conflictDetail!.order.grandTotal.toDecimalString()}',
          ),
          ExpansionTile(
            title: const Text('Compare complete commercial fields'),
            children: [
              SelectableText(
                'SERVER\n${s.conflictDetail!.draft.toJson()}\nLOCAL\n${s.form}',
              ),
            ],
          ),
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                onPressed: () => controller.resolveConflict(keepLocal: false),
                child: const Text('Use server version'),
              ),
              TextButton(
                onPressed: s.conflictDetail!.canEdit
                    ? () => controller.resolveConflict(keepLocal: true)
                    : null,
                child: const Text('Keep local edits for review'),
              ),
            ],
          ),
        ],
        if (s.conflictQuote != null) ...[
          Text(
            'Quotation v${s.conflictQuote!.quotation.version} · revision ${s.conflictQuote!.quotation.currentRevision} · ${orderStatus(s.conflictQuote!.quotation.status)}',
          ),
          TextButton(
            onPressed: s.conflictQuote!.quotation.status == 'accepted'
                ? () => controller.resolveConflict(keepLocal: true)
                : null,
            child: const Text('Use current accepted revision'),
          ),
        ],
      ],
    ),
  );
  Future<void> _credit(SalesOrderState s) async {
    final origin = controller;
    final originAccess = _CreditDialogAccess();
    _creditAccess.add(originAccess);
    var invalidated = false;
    void invalidate() {
      invalidated = true;
      originAccess.invalidate();
    }

    bool capabilitiesMatch(AsyncValue<Set<String>> value) =>
        !value.isLoading &&
        !value.hasError &&
        value.value != null &&
        value.value!.length == s.capabilities.length &&
        value.value!.containsAll(s.capabilities);
    final connection = ref.listenManual(connectivityStateProvider, (_, next) {
      if (next.isLoading ||
          next.hasError ||
          next.value != ConnectivityState.online) {
        invalidate();
      }
    });
    final scope = ref.listenManual(activeTenantContextProvider, (_, next) {
      if (next != s.context) invalidate();
    });
    final capabilities = ref.listenManual(businessCapabilitiesProvider, (
      _,
      next,
    ) {
      if (!capabilitiesMatch(next)) invalidate();
    });
    bool currentAccess() =>
        mounted &&
        !invalidated &&
        ref.read(activeTenantContextProvider) == s.context &&
        !ref.read(connectivityStateProvider).isLoading &&
        !ref.read(connectivityStateProvider).hasError &&
        ref.read(connectivityStateProvider).value == ConnectivityState.online &&
        capabilitiesMatch(ref.read(businessCapabilitiesProvider)) &&
        identical(ref.read(salesOrderProvider.notifier), origin);
    try {
      if (!currentAccess()) return;
      await origin.reviewCredit();
      if (!currentAccess()) return;
      final current = ref.read(salesOrderProvider).value;
      if (current?.context != s.context ||
          current?.credit == null ||
          current?.detail?.order.id != s.detail?.order.id ||
          current?.detail?.order.version != s.detail?.order.version) {
        return;
      }
      final preview = current!.credit!;
      if (!mounted) return;
      final response = await showDialog<({bool overrideCredit, String reason})>(
        context: context,
        builder: (_) => ListenableBuilder(
          listenable: originAccess,
          builder: (dialogContext, _) => originAccess.active
              ? QuotationScopeGuard(
                  scope: s.context,
                  capabilities: s.capabilities,
                  child: OrderCreditDialog(
                    preview: preview,
                    canOverride: current.canOverride,
                  ),
                )
              : AlertDialog(
                  title: const Text('Business scope or access changed'),
                  content: const Text(
                    'Close this dialog and review customer credit again.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Close'),
                    ),
                  ],
                ),
        ),
      );
      if (response != null &&
          currentAccess() &&
          identical(ref.read(salesOrderProvider).value?.credit, preview)) {
        await origin.confirm(
          overrideCredit: response.overrideCredit,
          reason: response.reason,
        );
      }
    } finally {
      connection.close();
      scope.close();
      capabilities.close();
      _creditAccess.remove(originAccess);
      originAccess.dispose();
    }
  }

  Future<void> _cancel(SalesOrderState s) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => QuotationScopeGuard(
        scope: s.context,
        capabilities: s.capabilities,
        child: const OrderCancelDialog(),
      ),
    );
    if (mounted && reason != null && widget.state.context == s.context) {
      await controller.cancel(reason);
    }
  }

  Future<void> _reserve(SalesOrderState s) async {
    final draft = await showDialog<StockReservationDraft>(
      context: context,
      builder: (_) => QuotationScopeGuard(
        scope: s.context,
        capabilities: s.capabilities,
        child: OrderReservationDialog(scope: s.context, detail: s.detail!),
      ),
    );
    if (mounted && draft != null && widget.state.context == s.context) {
      await controller.reserve(draft);
    }
  }
}

class _CreditDialogAccess extends ChangeNotifier {
  bool active = true, _disposed = false;
  void invalidate() {
    if (!active || _disposed) return;
    active = false;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

String orderStatus(String value) => value
    .split('_')
    .map(
      (part) =>
          part.isEmpty ? '' : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');

class SalesOrderFulfillmentEditor extends StatefulWidget {
  const SalesOrderFulfillmentEditor({
    required this.form,
    required this.enabled,
    required this.online,
    required this.onChanged,
    super.key,
  });
  final Map<String, Object?> form;
  final bool enabled, online;
  final Future<void> Function(Map<String, Object?>) onChanged;
  @override
  State<SalesOrderFulfillmentEditor> createState() => _FulfillmentState();
}

class _FulfillmentState extends State<SalesOrderFulfillmentEditor> {
  final _referenceDialogs = <QuotationDialogAccess>{};
  late final _promised = TextEditingController(
    text: widget.form['promised_date']?.toString(),
  );
  late final Map<String, Object?> _shipTo = Map<String, Object?>.from(
    widget.form['ship_to'] as Map? ?? {},
  );
  late String _warehouse = widget.form['warehouse_id']?.toString() ?? '';
  String? _warehouseLabel;
  void _save() => widget.onChanged({
    'promised_date': _promised.text,
    'warehouse_id': _warehouse,
    'ship_to': Map<String, Object?>.from(_shipTo),
  });
  @override
  void dispose() {
    for (final access in _referenceDialogs) {
      access.denyReadAccess();
    }
    _referenceDialogs.clear();
    _promised.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => JentraPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Delivery details',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('order-promised-date'),
          controller: _promised,
          enabled: widget.enabled,
          decoration: const InputDecoration(
            labelText: 'Promised date',
            helperText: 'YYYY-MM-DD',
          ),
          onChanged: (_) => _save(),
        ),
        const SizedBox(height: 16),
        InputDecorator(
          decoration: const InputDecoration(labelText: 'Fulfillment warehouse'),
          child: TextButton(
            onPressed: widget.enabled && widget.online
                ? () async {
                    final access = QuotationDialogAccess(context);
                    _referenceDialogs.add(access);
                    try {
                      final item = await showQuotationReferencePicker(
                        context,
                        originAccess: access,
                        title: 'Warehouse',
                        kind: QuotationReferenceKind.warehouse,
                        permission: 'sales.orders.manage',
                      );
                      if (!mounted || !widget.enabled || item == null) return;
                      setState(() {
                        _warehouse = item.id;
                        _warehouseLabel = item.label;
                      });
                      _save();
                    } finally {
                      _referenceDialogs.remove(access);
                      access.dispose();
                    }
                  }
                : null,
            child: _warehouse.isEmpty
                ? const Text('Choose warehouse')
                : QuotationReferenceLabel(
                    kind: QuotationReferenceKind.warehouse,
                    id: _warehouse,
                    savedLabel: _warehouseLabel,
                    orderMode: true,
                  ),
          ),
        ),
        const SizedBox(height: 16),
        for (final (key, label) in [
          ('address', 'Ship-to address'),
          ('city', 'City'),
          ('postal_code', 'Postal code'),
          ('country', 'Country'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextFormField(
              key: Key('order-ship-$key'),
              initialValue: _shipTo[key]?.toString() ?? '',
              enabled: widget.enabled,
              decoration: InputDecoration(labelText: label),
              onChanged: (text) {
                _shipTo[key] = text;
                _save();
              },
            ),
          ),
      ],
    ),
  );
}

class SavedOrderTerms extends StatelessWidget {
  const SavedOrderTerms({required this.detail, super.key});
  final SalesOrderDetail detail;
  @override
  Widget build(BuildContext context) {
    final order = detail.order, draft = detail.draft;
    return JentraPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Accepted commercial terms',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          QuotationReferenceLabel(
            kind: QuotationReferenceKind.customer,
            id: order.customerId,
            orderMode: true,
          ),
          if (order.contactId != null)
            QuotationReferenceLabel(
              kind: QuotationReferenceKind.contact,
              id: order.contactId!,
              customerId: order.customerId,
              orderMode: true,
            ),
          const SizedBox(height: 12),
          Text(
            'Order date ${draft.toJson()['order_date']} · Payment terms ${order.paymentTermsDays} days',
          ),
          Text('Delivery terms: ${order.deliveryTerms ?? 'None recorded'}'),
          Text(
            'Exchange rate ${order.exchangeRate.toDecimalString()} · Rate date ${draft.toJson()['rate_date']}',
          ),
          Text(
            'Subtotal ${order.currencyCode} ${order.subtotal.toDecimalString()}\nDiscount ${order.discountTotal.toDecimalString()} · Tax ${order.taxTotal.toDecimalString()}\nTotal ${order.grandTotal.toDecimalString()} · Base total ${order.baseTotal.currencyCode} ${order.baseTotal.toDecimalString()}',
          ),
          if (draft.notes != null) Text(draft.notes!),
          for (final raw in detail.snapshot['lines']! as List)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${(raw as Map)['description']}\nDiscount ${raw['line_discount_amount'] ?? '0.000000'} · Header allocation ${raw['header_discount_amount'] ?? '0.000000'}\nTax ${raw['tax_code'] ?? 'None'} · ${raw['tax_rate'] ?? '0.000000'}% · ${raw['tax_inclusive'] == true ? 'Inclusive' : 'Exclusive'} · ${raw['tax_amount'] ?? '0.000000'}',
              ),
            ),
        ],
      ),
    );
  }
}

class OrderLineSummary extends StatelessWidget {
  const OrderLineSummary({required this.detail, super.key});
  final SalesOrderDetail detail;
  @override
  Widget build(BuildContext context) => JentraPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Saved quantities & source trace',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Text(
          'Ordered is in the selling unit. All fulfillment quantities below are in base units.',
        ),
        for (final line in detail.order.lines)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.description,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  'Ordered ${line.orderedQuantity.toDecimalString()} · Base ordered ${line.baseOrderedQuantity.toDecimalString()}',
                ),
                Text(
                  'Cancelled ${line.cancelledQuantity.toDecimalString()} · Allocated ${line.allocatedQuantity.toDecimalString()}\nDelivered ${line.deliveredQuantity.toDecimalString()} · Invoiced ${line.invoicedQuantity.toDecimalString()}',
                ),
                Text(
                  '${line.unitPrice.currencyCode} ${line.unitPrice.toDecimalString()} per selling unit · Line total ${line.lineTotal.toDecimalString()}',
                ),
                if (line.sourceQuotationLineId != null)
                  SelectableText(
                    'Source line ${line.sourceQuotationLineId} · revision ${line.sourceQuotationRevision}',
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';

import '../../app_providers.dart';
import 'financial_dimension_controller.dart';
import '../operations/operational_read_access.dart';

class FinancialDimensionScreen extends ConsumerWidget {
  const FinancialDimensionScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(businessCapabilitiesProvider);
    if (caps.isLoading) return const Center(child: CircularProgressIndicator());
    final c = ref.watch(financialDimensionControllerProvider);
    if (c == null) {
      return const Center(
        child: Text(
          'Current finance and dimension-management access is required.',
        ),
      );
    }
    return FinancialDimensionWorkspace(controller: c);
  }
}

class FinancialDimensionWorkspace extends StatelessWidget {
  const FinancialDimensionWorkspace({super.key, required this.controller});
  final FinancialDimensionController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      if (!c.verified) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Encrypted dimension inputs are retained. Recheck current access to view the catalog.',
              ),
              if (c.error != null) Text(c.error!),
              TextButton(
                onPressed: c.busy || !c.online ? null : c.refresh,
                child: const Text('Recheck access'),
              ),
            ],
          ),
        );
      }
      final f = c.form;
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Financial dimensions',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Govern cost centres and project tags for journals and budgets. Posted and approved history retains its original identities and labels.',
          ),
          if (c.busy) const LinearProgressIndicator(),
          if (c.error != null)
            Text(
              c.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (c.message != null) Text(c.message!),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in ['cost_centre', 'project'])
                ChoiceChip(
                  label: Text(
                    k == 'cost_centre' ? 'Cost centres' : 'Project tags',
                  ),
                  selected: c.kind == k,
                  onSelected: c.busy || c.pending
                      ? null
                      : (_) => c.filter(k, ''),
                ),
              OutlinedButton(
                onPressed: c.locked ? null : c.create,
                child: const Text('New dimension'),
              ),
              TextButton(
                onPressed: c.busy ? null : c.refresh,
                child: const Text('Refresh catalog'),
              ),
            ],
          ),
          if (f.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Selected ${f['kind'] == 'cost_centre' ? 'cost centre' : 'project tag'} · version ${c.version}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final k in ['code', 'name', 'reason'])
                  SizedBox(
                    width: k == 'code' ? 320 : 640,
                    child: TextFormField(
                      key: ValueKey('${f['id']}-$k-${c.version}'),
                      initialValue: f[k] as String? ?? '',
                      maxLines: k == 'reason'
                          ? 3
                          : k == 'name'
                          ? 2
                          : 1,
                      enabled: !c.locked && (k != 'code' || c.version == 0),
                      onChanged: (v) => c.field(k, v),
                      decoration: InputDecoration(
                        labelText: k == 'code'
                            ? 'Code'
                            : k == 'name'
                            ? 'Name'
                            : 'Reason',
                      ),
                    ),
                  ),
                SizedBox(
                  width: 320,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('${f['id']}-status-${c.version}'),
                    initialValue: f['status'] as String,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: 'active', child: Text('Active')),
                      DropdownMenuItem(
                        value: 'retired',
                        child: Text('Retired'),
                      ),
                    ],
                    onChanged: c.locked ? null : (v) => c.field('status', v),
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('${f['id']}-branch'),
                    initialValue: f['dimension_branch_id'] as String? ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Dimension scope',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Entity-wide'),
                      ),
                      DropdownMenuItem(
                        value: c.scope.branchId,
                        child: const Text('Current branch only'),
                      ),
                    ],
                    onChanged: c.locked || c.version > 0
                        ? null
                        : (v) => c.field(
                            'dimension_branch_id',
                            v == '' ? null : v,
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: c.busy || !c.online || c.denied ? null : c.save,
                  child: Text(
                    c.pending
                        ? 'Retry sealed dimension'
                        : 'Save governed dimension',
                  ),
                ),
                OutlinedButton(
                  onPressed: c.busy || c.pending ? null : c.saveInputs,
                  child: const Text('Save encrypted inputs'),
                ),
              ],
            ),
            if (c.pending)
              const Text(
                'Only the original sealed request can resolve an uncertain result.',
              ),
          ],
          const Divider(height: 40),
          if (c.online &&
              !c.busy &&
              c.error == null &&
              f.isEmpty &&
              c.items.isEmpty)
            JentraPanel(
              child: JentraEmptyState(
                icon: Icons.account_tree_outlined,
                title: c.kind == 'cost_centre'
                    ? 'No cost centres yet'
                    : 'No project tags yet',
                description: c.kind == 'cost_centre'
                    ? 'Choose New dimension to create a cost centre for journals and budgets in this scope.'
                    : 'Choose New dimension to create a project tag for journals and budgets in this scope.',
              ),
            ),
          for (final row in c.items)
            Card(
              child: ListTile(
                title: Text('${row['code']} · ${row['name']}'),
                subtitle: Text(
                  '${row['status']} · version ${row['version']} · ${row['dimension_branch_id'] == null ? 'Entity' : 'Current branch'}',
                ),
                isThreeLine: true,
                onTap: c.locked ? null : () => c.open(row),
              ),
            ),
          if (c.cursor != null)
            TextButton(
              onPressed: c.busy ? null : c.more,
              child: const Text('More dimensions'),
            ),
        ],
      );
    },
  );
}

class FinancialDimensionButton extends StatefulWidget {
  const FinancialDimensionButton({
    super.key,
    required this.scope,
    required this.gateway,
    required this.kind,
    required this.label,
    required this.enabled,
    required this.onSelected,
    this.entityOnly = false,
  });
  final TenantContext scope;
  final FinancialDimensionGateway gateway;
  final String kind, label;
  final bool enabled;
  final bool entityOnly;
  final ValueChanged<Map<String, Object?>?> onSelected;
  @override
  State<FinancialDimensionButton> createState() => _DimensionButtonState();
}

class _DimensionPickerAccess extends ChangeNotifier
    implements OperationalReadAccess {
  _DimensionPickerAccess(this.allowed);
  final bool Function() allowed;
  int _epoch = 0;
  bool _disposed = false, _notifierDisposed = false;
  @override
  int get readAccessEpoch => _epoch;
  @override
  bool currentRead(int epoch) => !_disposed && epoch == _epoch && allowed();
  void invalidate() {
    if (_disposed) return;
    _epoch++;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_notifierDisposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  @override
  void denyReadAccess() => invalidate();
  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    void finish() {
      notifyListeners();
      _notifierDisposed = true;
      super.dispose();
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => finish());
    } else {
      finish();
    }
  }
}

class _DimensionButtonState extends State<FinancialDimensionButton> {
  late final _DimensionPickerAccess access;
  ProviderContainer? container;
  final subscriptions = <ProviderSubscription<dynamic>>[];
  bool allowed() {
    final current = container;
    if (!mounted || !widget.enabled || current == null) return false;
    final network = current.read(connectivityStateProvider);
    final caps = current.read(businessCapabilitiesProvider);
    return current.read(activeTenantContextProvider) == widget.scope &&
        !network.isLoading &&
        !network.hasError &&
        network.value == ConnectivityState.online &&
        !caps.isLoading &&
        !caps.hasError &&
        (caps.value?.contains('finance.view') ?? false);
  }

  @override
  void initState() {
    super.initState();
    access = _DimensionPickerAccess(allowed);
  }

  void closeSubscriptions() {
    for (final subscription in subscriptions) {
      subscription.close();
    }
    subscriptions.clear();
  }

  @override
  void didUpdateWidget(FinancialDimensionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope ||
        oldWidget.gateway != widget.gateway ||
        oldWidget.kind != widget.kind ||
        oldWidget.entityOnly != widget.entityOnly ||
        oldWidget.enabled && !widget.enabled) {
      access.invalidate();
    }
  }

  @override
  void dispose() {
    closeSubscriptions();
    access.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    if (subscriptions.isNotEmpty) return;
    final current = ProviderScope.containerOf(context, listen: false);
    container = current;
    subscriptions.add(
      current.listen(activeTenantContextProvider, (previous, next) {
        if (previous != next) access.invalidate();
      }),
    );
    subscriptions.add(
      current.listen(connectivityStateProvider, (previous, next) {
        if (previous != next) access.invalidate();
      }),
    );
    subscriptions.add(
      current.listen(businessCapabilitiesProvider, (previous, next) {
        if (previous != next) access.invalidate();
      }),
    );
    final epoch = access.readAccessEpoch;
    try {
      final result = await showOperationalReadDialog<Map<String, Object?>>(
        context,
        access,
        (_) => _DimensionPicker(
          scope: widget.scope,
          gateway: widget.gateway,
          kind: widget.kind,
          entityOnly: widget.entityOnly,
          access: access,
        ),
      );
      if (result != null && mounted && access.currentRead(epoch)) {
        widget.onSelected(result.isEmpty ? null : result);
      }
    } finally {
      closeSubscriptions();
      container = null;
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: widget.enabled ? pick : null,
    child: Text(widget.label),
  );
}

class _DimensionPicker extends ConsumerStatefulWidget {
  const _DimensionPicker({
    required this.scope,
    required this.gateway,
    required this.kind,
    required this.entityOnly,
    required this.access,
  });
  final OperationalReadAccess access;
  final bool entityOnly;
  final TenantContext scope;
  final FinancialDimensionGateway gateway;
  final String kind;
  @override
  ConsumerState<_DimensionPicker> createState() => _DimensionPickerState();
}

class _DimensionPickerState extends ConsumerState<_DimensionPicker> {
  bool started = false;
  bool busy = false;
  String? error, cursor;
  String search = '';
  int epoch = 0;
  List<Map<String, Object?>> rows = [];
  @override
  void initState() {
    super.initState();
  }

  bool allowed() {
    final network = ref.read(connectivityStateProvider);
    final caps = ref.read(businessCapabilitiesProvider);
    return ref.read(activeTenantContextProvider) == widget.scope &&
        !network.isLoading &&
        !network.hasError &&
        network.value == ConnectivityState.online &&
        !caps.isLoading &&
        !caps.hasError &&
        (caps.value?.contains('finance.view') ?? false);
  }

  Future<void> load({bool more = false}) async {
    if (!allowed()) return;
    final ticket = ++epoch;
    final accessEpoch = widget.access.readAccessEpoch;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await widget.gateway.page(
        widget.scope,
        widget.kind,
        after: more ? cursor : null,
        search: search,
      );
      if (!mounted ||
          ticket != epoch ||
          !allowed() ||
          !widget.access.currentRead(accessEpoch)) {
        return;
      }
      setState(() {
        rows = [
          if (more) ...rows,
          ...(r['items'] as List).map(
            (x) => (x as Map).cast<String, Object?>(),
          ),
        ];
        cursor = r['next_cursor'] as String?;
      });
    } catch (e) {
      if (mounted &&
          ticket == epoch &&
          widget.access.currentRead(accessEpoch)) {
        if (e is DomainError &&
            const {
              'PERMISSION_DENIED',
              'ACCESS_DENIED',
              'MFA_REQUIRED',
              'AUTHENTICATION_REQUIRED',
            }.contains(e.code)) {
          widget.access.denyReadAccess();
        }
        setState(() {
          rows = [];
          cursor = null;
          error = e is DomainError
              ? e.message
              : 'Unable to verify dimension choices.';
        });
      }
    } finally {
      if (mounted &&
          ticket == epoch &&
          widget.access.currentRead(accessEpoch)) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(activeTenantContextProvider);
    ref.watch(connectivityStateProvider);
    ref.watch(businessCapabilitiesProvider);
    if (!allowed()) {
      epoch++;
      rows = [];
      cursor = null;
      busy = false;
      started = false;
      return const AlertDialog(
        title: Text('Dimension access changed'),
        content: Text(
          'Close and reopen after verifying the selected scope and connection.',
        ),
      );
    }
    if (!started) {
      started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) load();
      });
    }
    return AlertDialog(
      title: Text(
        widget.kind == 'cost_centre'
            ? 'Choose cost centre'
            : 'Choose project tag',
      ),
      content: SizedBox(
        width: 620,
        height: 440,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search code or name',
              ),
              onChanged: (v) {
                search = v;
                rows = [];
                cursor = null;
                load();
              },
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null) Text(error!),
            Expanded(
              child: ListView(
                children: [
                  for (final row in rows.where(
                    (x) =>
                        !widget.entityOnly || x['dimension_branch_id'] == null,
                  ))
                    ListTile(
                      title: Text('${row['code']} · ${row['name']}'),
                      subtitle: Text(
                        'Version ${row['version']} · ${row['dimension_branch_id'] == null ? 'Entity' : 'Current branch'}',
                      ),
                      onTap: busy ? null : () => Navigator.pop(context, row),
                    ),
                  if (cursor != null)
                    TextButton(
                      onPressed: busy ? null : () => load(more: true),
                      child: const Text('More choices'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, <String, Object?>{}),
          child: const Text('Clear dimension'),
        ),
      ],
    );
  }
}

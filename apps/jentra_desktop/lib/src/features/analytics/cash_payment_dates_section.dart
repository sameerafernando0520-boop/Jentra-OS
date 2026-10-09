import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_platform/analytics_platform.dart';
import 'package:jentra_domain/jentra_domain.dart'
    show ConnectivityState, ExactDecimal;
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import 'cash_scenario_screen.dart' show datedCashGatewayProvider;

final cashPaymentDatesControllerProvider = Provider.autoDispose
    .family<CashPaymentDatesController?, String>((ref, kind) {
      ref.watch(authSessionRevisionProvider);
      final actor = ref.watch(authenticatedActorProvider),
          context = ref.watch(activeTenantContextProvider),
          caps = ref.watch(businessCapabilitiesProvider),
          rpc = ref.watch(datedCashGatewayProvider)?.rpc;
      if (actor.isLoading ||
          actor.hasError ||
          actor.value == null ||
          context?.actorId != actor.value ||
          context?.legalEntityId == null ||
          context?.branchId == null ||
          rpc == null ||
          caps.isLoading ||
          caps.hasError ||
          !(caps.value?.contains('analytics.cash_dates.prepare') == true ||
              caps.value?.contains('analytics.cash_dates.approve') == true)) {
        return null;
      }
      final gateway = CashPaymentDatesGateway(rpc);
      final scope = ProcessMetricScope(
        tenantId: context!.tenantId,
        legalEntityId: context.legalEntityId!,
        branchId: context.branchId,
      );
      Future<void> authorize(ProcessMetricScope s, String a) =>
          gateway.authorize(s, a, kind);
      final c = CashPaymentDatesController(
        scope,
        actor.value!,
        kind,
        gateway,
        Wave5CommandStore(
          ref.watch(encryptedDraftRepositoryProvider),
          authorize,
          namespace: 'cash_dates_$kind',
        ),
      );
      c.setOnline(
        ref.read(connectivityStateProvider).value == ConnectivityState.online,
      );
      ref.listen(
        connectivityStateProvider,
        (_, next) => c.setOnline(next.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      return c;
    });

final class CashPaymentDatesController extends ChangeNotifier {
  CashPaymentDatesController(
    this.scope,
    this.actor,
    this.kind,
    this.gateway,
    this.store,
  );
  final ProcessMetricScope scope;
  final String actor, kind;
  final CashPaymentDatesGateway gateway;
  final Wave5CommandStore store;
  List<CashPaymentDateSource> sources = const [];
  Map<String, Object?>? proposal, pending, receipt;
  String? next, error;
  bool busy = false, online = true, dead = false;
  int epoch = 0;
  bool current(int ticket) => !dead && online && epoch == ticket;
  void setOnline(bool value) {
    if (online == value) return;
    online = value;
    epoch++;
    busy = false;
    _clear();
    notifyListeners();
  }

  void _clear() {
    sources = const [];
    proposal = null;
    pending = null;
    receipt = null;
    next = null;
    error = null;
  }

  Future<void> _run(Future<void> Function(int) work) async {
    if (busy || dead || !online) return;
    final ticket = ++epoch;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await gateway.authorize(scope, actor, kind);
      if (!current(ticket)) return;
      await work(ticket);
    } catch (_) {
      if (current(ticket)) {
        _clear();
        error = 'Payment-date operation unavailable. Recheck access, then restore the original encrypted command if its response was uncertain.';
      }
    } finally {
      if (current(ticket)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> read({bool more = false}) => _run((ticket) async {
    final page = await gateway.sources(scope, kind, after: more ? next : null);
    if (!current(ticket)) return;
    await gateway.authorize(scope, actor, kind);
    if (current(ticket)) {
      sources = page.$1;
      next = page.$2;
      proposal = null;
      receipt = null;
    }
  });
  Future<void> inspect(String id) => _run((ticket) async {
    final p = await gateway.proposal(scope, kind, id);
    if (!current(ticket)) return;
    await gateway.authorize(scope, actor, kind);
    if (current(ticket)) {
      proposal = p;
      receipt = null;
    }
  });
  Future<void> restore() => _run((ticket) async {
    final saved = await store.restore(scope, actor);
    if (current(ticket)) pending = saved;
  });
  Future<void> _send(int ticket, Map<String, Object?> envelope) async {
    if (!current(ticket)) return;
    await store.save(scope, actor, envelope);
    if (!current(ticket)) return;
    pending = envelope;
    final result = await gateway.command(scope, envelope);
    if (!current(ticket)) return;
    await gateway.authorize(scope, actor, kind);
    if (!current(ticket)) return;
    await store.remove(scope, actor, isCurrent: () => current(ticket));
    if (current(ticket)) {
      pending = null;
      receipt = result;
      sources = const [];
      next = null;
      proposal = null;
    }
  }

  Future<void> retry() => _run((ticket) async {
    final original = pending ?? await store.restore(scope, actor);
    if (original == null) throw StateError('Original command required');
    await _send(ticket, original);
  });
  Map<String, Object?> _envelope(String action, Map<String, Object?> payload) =>
      {
        'commandId': const Uuid().v4(),
        'idempotencyKey': const Uuid().v4(),
        'clientTimestamp': DateTime.now().toUtc().toIso8601String(),
        'action': action,
        'payload': payload,
      };
  Future<void> prepare(
    CashPaymentDateSource source,
    String date,
    String reason,
  ) => _run((ticket) async {
    if (source.kind != kind ||
        source.branch != scope.branchId ||
        !sources.contains(source)) {
      throw StateError('Reviewed current source required');
    }
    final original = await store.restore(scope, actor);
    if (original != null) {
      if (current(ticket)) {
        pending = original;
        error = 'Review and retry the original uncertain command first.';
      }
      return;
    }
    await _send(
      ticket,
      _envelope('prepare', {
        'id': const Uuid().v4(),
        'sourceKind': kind,
        'sourceId': source.id,
        'sourceHash': source.hash,
        'dueDate': date,
        'reasonCode': reason,
        'expectedVersion': source.version,
      }),
    );
  });
  Future<void> decide(bool approve) => _run((ticket) async {
    final p = proposal;
    if (p == null || p['decision'] != null || p['preparedBy'] == actor) {
      throw StateError('Distinct approver required');
    }
    final original = await store.restore(scope, actor);
    if (original != null) {
      if (current(ticket)) {
        pending = original;
        error = 'Review and retry the original uncertain command first.';
      }
      return;
    }
    await _send(
      ticket,
      _envelope(approve ? 'approve' : 'reject', {
        'id': p['id'],
        'proposalHash': p['proposalHash'],
      }),
    );
  });
  @override
  void dispose() {
    dead = true;
    epoch++;
    _clear();
    super.dispose();
  }
}

class CashPaymentDatesSection extends ConsumerStatefulWidget {
  const CashPaymentDatesSection({super.key});
  @override
  ConsumerState<CashPaymentDatesSection> createState() =>
      _CashPaymentDatesSectionState();
}

class _CashPaymentDatesSectionState
    extends ConsumerState<CashPaymentDatesSection> {
  String kind = 'payroll_obligation', reason = 'payroll_calendar';
  String? sourceId;
  final date = TextEditingController(), proposalId = TextEditingController();
  String? actorKey;
  CashPaymentDatesController? listening;
  void clearUnavailableFields() {
    if (listening?.online != true || listening?.error != null) {
      date.clear();
      proposalId.clear();
      sourceId = null;
    }
  }

  @override
  void dispose() {
    listening?.removeListener(clearUnavailableFields);
    date.dispose();
    proposalId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(cashPaymentDatesControllerProvider(kind));
    if (listening != c) {
      listening?.removeListener(clearUnavailableFields);
      listening = c;
      listening?.addListener(clearUnavailableFields);
    }
    final key = c == null
        ? null
        : '${c.actor}:${c.scope.tenantId}:${c.scope.legalEntityId}:${c.scope.branchId}:$kind';
    if (key != actorKey) {
      actorKey = key;
      date.clear();
      proposalId.clear();
      sourceId = null;
    }
    return ExpansionTile(
      title: const Text('Authoritative payment dates'),
      childrenPadding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Propose a payment date for an issued payroll, recovery or reimbursement obligation. A distinct MFA approver reviews its exact revision. Scenario overrides remain hypothetical.',
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: kind,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Obligation family'),
          items: const [
            DropdownMenuItem(
              value: 'payroll_obligation',
              child: Text('Payroll obligations'),
            ),
            DropdownMenuItem(
              value: 'payroll_correction',
              child: Text('Payroll corrections and recoveries'),
            ),
            DropdownMenuItem(
              value: 'project_reimbursement',
              child: Text('Project reimbursements'),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() {
                kind = value;
                sourceId = null;
                date.clear();
                proposalId.clear();
              });
            }
          },
        ),
        const SizedBox(height: 16),
        if (c == null)
          const Text(
            'Select a branch with current payment-date and source access. MFA is required.',
          )
        else
          ListenableBuilder(
            listenable: c,
            builder: (context, _) {
              final ready = c.online && !c.busy;
              final selected = c.sources
                  .where((s) => s.id == sourceId)
                  .firstOrNull;
              final caps =
                  ref.watch(businessCapabilitiesProvider).value ??
                  const <String>{};
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (c.busy) const LinearProgressIndicator(),
                  if (c.error != null) Text(c.error!),
                  Wrap(
                    spacing: 12,
                    children: [
                      TextButton(
                        onPressed: ready ? c.read : null,
                        child: const Text('Read issued obligations'),
                      ),
                      TextButton(
                        onPressed: ready && c.next != null
                            ? () => c.read(more: true)
                            : null,
                        child: const Text('Next obligations'),
                      ),
                      TextButton(
                        onPressed: ready ? c.restore : null,
                        child: const Text('Restore payment-date command'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: ValueKey(c.sources.map((s) => s.id).join()),
                    initialValue: selected?.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Issued obligation',
                    ),
                    items: [
                      for (final s in c.sources)
                        DropdownMenuItem(
                          value: s.id,
                          child: Text(
                            '${s.currency} ${ExactDecimal.fromScaledValue(s.remaining.abs(), scale: 6).toDecimalString()} ${s.inflow ? 'recovery' : 'payment'} · ${s.approvedDate ?? 'date required'} · ${s.id}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: ready
                        ? (value) => setState(() => sourceId = value)
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: date,
                    enabled: ready,
                    decoration: const InputDecoration(
                      labelText: 'Authoritative payment date (YYYY-MM-DD)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: reason,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Date authority reason',
                    ),
                    items: [
                      for (final r in [
                        'payroll_calendar',
                        'payment_terms',
                        'reviewed_reschedule',
                        'correction_recovery',
                      ])
                        DropdownMenuItem(
                          value: r,
                          child: Text(r.replaceAll('_', ' ')),
                        ),
                    ],
                    onChanged: ready
                        ? (value) {
                            if (value != null) setState(() => reason = value);
                          }
                        : null,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed:
                        ready &&
                            selected != null &&
                            c.pending == null &&
                            caps.contains('analytics.cash_dates.prepare')
                        ? () => c.prepare(selected, date.text, reason)
                        : null,
                    child: const Text('Propose authoritative date'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: proposalId,
                    enabled: ready,
                    decoration: const InputDecoration(
                      labelText: 'Payment-date proposal ID',
                    ),
                    onSubmitted: ready ? c.inspect : null,
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: ready ? () => c.inspect(proposalId.text) : null,
                    child: const Text('Read exact proposal'),
                  ),
                  if (c.proposal != null) ...[
                    SelectableText(
                      'Proposal ${c.proposal!['id']} · ${c.proposal!['dueDate']} · ${c.proposal!['reasonCode']} · expected approved version ${c.proposal!['expectedVersion']} · ${c.proposal!['decision'] ?? 'awaiting independent review'}',
                    ),
                    SelectableText(
                      'Reviewed digest: ${c.proposal!['proposalHash']}',
                    ),
                    Wrap(
                      spacing: 12,
                      children: [
                        for (final approve in [true, false])
                          TextButton(
                            onPressed:
                                ready &&
                                    caps.contains(
                                      'analytics.cash_dates.approve',
                                    ) &&
                                    c.pending == null &&
                                    c.proposal!['decision'] == null &&
                                    c.proposal!['preparedBy'] != c.actor
                                ? () => c.decide(approve)
                                : null,
                            child: Text(
                              approve
                                  ? 'Approve exact payment date'
                                  : 'Reject payment date',
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (c.pending != null) ...[
                    SelectableText(
                      'Original ${c.pending!['action']} command ${(c.pending!['payload'] as Map)['id']} awaits reconciliation.',
                    ),
                    TextButton(
                      onPressed: ready ? c.retry : null,
                      child: const Text('Retry original payment-date command'),
                    ),
                  ],
                  if (c.receipt != null)
                    SelectableText(
                      'Payment-date proposal ${c.receipt!['id']} · ${c.receipt!['status']} · version ${c.receipt!['version']}',
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

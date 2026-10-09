import 'package:flutter/material.dart';

import 'analytics_rows.dart';
import 'cash_payment_dates_section.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart'
    show ConnectivityState, ExactDecimal;
import 'package:jentra_platform/analytics_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import '../report_export/report_export_screen.dart';

final datedCashGatewayProvider = Provider<DatedCashGateway?>((ref) => null);
final cashScenarioControllerProvider =
    Provider.autoDispose<CashScenarioController?>((ref) {
      ref.watch(authSessionRevisionProvider);
      final actor = ref.watch(authenticatedActorProvider),
          context = ref.watch(activeTenantContextProvider),
          caps = ref.watch(businessCapabilitiesProvider),
          gateway = ref.watch(datedCashGatewayProvider);
      if (actor.isLoading ||
          actor.hasError ||
          actor.value == null ||
          context?.actorId != actor.value ||
          context?.legalEntityId == null ||
          gateway == null ||
          caps.isLoading ||
          caps.hasError ||
          !{
            'analytics.view',
            'finance.view',
            'finance.receivables.view',
          }.every((p) => caps.value?.contains(p) ?? false)) {
        return null;
      }
      final c = CashScenarioController(
        ProcessMetricScope(
          tenantId: context!.tenantId,
          legalEntityId: context.legalEntityId!,
          branchId: context.branchId,
        ),
        actor.value!,
        gateway,
        CashScenarioStore(
          ref.watch(encryptedDraftRepositoryProvider),
          gateway.authorize,
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

final class CashScenarioController extends ChangeNotifier {
  CashScenarioController(this.scope, this.actor, this.gateway, this.store);
  final ProcessMetricScope scope;
  final String actor;
  final DatedCashGateway gateway;
  final CashScenarioStore store;
  bool online = true, busy = false, dead = false;
  int epoch = 0;
  String? error, savedId;
  DatedCashBasis? basis;
  CashScenarioRevision? revision;
  void setOnline(bool value) {
    if (online == value) return;
    online = value;
    epoch++;
    basis = null;
    revision = null;
    savedId = null;
    busy = false;
    error = null;
    notifyListeners();
  }

  bool current(int ticket) => !dead && online && epoch == ticket;
  Future<void> _run(Future<void> Function(int) work) async {
    if (!online || busy || dead) return;
    final ticket = ++epoch;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await gateway.authorize(scope, actor);
      if (!current(ticket)) return;
      await work(ticket);
    } catch (_) {
      if (current(ticket)) {
        basis = null;
        revision = null;
        savedId = null;
        error = 'Scenario access, source basis or command outcome could not be confirmed. Restore the saved request before retrying.';
      }
    } finally {
      if (current(ticket)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  CashScenarioRevision _revision(
    DatedCashBasis b,
    Map<String, Map<String, String>> overrides,
  ) => CashScenarioRevision(
    id: const Uuid().v4(),
    scope: scope,
    sourceHash: b.hash,
    horizonStart: b.start,
    horizonEnd: b.end,
    recordedThrough: b.recordedThrough,
    overrides: overrides,
  );
  Future<void> read(String start, String end) => _run((ticket) async {
    final next = await gateway.read(
      scope,
      start,
      end,
      DateTime.now().toUtc().toIso8601String(),
    );
    if (!current(ticket)) return;
    await gateway.authorize(scope, actor);
    if (!current(ticket)) return;
    final parameters = _revision(next, {});
    next.project(parameters, requiredProviders: next.requiredProviders);
    if (current(ticket)) {
      basis = next;
      revision = parameters;
      savedId = null;
    }
  });
  Future<void> reviseObligation(
    String id,
    String date,
    String amount,
    String reason,
  ) => _run((ticket) async {
    final b = basis, r = revision;
    if (b == null || r == null) throw StateError('Source required');
    final next = _revision(b, {
      ...r.overrides,
      id: {
        'dueDate': date,
        'remainingUnits': ExactDecimal.parse(
          amount,
          scale: 6,
        ).scaledValue.toString(),
        'reasonCode': reason,
      },
    });
    b.project(next, requiredProviders: b.requiredProviders);
    await store.save(actor, next);
    if (!current(ticket)) return;
    await gateway.authorize(scope, actor);
    if (current(ticket)) {
      revision = next;
      savedId = null;
    }
  });
  Future<void> saveDraft() => _run((ticket) async {
    final r = revision;
    if (r == null) throw StateError('Source required');
    await store.save(actor, r);
  });
  Future<void> restore() => _run((ticket) async {
    var r = await store.restore(scope, actor, pending: true);
    if (!current(ticket)) return;
    r ??= await store.restore(scope, actor);
    if (!current(ticket) || r == null) return;
    final b = await gateway.read(
      scope,
      r.horizonStart,
      r.horizonEnd,
      r.recordedThrough,
    );
    if (!current(ticket)) return;
    final projection = b.project(r, requiredProviders: b.requiredProviders);
    if (!projection.available) {
      throw StateError('Every required cash provider must be complete.');
    }
    await gateway.authorize(scope, actor);
    if (current(ticket)) {
      basis = b;
      revision = r;
      savedId = null;
    }
  });
  Future<void> freeze() => _run((ticket) async {
    final r = revision, b = basis;
    if (r == null || b == null) throw StateError('Source required');
    final original = await store.restore(scope, actor, pending: true);
    if (!current(ticket)) return;
    if (original != null && original.id != r.id) {
      final captured = await gateway.read(
        scope,
        original.horizonStart,
        original.horizonEnd,
        original.recordedThrough,
      );
      if (!current(ticket)) return;
      captured.project(original, requiredProviders: captured.requiredProviders);
      await gateway.authorize(scope, actor);
      if (current(ticket)) {
        basis = captured;
        revision = original;
        savedId = null;
        error = 'The original uncertain freeze was restored. Review its assumptions before retrying.';
      }
      return;
    }
    final projection = b.project(r, requiredProviders: b.requiredProviders);
    if (!projection.available) {
      throw StateError('Every required cash provider must be complete.');
    }
    await store.save(actor, r, pending: true);
    if (!current(ticket)) return;
    final id = await gateway.save(r);
    if (!current(ticket)) return;
    await gateway.authorize(scope, actor);
    if (!current(ticket)) return;
    await store.removePending(scope, actor, isCurrent: () => current(ticket));
    if (current(ticket)) savedId = id;
  });
  Future<void> reopen(String id) => _run((ticket) async {
    final next = await gateway.reopen(scope, id);
    if (!current(ticket)) return;
    next.$1.project(next.$2, requiredProviders: next.$1.requiredProviders);
    await gateway.authorize(scope, actor);
    if (current(ticket)) {
      basis = next.$1;
      revision = next.$2;
      savedId = id;
    }
  });
  @override
  void dispose() {
    dead = true;
    epoch++;
    basis = null;
    revision = null;
    savedId = null;
    super.dispose();
  }
}

class CashScenarioScreen extends ConsumerStatefulWidget {
  const CashScenarioScreen({super.key});
  @override
  ConsumerState<CashScenarioScreen> createState() => _CashScenarioScreenState();
}

class _CashScenarioScreenState extends ConsumerState<CashScenarioScreen> {
  final start = TextEditingController(),
      end = TextEditingController(),
      reopen = TextEditingController(),
      date = TextEditingController(),
      amount = TextEditingController();
  String? obligation;
  String reason = 'collection_delay';
  CashScenarioController? listening;
  void clearUnavailableFields() {
    if (listening?.online != true || listening?.error != null) {
      _clearFields();
    }
  }

  void _clearFields() {
    for (final c in [start, end, reopen, date, amount]) {
      c.clear();
    }
    obligation = null;
    reason = 'collection_delay';
  }

  @override
  void dispose() {
    listening?.removeListener(clearUnavailableFields);
    for (final c in [start, end, reopen, date, amount]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(cashScenarioControllerProvider);
    if (listening != c) {
      listening?.removeListener(clearUnavailableFields);
      _clearFields();
      listening = c;
      listening?.addListener(clearUnavailableFields);
    }
    if (c == null) {
      return const Center(
        child: Text(
          'Select an online scope with analytics, finance and receivables access.',
        ),
      );
    }
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        CashScenario? result;
        if (c.basis != null && c.revision != null) {
          result = c.basis!.project(
            c.revision!,
            requiredProviders: c.basis!.requiredProviders,
          );
        }
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Cash scenarios',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const Text(
              'Cash includes posted bank cash and dated remaining obligations. Payroll, recoveries and project reimbursements require independently approved payment dates. A complete projection requires every provider. Overdue items and unallocated credits are excluded.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: start,
              decoration: const InputDecoration(
                labelText: 'Horizon start (YYYY-MM-DD)',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: end,
              decoration: const InputDecoration(
                labelText: 'Horizon end, exclusive (YYYY-MM-DD)',
              ),
              onSubmitted: (_) => c.read(start.text, end.text),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              children: [
                FilledButton(
                  onPressed: c.online && !c.busy
                      ? () => c.read(start.text, end.text)
                      : null,
                  child: const Text('Read dated sources'),
                ),
                TextButton(
                  onPressed: c.online && !c.busy ? c.restore : null,
                  child: const Text('Restore encrypted draft'),
                ),
              ],
            ),
            if (c.busy) const LinearProgressIndicator(),
            if (c.error != null) Text(c.error!),
            if (result != null && !result.available)
              Text(
                'Projection unavailable: ${result.unavailableProviders.join(', ')}',
              ),
            if (c.basis != null) ...[
              Text(
                'Provider status · ${c.basis!.providerStatus.entries.map((e) => '${e.key}: ${e.value}').join(' · ')}',
              ),
              Text(
                '${c.basis!.controls.length} cash controls · ${c.basis!.obligations.length} dated remaining obligations · ${c.basis!.contractRevision == 3 ? 'full provider contract' : 'legacy partial bank/AR/AP basis'}',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue:
                    c.basis!.obligations.any((o) => o.id == obligation)
                    ? obligation
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Obligation to override',
                ),
                items: [
                  for (final o in c.basis!.obligations)
                    DropdownMenuItem(
                      value: o.id,
                      child: Text(
                        '${o.currency} ${exactHistoricalAmount(o.remainingUnits)} · ${o.dueDate.toIso8601String().substring(0, 10)} · ${o.id}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() {
                  obligation = v;
                  final selected = c.basis!.obligations
                      .where((o) => o.id == v)
                      .firstOrNull;
                  if (selected != null) {
                    reason = selected.provider == 'payables'
                        ? 'payment_delay'
                        : 'collection_delay';
                  }
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: date,
                decoration: const InputDecoration(
                  labelText: 'Scenario due date (YYYY-MM-DD)',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amount,
                decoration: const InputDecoration(
                  labelText: 'Scenario remaining amount, exact decimal',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: reason,
                items: const [
                  DropdownMenuItem(
                    value: 'collection_delay',
                    child: Text('Collection delay'),
                  ),
                  DropdownMenuItem(
                    value: 'payment_delay',
                    child: Text('Payment delay'),
                  ),
                  DropdownMenuItem(
                    value: 'reviewed_amount',
                    child: Text('Reviewed amount'),
                  ),
                ],
                onChanged: (v) => setState(() => reason = v!),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                children: [
                  TextButton(
                    onPressed: !c.busy && obligation != null
                        ? () => c.reviseObligation(
                            obligation!,
                            date.text,
                            amount.text,
                            reason,
                          )
                        : null,
                    child: const Text('Create assumption revision'),
                  ),
                  TextButton(
                    onPressed: !c.busy ? c.saveDraft : null,
                    child: const Text('Save encrypted draft'),
                  ),
                  FilledButton(
                    onPressed: !c.busy && result?.available == true
                        ? c.freeze
                        : null,
                    child: const Text('Freeze immutable scenario'),
                  ),
                ],
              ),
            ],
            if (c.savedId != null)
              SelectableText('Frozen scenario: ${c.savedId}'),
            if (c.savedId != null)
              ReportExportLink(
                sourceType: 'w5_cash',
                sourceId: c.savedId!,
                section: 'buckets',
                enabled: c.online && !c.busy,
                label: 'Create governed scenario export',
              ),
            const SizedBox(height: 16),
            TextField(
              controller: reopen,
              decoration: const InputDecoration(
                labelText: 'Frozen scenario ID',
              ),
              onSubmitted: (v) => c.reopen(v),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: c.online && !c.busy
                  ? () => c.reopen(reopen.text)
                  : null,
              child: const Text('Reopen under current access'),
            ),
            if (result != null) ...[
              Text(
                '${result.buckets.length} daily currency buckets · 50 per page',
              ),
              AnalyticsRows(
                key: ValueKey(c.revision?.id),
                rows: result.buckets,
                row: (b) => Text(
                  '${b.date.toIso8601String().substring(0, 10)} · ${b.currency} · ${b.exactBalance}',
                ),
              ),
            ],
            const CashPaymentDatesSection(),
          ],
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart'
    show DomainError, ConnectivityState;
import 'package:jentra_platform/analytics_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import 'reviewed_model_section.dart';

final wave5ControlRepositoryProvider = Provider<Wave5ControlRepository?>(
  (ref) => null,
);
final wave5ControlControllerProvider =
    Provider.autoDispose<Wave5ControlController?>((ref) {
      ref.watch(authSessionRevisionProvider);
      final repo = ref.watch(wave5ControlRepositoryProvider),
          active = ref.watch(activeTenantContextProvider),
          auth = ref.watch(authenticatedActorProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      if (repo == null ||
          auth.isLoading ||
          auth.hasError ||
          auth.value == null ||
          caps.isLoading ||
          caps.hasError) {
        return null;
      }
      final scope = active?.legalEntityId == null
          ? null
          : ProcessMetricScope(
              tenantId: active!.tenantId,
              legalEntityId: active.legalEntityId!,
              branchId: active.branchId,
            );
      final c = Wave5ControlController(
        repository: repo,
        actor: auth.value!,
        scope: scope,
        store: Wave5CommandStore(
          ref.watch(encryptedDraftRepositoryProvider),
          repo.authorizeProposalRecovery,
          namespace: 'proposal',
        ),
        billingStore: Wave5CommandStore(
          ref.watch(encryptedDraftRepositoryProvider),
          repo.authorizeSubscriptionRecovery,
          namespace: 'subscription',
        ),
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
      );
      ref.listen(
        connectivityStateProvider,
        (_, v) => c.setOnline(v.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      return c;
    });

final class Wave5ControlController extends ChangeNotifier {
  Wave5ControlController({
    required this.repository,
    required this.actor,
    required this.scope,
    this.store,
    this.billingStore,
    this.online = true,
  });
  final Wave5ControlRepository repository;
  final String actor;
  final ProcessMetricScope? scope;
  final Wave5CommandStore? store, billingStore;
  bool online, busy = false, disposed = false;
  int epoch = 0;
  String? error;
  VerifiedHumanProposal? proposal;
  Map<String, Object?>? usage, health, pending, subscription, billingPending;
  String? scheduledRevision;
  void clear() {
    epoch++;
    proposal = null;
    usage = null;
    health = null;
    subscription = null;
    error = null;
    busy = false;
    if (!disposed) notifyListeners();
  }

  void setOnline(bool v) {
    if (online == v) return;
    online = v;
    pending = null;
    billingPending = null;
    scheduledRevision = null;
    clear();
  }

  bool current(int ticket) => !disposed && online && epoch == ticket;
  Future<void> run(Future<void> Function(int) action) async {
    if (!online || busy) return;
    clear();
    final ticket = epoch;
    busy = true;
    notifyListeners();
    try {
      await action(ticket);
    } catch (e) {
      if (current(ticket)) {
        proposal = null;
        usage = null;
        health = null;
        error = e is DomainError ? e.message : 'Control evidence is unavailable under the current contract and source access.';
      }
    } finally {
      if (current(ticket)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> openProposal(String id) => run((ticket) async {
    if (scope == null) throw const FormatException('Choose an entity.');
    final value = await repository.proposal(scope!, id);
    await repository.authorizeProposalRecovery(scope!, actor);
    if (current(ticket)) proposal = value;
  });
  Future<void> readUsage(String metric, String period) => run((ticket) async {
    if (scope == null) throw const FormatException('Choose an entity.');
    final value = await repository.usage(scope!.tenantId, metric, period);
    if (current(ticket)) usage = value;
  });
  Future<void> readHealth({String? grant}) => run((ticket) async {
    final selected = grant != null && grant.isNotEmpty;
    if (selected && scope == null) {
      throw const FormatException('Choose a tenant.');
    }
    final value = await repository.health(
      tenant: selected ? scope!.tenantId : null,
      grant: selected ? grant : null,
    );
    if (current(ticket)) health = value;
  });
  Future<void> restore() => run((ticket) async {
    if (scope == null || store == null) return;
    final value = await store!.restore(scope!, actor);
    if (current(ticket)) pending = value;
  });
  Future<void> submit(String action, Map<String, Object?> payload) async {
    if (pending != null || scope == null || !online || busy) return;
    final envelope = <String, Object?>{
      'commandId': const Uuid().v4(),
      'idempotencyKey': const Uuid().v4(),
      'clientTimestamp': DateTime.now().toUtc().toIso8601String(),
      'action': action,
      'payload': Map<String, Object?>.unmodifiable(payload),
    };
    try {
      store?.validate(envelope);
    } on FormatException catch (e) {
      error = e.message;
      notifyListeners();
      return;
    }
    pending = envelope;
    await retryOriginal(creating: true);
  }

  Future<void> retryOriginal({bool creating = false}) => run((ticket) async {
    final envelope = pending;
    if (scope == null || envelope == null) return;
    await repository.authorizeProposalRecovery(scope!, actor);
    if (!current(ticket)) return;
    if (creating && store != null) {
      final saved = await store!.restore(scope!, actor);
      if (!current(ticket)) return;
      if (saved != null) {
        pending = saved;
        error = 'A saved original control request must be reviewed and retried before starting another.';
        return;
      }
    }
    await store?.save(scope!, actor, envelope);
    if (!current(ticket)) return;
    final id = await repository.command(scope!, envelope);
    final value = await repository.proposal(scope!, id);
    await repository.authorizeProposalRecovery(scope!, actor);
    if (!current(ticket)) return;
    await store?.remove(scope!, actor);
    if (!current(ticket)) return;
    pending = null;
    proposal = value;
  });
  Future<void> readSubscription() => run((ticket) async {
    if (scope == null) return;
    final value = await repository.subscription(scope!.tenantId);
    if (current(ticket)) subscription = value;
  });
  Future<void> restoreBilling() => run((ticket) async {
    if (scope == null || billingStore == null) return;
    final saved = await billingStore!.restore(scope!, actor);
    if (current(ticket)) billingPending = saved;
  });
  Future<void> scheduleTrial(Map<String, Object?> payload) async {
    if (billingPending != null || scope == null || !online || busy) return;
    final envelope = <String, Object?>{
      'commandId': const Uuid().v4(),
      'idempotencyKey': const Uuid().v4(),
      'clientTimestamp': DateTime.now().toUtc().toIso8601String(),
      'action': 'schedule',
      'payload': Map<String, Object?>.unmodifiable(payload),
    };
    try {
      billingStore?.validate(envelope);
    } on FormatException catch (e) {
      error = e.message;
      notifyListeners();
      return;
    }
    billingPending = envelope;
    await retryBilling(creating: true);
  }

  Future<void> retryBilling({bool creating = false}) => run((ticket) async {
    final envelope = billingPending;
    if (scope == null || envelope == null) return;
    await repository.authorizeSubscriptionRecovery(scope!, actor);
    if (!current(ticket)) return;
    if (creating && billingStore != null) {
      final saved = await billingStore!.restore(scope!, actor);
      if (!current(ticket)) return;
      if (saved != null) {
        billingPending = saved;
        error =
            'Review and retry the saved original subscription request first.';
        return;
      }
    }
    await billingStore?.save(scope!, actor, envelope);
    if (!current(ticket)) return;
    final revision = await repository.scheduleSubscription(scope!, envelope);
    await repository.authorizeSubscriptionRecovery(scope!, actor);
    if (!current(ticket)) return;
    await billingStore?.remove(scope!, actor);
    if (!current(ticket)) return;
    billingPending = null;
    scheduledRevision = revision;
  });
  @override
  void dispose() {
    disposed = true;
    epoch++;
    proposal = null;
    usage = null;
    health = null;
    pending = null;
    billingPending = null;
    subscription = null;
    super.dispose();
  }
}

class Wave5ControlScreen extends ConsumerWidget {
  const Wave5ControlScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(wave5ControlControllerProvider),
        model = ref.watch(reviewedModelControllerProvider),
        caps = ref.watch(businessCapabilitiesProvider).value ?? {};
    if (c == null) {
      return const Center(
        child: Text('Control providers require a current signed-in session.'),
      );
    }
    return Wave5ControlWorkspace(
      key: ValueKey(c),
      controller: c,
      modelController: model,
      capabilities: caps,
    );
  }
}

class Wave5ControlWorkspace extends StatefulWidget {
  const Wave5ControlWorkspace({
    super.key,
    required this.controller,
    required this.capabilities,
    this.modelController,
  });
  final Wave5ControlController controller;
  final Set<String> capabilities;
  final ReviewedModelController? modelController;
  @override
  State<Wave5ControlWorkspace> createState() => _Wave5ControlWorkspaceState();
}

class _Wave5ControlWorkspaceState extends State<Wave5ControlWorkspace> {
  final source = TextEditingController(),
      identity = TextEditingController(),
      expiry = TextEditingController(),
      period = TextEditingController(),
      grant = TextEditingController(),
      plan = TextEditingController(),
      seats = TextEditingController(),
      trialStart = TextEditingController(),
      trialEnd = TextEditingController();
  String metric = 'ai.tokens';
  @override
  void initState() {
    super.initState();
    expiry.text = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 1))
        .toIso8601String();
    final now = DateTime.now().toUtc();
    trialStart.text = now.add(const Duration(minutes: 5)).toIso8601String();
    trialEnd.text = now
        .add(const Duration(days: 14, minutes: 5))
        .toIso8601String();
    period.text = DateTime.utc(now.year, now.month, 1).toIso8601String();
  }

  @override
  void dispose() {
    for (final c in [
      source,
      identity,
      expiry,
      period,
      grant,
      plan,
      seats,
      trialStart,
      trialEnd,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller,
          p = c.proposal,
          canAct = c.online && !c.busy && c.pending == null;
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Jentra Control',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const Text(
            'Review exact human proposals, trusted usage and separately authorized operator health.',
          ),
          if (!c.online)
            const Text('Offline · protected control evidence cleared.'),
          if (c.busy) const LinearProgressIndicator(),
          if (c.error != null) Text(c.error!),
          const SizedBox(height: 20),
          if (widget.modelController != null)
            ReviewedModelWorkspace(
              key: ValueKey(widget.modelController),
              controller: widget.modelController!,
              capabilities: widget.capabilities,
              onHumanSource: (id) {
                source.text = id;
                c.clear();
              },
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Reviewed model requests require current sign-in, source access and a configured worker.',
              ),
            ),
          Text(
            'Human proposals',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'Human proposals freeze a reviewed current pipeline forecast. Model suggestions require explicit human submission; a distinct MFA approver must approve the exact proposal revision.',
          ),
          TextField(
            controller: source,
            decoration: const InputDecoration(
              labelText: 'Frozen source forecast ID',
            ),
            onChanged: (_) => c.clear(),
          ),
          TextField(
            controller: expiry,
            decoration: const InputDecoration(
              labelText: 'Proposal expiry UTC (within 24 hours)',
            ),
            onChanged: (_) => c.clear(),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed:
                  canAct &&
                      c.scope != null &&
                      widget.capabilities.contains('ai.proposals.manage')
                  ? () => c.submit('create', {
                      'sourceId': source.text,
                      'expiresAt': expiry.text,
                    })
                  : null,
              child: const Text('Create immutable human proposal'),
            ),
          ),
          TextField(
            controller: identity,
            decoration: const InputDecoration(labelText: 'Proposal ID'),
            onChanged: (_) => c.clear(),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed:
                  c.online &&
                      !c.busy &&
                      widget.capabilities.contains('ai.proposals.view')
                  ? () => c.openProposal(identity.text)
                  : null,
              child: const Text('Read exact revision'),
            ),
          ),
          if (p != null) ...[
            SelectableText(
              'Proposal ${p.revision.id} · revision ${p.revision.revision} · ${p.state}',
            ),
            const Text(
              'Action: freeze the current pipeline for review. One forecast command; zero model usage.',
            ),
            Text(
              'Horizon ${p.revision.horizonStart} to ${p.revision.horizonEnd} (excluded) · expires ${p.revision.expiresAt.toIso8601String()}',
            ),
            Text(
              'Target revisions ${p.revision.evidence.targetVersions.length} · proposer ${p.revision.proposerId}',
            ),
            SelectableText(
              'Source forecast ${p.revision.evidence.sourceId} · digest ${p.revision.evidence.sourceHash}',
            ),
            SelectableText('Approval hash ${p.revision.parametersHash}'),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(
                  onPressed:
                      canAct &&
                          p.state == 'proposed' &&
                          p.revision.proposerId != c.actor &&
                          widget.capabilities.contains('ai.proposals.approve')
                      ? () => c.submit('decide', {
                          'proposalId': p.revision.id,
                          'parametersHash': p.revision.parametersHash,
                          'decision': 'approved',
                        })
                      : null,
                  child: const Text('Approve this exact revision'),
                ),
                OutlinedButton(
                  onPressed:
                      canAct &&
                          p.state == 'proposed' &&
                          p.revision.proposerId != c.actor &&
                          widget.capabilities.contains('ai.proposals.approve')
                      ? () => c.submit('decide', {
                          'proposalId': p.revision.id,
                          'parametersHash': p.revision.parametersHash,
                          'decision': 'rejected',
                        })
                      : null,
                  child: const Text('Reject this revision'),
                ),
                FilledButton(
                  onPressed:
                      canAct &&
                          p.state == 'approved' &&
                          widget.capabilities.contains('ai.proposals.execute')
                      ? () => c.submit('execute', {'proposalId': p.revision.id})
                      : null,
                  child: const Text('Execute approved forecast command'),
                ),
              ],
            ),
          ],
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                onPressed: c.online && !c.busy ? c.restore : null,
                child: const Text('Restore saved control request'),
              ),
              TextButton(
                onPressed: c.online && !c.busy && c.pending != null
                    ? c.retryOriginal
                    : null,
                child: const Text('Retry original control request'),
              ),
            ],
          ),
          if (c.pending != null)
            SelectableText(
              'Saved ${c.pending!['action']} request ${c.pending!['commandId']} · ${c.pending!['payload']}',
            ),
          const Divider(height: 40),
          Text(
            'Synthetic subscription review',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'Read the current subscription, then schedule an explicit synthetic trial revision. The trusted worker applies it at the start time; real payment collection is unavailable.',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed:
                  c.online &&
                      !c.busy &&
                      c.scope != null &&
                      widget.capabilities.contains('billing.read')
                  ? () async {
                      await c.readSubscription();
                      if (!mounted || c.subscription == null) return;
                      plan.text = c.subscription!['plan'] as String;
                      seats.text = c.subscription!['seats'].toString();
                    }
                  : null,
              child: const Text('Read current subscription'),
            ),
          ),
          if (c.subscription != null)
            Text(
              'Plan ${c.subscription!['plan']} · ${c.subscription!['status']} · ${c.subscription!['seats']} seats · version ${c.subscription!['version']} · synthetic target ${c.subscription!['syntheticTarget']}',
            ),
          for (final field in [
            (plan, 'Reviewed plan code'),
            (seats, 'Seat cap'),
            (trialStart, 'Trial start UTC'),
            (trialEnd, 'Trial end UTC (excluded)'),
          ])
            TextField(
              controller: field.$1,
              decoration: InputDecoration(labelText: field.$2),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed:
                  canAct &&
                      c.billingPending == null &&
                      c.subscription?['syntheticTarget'] == true &&
                      widget.capabilities.contains('billing.synthetic.manage')
                  ? () {
                      final version = c.subscription!['version'] as String;
                      c.scheduleTrial({
                        'expectedVersion': version,
                        'plan': plan.text,
                        'seats': seats.text,
                        'trialStart': trialStart.text,
                        'trialEnd': trialEnd.text,
                      });
                    }
                  : null,
              child: const Text('Schedule reviewed synthetic trial'),
            ),
          ),
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                onPressed: c.online && !c.busy ? c.restoreBilling : null,
                child: const Text('Restore subscription request'),
              ),
              TextButton(
                onPressed: c.online && !c.busy && c.billingPending != null
                    ? c.retryBilling
                    : null,
                child: const Text('Retry original subscription request'),
              ),
            ],
          ),
          if (c.billingPending != null)
            SelectableText(
              'Saved subscription request ${c.billingPending!['commandId']} · ${c.billingPending!['payload']}',
            ),
          if (c.scheduledRevision != null)
            SelectableText(
              'Scheduled revision ${c.scheduledRevision} · activation requires the trusted worker and current privileged authority.',
            ),
          const Divider(height: 40),
          Text(
            'Trusted metering',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'Plan and trial changes require separately authorized synthetic scope. Only the trusted worker can reserve and settle model or delivery usage.',
          ),
          DropdownButton<String>(
            value: metric,
            items: const [
              DropdownMenuItem(value: 'ai.tokens', child: Text('AI tokens')),
              DropdownMenuItem(
                value: 'webhook.deliveries',
                child: Text('Webhook deliveries'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => metric = value);
              c.clear();
            },
          ),
          TextField(
            controller: period,
            decoration: const InputDecoration(
              labelText: 'Authoritative period start UTC',
            ),
            onChanged: (_) => c.clear(),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed:
                  c.online &&
                      !c.busy &&
                      c.scope != null &&
                      widget.capabilities.contains('billing.read')
                  ? () => c.readUsage(metric, period.text)
                  : null,
              child: const Text('Read trusted allowance'),
            ),
          ),
          if (c.usage != null)
            Text(
              c.usage!['state'] == 'available'
                  ? 'Limit ${c.usage!['limit']} · settled ${c.usage!['settled']} · reserved ${c.usage!['reserved']} · remaining ${c.usage!['remaining']}'
                  : 'Allowance unavailable: no authoritative period reservation exists.',
            ),
          const Divider(height: 40),
          Text(
            'Operator health',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'Operator authority is separate from tenant roles and requires MFA. Missing probes are unknown.',
          ),
          TextField(
            controller: grant,
            decoration: const InputDecoration(
              labelText: 'Current selected-tenant access grant ID (optional)',
            ),
            onChanged: (_) => c.clear(),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: c.online && !c.busy
                  ? () => c.readHealth(grant: grant.text)
                  : null,
              child: const Text('Read authorized operator health'),
            ),
          ),
          if (c.health != null) ...[
            Text('Generated ${c.health!['generatedAt']}'),
            for (final probe in c.health!['probes'] as List)
              Text(
                '${(probe as Map)['code']} · ${probe['state']} · ${probe['exactValue'] ?? 'unknown'}',
              ),
          ],
          const Divider(height: 40),
          Text('Integrations', style: Theme.of(context).textTheme.titleLarge),
          const Text(
            'Use the Integrations workspace to register scoped subscriptions, rotate vault references and review delivery outcomes. Worker deployment and a reviewed test destination are required before delivery.',
          ),
        ],
      );
    },
  );
}

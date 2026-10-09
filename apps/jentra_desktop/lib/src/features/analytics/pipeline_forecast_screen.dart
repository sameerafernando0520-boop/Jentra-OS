import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart'
    show DomainError, ConnectivityState;
import 'package:jentra_platform/analytics_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import '../report_export/report_export_screen.dart';

final pipelineForecastRepositoryProvider =
    Provider<PipelineForecastRepository?>((ref) => null);
final pipelineForecastControllerProvider =
    Provider.autoDispose<PipelineForecastController?>((ref) {
      ref.watch(authSessionRevisionProvider);
      final actor = ref.watch(authenticatedActorProvider);
      final active = ref.watch(activeTenantContextProvider),
          caps = ref.watch(businessCapabilitiesProvider),
          repo = ref.watch(pipelineForecastRepositoryProvider);
      if (actor.isLoading ||
          actor.hasError ||
          actor.value == null ||
          actor.value != active?.actorId ||
          caps.isLoading ||
          caps.hasError ||
          active == null ||
          active.legalEntityId == null ||
          repo == null ||
          !(caps.value?.contains('analytics.view') ?? false) ||
          !{
            'crm.opportunities.view',
            'crm.opportunities.manage',
          }.any((p) => caps.value?.contains(p) ?? false)) {
        return null;
      }
      final c = PipelineForecastController(
        scope: ProcessMetricScope(
          tenantId: active.tenantId,
          legalEntityId: active.legalEntityId!,
          branchId: active.branchId,
        ),
        actor: active.actorId,
        repository: repo,
        store: Wave5CommandStore(
          ref.watch(encryptedDraftRepositoryProvider),
          repo.authorizeRecovery,
          namespace: 'pipeline',
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

final class PipelineForecastController extends ChangeNotifier {
  PipelineForecastController({
    required this.scope,
    required this.actor,
    required this.repository,
    this.store,
    this.online = true,
  });
  final ProcessMetricScope scope;
  final String actor;
  final PipelineForecastRepository repository;
  final Wave5CommandStore? store;
  bool online, busy = false, disposed = false;
  int epoch = 0;
  String? error;
  FrozenPipelineForecast? forecast;
  Map<String, Object?>? pending;
  void clear() {
    epoch++;
    forecast = null;
    error = null;
    busy = false;
    if (!disposed) notifyListeners();
  }

  void setOnline(bool value) {
    if (online == value) return;
    online = value;
    pending = null;
    clear();
  }

  bool current(int ticket) => !disposed && online && epoch == ticket;
  Future<void> restore() async {
    clear();
    if (!online || store == null) return;
    final ticket = epoch;
    try {
      final value = await store!.restore(scope, actor);
      if (current(ticket)) {
        pending = value;
        notifyListeners();
      }
    } catch (_) {
      if (current(ticket)) {
        error = 'Saved forecast request is unavailable under current access.';
        notifyListeners();
      }
    }
  }

  Future<void> freeze(String start, String end, {bool retry = false}) async {
    if (busy || !online) return;
    if (!retry && pending != null) {
      error = 'Resolve the saved request before starting another forecast.';
      notifyListeners();
      return;
    }
    final envelope = retry
        ? pending
        : {
            'commandId': const Uuid().v4(),
            'idempotencyKey': const Uuid().v4(),
            'clientTimestamp': DateTime.now().toUtc().toIso8601String(),
            'action': 'freeze',
            'payload': {'horizonStart': start, 'horizonEnd': end},
          };
    if (envelope == null) return;
    final parameters = envelope['payload'] as Map<String, Object?>;
    calculatePipelineForecast(
      scope,
      [],
      horizonStart: parameters['horizonStart'] as String,
      horizonEnd: parameters['horizonEnd'] as String,
      complete: true,
    );
    clear();
    final ticket = epoch;
    busy = true;
    pending = envelope;
    notifyListeners();
    try {
      await repository.authorizeRecovery(scope, actor);
      if (!current(ticket)) return;
      if (!retry && store != null) {
        final saved = await store!.restore(scope, actor);
        if (!current(ticket)) return;
        if (saved != null) {
          pending = saved;
          error = 'A saved original request must be reviewed and retried before creating another forecast.';
          return;
        }
      }
      await store?.save(scope, actor, envelope);
      if (!current(ticket)) return;
      final p = envelope['payload'] as Map<String, Object?>;
      final id = await repository.freeze(
        scope,
        commandId: envelope['commandId'] as String,
        idempotencyKey: envelope['idempotencyKey'] as String,
        clientTimestamp: envelope['clientTimestamp'] as String,
        horizonStart: p['horizonStart'] as String,
        horizonEnd: p['horizonEnd'] as String,
      );
      final value = await repository.get(scope, id);
      await repository.authorize(scope);
      if (!current(ticket)) return;
      await store?.remove(scope, actor);
      if (!current(ticket)) return;
      pending = null;
      forecast = value;
    } catch (e) {
      if (current(ticket)) {
        forecast = null;
        error = e is DomainError ? e.message : 'The forecast could not be confirmed. Its original request is saved for review and retry.';
      }
    } finally {
      if (current(ticket)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> open(String id) async {
    if (busy || !online) return;
    clear();
    final ticket = epoch;
    busy = true;
    notifyListeners();
    try {
      await repository.authorize(scope);
      final value = await repository.get(scope, id);
      await repository.authorize(scope);
      if (current(ticket)) forecast = value;
    } catch (e) {
      if (current(ticket)) {
        error = e is DomainError
            ? e.message
            : 'Forecast evidence is unavailable under current source access.';
      }
    } finally {
      if (current(ticket)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    disposed = true;
    epoch++;
    forecast = null;
    pending = null;
    super.dispose();
  }
}

class PipelineForecastScreen extends ConsumerWidget {
  const PipelineForecastScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(pipelineForecastControllerProvider);
    if (c == null) {
      return const Center(
        child: Text('Select an entity with analytics and CRM source access.'),
      );
    }
    return PipelineForecastWorkspace(key: ValueKey(c), controller: c);
  }
}

class PipelineForecastWorkspace extends StatefulWidget {
  const PipelineForecastWorkspace({super.key, required this.controller});
  final PipelineForecastController controller;
  @override
  State<PipelineForecastWorkspace> createState() =>
      _PipelineForecastWorkspaceState();
}

class _PipelineForecastWorkspaceState extends State<PipelineForecastWorkspace> {
  final start = TextEditingController(),
      end = TextEditingController(),
      identity = TextEditingController();
  int page = 0;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc();
    start.text = DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).toIso8601String().substring(0, 10);
    end.text = DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 30)).toIso8601String().substring(0, 10);
  }

  @override
  void dispose() {
    start.dispose();
    end.dispose();
    identity.dispose();
    super.dispose();
  }

  Future<void> freeze() async {
    try {
      await widget.controller.freeze(start.text, end.text);
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Use a valid dated horizon of at most 366 days.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller, f = c.forecast;
      final rows = f?.observations ?? const <ForecastOpportunity>[];
      final first = (page * 50).clamp(0, rows.length),
          last = (first + 50).clamp(0, rows.length);
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Pipeline forecasts',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const Text(
            'Freeze current open opportunities with their exact revisions, probabilities and close dates. Each currency has its own total.',
          ),
          TextField(
            controller: start,
            decoration: const InputDecoration(labelText: 'Horizon start date'),
            onChanged: (_) => c.clear(),
          ),
          TextField(
            controller: end,
            decoration: const InputDecoration(
              labelText: 'Horizon end date (excluded)',
            ),
            onChanged: (_) => c.clear(),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                onPressed: c.online && !c.busy && c.pending == null
                    ? freeze
                    : null,
                child: const Text('Freeze current forecast'),
              ),
              OutlinedButton(
                onPressed: c.online && !c.busy ? c.restore : null,
                child: const Text('Restore saved request'),
              ),
              OutlinedButton(
                onPressed: c.online && !c.busy && c.pending != null
                    ? () => c.freeze(start.text, end.text, retry: true)
                    : null,
                child: const Text('Retry original request'),
              ),
            ],
          ),
          if (c.pending != null)
            SelectableText(
              'Saved request ${c.pending!['commandId']} · review before retry',
            ),
          TextField(
            controller: identity,
            decoration: const InputDecoration(labelText: 'Frozen forecast ID'),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: c.online && !c.busy
                  ? () => c.open(identity.text)
                  : null,
              child: const Text('Open with current source access'),
            ),
          ),
          if (!c.online) const Text('Offline · forecast evidence cleared.'),
          if (c.busy) const LinearProgressIndicator(),
          if (c.error != null) Text(c.error!),
          if (f != null) ...[
            SelectableText('Frozen forecast ${f.id}'),
            ReportExportLink(
              sourceType: 'w5_pipeline',
              sourceId: f.id,
              section: 'currencies',
              enabled: c.online && !c.busy,
              label: 'Create governed forecast export',
            ),
            Text(
              'Observed ${f.observedAt.toIso8601String()} · ${f.horizonStart} to ${f.horizonEnd} (excluded)',
            ),
            Text(
              'Complete current population: ${rows.length} · weighting version 1',
            ),
            for (final g in f.currencies)
              Text(
                '${g.currency} · ${g.population} opportunities · amount ${g.amount} · weighted ${g.weightedAmount}',
              ),
            if (f.currencies.isEmpty)
              const Text(
                'The complete horizon contains no eligible opportunities.',
              ),
            SelectableText('Source digest ${f.sourceHash}'),
            Text(
              'Opportunity revisions ${rows.isEmpty ? 0 : first + 1}–$last of ${rows.length}',
            ),
            for (final o in rows.sublist(first, last))
              Text(
                '${o.id} · revision ${o.version} · ${o.currency} ${o.amount.toDecimalString()} × ${o.probability.toDecimalString()}%',
              ),
            Wrap(
              children: [
                TextButton(
                  onPressed: page > 0 ? () => setState(() => page--) : null,
                  child: const Text('Previous 50'),
                ),
                TextButton(
                  onPressed: last < rows.length
                      ? () => setState(() => page++)
                      : null,
                  child: const Text('Next 50'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            'Historical metrics and realized gross-invoice accuracy use their separate providers in Historical pipeline. This frozen publication retains its original current-observation basis.',
          ),
        ],
      );
    },
  );
}

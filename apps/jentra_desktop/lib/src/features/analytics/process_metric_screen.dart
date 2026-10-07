import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/analytics_platform.dart';

import '../../app_providers.dart';
import 'process_metric_controller.dart';

final processMetricRepositoryProvider = Provider<ProcessMetricRepository?>(
  (ref) => null,
);
final processMetricControllerProvider =
    Provider.autoDispose<ProcessMetricController?>((ref) {
      ref.watch(authSessionRevisionProvider);
      final actor = ref.watch(authenticatedActorProvider);
      final active = ref.watch(activeTenantContextProvider);
      final repository = ref.watch(processMetricRepositoryProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      if (actor.isLoading ||
          actor.hasError ||
          actor.value == null ||
          actor.value != active?.actorId ||
          active == null ||
          active.legalEntityId == null ||
          repository == null ||
          caps.isLoading ||
          caps.hasError ||
          !{
            'analytics.view',
            'workflow.process.view',
          }.every((p) => caps.value?.contains(p) ?? false) ||
          !{
            'crm.opportunities.view',
            'crm.opportunities.manage',
          }.any((p) => caps.value?.contains(p) ?? false)) {
        return null;
      }
      final controller = ProcessMetricController(
        scope: ProcessMetricScope(
          tenantId: active.tenantId,
          legalEntityId: active.legalEntityId!,
          branchId: active.branchId,
        ),
        actorId: active.actorId,
        repository: repository,
        filters: ProcessFilterStore(
          ref.watch(encryptedDraftRepositoryProvider),
          repository.authorizeRecovery,
        ),
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
      );
      ref.listen(
        connectivityStateProvider,
        (_, v) => controller.setOnline(v.value == ConnectivityState.online),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

class ProcessMetricScreen extends ConsumerWidget {
  const ProcessMetricScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(businessCapabilitiesProvider);
    if (caps.isLoading) return const Center(child: CircularProgressIndicator());
    final controller = ref.watch(processMetricControllerProvider);
    if (controller == null) {
      return const Center(
        child: Text(
          'Select a legal entity with analytics, workflow and CRM source access. The process provider must be configured.',
        ),
      );
    }
    return ProcessMetricWorkspace(
      key: ValueKey(controller),
      controller: controller,
    );
  }
}

class ProcessMetricWorkspace extends StatefulWidget {
  const ProcessMetricWorkspace({required this.controller, super.key});
  final ProcessMetricController controller;
  @override
  State<ProcessMetricWorkspace> createState() => _ProcessMetricWorkspaceState();
}

class _ProcessMetricWorkspaceState extends State<ProcessMetricWorkspace> {
  final fields = List.generate(4, (_) => TextEditingController());
  int page = 0;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc();
    final end = DateTime.utc(now.year, now.month, now.day);
    fields[0].text = end.subtract(const Duration(days: 30)).toIso8601String();
    fields[1].text = end.toIso8601String();
    fields[2].text = now.toIso8601String();
    fields[3].text = now.toIso8601String();
    final existing = widget.controller.filter;
    if (existing != null) {
      final values = existing.toJson().values.toList();
      for (var i = 0; i < 4; i++) {
        fields[i].text = values[i] as String;
      }
    }
  }

  @override
  void dispose() {
    for (final field in fields) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _restore() async {
    await widget.controller.restoreFilter();
    if (!mounted) return;
    final f = widget.controller.filter;
    if (f != null) {
      final values = f.toJson().values.toList();
      for (var i = 0; i < 4; i++) {
        fields[i].text = values[i] as String;
      }
    }
  }

  void _read() {
    try {
      page = 0;
      widget.controller.read(
        ProcessMetricFilter(
          windowStart: fields[0].text,
          windowEnd: fields[1].text,
          asOf: fields[2].text,
          recordedThrough: fields[3].text,
        ),
      );
    } on FormatException {
      widget.controller.clear();
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Use valid UTC instants and ordered cutoffs.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller, s = c.summary;
      final ids = s?.source.sourceEventIds ?? const <String>[];
      final start = (page * 50).clamp(0, ids.length),
          end = (start + 50).clamp(0, ids.length);
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Process analytics',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const Text(
            'Reported CRM transition durations. Stage dwell, throughput, productive work and rework are unavailable without certified timing evidence.',
          ),
          const SizedBox(height: 12),
          SelectableText(
            'Entity ${c.scope.legalEntityId} · Branch ${c.scope.branchId ?? 'all authorized'}',
          ),
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: TextField(
                controller: fields[i],
                decoration: InputDecoration(
                  labelText: [
                    'Cohort start UTC',
                    'Cohort end UTC (excluded)',
                    'Business cutoff UTC',
                    'Recorded cutoff UTC',
                  ][i],
                ),
                onChanged: (_) {
                  c.clear();
                },
              ),
            ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                onPressed: c.busy || !c.online ? null : _read,
                child: const Text('Calculate complete snapshot'),
              ),
              OutlinedButton(
                onPressed: c.busy || !c.online || c.filter == null
                    ? null
                    : c.saveFilter,
                child: const Text('Save filters'),
              ),
              OutlinedButton(
                onPressed: c.busy || !c.online ? null : _restore,
                child: const Text('Restore filters'),
              ),
            ],
          ),
          if (!c.online)
            const Text(
              'Offline · protected evidence cleared. Reconnect to authorize a read.',
            ),
          if (c.busy) const LinearProgressIndicator(),
          if (c.error != null) Text(c.error!),
          if (s != null) ...[
            const SizedBox(height: 20),
            Text(
              'Event duration · version 1',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              'Source ${s.source.sourceCount} · completed ${s.completedCount} · open ${s.openCount} · invalid ${s.invalidCount} · excluded ${s.excludedCount}',
            ),
            Text('Completeness: ${s.completeness} · nearest-rank percentiles'),
            Text('Business cutoff: ${s.source.asOf.toIso8601String()}'),
            Text(
              'Recorded cutoff: ${s.source.recordedThrough.toIso8601String()}',
            ),
            Text(
              'P50: ${s.p50Microseconds?.toString() ?? 'unavailable'} microseconds',
            ),
            Text(
              'P90: ${s.p90Microseconds?.toString() ?? 'unavailable'} microseconds',
            ),
            if (s.emptyDurationReason != null) Text(s.emptyDurationReason!),
            SelectableText(
              'Frozen source digest: ${s.source.sourceManifestHash}',
            ),
            const SizedBox(height: 16),
            Text(
              'Source events ${ids.isEmpty ? 0 : start + 1}–$end of ${ids.length}',
            ),
            for (final id in ids.sublist(start, end))
              TextButton(
                onPressed: () => c.openEvent(id),
                child: Text('Inspect event $id'),
              ),
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: page > 0 ? () => setState(() => page--) : null,
                  child: const Text('Previous 50'),
                ),
                TextButton(
                  onPressed: end < ids.length
                      ? () => setState(() => page++)
                      : null,
                  child: const Text('Next 50'),
                ),
              ],
            ),
            if (c.detail != null)
              SelectableText(
                'Authorized CRM source: ${c.detail!['documentId']}',
              ),
          ],
        ],
      );
    },
  );
}

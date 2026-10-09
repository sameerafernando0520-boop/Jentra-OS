import 'package:flutter/material.dart';

import 'analytics_rows.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart' show ConnectivityState;
import 'package:jentra_platform/analytics_platform.dart';

import '../../app_providers.dart';
import 'pipeline_forecast_screen.dart';

final historicalPipelineGatewayProvider = Provider<HistoricalPipelineGateway?>(
  (ref) => null,
);
final historicalMetricsProvider = FutureProvider.autoDispose
    .family<HistoricalPipelineMetrics, (String, String)>((ref, dates) async {
      ref.watch(authSessionRevisionProvider);
      final actor = await ref.watch(authenticatedActorProvider.future);
      final scope = ref.watch(activeTenantContextProvider);
      final caps = await ref.watch(businessCapabilitiesProvider.future);
      final online = await ref.watch(connectivityStateProvider.future);
      final gateway = ref.watch(historicalPipelineGatewayProvider),
          authority = ref.watch(pipelineForecastRepositoryProvider);
      if (actor == null ||
          actor != scope?.actorId ||
          scope?.legalEntityId == null ||
          !caps.contains('analytics.view') ||
          !{
            'crm.opportunities.view',
            'crm.opportunities.manage',
          }.any(caps.contains) ||
          online != ConnectivityState.online ||
          gateway == null ||
          authority == null) {
        throw StateError(
          'Historical analytics requires current online source access.',
        );
      }
      final s = ProcessMetricScope(
        tenantId: scope!.tenantId,
        legalEntityId: scope.legalEntityId!,
        branchId: scope.branchId,
      );
      await authority.authorizeRecovery(s, actor);
      final value = await gateway.read(s, dates.$1, dates.$2);
      await authority.authorizeRecovery(s, actor);
      return value;
    });
final realizedAccuracyProvider = FutureProvider.autoDispose
    .family<Map<String, (BigInt, ExactRatio?)>, (String, String)>((
      ref,
      selection,
    ) async {
      ref.watch(authSessionRevisionProvider);
      final actor = await ref.watch(authenticatedActorProvider.future),
          scope = ref.watch(activeTenantContextProvider),
          caps = await ref.watch(businessCapabilitiesProvider.future),
          online = await ref.watch(connectivityStateProvider.future);
      final authority = ref.watch(pipelineForecastRepositoryProvider),
          gateway = ref.watch(historicalPipelineGatewayProvider);
      if (actor == null ||
          actor != scope?.actorId ||
          scope?.legalEntityId == null ||
          authority == null ||
          gateway == null ||
          online != ConnectivityState.online ||
          !{
            'analytics.view',
            'finance.receivables.view',
            'sales.returns.view',
          }.every(caps.contains)) {
        throw StateError('Current realized source authority required.');
      }
      final s = ProcessMetricScope(
        tenantId: scope!.tenantId,
        legalEntityId: scope.legalEntityId!,
        branchId: scope.branchId,
      );
      await authority.authorizeRecovery(s, actor);
      final frozen = await authority.get(s, selection.$1);
      final result = await gateway.accuracy(frozen, selection.$2);
      await authority.authorizeRecovery(s, actor);
      return result;
    });

class HistoricalPipelineScreen extends ConsumerStatefulWidget {
  const HistoricalPipelineScreen({super.key});
  @override
  ConsumerState<HistoricalPipelineScreen> createState() =>
      _HistoricalPipelineScreenState();
}

class _HistoricalPipelineScreenState
    extends ConsumerState<HistoricalPipelineScreen> {
  final cutoff = TextEditingController();
  final forecastId = TextEditingController();
  (String, String)? selection;
  (String, String)? realizedSelection;
  @override
  void dispose() {
    cutoff.dispose();
    forecastId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = selection == null
        ? null
        : ref.watch(historicalMetricsProvider(selection!));
    final accuracy = realizedSelection == null
        ? null
        : ref.watch(realizedAccuracyProvider(realizedSelection!));
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          controller: forecastId,
          decoration: const InputDecoration(
            labelText: 'Frozen forecast ID for realized accuracy',
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () {
              try {
                ProcessMetricScope(
                  tenantId: forecastId.text,
                  legalEntityId: forecastId.text,
                );
                parseProcessMetricUtc(cutoff.text);
                setState(
                  () => realizedSelection = (forecastId.text, cutoff.text),
                );
              } catch (_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Enter the frozen forecast ID and UTC cutoff.',
                    ),
                  ),
                );
              }
            },
            child: const Text('Compare realized gross invoice result'),
          ),
        ),
        if (accuracy != null)
          accuracy.when(
            skipLoadingOnReload: false,
            skipLoadingOnRefresh: false,
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const Text(
              'Realized horizon, mapping or source authority is unavailable.',
            ),
            data: (rows) => Column(
              children: [
                for (final e in rows.entries)
                  Text(
                    '${e.key}: signed error ${exactHistoricalAmount(e.value.$1)} · absolute relative error ${e.value.$2?.exactValue ?? 'undefined: realized zero'}',
                  ),
              ],
            ),
          ),
        Text(
          'Historical pipeline',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const Text(
          'Immutable CRM revisions at an explicit UTC cutoff. Win conversion is won / decided; won opportunity value is separate from invoiced revenue.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: cutoff,
          decoration: const InputDecoration(
            labelText: 'UTC cutoff',
            hintText: '2026-10-08T00:00:00Z',
          ),
          onSubmitted: (_) => _read(),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _read,
            child: const Text('Read history'),
          ),
        ),
        if (value != null)
          value.when(
            skipLoadingOnRefresh: false,
            skipLoadingOnReload: false,
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const Text(
              'Historical evidence is unavailable under current access or provider readiness.',
            ),
            data: (m) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${m.population} opportunities · ${m.won} won / ${m.decided} decided',
                ),
                Text(
                  'Win conversion: ${m.conversion?.exactValue ?? 'undefined: no decided opportunities'}',
                ),
                for (final e in m.wonUnitsByCurrency.entries)
                  Text(
                    '${e.key} won opportunity value: ${exactHistoricalAmount(e.value)}',
                  ),
                AnalyticsRows<MapEntry<String, BigInt>>(
                  key: ValueKey(m),
                  rows: m.stageAgeMicroseconds.entries.toList(),
                  row: (e) =>
                      Text('Stage age ${e.key}: ${e.value} microseconds'),
                ),
                for (final e in m.wonValuePerMeanCycleDay.entries)
                  Text(
                    '${e.key} closed-cohort won value / mean cycle day: ${e.value?.exactValue ?? 'undefined: zero cycle duration'}',
                  ),
                for (final reason in m.unavailableReasons) Text(reason),
              ],
            ),
          ),
      ],
    );
  }

  void _read() {
    try {
      parseProcessMetricUtc(cutoff.text);
      setState(() => selection = (cutoff.text, cutoff.text));
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid UTC cutoff.')),
      );
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';

import '../../app_providers.dart';
import 'operational_controller.dart';
import 'operational_link.dart';
import 'operational_metric_card.dart';
import 'operational_screen.dart';

final operationalDashboardProvider =
    FutureProvider.autoDispose<Map<String, Object?>>((ref) async {
      final scope = ref.watch(activeTenantContextProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      final gateway = ref.watch(operationalGatewayProvider);
      final connectivity = ref.watch(connectivityStateProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          caps.isLoading ||
          caps.hasError ||
          connectivity.value != ConnectivityState.online) {
        return {};
      }
      return gateway.dashboard(scope);
    });

class OperationalDashboard extends ConsumerWidget {
  const OperationalDashboard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(activeTenantContextProvider);
    final state = ref.watch(operationalDashboardProvider);
    final online =
        ref.watch(connectivityStateProvider).value == ConnectivityState.online;
    final canLoad = online && scope != null && scope.hasOperationalScope;
    final snapshot = canLoad && !state.isLoading && !state.hasError
        ? state.asData?.value
        : null;
    final verified = DateTime.tryParse('${snapshot?['generated_at']}');
    final localizations = MaterialLocalizations.of(context);
    final theme = Theme.of(context);
    return ListView(
      padding: EdgeInsets.all(
        MediaQuery.sizeOf(context).width < 700
            ? JentraSpacing.x4
            : JentraSpacing.x6,
      ),
      children: [
        JentraPanel(
          child: OverflowBar(
            alignment: MainAxisAlignment.spaceBetween,
            overflowAlignment: OverflowBarAlignment.start,
            spacing: JentraSpacing.x4,
            overflowSpacing: JentraSpacing.x4,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Command centre',
                      style: theme.textTheme.headlineMedium,
                    ),
                  ),
                  const SizedBox(height: JentraSpacing.x2),
                  Text(
                    'Business metrics and action queues for your selected company and branch.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: context.jentraColors.textSecondary,
                    ),
                  ),
                  if (verified != null) ...[
                    const SizedBox(height: JentraSpacing.x2),
                    Tooltip(
                      message: '${snapshot?['generated_at']}',
                      child: Text(
                        'Verified ${localizations.formatShortDate(verified.toLocal())}'
                        ' · ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(verified.toLocal()))}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.jentraColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              OutlinedButton.icon(
                onPressed: canLoad && !state.isLoading
                    ? () => ref.invalidate(operationalDashboardProvider)
                    : null,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh queues'),
              ),
            ],
          ),
        ),
        const SizedBox(height: JentraSpacing.x6),
        if (!online)
          const JentraPanel(
            child: Text(
              'You’re offline. Reconnect to view current metrics and queues.',
            ),
          )
        else if (!canLoad)
          const JentraPanel(
            child: Text(
              'Select a company and branch to view metrics and queues.',
            ),
          )
        else
          state.when(
            skipLoadingOnRefresh: false,
            skipLoadingOnReload: false,
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const JentraPanel(
              child: Text(
                'Could not verify the current metrics and queues. Refresh queues to try again.',
              ),
            ),
            data: (data) {
              final cards =
                  (data['cards'] as List?)?.whereType<Map>().toList() ?? [];
              final metrics =
                  (data['metrics'] as List?)?.whereType<Map>().toList() ?? [];
              if (cards.isEmpty && metrics.isEmpty) {
                return const JentraPanel(
                  child: Text(
                    'No metrics or action queues are available with your current access.',
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (metrics.isNotEmpty) ...[
                    _sectionTitle(context, 'Business snapshot'),
                    _OverviewGrid(
                      cards: [
                        for (final metric in metrics)
                          OperationalMetricCard(
                            key: ValueKey(metric['kind']),
                            metric: metric,
                          ),
                      ],
                    ),
                  ],
                  if (cards.isNotEmpty) ...[
                    if (metrics.isNotEmpty)
                      const SizedBox(height: JentraSpacing.x8),
                    _sectionTitle(context, 'Action queues'),
                    _OverviewGrid(
                      cards: [
                        for (final card in cards)
                          OperationalOverviewCard(
                            title: operationalLabel(card['kind'] as String),
                            icon: Icons.inbox_outlined,
                            accent: JentraColors.blue600,
                            body: Text(
                              '${card['count']} current actionable records',
                            ),
                            action: OperationalLink(
                              scope: scope,
                              kind: card['kind'] as String,
                              label: 'Open current documents',
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String label) => Padding(
    padding: const EdgeInsets.only(bottom: JentraSpacing.x3),
    child: Semantics(
      header: true,
      child: Text(label, style: Theme.of(context).textTheme.titleLarge),
    ),
  );
}

class _OverviewGrid extends StatelessWidget {
  const _OverviewGrid({required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final width = constraints.maxWidth;
      final maxColumns = width >= 1008 * scale
          ? 3
          : width >= 650 * scale
          ? 2
          : 1;
      final rows = (cards.length / maxColumns).ceil();
      var offset = 0;
      return Column(
        children: [
          for (var row = 0; row < rows; row++) ...[
            if (row > 0) const SizedBox(height: JentraSpacing.x4),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (
                    var column = 0,
                        count = ((cards.length - offset) / (rows - row)).ceil();
                    column < count;
                    column++
                  ) ...[
                    if (column > 0) const SizedBox(width: JentraSpacing.x4),
                    Expanded(child: cards[offset++]),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
}

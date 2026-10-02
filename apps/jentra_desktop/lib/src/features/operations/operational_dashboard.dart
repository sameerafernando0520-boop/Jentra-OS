import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';

import '../../app_providers.dart';
import 'operational_controller.dart';
import 'operational_link.dart';
import 'operational_screen.dart';
import 'operational_metric_card.dart';

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
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Command centre',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        const Text(
          'Dated business metrics and current queues for your selected business scope.',
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: online
                ? () => ref.invalidate(operationalDashboardProvider)
                : null,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh queues'),
          ),
        ),
        if (!online)
          const Text('Offline. Server dashboard evidence has been cleared.'),
        if (scope == null || !scope.hasOperationalScope)
          const Text('Select a permitted legal entity and branch.'),
        if (online && scope != null && scope.hasOperationalScope)
          state.when(
            skipLoadingOnRefresh: false,
            skipLoadingOnReload: false,
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const Text(
              'The current queues could not be verified. Refresh access and try again.',
            ),
            data: (data) {
              final cards = (data['cards'] as List?) ?? [];
              final metrics = (data['metrics'] as List?) ?? [];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (data['generated_at'] != null)
                    Text('Verified ${data['generated_at']}'),
                  if (cards.isEmpty && metrics.isEmpty)
                    const Text(
                      'No operational queues are available with your current access.',
                    ),
                  for (final metric in metrics)
                    OperationalMetricCard(metric: metric as Map),
                  for (final card in cards)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              operationalLabel(card['kind'] as String),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text('${card['count']} current actionable records'),
                            OperationalLink(
                              scope: scope,
                              kind: card['kind'] as String,
                              label: 'Open current documents',
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

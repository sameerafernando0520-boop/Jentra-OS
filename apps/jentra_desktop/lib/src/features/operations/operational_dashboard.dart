import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';

import '../../app_providers.dart';
import '../../shell/navigation.dart';
import '../../shell/workspace_context_dialog.dart';
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
    final business = ref.watch(businessScopeProvider);
    final access = ref.watch(businessCapabilitiesProvider);
    final state = ref.watch(operationalDashboardProvider);
    final online =
        ref.watch(connectivityStateProvider).value == ConnectivityState.online;
    final canRead =
        online &&
        scope != null &&
        scope.hasOperationalScope &&
        !access.isLoading &&
        !access.hasError;
    void refresh() {
      ref.invalidate(businessCapabilitiesProvider);
      ref.invalidate(operationalDashboardProvider);
    }

    final destinations = access.isLoading || access.hasError
        ? const <JentraDestination>[]
        : visibleJentraDestinations(access.value)
              .where(
                (item) => const {
                  '/crm',
                  '/sales',
                  '/procurement',
                  '/receivables',
                  '/inventory',
                  '/finance',
                  '/people',
                  '/assets',
                  '/projects',
                  '/service',
                  '/governance/audit',
                  '/analytics',
                  '/setup',
                }.contains(item.path),
              )
              .toList();
    return ListView(
      padding: EdgeInsets.all(
        MediaQuery.sizeOf(context).width < 700
            ? JentraSpacing.x4
            : JentraSpacing.x6,
      ),
      children: [
        JentraPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              JentraSectionHeader(
                title: 'Command centre',
                description: business.isLoading
                    ? 'Loading your workspace…'
                    : business.value?.tenant.name ?? 'Your workspace',
                trailing: IconButton(
                  tooltip: 'Refresh workspace',
                  onPressed: online ? refresh : null,
                  icon: const Icon(Icons.refresh),
                ),
              ),
              const SizedBox(height: JentraSpacing.x4),
              Text(
                'Your business, working as one.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: JentraSpacing.x2),
              const Text(
                'Review current work, open your business workspaces and follow decisions through to completion.',
              ),
              const SizedBox(height: JentraSpacing.x4),
              Wrap(
                spacing: JentraSpacing.x3,
                runSpacing: JentraSpacing.x2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  JentraStatusBadge(
                    label: online ? 'Connected workspace' : 'Offline',
                    tone: online
                        ? JentraStatusTone.success
                        : JentraStatusTone.warning,
                  ),
                  if (!business.isLoading &&
                      !business.hasError &&
                      business.value?.legalEntity != null)
                    Text(
                      '${business.value!.legalEntity!.name} · ${business.value!.branch?.name ?? 'Choose a branch'}',
                    ),
                  TextButton.icon(
                    onPressed: () => showWorkspaceContext(context),
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text('Switch workspace'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: JentraSpacing.x6),
        if (destinations.isNotEmpty) ...[
          const JentraSectionHeader(
            title: 'Business workspaces',
            description: 'Open the work available to your role.',
          ),
          const SizedBox(height: JentraSpacing.x4),
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(1);
              final columns = (constraints.maxWidth / (245 * scale))
                  .floor()
                  .clamp(1, 4);
              final width =
                  (constraints.maxWidth - (columns - 1) * JentraSpacing.x3) /
                  columns;
              return Wrap(
                spacing: JentraSpacing.x3,
                runSpacing: JentraSpacing.x3,
                children: [
                  for (final destination in destinations)
                    SizedBox(
                      width: width,
                      child: OutlinedButton(
                        onPressed: () => context.go(destination.path),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.all(JentraSpacing.x4),
                          alignment: Alignment.centerLeft,
                        ),
                        child: Row(
                          children: [
                            Icon(destination.icon, size: 22),
                            const SizedBox(width: JentraSpacing.x3),
                            Expanded(child: Text(destination.label)),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: JentraSpacing.x6),
        ],
        const JentraSectionHeader(
          title: 'Current work and business position',
          description: 'Balances and queues reflect the selected scope and the dates shown on each view.',
        ),
        const SizedBox(height: JentraSpacing.x4),
        if (!online)
          const _DashboardNotice(
            icon: Icons.cloud_off_outlined,
            title: 'You are offline',
            description: 'Current balances and queues are hidden until you reconnect. You can open workspaces to continue with saved drafts.',
          ),
        if (online && (scope == null || !scope.hasOperationalScope))
          _DashboardNotice(
            icon: Icons.business_outlined,
            title: 'Choose your workspace',
            description: 'Select a business, legal entity and branch to see its current work.',
            action: TextButton(
              onPressed: () => showWorkspaceContext(context),
              child: const Text('Select workspace'),
            ),
          ),
        if (online && access.isLoading)
          const LinearProgressIndicator(
            semanticsLabel: 'Checking workspace access',
          ),
        if (online && access.hasError)
          _DashboardNotice(
            icon: Icons.lock_reset_outlined,
            title: 'Access could not be checked',
            description: 'Reconnect and refresh your access to this workspace.',
            action: TextButton(
              onPressed: refresh,
              child: const Text('Check access'),
            ),
          ),
        if (canRead)
          state.when(
            skipLoadingOnRefresh: false,
            skipLoadingOnReload: false,
            loading: () => const LinearProgressIndicator(
              semanticsLabel: 'Loading current business work',
            ),
            error: (_, _) => _DashboardNotice(
              icon: Icons.cloud_off_outlined,
              title: 'Current work could not be loaded',
              description: 'Check your connection and refresh. Your saved documents have not changed.',
              action: TextButton(
                onPressed: refresh,
                child: const Text('Try again'),
              ),
            ),
            data: (data) {
              final cards = (data['cards'] as List?) ?? [];
              final metrics = (data['metrics'] as List?) ?? [];
              final generated = DateTime.tryParse('${data['generated_at']}');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (generated != null) ...[
                    Text(
                      'Updated ${DateFormat('d MMM yyyy, HH:mm').format(generated.toUtc())} UTC',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: JentraSpacing.x3),
                  ],
                  if (cards.isEmpty && metrics.isEmpty)
                    const _DashboardNotice(
                      icon: Icons.task_alt,
                      title: 'Your workspace is ready',
                      description: 'There is no current work to show with your access. Open a business workspace to create or review documents.',
                    ),
                  if (cards.isNotEmpty) ...[
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final scale = MediaQuery.textScalerOf(context).scale(1);
                        final columns = (constraints.maxWidth / (290 * scale))
                            .floor()
                            .clamp(1, 3);
                        final width =
                            (constraints.maxWidth -
                                (columns - 1) * JentraSpacing.x4) /
                            columns;
                        return Wrap(
                          spacing: JentraSpacing.x4,
                          runSpacing: JentraSpacing.x4,
                          children: [
                            for (final card in cards)
                              SizedBox(
                                width: width,
                                child: JentraPanel(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        operationalLabel(
                                          card['kind'] as String,
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      const SizedBox(height: JentraSpacing.x3),
                                      Text(
                                        '${card['count']}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineLarge
                                            ?.copyWith(
                                              fontFamily:
                                                  JentraTypography.monoFamily,
                                            ),
                                      ),
                                      Text(
                                        card['count'] == '0'
                                            ? 'No records need action'
                                            : 'Records ready for review',
                                      ),
                                      const SizedBox(height: JentraSpacing.x3),
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
                    const SizedBox(height: JentraSpacing.x5),
                  ],
                  for (final metric in metrics)
                    OperationalMetricCard(metric: metric as Map),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _DashboardNotice extends StatelessWidget {
  const _DashboardNotice({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });
  final IconData icon;
  final String title, description;
  final Widget? action;

  @override
  Widget build(BuildContext context) => JentraPanel(
    child: JentraEmptyState(
      icon: icon,
      title: title,
      description: description,
      action: action,
    ),
  );
}

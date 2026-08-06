import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../company/application/company_state.dart';
import '../../../company/presentation/widgets/company_context_gate.dart';
import '../../application/ai_models.dart';
import '../../application/ai_assistant_state.dart';

final class AiInsightsScreen extends ConsumerStatefulWidget {
  const AiInsightsScreen({super.key});

  @override
  ConsumerState<AiInsightsScreen> createState() => _AiInsightsScreenState();
}

final class _AiInsightsScreenState extends ConsumerState<AiInsightsScreen> {
  String? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(selectedCompanyProvider);
    if (company == null) {
      return const CompanyRouteRedirect(location: '/company/select');
    }

    final insightsAsync = ref.watch(aiInsightsProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(aiInsightsProvider),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category filter chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('All Categories'),
                      selected: _selectedCategory == null,
                      onSelected: (_) => setState(() => _selectedCategory = null),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Cash Flow'),
                      selected: _selectedCategory == 'cash_flow',
                      onSelected: (_) => setState(() => _selectedCategory = 'cash_flow'),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Inventory'),
                      selected: _selectedCategory == 'inventory',
                      onSelected: (_) => setState(() => _selectedCategory = 'inventory'),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Sales'),
                      selected: _selectedCategory == 'sales',
                      onSelected: (_) => setState(() => _selectedCategory = 'sales'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              insightsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text('Error loading business insights: $err'),
                  ),
                ),
                data: (allInsights) {
                  final filtered = _selectedCategory == null
                      ? allInsights
                      : allInsights.where((i) => i.category == _selectedCategory).toList();

                  if (filtered.isEmpty) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
                              SizedBox(height: 12),
                              Text(
                                'No pending business insights',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 4),
                              Text('Your business is running smoothly!'),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return _InsightCard(
                        insight: item,
                        onDismiss: () => ref
                            .read(aiChatControllerProvider.notifier)
                            .dismissInsight(item.id),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.insight,
    required this.onDismiss,
  });

  final AiInsight insight;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    Color borderBg;
    Color badgeColor;
    IconData icon;

    switch (insight.severity) {
      case 'warning':
        borderBg = Colors.amber.shade50;
        badgeColor = Colors.amber.shade900;
        icon = Icons.warning_amber_rounded;
        break;
      case 'action_required':
        borderBg = Colors.red.shade50;
        badgeColor = Colors.red.shade900;
        icon = Icons.error_outline;
        break;
      case 'info':
      default:
        borderBg = Colors.blue.shade50;
        badgeColor = Colors.blue.shade900;
        icon = Icons.insights;
        break;
    }

    return Card(
      color: borderBg,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: badgeColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    insight.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Dismiss',
                  onPressed: onDismiss,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              insight.summary,
              style: const TextStyle(fontSize: 14),
            ),
            if (insight.actionLabel != null && insight.actionTarget != null) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: badgeColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => context.push(insight.actionTarget!),
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: Text(insight.actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'process_metric_screen.dart';
import 'pipeline_forecast_screen.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Column(
      children: [
        const TabBar(
          isScrollable: true,
          tabs: [
            Tab(text: 'Process'),
            Tab(text: 'Pipeline'),
            Tab(text: 'Finance readiness'),
          ],
        ),
        const Expanded(
          child: TabBarView(
            children: [
              ProcessMetricScreen(),
              PipelineForecastScreen(),
              _FinanceReadiness(),
            ],
          ),
        ),
      ],
    ),
  );
}

class _FinanceReadiness extends StatelessWidget {
  const _FinanceReadiness();
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        'Financial analytics',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const Text(
        'Financial ratios require a complete authoritative statement publication with matching scope, period, currency and formula version.',
      ),
      const ListTile(
        title: Text('Ratios unavailable'),
        subtitle: Text('A verified statement adapter has not been connected.'),
      ),
      const ListTile(
        title: Text('Cash scenarios unavailable'),
        subtitle: Text(
          'Verified dated bank controls and remaining receivable, payable, payroll and expense obligations are required.',
        ),
      ),
      const Text(
        'No financial balance or forecast has been calculated. Frozen exports require the governed report provider and current source access.',
      ),
    ],
  );
}

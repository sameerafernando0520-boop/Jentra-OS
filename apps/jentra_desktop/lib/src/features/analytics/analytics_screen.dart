import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';

import 'process_metric_screen.dart';
import 'pipeline_forecast_screen.dart';
import 'historical_pipeline_screen.dart';
import 'financial_analytics_screen.dart';
import 'integration_screen.dart';
import 'cash_scenario_screen.dart';
import 'governed_export_screen.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => DefaultTabController(
    key: ValueKey((
      ref.watch(activeTenantContextProvider),
      ref.watch(authSessionRevisionProvider),
      ref.watch(businessCapabilitiesProvider),
    )),
    length: 7,
    child: Column(
      children: [
        const TabBar(
          isScrollable: true,
          tabs: [
            Tab(text: 'Process'),
            Tab(text: 'Pipeline'),
            Tab(text: 'Historical pipeline'),
            Tab(text: 'Financial ratios'),
            Tab(text: 'Cash scenarios'),
            Tab(text: 'Integrations'),
            Tab(text: 'Governed exports'),
          ],
        ),
        const Expanded(
          child: TabBarView(
            children: [
              ProcessMetricScreen(),
              PipelineForecastScreen(),
              HistoricalPipelineScreen(),
              FinancialAnalyticsScreen(),
              CashScenarioScreen(),
              IntegrationScreen(),
              GovernedExportScreen(),
            ],
          ),
        ),
      ],
    ),
  );
}

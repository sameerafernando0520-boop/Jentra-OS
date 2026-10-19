import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_platform/jentra_receivables_platform.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:jentra_platform/analytics_platform.dart';
import 'package:jentra_platform/jentra_assurance_platform.dart';

import 'src/features/assurance/assurance_access_controller.dart';
import 'src/features/assurance/assurance_workspace_controller.dart';

import 'src/features/analytics/process_metric_screen.dart';
import 'src/features/analytics/pipeline_forecast_screen.dart';
import 'src/features/analytics/historical_pipeline_screen.dart';
import 'src/features/analytics/integration_screen.dart';
import 'src/features/analytics/cash_scenario_screen.dart';
import 'src/features/analytics/wave5_control_screen.dart';
import 'src/features/analytics/reviewed_model_section.dart';

import 'src/features/procurement/procurement_controller.dart';

import 'package:jentra_platform/landed_extension_platform.dart';
import 'package:jentra_platform/disposition.dart';
import 'package:jentra_platform/count_partitions.dart';

import 'src/features/landed_extension/landed_extension_controller.dart';
import 'src/features/disposition/disposition_controller.dart';
import 'src/features/inventory_transfer/inventory_transfer_controller.dart';
import 'src/features/stock_count/stock_count_controller.dart';
import 'src/features/reservations/reservation_controller.dart';
import 'src/features/negative_stock/negative_stock_policy_controller.dart';
import 'src/features/receipt_trace/receipt_trace_controller.dart';
import 'src/features/landed_value/landed_value_controller.dart';
import 'src/features/inventory_valuation/inventory_valuation_controller.dart';

import 'package:jentra_platform/jentra_finance_platform.dart';

import 'src/features/manual_journal/manual_journal_controller.dart';
import 'src/features/control_reconciliation/control_reconciliation_controller.dart';
import 'src/features/close_review/close_review_controller.dart';
import 'src/features/journal_evidence/posted_journal_controller.dart';
import 'src/features/operations/operational_controller.dart';
import 'src/features/operations/notification_admin_controller.dart';
import 'src/features/financial_dimensions/financial_dimension_controller.dart';
import 'src/features/report_export/report_export_controller.dart';
import 'src/features/bank_reconciliation/bank_reconciliation_controller.dart';
import 'src/features/period_fx/period_fx_controller.dart';
import 'src/features/financial_statements/financial_statement_controller.dart';
import 'src/features/financial_statements/cash_flow_mapping_controller.dart';
import 'src/features/financial_statements/tax_summary_controller.dart';
import 'src/features/budgets/budget_controller.dart';

import 'package:jentra_platform/jentra_people_platform.dart';
import 'package:jentra_platform/jentra_payroll_platform.dart';
import 'package:jentra_platform/jentra_assets_platform.dart';
import 'package:jentra_platform/jentra_projects_platform.dart';
import 'package:jentra_platform/jentra_project_finance_platform.dart';
import 'package:jentra_platform/jentra_service_platform.dart';
import 'package:jentra_platform/jentra_milestones_platform.dart';
import 'package:jentra_platform/jentra_expense_evidence_platform.dart';
import 'package:jentra_platform/jentra_asset_equipment_platform.dart';

import 'src/features/assets/assets_controller.dart';
import 'src/features/projects/projects_controller.dart';
import 'src/features/projects/project_finance_controller.dart';
import 'src/features/projects/milestones_controller.dart';
import 'src/features/service/service_controller.dart';
import 'src/features/service/asset_equipment_controller.dart';

import 'src/features/people/employee_controller.dart';
import 'src/features/people/calendar_controller.dart';
import 'src/features/people/organization_controller.dart';
import 'src/features/people/private_hr_controller.dart';
import 'src/features/people/workforce_controller.dart';
import 'src/features/people/payroll_controller.dart';

import 'package:jentra_platform/jentra_stock_opening_platform.dart';

import 'src/features/stock_opening/stock_opening_controller.dart';
import 'src/app.dart';
import 'src/app_providers.dart';
import 'src/features/receivables/receivables_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = RuntimeConfig.fromEnvironment();
  final client = await SupabasePlatform.initialize(config);
  final foundationGateway = client == null
      ? null
      : SupabaseFoundationGateway(client);
  final businessSetupGateway = client == null
      ? null
      : SupabaseBusinessSetupGateway(client);
  final crmRepository = client == null ? null : SupabaseCrmGateway(client);
  final quotations = client == null ? null : SupabaseLeadToCashGateway(client);

  runApp(
    ProviderScope(
      overrides: [
        runtimeConfigProvider.overrideWithValue(config),
        foundationGatewayProvider.overrideWithValue(foundationGateway),
        stockOpeningAccessGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseStockOpeningAccessGateway(client),
        ),
        businessSetupGatewayProvider.overrideWithValue(businessSetupGateway),
        crmRepositoryProvider.overrideWithValue(crmRepository),
        leadToCashRepositoryProvider.overrideWithValue(quotations),
        quotationWorkspaceRepositoryProvider.overrideWithValue(quotations),
        salesOrderRepositoryProvider.overrideWithValue(quotations),
        quotationReferenceRepositoryProvider.overrideWithValue(quotations),
        stockOpeningRepositoryProvider.overrideWithValue(
          client == null ? null : SupabaseStockOpeningGateway(client),
        ),
        receivablesRepositoryProvider.overrideWithValue(
          client == null ? null : SupabaseReceivablesGateway(client),
        ),
        procurementGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseProcurementGateway(client),
        ),
        inventoryTransferGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseInventoryTransferGateway(client),
        ),
        stockCountGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseStockCountGateway(client),
        ),
        countPartitionGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseCountPartitionGateway(client),
        ),
        landedExtensionGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseLandedExtensionGateway(client),
        ),
        dispositionGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseDispositionGateway(client),
        ),
        reservationGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseReservationGateway(client),
        ),
        negativeStockPolicyRepositoryProvider.overrideWithValue(
          client == null ? null : SupabaseNegativeStockPolicyGateway(client),
        ),
        receiptTraceGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseReceiptTraceGateway(client),
        ),
        landedValueGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseLandedValueGateway(client),
        ),
        inventoryValuationGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseInventoryValuationGateway(client),
        ),
        manualJournalGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseManualJournalGateway(client),
        ),
        controlReconciliationGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseControlReconciliationGateway(client),
        ),
        assuranceGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseAssuranceGateway(client),
        ),
        assuranceAccessGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseAssuranceAccessGateway(client),
        ),
        closeReviewGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseCloseReviewGateway(client),
        ),
        reportExportGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseReportExportGateway(client),
        ),
        financialDimensionGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseFinancialDimensionGateway(client),
        ),
        postedJournalGatewayProvider.overrideWithValue(
          client == null ? null : SupabasePostedJournalGateway(client),
        ),
        operationalGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseOperationalGateway(client),
        ),
        wave3NotificationGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseWave3NotificationGateway(client),
        ),
        bankReconciliationGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseBankReconciliationGateway(client),
        ),
        periodFxGatewayProvider.overrideWithValue(
          client == null ? null : SupabasePeriodFxGateway(client),
        ),
        financialStatementGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseFinancialStatementGateway(client),
        ),
        taxSummaryGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseTaxSummaryGateway(client),
        ),
        cashFlowMappingGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseCashFlowMappingGateway(client),
        ),
        budgetGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseBudgetGateway(client),
        ),
        employeeRepositoryProvider.overrideWithValue(
          client == null ? null : SupabaseEmployeeGateway(client),
        ),
        processMetricRepositoryProvider.overrideWithValue(
          client == null ? null : SupabaseProcessMetricGateway(client),
        ),
        pipelineForecastRepositoryProvider.overrideWithValue(
          client == null ? null : SupabasePipelineForecastGateway(client),
        ),
        historicalPipelineGatewayProvider.overrideWithValue(
          client == null
              ? null
              : HistoricalPipelineGateway(
                  (name, params) =>
                      client.schema('api').rpc(name, params: params),
                ),
        ),
        integrationRpcProvider.overrideWithValue(
          client == null
              ? null
              : (name, params) =>
                    client.schema('api').rpc(name, params: params),
        ),
        datedCashGatewayProvider.overrideWithValue(
          client == null
              ? null
              : DatedCashGateway(
                  (name, params) =>
                      client.schema('api').rpc(name, params: params),
                ),
        ),
        wave5ControlRepositoryProvider.overrideWithValue(
          client == null ? null : SupabaseWave5ControlGateway(client),
        ),
        reviewedModelRepositoryProvider.overrideWithValue(
          client == null ? null : SupabaseReviewedModelGateway(client),
        ),
        calendarRepositoryProvider.overrideWithValue(
          client == null ? null : SupabaseCalendarGateway(client),
        ),
        organizationRepositoryProvider.overrideWithValue(
          client == null ? null : SupabaseOrganizationGateway(client),
        ),
        privateHrRepositoryProvider.overrideWithValue(
          client == null ? null : SupabasePrivateHrGateway(client),
        ),
        workforceRepositoryProvider.overrideWithValue(
          client == null ? null : SupabaseWorkforceGateway(client),
        ),
        payrollRepositoryProvider.overrideWithValue(
          client == null ? null : SupabasePayrollGateway(client),
        ),
        assetsRepositoryProvider.overrideWithValue(
          client == null ? null : SupabaseAssetGateway(client),
        ),
        projectsRepositoryProvider.overrideWithValue(
          client == null ? null : SupabaseProjectGateway(client),
        ),
        projectFinanceRepositoryProvider.overrideWithValue(
          client == null ? null : SupabaseProjectFinanceGateway(client),
        ),
        projectExpenseEvidenceRepositoryProvider.overrideWithValue(
          client == null ? null : SupabaseExpenseEvidenceGateway(client),
        ),
        milestoneRepositoryProvider.overrideWithValue(
          client == null ? null : SupabaseMilestoneGateway(client),
        ),
        serviceRepositoryProvider.overrideWithValue(
          client == null ? null : SupabaseServiceGateway(client),
        ),
        assetEquipmentRepositoryProvider.overrideWithValue(
          client == null ? null : SupabaseAssetEquipmentGateway(client),
        ),
      ],
      child: const JentraApp(),
    ),
  );
}

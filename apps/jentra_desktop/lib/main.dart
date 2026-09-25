import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_platform/jentra_receivables_platform.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'src/features/procurement/procurement_controller.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'src/features/inventory_transfer/inventory_transfer_controller.dart';
import 'src/features/stock_count/stock_count_controller.dart';
import 'src/features/reservations/reservation_controller.dart';
import 'src/features/receipt_trace/receipt_trace_controller.dart';
import 'src/features/landed_value/landed_value_controller.dart';
import 'src/features/inventory_valuation/inventory_valuation_controller.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'src/features/manual_journal/manual_journal_controller.dart';
import 'src/features/control_reconciliation/control_reconciliation_controller.dart';
import 'src/features/bank_reconciliation/bank_reconciliation_controller.dart';
import 'src/features/period_fx/period_fx_controller.dart';
import 'src/features/financial_statements/financial_statement_controller.dart';
import 'package:jentra_platform/jentra_people_platform.dart';
import 'src/features/people/employee_controller.dart';

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
        reservationGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseReservationGateway(client),
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
        bankReconciliationGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseBankReconciliationGateway(client),
        ),
        periodFxGatewayProvider.overrideWithValue(
          client == null ? null : SupabasePeriodFxGateway(client),
        ),
        financialStatementGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseFinancialStatementGateway(client),
        ),
        employeeRepositoryProvider.overrideWithValue(
          client == null ? null : SupabaseEmployeeGateway(client),
        ),
      ],
      child: const JentraApp(),
    ),
  );
}

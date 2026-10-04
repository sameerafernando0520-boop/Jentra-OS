import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_domain/jentra_receivables.dart';
import 'package:jentra_domain/jentra_projects.dart';

import 'app_providers.dart';
import 'features/manual_journal/manual_journal_controller.dart';
import 'features/negative_stock/negative_stock_policy_screen.dart';
import 'features/manual_journal/manual_journal_screen.dart';
import 'features/control_reconciliation/control_reconciliation_controller.dart';
import 'features/control_reconciliation/control_reconciliation_screen.dart';
import 'features/close_review/close_review_controller.dart';
import 'features/close_review/close_review_screen.dart';
import 'features/journal_evidence/posted_journal_screen.dart';
import 'features/operations/operational_screen.dart';
import 'features/operations/notification_admin_screen.dart';
import 'features/financial_dimensions/financial_dimension_controller.dart';
import 'features/financial_dimensions/financial_dimension_screen.dart';
import 'features/report_export/report_export_controller.dart';
import 'features/report_export/report_export_screen.dart';
import 'features/bank_reconciliation/bank_reconciliation_controller.dart';
import 'features/bank_reconciliation/bank_reconciliation_screen.dart';
import 'features/period_fx/period_fx_controller.dart';
import 'features/period_fx/period_fx_screen.dart';
import 'features/financial_statements/financial_statement_controller.dart';
import 'features/financial_statements/financial_statement_screen.dart';
import 'features/financial_statements/cash_flow_mapping_controller.dart';
import 'features/financial_statements/cash_flow_mapping_screen.dart';
import 'features/financial_statements/tax_summary_controller.dart';
import 'features/financial_statements/tax_summary_screen.dart';
import 'features/budgets/budget_controller.dart';
import 'features/budgets/budget_screen.dart';
import 'features/people/employee_controller.dart';
import 'features/people/employee_screen.dart';
import 'features/people/calendar_controller.dart';
import 'features/people/calendar_screen.dart';
import 'features/people/organization_controller.dart';
import 'features/people/organization_screen.dart';
import 'features/people/private_hr_controller.dart';
import 'features/people/private_hr_screen.dart';
import 'features/people/workforce_controller.dart';
import 'features/people/workforce_screen.dart';
import 'features/people/payroll_controller.dart';
import 'features/people/payroll_screen.dart';
import 'features/assets/assets_controller.dart';
import 'features/assets/assets_screen.dart';
import 'features/projects/projects_controller.dart';
import 'features/projects/projects_screen.dart';
import 'features/projects/project_finance_controller.dart';
import 'features/projects/project_finance_screen.dart';
import 'features/service/service_controller.dart';
import 'features/service/service_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/catalogue/component_catalogue_screen.dart';
import 'features/crm/crm_screen.dart';
import 'features/procurement/procurement_screen.dart';
import 'features/procurement/procurement_controller.dart';
import 'features/procurement/sourcing_controller.dart';
import 'features/procurement/sourcing_screen.dart';
import 'features/procurement/purchase_order_screen.dart';
import 'features/procurement/purchase_order_controller.dart';
import 'features/procurement/product_unit_controller.dart';
import 'features/procurement/product_unit_screen.dart';
import 'features/procurement/goods_receipt_controller.dart';
import 'features/procurement/goods_receipt_screen.dart';
import 'features/procurement/supplier_bill_controller.dart';
import 'features/procurement/supplier_bill_screen.dart';
import 'features/procurement/supplier_payment_controller.dart';
import 'features/procurement/supplier_payment_screen.dart';
import 'features/procurement/purchase_return_controller.dart';
import 'features/procurement/purchase_return_screen.dart';
import 'features/inventory_transfer/inventory_transfer_controller.dart';
import 'features/inventory_transfer/inventory_transfer_screen.dart';
import 'features/stock_count/stock_count_controller.dart';
import 'features/stock_count/stock_count_screen.dart';
import 'features/landed_extension/landed_extension_controller.dart';
import 'features/landed_extension/landed_extension_screen.dart';
import 'features/disposition/disposition_controller.dart';
import 'features/disposition/disposition_screen.dart';
import 'features/reservations/reservation_controller.dart';
import 'features/reservations/reservation_screen.dart';
import 'features/receipt_trace/receipt_trace_screen.dart';
import 'features/landed_value/landed_value_screen.dart';
import 'features/landed_value/landed_value_controller.dart';
import 'features/inventory_valuation/inventory_valuation_controller.dart';
import 'features/inventory_valuation/inventory_valuation_screen.dart';
import 'features/receivables/receivables_screen.dart';
import 'features/stock_opening/stock_opening_screen.dart';
import 'features/stock_opening/stock_opening_controller.dart';
import 'features/sales/quotation_screen.dart';
import 'features/sales/sales_order_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/setup/business_setup_screen.dart';
import 'features/tenant/accept_invitation_screen.dart';
import 'features/shared/module_placeholder_screen.dart';
import 'shell/jentra_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final gateway = ref.watch(foundationGatewayProvider);
  final refresh = _AuthRefresh();
  final subscription = gateway?.authChanges.listen((_) => refresh.notify());
  ref.onDispose(() {
    unawaited(subscription?.cancel());
    refresh.dispose();
  });

  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: refresh,
    redirect: (context, state) {
      final configured = gateway != null;
      final authenticated = gateway?.currentUser != null;
      final atLogin = state.matchedLocation == '/login';
      if (configured && !authenticated && !atLogin) {
        return Uri(
          path: '/login',
          queryParameters: {'redirect': state.uri.toString()},
        ).toString();
      }
      if ((!configured || authenticated) && atLogin) {
        return state.uri.queryParameters['redirect'] ?? '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) => JentraShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/operations/documents',
            builder: (context, state) => OperationalScreen(
              target: (
                tenantId: state.uri.queryParameters['tenant'] ?? '',
                entityId: state.uri.queryParameters['entity'] ?? '',
                branchId: state.uri.queryParameters['branch'] ?? '',
                kind: state.uri.queryParameters['kind'] ?? '',
                id: state.uri.queryParameters['id'],
              ),
            ),
          ),
          GoRoute(
            path: '/operations/notifications',
            builder: (context, state) => const NotificationAdminScreen(),
          ),
          GoRoute(
            path: '/finance/journal-evidence',
            builder: (context, state) => PostedJournalScreen(
              target: (
                tenantId: state.uri.queryParameters['tenant'] ?? '',
                entityId: state.uri.queryParameters['entity'] ?? '',
                branchId: state.uri.queryParameters['branch'] ?? '',
                journalId: state.uri.queryParameters['journal'] ?? '',
              ),
            ),
          ),
          GoRoute(
            path: '/setup',
            builder: (context, state) => BusinessSetupScreen(
              key: ValueKey(state.uri.queryParameters['resource']),
              initialResource: BusinessSetupResource.values
                  .where((r) => r.name == state.uri.queryParameters['resource'])
                  .firstOrNull,
            ),
          ),
          GoRoute(path: '/crm', builder: (context, state) => const CrmScreen()),
          GoRoute(
            path: '/receivables',
            builder: (context, state) => ReceivablesScreen(
              initialKind: ReceivableKind.values
                  .where((k) => k.wire == state.uri.queryParameters['kind'])
                  .firstOrNull,
            ),
          ),
          GoRoute(
            path: '/sales',
            builder: (context, state) => const QuotationScreen(),
          ),
          GoRoute(
            path: '/sales/orders',
            builder: (context, state) => SalesOrderScreen(
              orderId: state.uri.queryParameters['order'],
              quotationId: state.uri.queryParameters['quotation'],
              sourceQuotationId: state.uri.queryParameters['source'],
            ),
          ),
          GoRoute(
            path: '/inventory',
            builder: (context, state) => const StockOpeningScreen(),
            onExit: (context, state) async =>
                await ref.read(stockOpeningControllerProvider)?.canLeave() ??
                true,
          ),
          GoRoute(
            path: '/inventory/transfers',
            builder: (context, state) => const InventoryTransferScreen(),
            onExit: (context, state) async =>
                await ref
                    .read(inventoryTransferControllerProvider)
                    ?.canLeave() ??
                true,
          ),
          GoRoute(
            path: '/inventory/counts',
            builder: (context, state) => const StockCountScreen(),
            onExit: (context, state) async =>
                await ref.read(stockCountControllerProvider)?.canLeave() ??
                true,
          ),
          GoRoute(
            path: '/inventory/reservations',
            builder: (context, state) => const ReservationScreen(),
            onExit: (context, state) async =>
                await ref.read(reservationControllerProvider)?.canLeave() ??
                true,
          ),
          GoRoute(
            path: '/inventory/negative-stock-policy',
            builder: (context, state) => const NegativeStockPolicyScreen(),
          ),
          GoRoute(
            path: '/inventory/landed-extensions',
            builder: (context, state) => const LandedExtensionScreen(),
            onExit: (context, state) async =>
                await ref.read(landedExtensionControllerProvider)?.canLeave() ??
                true,
          ),
          GoRoute(
            path: '/inventory/dispositions',
            builder: (context, state) => const DispositionScreen(),
            onExit: (context, state) async =>
                await ref.read(dispositionControllerProvider)?.canLeave() ??
                true,
          ),
          GoRoute(
            path: '/inventory/receipt-trace',
            builder: (context, state) => const ReceiptTraceScreen(),
          ),
          GoRoute(
            path: '/inventory/valuation',
            builder: (context, state) => const InventoryValuationScreen(),
            onExit: (context, state) async =>
                await ref
                    .read(inventoryValuationControllerProvider)
                    ?.canLeave() ??
                true,
          ),
          GoRoute(
            path: '/finance/journals',
            builder: (context, state) => const ManualJournalScreen(),
            onExit: (context, state) async =>
                await ref.read(manualJournalControllerProvider)?.canLeave() ??
                true,
          ),
          GoRoute(
            path: '/finance/controls',
            builder: (context, state) => const ControlReconciliationScreen(),
            onExit: (context, state) async =>
                await ref
                    .read(controlReconciliationControllerProvider)
                    ?.canLeave() ??
                true,
          ),
          GoRoute(
            path: '/finance/close-review',
            builder: (context, state) => const CloseReviewScreen(),
            onExit: (context, state) async =>
                await ref.read(closeReviewControllerProvider)?.canLeave() ??
                true,
          ),
          GoRoute(
            path: '/finance/dimensions',
            builder: (context, state) => const FinancialDimensionScreen(),
            onExit: (context, state) async =>
                await ref
                    .read(financialDimensionControllerProvider)
                    ?.canLeave() ??
                true,
          ),
          GoRoute(
            path: '/finance/report-export',
            builder: (context, state) => ReportExportScreen(
              initial: {
                'source_type': state.uri.queryParameters['source'],
                'source_id': state.uri.queryParameters['id'],
                'section': state.uri.queryParameters['section'],
                'filters': {
                  for (final key in [
                    'account_id',
                    'evidence_key',
                    'source_line_id',
                    'budget_line_id',
                    'component_key',
                  ])
                    if (state.uri.queryParameters[key] != null)
                      key: state.uri.queryParameters[key],
                },
              },
            ),
            onExit: (context, state) async =>
                await ref.read(reportExportControllerProvider)?.canLeave() ??
                true,
          ),
          GoRoute(
            path: '/finance/bank',
            builder: (context, state) => const BankReconciliationScreen(),
            onExit: (context, state) async =>
                await ref
                    .read(bankReconciliationControllerProvider)
                    ?.canLeave() ??
                true,
          ),
          GoRoute(
            path: '/finance/periods',
            builder: (context, state) => const PeriodFxScreen(),
            onExit: (context, state) async =>
                await ref.read(periodFxControllerProvider)?.canLeave() ?? true,
          ),
          GoRoute(
            path: '/finance/statements',
            builder: (context, state) => const FinancialStatementScreen(),
            onExit: (context, state) async =>
                await ref
                    .read(financialStatementControllerProvider)
                    ?.canLeave() ??
                true,
          ),
          GoRoute(
            path: '/finance/tax',
            builder: (context, state) => const TaxSummaryScreen(),
            onExit: (context, state) async =>
                await ref.read(taxSummaryControllerProvider)?.canLeave() ??
                true,
          ),
          GoRoute(
            path: '/finance/cash-flow-mappings',
            builder: (context, state) => const CashFlowMappingScreen(),
            onExit: (context, state) async =>
                await ref.read(cashFlowMappingControllerProvider)?.canLeave() ??
                true,
          ),
          GoRoute(
            path: '/finance/budgets',
            builder: (context, state) => const BudgetScreen(),
            onExit: (context, state) async =>
                await ref.read(budgetControllerProvider)?.canLeave() ?? true,
          ),
          GoRoute(
            path: '/inventory/landed-value',
            builder: (context, state) => const LandedValueScreen(),
            onExit: (context, state) async =>
                await ref.read(landedValueControllerProvider)?.canLeave() ??
                true,
          ),
          GoRoute(
            path: '/procurement',
            builder: (context, state) => const ProcurementScreen(),
            onExit: (context, state) async =>
                await ref.read(procurementControllerProvider)?.canLeave() ??
                true,
          ),
          GoRoute(
            path: '/procurement/sourcing',
            builder: (context, state) => const SourcingScreen(),
            onExit: (context, state) async =>
                await ref.read(sourcingControllerProvider)?.canLeave() ?? true,
          ),
          GoRoute(
            path: '/procurement/orders',
            builder: (context, state) => const PurchaseOrderScreen(),
            onExit: (context, state) async =>
                await ref.read(purchaseOrderControllerProvider)?.canLeave() ??
                true,
          ),
          GoRoute(
            path: '/procurement/units',
            builder: (context, state) => const ProductUnitScreen(),
            onExit: (context, state) async =>
                await ref.read(productUnitControllerProvider)?.canLeave() ??
                true,
          ),
          GoRoute(
            path: '/procurement/receipts',
            builder: (context, state) => const GoodsReceiptScreen(),
            onExit: (context, state) async =>
                await ref.read(goodsReceiptControllerProvider)?.canLeave() ??
                true,
          ),
          GoRoute(
            path: '/procurement/bills',
            builder: (context, state) => const SupplierBillScreen(),
            onExit: (context, state) async =>
                await ref.read(supplierBillControllerProvider)?.canLeave() ??
                true,
          ),
          GoRoute(
            path: '/procurement/payments',
            builder: (context, state) => const SupplierPaymentScreen(),
            onExit: (context, state) async =>
                await ref.read(supplierPaymentControllerProvider)?.canLeave() ??
                true,
          ),
          GoRoute(
            path: '/procurement/returns',
            builder: (context, state) => const PurchaseReturnScreen(),
            onExit: (context, state) async =>
                await ref.read(purchaseReturnControllerProvider)?.canLeave() ??
                true,
          ),
          GoRoute(
            path: '/people',
            builder: (context, state) => const EmployeeScreen(),
            onExit: (context, state) async =>
                await ref.read(employeeControllerProvider)?.canLeave() ?? true,
          ),
          GoRoute(
            path: '/assets',
            builder: (context, state) => const AssetsScreen(),
            onExit: (context, state) async =>
                await ref.read(assetsControllerProvider)?.canLeave() ?? true,
          ),
          GoRoute(
            path: '/people/employees',
            builder: (context, state) => const EmployeeScreen(),
            onExit: (context, state) async =>
                await ref.read(employeeControllerProvider)?.canLeave() ?? true,
          ),
          GoRoute(
            path: '/people/calendars',
            builder: (context, state) => const CalendarScreen(),
            onExit: (context, state) async =>
                await ref.read(calendarControllerProvider)?.canLeave() ?? true,
          ),
          GoRoute(
            path: '/people/organization',
            builder: (context, state) => const OrganizationScreen(),
            onExit: (context, state) async =>
                await ref.read(organizationControllerProvider)?.canLeave() ??
                true,
          ),
          GoRoute(
            path: '/people/private',
            builder: (context, state) => const PrivateHrScreen(),
            onExit: (context, state) async =>
                await ref.read(privateHrControllerProvider)?.canLeave() ?? true,
          ),
          GoRoute(
            path: '/people/workforce',
            builder: (context, state) => const WorkforceScreen(),
            onExit: (context, state) async =>
                await ref.read(workforceControllerProvider)?.canLeave() ?? true,
          ),
          GoRoute(
            path: '/people/payroll',
            builder: (context, state) => const PayrollScreen(),
            onExit: (context, state) async =>
                await ref.read(payrollControllerProvider)?.canLeave() ?? true,
          ),
          GoRoute(
            path: '/projects',
            builder: (context, state) => const ProjectsScreen(),
            onExit: (context, state) async =>
                await ref.read(projectsControllerProvider)?.canLeave() ?? true,
          ),
          GoRoute(
            path: '/projects/:projectId/finance',
            builder: (context, state) {
              final project = state.extra;
              if (project is! ProjectRecord ||
                  project.id != state.pathParameters['projectId']) {
                return const Center(
                  child: Text(
                    'Open a project from the register to view its finances.',
                  ),
                );
              }
              return ProjectFinanceScreen(
                projectId: project.id,
                projectName: project.name,
                currency: project.currency,
                precision: project.precision,
              );
            },
            onExit: (context, state) async {
              final project = state.extra;
              if (project is! ProjectRecord) return true;
              return await ref
                      .read(
                        projectFinanceControllerProvider((
                          project.id,
                          project.currency,
                          project.precision,
                        )),
                      )
                      ?.canLeave() ??
                  true;
            },
          ),
          GoRoute(
            path: '/service',
            builder: (context, state) => const ServiceScreen(),
            onExit: (context, state) async =>
                await ref.read(serviceControllerProvider)?.canLeave() ?? true,
          ),
          for (final module in const [
            (
              'finance',
              'Finance',
              'Ledger, AR/AP, cash, tax and financial reporting.',
            ),
            (
              'analytics',
              'Analytics',
              'Role-aware operating and financial intelligence.',
            ),
            (
              'control',
              'Jentra Control',
              'Plans, entitlements, usage and tenant operations.',
            ),
          ])
            GoRoute(
              path: '/${module.$1}',
              builder: (context, state) => ModulePlaceholderScreen(
                title: module.$2,
                description: module.$3,
              ),
            ),
          GoRoute(
            path: '/catalogue',
            builder: (context, state) => const ComponentCatalogueScreen(),
          ),
          GoRoute(
            path: '/invitation/:token',
            builder: (context, state) =>
                AcceptInvitationScreen(token: state.pathParameters['token']!),
          ),
        ],
      ),
    ],
  );
});

final class _AuthRefresh extends ChangeNotifier {
  void notify() => notifyListeners();
}

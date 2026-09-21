import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_domain/jentra_receivables.dart';

import 'app_providers.dart';
import 'features/manual_journal/manual_journal_controller.dart';
import 'features/manual_journal/manual_journal_screen.dart';
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
          for (final module in const [
            (
              'finance',
              'Finance',
              'Ledger, AR/AP, cash, tax and financial reporting.',
            ),
            ('people', 'People', 'Employees, attendance, leave and payroll.'),
            (
              'projects',
              'Projects',
              'Plan delivery, capture time and protect margin.',
            ),
            (
              'service',
              'Service',
              'Tickets, SLAs, work orders and maintenance.',
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

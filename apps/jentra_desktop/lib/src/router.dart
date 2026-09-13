import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_domain/jentra_receivables.dart';

import 'app_providers.dart';
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

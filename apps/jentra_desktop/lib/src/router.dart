import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_providers.dart';
import 'features/auth/login_screen.dart';
import 'features/catalogue/component_catalogue_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
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
          for (final module in const [
            ('crm', 'CRM & Revenue', 'Build trusted customer relationships.'),
            (
              'sales',
              'Sales',
              'Quotes, orders, deliveries, invoices and returns.',
            ),
            (
              'procurement',
              'Procurement',
              'Requisitions, approvals, RFQs and purchasing.',
            ),
            (
              'inventory',
              'Inventory',
              'Stock, warehouses, transfers and valuation.',
            ),
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

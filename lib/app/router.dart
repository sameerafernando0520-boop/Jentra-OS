import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_providers.dart';
import '../core/widgets/configuration_screen.dart';
import '../core/widgets/startup_screen.dart';
import '../features/accounting/presentation/screens/accounting_screen.dart';
import '../features/ai_assistant/presentation/screens/ai_assistant_screen.dart';
import '../features/ai_assistant/presentation/screens/ai_chat_screen.dart';
import '../features/ai_assistant/presentation/screens/ai_insights_screen.dart';
import '../features/ai_assistant/presentation/screens/ai_settings_screen.dart';
import '../features/auth/presentation/screens/auth_gate_screen.dart';
import '../features/auth/presentation/screens/forgot_password_screen.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/auth/presentation/screens/register_screen.dart';
import '../features/company/presentation/screens/company_onboarding_screen.dart';
import '../features/company/presentation/screens/company_selector_screen.dart';
import '../features/company/presentation/screens/company_settings_overview_screen.dart';
import '../features/company/presentation/screens/create_company_screen.dart';
import '../features/company/presentation/widgets/company_context_gate.dart';
import '../features/crm/presentation/screens/create_customer_screen.dart';
import '../features/crm/presentation/screens/crm_screen.dart';
import '../features/crm/presentation/screens/customer_detail_screen.dart';
import '../features/crm/presentation/screens/edit_customer_screen.dart';
import '../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../features/finance/presentation/screens/finance_screen.dart';
import '../features/inventory/presentation/screens/create_product_screen.dart';
import '../features/inventory/presentation/screens/edit_product_screen.dart';
import '../features/inventory/presentation/screens/inventory_screen.dart';
import '../features/inventory/presentation/screens/product_detail_screen.dart';
import '../features/inventory/presentation/screens/product_list_screen.dart';
import '../features/inventory/presentation/screens/stock_overview_screen.dart';
import '../features/inventory/presentation/screens/warehouse_list_screen.dart';
import '../features/sales/presentation/screens/create_invoice_screen.dart';
import '../features/sales/presentation/screens/edit_invoice_screen.dart';
import '../features/sales/presentation/screens/invoice_detail_screen.dart';
import '../features/sales/presentation/screens/invoice_list_screen.dart';
import '../features/sales/presentation/screens/sales_screen.dart';
import '../features/settings/presentation/screens/settings_screen.dart';
import '../features/subscription/presentation/screens/subscription_screen.dart';
import '../shared/layouts/app_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final config = ref.watch(envConfigProvider);
  final client = ref.watch(supabaseClientProvider);
  final startupFailure = ref.watch(startupFailureProvider);
  final refreshNotifier = _AuthRefreshNotifier(client?.auth.onAuthStateChange);

  final router = GoRouter(
    initialLocation: '/auth-gate',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final path = state.uri.path;
      final configurationFailed =
          !config.isSupabaseConfigured ||
          startupFailure != null ||
          client == null;

      if (configurationFailed) {
        return path == '/configuration' ? null : '/configuration';
      }

      final signedIn = client.auth.currentSession != null;
      if (!signedIn) {
        if (path == '/sign-in') return '/login';
        return _publicAuthPaths.contains(path) ? null : '/login';
      }

      if (path == '/' || path == '/startup' || path == '/configuration') {
        return '/auth-gate';
      }

      if (_publicAuthPaths.contains(path) || path == '/sign-in') {
        return '/auth-gate';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const StartupScreen()),
      GoRoute(
        path: '/startup',
        builder: (context, state) => const StartupScreen(),
      ),
      GoRoute(
        path: '/configuration',
        builder: (context, state) => const ConfigurationScreen(),
      ),
      GoRoute(
        path: '/auth-gate',
        builder: (context, state) => const AuthGateScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/sign-in', redirect: (context, state) => '/login'),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/company',
        redirect: (context, state) => '/company/select',
      ),
      GoRoute(
        path: '/company/onboarding',
        builder: (context, state) => const CompanyOnboardingScreen(),
      ),
      GoRoute(
        path: '/company/create',
        builder: (context, state) => const CreateCompanyScreen(),
      ),
      GoRoute(
        path: '/company/select',
        builder: (context, state) => const CompanySelectorScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(child: CompanyContextGate(child: child)),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/company/settings',
            builder: (context, state) => const CompanySettingsOverviewScreen(),
          ),
          GoRoute(path: '/crm', builder: (context, state) => const CrmScreen()),
          GoRoute(
            path: '/crm/customers/new',
            builder: (context, state) => const CreateCustomerScreen(),
          ),
          GoRoute(
            path: '/crm/customers/:customerId/edit',
            builder: (context, state) => EditCustomerScreen(
              customerId: state.pathParameters['customerId']!,
            ),
          ),
          GoRoute(
            path: '/crm/customers/:customerId',
            builder: (context, state) => CustomerDetailScreen(
              customerId: state.pathParameters['customerId']!,
            ),
          ),
          GoRoute(
            path: '/sales',
            builder: (context, state) => const SalesScreen(),
          ),
          GoRoute(
            path: '/sales/invoices',
            builder: (context, state) => const InvoiceListScreen(),
          ),
          GoRoute(
            path: '/sales/invoices/new',
            builder: (context, state) => const CreateInvoiceScreen(),
          ),
          GoRoute(
            path: '/sales/invoices/:invoiceId/edit',
            builder: (context, state) => EditInvoiceScreen(
              invoiceId: state.pathParameters['invoiceId']!,
            ),
          ),
          GoRoute(
            path: '/sales/invoices/:invoiceId',
            builder: (context, state) => InvoiceDetailScreen(
              invoiceId: state.pathParameters['invoiceId']!,
            ),
          ),
          GoRoute(
            path: '/inventory',
            builder: (context, state) => const InventoryScreen(),
          ),
          GoRoute(
            path: '/inventory/products',
            builder: (context, state) => const ProductListScreen(),
          ),
          GoRoute(
            path: '/inventory/products/new',
            builder: (context, state) => const CreateProductScreen(),
          ),
          GoRoute(
            path: '/inventory/products/:productId/edit',
            builder: (context, state) => EditProductScreen(
              productId: state.pathParameters['productId']!,
            ),
          ),
          GoRoute(
            path: '/inventory/products/:productId',
            builder: (context, state) => ProductDetailScreen(
              productId: state.pathParameters['productId']!,
            ),
          ),
          GoRoute(
            path: '/inventory/warehouses',
            builder: (context, state) => const WarehouseListScreen(),
          ),
          GoRoute(
            path: '/inventory/stock',
            builder: (context, state) => const StockOverviewScreen(),
          ),
          GoRoute(
            path: '/finance',
            builder: (context, state) => const FinanceScreen(),
          ),
          GoRoute(
            path: '/accounting',
            builder: (context, state) => const AccountingScreen(),
          ),
          GoRoute(
            path: '/ai-assistant',
            builder: (context, state) => const AiAssistantScreen(),
          ),
          GoRoute(
            path: '/ai',
            builder: (context, state) => const AiAssistantScreen(),
          ),
          GoRoute(
            path: '/ai/chat',
            builder: (context, state) => const AiChatScreen(),
          ),
          GoRoute(
            path: '/ai/insights',
            builder: (context, state) => const AiInsightsScreen(),
          ),
          GoRoute(
            path: '/ai/settings',
            builder: (context, state) => const AiSettingsScreen(),
          ),
          GoRoute(
            path: '/subscription',
            builder: (context, state) => const SubscriptionScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    refreshNotifier.dispose();
  });
  return router;
});

final class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Stream<AuthState>? authChanges) {
    _subscription = authChanges?.listen(
      (_) => notifyListeners(),
      onError: (Object error, StackTrace stackTrace) {
        // The auth state provider exposes the error to interested UI. The
        // router only refreshes so a transient token-refresh failure cannot
        // become an unhandled zone exception.
        notifyListeners();
      },
    );
  }

  StreamSubscription<AuthState>? _subscription;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

const _publicAuthPaths = {'/login', '/register', '/forgot-password'};

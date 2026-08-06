import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_os/features/company/application/company_models.dart';
import 'package:jentra_os/features/company/application/company_state.dart';
import 'package:jentra_os/features/dashboard/application/dashboard_models.dart';
import 'package:jentra_os/features/dashboard/data/supabase_dashboard_repository.dart';
import 'package:jentra_os/features/dashboard/presentation/screens/dashboard_screen.dart';

import '../fake_dashboard_repository.dart';

void main() {
  testWidgets('dashboard redirects to company selector without a company', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (_, _) => const Scaffold(body: DashboardScreen()),
        ),
        GoRoute(
          path: '/company/select',
          builder: (_, _) => const Scaffold(body: Text('Company selector')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [selectedCompanyProvider.overrideWithValue(null)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/company/select');
    expect(find.text('Company selector'), findsOneWidget);
  });

  testWidgets('empty company renders zero KPIs and required quick actions', (
    tester,
  ) async {
    final repository = FakeDashboardRepository(
      snapshot: DashboardSnapshot(
        companyId: _company.id,
        kpis: const DashboardKpis.empty(),
        recentActivity: const [],
        generatedAt: DateTime.utc(2026, 7, 14, 10, 30),
        dataStatus: 'foundation',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          selectedCompanyProvider.overrideWithValue(_company),
          dashboardRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: Scaffold(body: DashboardScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('dashboard-company-company-1')),
      findsOneWidget,
    );
    expect(find.text(_company.name), findsOneWidget);
    expect(find.text('Add Customer'), findsOneWidget);
    expect(find.text('Create Invoice'), findsOneWidget);
    expect(find.text('Add Product'), findsOneWidget);
    expect(find.text('Record Expense'), findsOneWidget);
    expect(find.text('Today Sales'), findsOneWidget);
    expect(find.text('This Month Sales'), findsOneWidget);
    expect(find.text('Outstanding Invoices'), findsOneWidget);
    expect(find.text('Cash Balance'), findsOneWidget);
    expect(find.text('LKR 0.00'), findsNWidgets(4));
    expect(find.text('No recent activity yet'), findsOneWidget);
    expect(repository.requestedCompanyIds, [_company.id]);
  });
}

const _company = Company(
  id: 'company-1',
  ownerUserId: 'user-1',
  name: 'Acme Trading',
  legalName: null,
  currencyCode: 'LKR',
  countryCode: 'LK',
  timezone: 'Asia/Colombo',
  membershipRole: 'Owner',
  isOwner: true,
  isAdmin: true,
);

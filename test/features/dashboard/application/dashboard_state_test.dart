import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_os/features/company/application/company_models.dart';
import 'package:jentra_os/features/company/application/company_state.dart';
import 'package:jentra_os/features/dashboard/application/dashboard_failure.dart';
import 'package:jentra_os/features/dashboard/application/dashboard_models.dart';
import 'package:jentra_os/features/dashboard/application/dashboard_state.dart';
import 'package:jentra_os/features/dashboard/data/supabase_dashboard_repository.dart';

import '../fake_dashboard_repository.dart';

void main() {
  test('missing company fails closed without a repository request', () async {
    final repository = FakeDashboardRepository(snapshot: _emptySnapshot);
    final container = ProviderContainer(
      overrides: [
        selectedCompanyProvider.overrideWithValue(null),
        dashboardRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(dashboardControllerProvider.future),
      throwsA(
        isA<DashboardFailure>().having(
          (failure) => failure.userMessage,
          'userMessage',
          'Select a company before loading its dashboard.',
        ),
      ),
    );
    expect(repository.requestedCompanyIds, isEmpty);
  });

  test(
    'selected company ID is the only scope sent to the repository',
    () async {
      final repository = FakeDashboardRepository(snapshot: _emptySnapshot);
      final container = ProviderContainer(
        overrides: [
          selectedCompanyProvider.overrideWithValue(_company),
          dashboardRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final state = await container.read(dashboardControllerProvider.future);

      expect(state.snapshot.companyId, _company.id);
      expect(state.snapshot.kpis.todaySales, 0);
      expect(state.snapshot.kpis.cashBalance, 0);
      expect(repository.requestedCompanyIds, [_company.id]);
    },
  );

  test('a response for another company is rejected', () async {
    final repository = FakeDashboardRepository(
      snapshot: DashboardSnapshot(
        companyId: 'company-2',
        kpis: const DashboardKpis.empty(),
        recentActivity: const [],
        generatedAt: DateTime.utc(2026, 7, 14),
        dataStatus: 'foundation',
      ),
    );
    final container = ProviderContainer(
      overrides: [
        selectedCompanyProvider.overrideWithValue(_company),
        dashboardRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(dashboardControllerProvider.future),
      throwsA(isA<DashboardFailure>()),
    );
    expect(repository.requestedCompanyIds, [_company.id]);
  });

  test('missing KPI values safely map to zero', () {
    final snapshot = DashboardSnapshot.fromJson({
      'company_id': _company.id,
      'generated_at': '2026-07-14T10:30:00Z',
      'recent_activity': <Object>[],
      'data_status': 'foundation',
    });

    expect(snapshot.kpis.todaySales, 0);
    expect(snapshot.kpis.monthSales, 0);
    expect(snapshot.kpis.outstandingInvoices, 0);
    expect(snapshot.kpis.outstandingInvoiceCount, 0);
    expect(snapshot.kpis.cashBalance, 0);
    expect(snapshot.recentActivity, isEmpty);
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

final _emptySnapshot = DashboardSnapshot(
  companyId: _company.id,
  kpis: const DashboardKpis.empty(),
  recentActivity: const [],
  generatedAt: DateTime.utc(2026, 7, 14, 10, 30),
  dataStatus: 'foundation',
);

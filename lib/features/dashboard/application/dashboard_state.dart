import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../company/application/company_state.dart';
import '../data/supabase_dashboard_repository.dart';
import 'dashboard_failure.dart';
import 'dashboard_models.dart';

final dashboardControllerProvider =
    AsyncNotifierProvider<DashboardController, DashboardState>(
      DashboardController.new,
      retry: (_, _) => null,
    );

final class DashboardState {
  const DashboardState({required this.snapshot, this.isRefreshing = false});

  final DashboardSnapshot snapshot;
  final bool isRefreshing;

  DashboardState withRefreshing(bool value) {
    return DashboardState(snapshot: snapshot, isRefreshing: value);
  }
}

final class DashboardController extends AsyncNotifier<DashboardState> {
  @override
  Future<DashboardState> build() async {
    final companyId = ref.watch(selectedCompanyIdProvider);
    if (companyId == null || companyId.trim().isEmpty) {
      throw const DashboardFailure(
        'Select a company before loading its dashboard.',
      );
    }

    final snapshot = await ref
        .watch(dashboardRepositoryProvider)
        .getSummary(companyId);
    _ensureCurrentCompany(snapshot.companyId);
    return DashboardState(snapshot: snapshot);
  }

  Future<void> refreshDashboard() async {
    final current = state.asData?.value;
    final companyId = ref.read(selectedCompanyIdProvider);
    if (companyId == null || companyId.trim().isEmpty) {
      state = AsyncError(
        const DashboardFailure(
          'Select a company before loading its dashboard.',
        ),
        StackTrace.current,
      );
      return;
    }

    if (current != null) {
      state = AsyncData(current.withRefreshing(true));
    } else {
      state = const AsyncLoading();
    }

    try {
      final snapshot = await ref
          .read(dashboardRepositoryProvider)
          .getSummary(companyId);
      _ensureCurrentCompany(snapshot.companyId);
      state = AsyncData(DashboardState(snapshot: snapshot));
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  void _ensureCurrentCompany(String responseCompanyId) {
    if (ref.read(selectedCompanyIdProvider) != responseCompanyId) {
      throw const DashboardFailure(
        'The selected company changed while loading. Please refresh.',
      );
    }
  }
}

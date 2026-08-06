import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/dashboard_failure.dart';
import '../application/dashboard_models.dart';
import '../application/dashboard_repository.dart';
import 'dashboard_service.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return SupabaseDashboardRepository(ref.watch(dashboardServiceProvider));
});

final class SupabaseDashboardRepository implements DashboardRepository {
  const SupabaseDashboardRepository(this._service);

  final DashboardService _service;

  @override
  Future<DashboardSnapshot> getSummary(String companyId) async {
    final normalizedCompanyId = companyId.trim();
    if (normalizedCompanyId.isEmpty) {
      throw const DashboardFailure(
        'Select a company before loading its dashboard.',
      );
    }

    try {
      final row = await _service.fetchSummary(normalizedCompanyId);
      final snapshot = DashboardSnapshot.fromJson(row);

      // Defense in depth: never render a payload whose tenant identifier does
      // not match the company requested by state.
      if (snapshot.companyId != normalizedCompanyId) {
        throw const DashboardFailure(
          'The dashboard company context changed. Please refresh.',
        );
      }
      return snapshot;
    } on DashboardFailure {
      rethrow;
    } on AuthException catch (error, stackTrace) {
      throw DashboardFailure(
        'Your session is no longer valid. Please sign in again.',
        cause: error,
        stackTrace: stackTrace,
      );
    } on PostgrestException catch (error, stackTrace) {
      final denied = error.code == '42501';
      throw DashboardFailure(
        denied
            ? 'You no longer have access to this company.'
            : 'We could not load the dashboard. Check your connection and try again.',
        cause: error,
        stackTrace: stackTrace,
      );
    } on Object catch (error, stackTrace) {
      throw DashboardFailure(
        'We could not load the dashboard. Please try again.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }
}

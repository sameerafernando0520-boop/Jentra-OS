import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_providers.dart';
import '../application/dashboard_failure.dart';

final dashboardServiceProvider = Provider<DashboardService>((ref) {
  return DashboardService(ref.watch(supabaseServiceProvider).client);
});

/// Low-level Supabase adapter. The selected company ID is always sent to the
/// database function, which independently verifies active membership.
final class DashboardService {
  const DashboardService(this._client);

  final SupabaseClient _client;

  Future<Map<String, dynamic>> fetchSummary(String companyId) async {
    if (_client.auth.currentUser == null) {
      throw const DashboardFailure('Please sign in to view the dashboard.');
    }

    final response = await _client.rpc(
      'get_dashboard_summary',
      params: {'p_company_id': companyId},
    );

    if (response is! Map) {
      throw const DashboardFailure(
        'The dashboard returned an unexpected response. Please try again.',
      );
    }

    return Map<String, dynamic>.from(response);
  }
}

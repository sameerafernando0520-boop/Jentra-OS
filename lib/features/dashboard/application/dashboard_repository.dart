import 'dashboard_models.dart';

abstract interface class DashboardRepository {
  /// Loads a summary for exactly [companyId]. Implementations must pass this
  /// scope to the backend and reject responses for any different tenant.
  Future<DashboardSnapshot> getSummary(String companyId);
}

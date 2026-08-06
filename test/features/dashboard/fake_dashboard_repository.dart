import 'package:jentra_os/features/dashboard/application/dashboard_models.dart';
import 'package:jentra_os/features/dashboard/application/dashboard_repository.dart';

final class FakeDashboardRepository implements DashboardRepository {
  FakeDashboardRepository({required this.snapshot, this.error});

  final DashboardSnapshot snapshot;
  final Object? error;
  final List<String> requestedCompanyIds = <String>[];

  @override
  Future<DashboardSnapshot> getSummary(String companyId) async {
    requestedCompanyIds.add(companyId);
    if (error case final error?) throw error;
    return snapshot;
  }
}

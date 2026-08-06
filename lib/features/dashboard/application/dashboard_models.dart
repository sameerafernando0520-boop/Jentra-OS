/// Dashboard KPI values for exactly one company.
final class DashboardKpis {
  const DashboardKpis({
    required this.todaySales,
    required this.monthSales,
    required this.outstandingInvoices,
    required this.outstandingInvoiceCount,
    required this.cashBalance,
  });

  const DashboardKpis.empty()
    : todaySales = 0,
      monthSales = 0,
      outstandingInvoices = 0,
      outstandingInvoiceCount = 0,
      cashBalance = 0;

  final double todaySales;
  final double monthSales;
  final double outstandingInvoices;
  final int outstandingInvoiceCount;
  final double cashBalance;
}

/// A compact activity item. Later modules can extend the database function
/// while keeping this presentation contract stable.
final class DashboardActivity {
  const DashboardActivity({
    required this.id,
    required this.title,
    required this.description,
    required this.occurredAt,
    required this.category,
  });

  final String id;
  final String title;
  final String description;
  final DateTime occurredAt;
  final String category;

  factory DashboardActivity.fromJson(Map<String, dynamic> json) {
    final occurredAt = DateTime.tryParse(json['occurred_at']?.toString() ?? '');
    if (occurredAt == null) {
      throw const FormatException('Dashboard activity has no valid date.');
    }

    return DashboardActivity(
      id: _requiredString(json, 'id'),
      title: _requiredString(json, 'title'),
      description: json['description']?.toString().trim() ?? '',
      occurredAt: occurredAt,
      category: json['category']?.toString().trim() ?? 'general',
    );
  }
}

/// One server-generated dashboard snapshot, always bound to [companyId].
final class DashboardSnapshot {
  const DashboardSnapshot({
    required this.companyId,
    required this.kpis,
    required this.recentActivity,
    required this.generatedAt,
    required this.dataStatus,
  });

  final String companyId;
  final DashboardKpis kpis;
  final List<DashboardActivity> recentActivity;
  final DateTime generatedAt;

  /// `foundation` means later Sales and Finance tables are not sources yet.
  final String dataStatus;

  factory DashboardSnapshot.fromJson(Map<String, dynamic> json) {
    final generatedAt = DateTime.tryParse(
      json['generated_at']?.toString() ?? '',
    );
    if (generatedAt == null) {
      throw const FormatException('Dashboard summary has no valid timestamp.');
    }

    final activityRows = json['recent_activity'];
    final activities = activityRows is List
        ? activityRows
              .whereType<Map>()
              .map(
                (row) =>
                    DashboardActivity.fromJson(Map<String, dynamic>.from(row)),
              )
              .toList(growable: false)
        : const <DashboardActivity>[];

    return DashboardSnapshot(
      companyId: _requiredString(json, 'company_id'),
      kpis: DashboardKpis(
        todaySales: _readDouble(json['today_sales']),
        monthSales: _readDouble(json['month_sales']),
        outstandingInvoices: _readDouble(json['outstanding_invoices']),
        outstandingInvoiceCount: _readInt(json['outstanding_invoice_count']),
        cashBalance: _readDouble(json['cash_balance']),
      ),
      recentActivity: List<DashboardActivity>.unmodifiable(activities),
      generatedAt: generatedAt,
      dataStatus: json['data_status']?.toString() ?? 'ready',
    );
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key]?.toString().trim() ?? '';
  if (value.isEmpty) throw FormatException('Missing dashboard field: $key');
  return value;
}

double _readDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _readInt(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

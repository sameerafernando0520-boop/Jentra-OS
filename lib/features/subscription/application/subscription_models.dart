final class Plan {
  const Plan({
    required this.id,
    required this.name,
    required this.code,
    required this.priceCents,
    required this.maxMembers,
    required this.maxMonthlyInvoices,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String code;
  final int priceCents;
  final int maxMembers;
  final int maxMonthlyInvoices;
  final bool isActive;
}

final class CompanySubscription {
  const CompanySubscription({
    required this.id,
    required this.companyId,
    required this.planId,
    required this.status,
    required this.currentPeriodStart,
    required this.currentPeriodEnd,
    this.trialEndsAt,
    this.canceledAt,
  });

  final String id;
  final String companyId;
  final String planId;
  final String status;
  final DateTime currentPeriodStart;
  final DateTime currentPeriodEnd;
  final DateTime? trialEndsAt;
  final DateTime? canceledAt;
}

final class EntitlementStatus {
  const EntitlementStatus({
    required this.hasSubscription,
    required this.status,
    required this.isEntitled,
    this.planName,
    this.planCode,
    this.maxMembers,
    this.maxMonthlyInvoices,
    this.currentPeriodEnd,
    this.trialEndsAt,
  });

  final bool hasSubscription;
  final String status;
  final bool isEntitled;
  final String? planName;
  final String? planCode;
  final int? maxMembers;
  final int? maxMonthlyInvoices;
  final DateTime? currentPeriodEnd;
  final DateTime? trialEndsAt;
}

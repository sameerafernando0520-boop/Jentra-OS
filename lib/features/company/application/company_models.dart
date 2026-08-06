/// A company the signed-in user can access through an active membership.
final class Company {
  const Company({
    required this.id,
    required this.ownerUserId,
    required this.name,
    required this.legalName,
    required this.currencyCode,
    required this.countryCode,
    required this.timezone,
    required this.membershipRole,
    required this.isOwner,
    required this.isAdmin,
  });

  final String id;
  final String ownerUserId;
  final String name;
  final String? legalName;
  final String currencyCode;
  final String countryCode;
  final String timezone;
  final String membershipRole;
  final bool isOwner;
  final bool isAdmin;
}

/// Whitelisted values accepted by the company creation flow.
final class CreateCompanyInput {
  const CreateCompanyInput({
    required this.name,
    this.legalName,
    this.currencyCode = 'LKR',
    this.countryCode = 'LK',
    this.timezone = 'Asia/Colombo',
  });

  final String name;
  final String? legalName;
  final String currencyCode;
  final String countryCode;
  final String timezone;
}

/// Read-only settings needed by the initial company settings overview.
final class CompanySettingsOverview {
  const CompanySettingsOverview({
    required this.companyId,
    required this.invoicePrefix,
    required this.quotationPrefix,
    required this.salesOrderPrefix,
    required this.purchaseOrderPrefix,
    required this.billPrefix,
    required this.nextInvoiceNumber,
    required this.nextQuotationNumber,
    required this.nextSalesOrderNumber,
    required this.nextPurchaseOrderNumber,
    required this.nextBillNumber,
    required this.defaultPaymentTermsDays,
  });

  final String companyId;
  final String invoicePrefix;
  final String quotationPrefix;
  final String salesOrderPrefix;
  final String purchaseOrderPrefix;
  final String billPrefix;
  final int nextInvoiceNumber;
  final int nextQuotationNumber;
  final int nextSalesOrderNumber;
  final int nextPurchaseOrderNumber;
  final int nextBillNumber;
  final int defaultPaymentTermsDays;
}

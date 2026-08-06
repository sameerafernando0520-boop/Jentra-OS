import 'package:i_book/features/company/application/company_models.dart';
import 'package:i_book/features/company/application/company_repository.dart';

/// In-memory company boundary used by controller and widget tests.
///
/// It deliberately models repository effects (including persisting the
/// preferred company) without reaching Supabase or requiring mock packages.
final class FakeCompanyRepository implements CompanyRepository {
  FakeCompanyRepository({
    List<Company> companies = const <Company>[],
    this.preferredCompanyId,
    this.companyToCreate,
  }) : companies = List<Company>.of(companies);

  final List<Company> companies;
  final Company? companyToCreate;

  String? preferredCompanyId;
  CreateCompanyInput? lastCreateInput;
  final List<String> savedPreferredCompanyIds = <String>[];

  int listAvailableCompaniesCalls = 0;
  int getPreferredCompanyIdCalls = 0;
  int createCompanyCalls = 0;
  int savePreferredCompanyIdCalls = 0;
  int getCompanySettingsCalls = 0;

  int get totalCalls =>
      listAvailableCompaniesCalls +
      getPreferredCompanyIdCalls +
      createCompanyCalls +
      savePreferredCompanyIdCalls +
      getCompanySettingsCalls;

  @override
  Future<List<Company>> listAvailableCompanies() async {
    listAvailableCompaniesCalls += 1;
    return List<Company>.unmodifiable(companies);
  }

  @override
  Future<String?> getPreferredCompanyId() async {
    getPreferredCompanyIdCalls += 1;
    return preferredCompanyId;
  }

  @override
  Future<Company> createCompany(CreateCompanyInput input) async {
    createCompanyCalls += 1;
    lastCreateInput = input;

    final company =
        companyToCreate ??
        Company(
          id: 'created-company',
          ownerUserId: 'user-1',
          name: input.name.trim(),
          legalName: input.legalName?.trim(),
          currencyCode: input.currencyCode.trim().toUpperCase(),
          countryCode: input.countryCode.trim().toUpperCase(),
          timezone: input.timezone.trim(),
          membershipRole: 'Owner',
          isOwner: true,
          isAdmin: true,
        );

    if (!companies.any((candidate) => candidate.id == company.id)) {
      companies.add(company);
    }
    return company;
  }

  @override
  Future<void> savePreferredCompanyId(String companyId) async {
    savePreferredCompanyIdCalls += 1;
    savedPreferredCompanyIds.add(companyId);
    preferredCompanyId = companyId;
  }

  @override
  Future<CompanySettingsOverview> getCompanySettings(String companyId) async {
    getCompanySettingsCalls += 1;
    return CompanySettingsOverview(
      companyId: companyId,
      invoicePrefix: 'INV',
      quotationPrefix: 'QT',
      salesOrderPrefix: 'SO',
      purchaseOrderPrefix: 'PO',
      billPrefix: 'BILL',
      nextInvoiceNumber: 1,
      nextQuotationNumber: 1,
      nextSalesOrderNumber: 1,
      nextPurchaseOrderNumber: 1,
      nextBillNumber: 1,
      defaultPaymentTermsDays: 14,
    );
  }
}

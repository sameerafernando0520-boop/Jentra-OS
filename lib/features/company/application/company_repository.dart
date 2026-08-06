import 'company_models.dart';

abstract interface class CompanyRepository {
  Future<List<Company>> listAvailableCompanies();

  Future<String?> getPreferredCompanyId();

  Future<Company> createCompany(CreateCompanyInput input);

  Future<void> savePreferredCompanyId(String companyId);

  Future<CompanySettingsOverview> getCompanySettings(String companyId);
}

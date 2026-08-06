import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_models.dart';
import '../../auth/application/auth_state_provider.dart';
import '../data/supabase_company_repository.dart';
import 'company_failure.dart';
import 'company_models.dart';

final companyControllerProvider =
    AsyncNotifierProvider<CompanyController, CompanyState>(
      CompanyController.new,
      retry: (_, _) => null,
    );

/// The selected tenant. Business repositories must require its ID explicitly.
final selectedCompanyProvider = Provider<Company?>((ref) {
  return ref.watch(companyControllerProvider).asData?.value.selectedCompany;
});

/// The mandatory scope for all future business-data queries.
final selectedCompanyIdProvider = Provider<String?>((ref) {
  return ref.watch(selectedCompanyProvider)?.id;
});

final companySettingsProvider = FutureProvider.autoDispose
    .family<CompanySettingsOverview, String>((ref, companyId) async {
      final selectedCompanyId = ref.watch(selectedCompanyIdProvider);
      if (selectedCompanyId == null || selectedCompanyId != companyId) {
        throw const CompanyFailure(
          'Select this company before loading its business settings.',
        );
      }
      return ref.watch(companyRepositoryProvider).getCompanySettings(companyId);
    }, retry: (_, _) => null);

final class CompanyState {
  const CompanyState({
    this.companies = const <Company>[],
    this.selectedCompany,
    this.isSubmitting = false,
  });

  final List<Company> companies;
  final Company? selectedCompany;
  final bool isSubmitting;

  bool get hasCompanies => companies.isNotEmpty;

  CompanyState withSubmitting(bool value) {
    return CompanyState(
      companies: companies,
      selectedCompany: selectedCompany,
      isSubmitting: value,
    );
  }
}

final class CompanyController extends AsyncNotifier<CompanyState> {
  @override
  Future<CompanyState> build() async {
    final session = await ref.watch(authSessionProvider.future);
    return _load(session);
  }

  Future<Company> createCompany(CreateCompanyInput input) async {
    final current = _currentState();
    state = AsyncData(current.withSubmitting(true));

    try {
      final repository = ref.read(companyRepositoryProvider);
      final created = await repository.createCompany(input);
      await repository.savePreferredCompanyId(created.id);

      final companies = await repository.listAvailableCompanies();
      final selected = _findById(companies, created.id) ?? created;
      state = AsyncData(
        CompanyState(companies: companies, selectedCompany: selected),
      );
      return selected;
    } on Object {
      state = AsyncData(current.withSubmitting(false));
      rethrow;
    }
  }

  Future<void> selectCompany(Company company) async {
    final current = _currentState();
    final available = _findById(current.companies, company.id);
    if (available == null) {
      throw const CompanyFailure(
        'This company is not available to your account.',
      );
    }

    state = AsyncData(current.withSubmitting(true));
    try {
      await ref
          .read(companyRepositoryProvider)
          .savePreferredCompanyId(available.id);
      state = AsyncData(
        CompanyState(companies: current.companies, selectedCompany: available),
      );
    } on Object {
      state = AsyncData(current.withSubmitting(false));
      rethrow;
    }
  }

  Future<void> refreshCompanies() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final session = await ref.read(authSessionProvider.future);
      return _load(session);
    });
  }

  Future<CompanyState> _load(AuthSession? session) async {
    if (session == null) return const CompanyState();

    final repository = ref.read(companyRepositoryProvider);
    final companies = await repository.listAvailableCompanies();
    if (companies.isEmpty) return const CompanyState();

    final preferredCompanyId = await repository.getPreferredCompanyId();
    final preferred = preferredCompanyId == null
        ? null
        : _findById(companies, preferredCompanyId);
    if (preferred != null) {
      return CompanyState(companies: companies, selectedCompany: preferred);
    }

    if (companies.length == 1) {
      final onlyCompany = companies.single;
      await repository.savePreferredCompanyId(onlyCompany.id);
      return CompanyState(companies: companies, selectedCompany: onlyCompany);
    }

    // Multiple memberships without a valid stored preference require an
    // explicit selection before any business module is allowed to query.
    return CompanyState(companies: companies);
  }

  CompanyState _currentState() {
    return state.asData?.value ?? const CompanyState();
  }

  Company? _findById(List<Company> companies, String id) {
    for (final company in companies) {
      if (company.id == id) return company;
    }
    return null;
  }
}

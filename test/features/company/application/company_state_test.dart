import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_book/features/auth/application/auth_models.dart';
import 'package:i_book/features/auth/application/auth_state_provider.dart';
import 'package:i_book/features/company/application/company_failure.dart';
import 'package:i_book/features/company/application/company_models.dart';
import 'package:i_book/features/company/application/company_state.dart';
import 'package:i_book/features/company/data/supabase_company_repository.dart';

import '../fake_company_repository.dart';

void main() {
  const firstCompany = Company(
    id: 'company-1',
    ownerUserId: 'user-1',
    name: 'Acme Trading',
    legalName: 'Acme Trading (Pvt) Ltd',
    currencyCode: 'LKR',
    countryCode: 'LK',
    timezone: 'Asia/Colombo',
    membershipRole: 'Owner',
    isOwner: true,
    isAdmin: true,
  );
  const secondCompany = Company(
    id: 'company-2',
    ownerUserId: 'user-2',
    name: 'Coastal Supplies',
    legalName: null,
    currencyCode: 'USD',
    countryCode: 'LK',
    timezone: 'Asia/Colombo',
    membershipRole: 'Admin',
    isOwner: false,
    isAdmin: true,
  );

  test('signed-out state is empty and never calls the repository', () async {
    final repository = FakeCompanyRepository(companies: const [firstCompany]);
    final container = _createContainer(repository: repository, session: null);
    addTearDown(container.dispose);

    final state = await container.read(companyControllerProvider.future);

    expect(state.companies, isEmpty);
    expect(state.selectedCompany, isNull);
    expect(container.read(selectedCompanyProvider), isNull);
    expect(container.read(selectedCompanyIdProvider), isNull);
    expect(repository.totalCalls, 0);
  });

  test(
    'a sole active company is selected and persisted automatically',
    () async {
      final repository = FakeCompanyRepository(companies: const [firstCompany]);
      final container = _createContainer(
        repository: repository,
        session: _signedInSession,
      );
      addTearDown(container.dispose);

      final state = await container.read(companyControllerProvider.future);

      expect(state.companies, const [firstCompany]);
      expect(state.selectedCompany, same(firstCompany));
      expect(container.read(selectedCompanyIdProvider), firstCompany.id);
      expect(repository.savedPreferredCompanyIds, [firstCompany.id]);
      expect(repository.preferredCompanyId, firstCompany.id);
      expect(repository.listAvailableCompaniesCalls, 1);
      expect(repository.getPreferredCompanyIdCalls, 1);
    },
  );

  test(
    'multiple companies without a preferred ID require explicit selection',
    () async {
      final repository = FakeCompanyRepository(
        companies: const [firstCompany, secondCompany],
      );
      final container = _createContainer(
        repository: repository,
        session: _signedInSession,
      );
      addTearDown(container.dispose);

      final state = await container.read(companyControllerProvider.future);

      expect(state.companies, const [firstCompany, secondCompany]);
      expect(state.selectedCompany, isNull);
      expect(container.read(selectedCompanyIdProvider), isNull);
      expect(repository.savePreferredCompanyIdCalls, 0);
    },
  );

  test('selectCompany persists and exposes the chosen company ID', () async {
    final repository = FakeCompanyRepository(
      companies: const [firstCompany, secondCompany],
    );
    final container = _createContainer(
      repository: repository,
      session: _signedInSession,
    );
    addTearDown(container.dispose);
    await container.read(companyControllerProvider.future);

    await container
        .read(companyControllerProvider.notifier)
        .selectCompany(secondCompany);

    final state = container.read(companyControllerProvider).asData?.value;
    expect(state?.selectedCompany, same(secondCompany));
    expect(container.read(selectedCompanyProvider), same(secondCompany));
    expect(container.read(selectedCompanyIdProvider), secondCompany.id);
    expect(repository.savedPreferredCompanyIds, [secondCompany.id]);
  });

  test(
    'createCompany selects and persists the newly created company',
    () async {
      const createdCompany = Company(
        id: 'company-created',
        ownerUserId: 'user-1',
        name: 'New Ventures',
        legalName: 'New Ventures (Pvt) Ltd',
        currencyCode: 'LKR',
        countryCode: 'LK',
        timezone: 'Asia/Colombo',
        membershipRole: 'Owner',
        isOwner: true,
        isAdmin: true,
      );
      const input = CreateCompanyInput(
        name: 'New Ventures',
        legalName: 'New Ventures (Pvt) Ltd',
      );
      final repository = FakeCompanyRepository(companyToCreate: createdCompany);
      final container = _createContainer(
        repository: repository,
        session: _signedInSession,
      );
      addTearDown(container.dispose);
      await container.read(companyControllerProvider.future);

      final created = await container
          .read(companyControllerProvider.notifier)
          .createCompany(input);

      expect(created, same(createdCompany));
      expect(repository.lastCreateInput, same(input));
      expect(repository.savedPreferredCompanyIds, [createdCompany.id]);
      expect(container.read(selectedCompanyProvider), same(createdCompany));
      expect(container.read(selectedCompanyIdProvider), createdCompany.id);
      expect(repository.listAvailableCompaniesCalls, 2);
    },
  );

  test(
    'company settings fail closed without a selected company or repo call',
    () async {
      final repository = FakeCompanyRepository(companies: const [firstCompany]);
      final container = ProviderContainer(
        overrides: [
          selectedCompanyProvider.overrideWithValue(null),
          companyRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final settings = companySettingsProvider(firstCompany.id);
      final subscription = container.listen(settings, (previous, next) {});
      addTearDown(subscription.close);

      await expectLater(
        container.read(settings.future),
        throwsA(
          isA<CompanyFailure>().having(
            (failure) => failure.userMessage,
            'userMessage',
            'Select this company before loading its business settings.',
          ),
        ),
      );
      expect(repository.getCompanySettingsCalls, 0);
    },
  );
}

const _signedInSession = AuthSession(
  userId: 'user-1',
  email: 'owner@example.com',
);

ProviderContainer _createContainer({
  required FakeCompanyRepository repository,
  required AuthSession? session,
}) {
  return ProviderContainer(
    overrides: [
      authSessionProvider.overrideWithValue(AsyncData(session)),
      companyRepositoryProvider.overrideWithValue(repository),
    ],
  );
}

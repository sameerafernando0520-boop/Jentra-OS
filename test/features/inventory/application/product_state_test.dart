import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_os/features/company/application/company_models.dart';
import 'package:jentra_os/features/company/application/company_state.dart';
import 'package:jentra_os/features/inventory/application/inventory_failure.dart';
import 'package:jentra_os/features/inventory/application/product_models.dart';
import 'package:jentra_os/features/inventory/application/product_state.dart';
import 'package:jentra_os/features/inventory/data/supabase_product_repository.dart';

import '../fake_inventory_repositories.dart';

void main() {
  const company1 = Company(
    id: 'comp-1',
    ownerUserId: 'user-1',
    name: 'Acme Corp',
    legalName: 'Acme Corp LLC',
    currencyCode: 'USD',
    countryCode: 'US',
    timezone: 'UTC',
    membershipRole: 'Owner',
    isOwner: true,
    isAdmin: true,
  );

  final sampleProduct = Product(
    id: 'prod-1',
    companyId: 'comp-1',
    name: 'Wireless Mouse',
    unitPrice: 29.99,
    costPrice: 15.00,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  group('ProductState & ProductController', () {
    test('missing selected company throws InventoryFailure', () async {
      final fakeRepo = FakeProductRepository();
      final container = ProviderContainer(
        overrides: [
          productRepositoryProvider.overrideWithValue(fakeRepo),
          selectedCompanyIdProvider.overrideWith((ref) => null),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(productControllerProvider.future),
        throwsA(isA<InventoryFailure>()),
      );
    });

    test('lists products using selected company ID scope', () async {
      final fakeRepo = FakeProductRepository(products: [sampleProduct]);
      final container = ProviderContainer(
        overrides: [
          productRepositoryProvider.overrideWithValue(fakeRepo),
          selectedCompanyIdProvider.overrideWith((ref) => 'comp-1'),
        ],
      );
      addTearDown(container.dispose);

      final state = await container.read(productControllerProvider.future);
      expect(state.companyId, equals('comp-1'));
      expect(state.products, hasLength(1));
      expect(state.products.first.name, equals('Wireless Mouse'));
    });

    test('create product injects selected company ID scope', () async {
      final fakeRepo = FakeProductRepository();
      final container = ProviderContainer(
        overrides: [
          productRepositoryProvider.overrideWithValue(fakeRepo),
          selectedCompanyProvider.overrideWith((ref) => company1),
          selectedCompanyIdProvider.overrideWith((ref) => 'comp-1'),
        ],
      );
      addTearDown(container.dispose);

      const input = ProductInput(
        name: 'USB Cable',
        unitPrice: 9.99,
        costPrice: 2.50,
      );

      final created = await container
          .read(productMutationProvider.notifier)
          .createProduct(input);

      expect(created.companyId, equals('comp-1'));
      expect(created.name, equals('USB Cable'));
      expect(fakeRepo.createCompanyIds, contains('comp-1'));
    });
  });
}

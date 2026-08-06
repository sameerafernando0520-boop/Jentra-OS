import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_os/features/company/application/company_models.dart';
import 'package:jentra_os/features/company/application/company_state.dart';
import 'package:jentra_os/features/inventory/application/inventory_models.dart';
import 'package:jentra_os/features/inventory/application/product_models.dart';
import 'package:jentra_os/features/inventory/data/supabase_inventory_repository.dart';
import 'package:jentra_os/features/inventory/data/supabase_product_repository.dart';
import 'package:jentra_os/features/inventory/presentation/screens/create_product_screen.dart';
import 'package:jentra_os/features/inventory/presentation/screens/product_detail_screen.dart';
import 'package:jentra_os/features/inventory/presentation/screens/product_list_screen.dart';
import 'package:jentra_os/features/inventory/presentation/screens/stock_overview_screen.dart';
import 'package:jentra_os/features/inventory/presentation/screens/warehouse_list_screen.dart';

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
    sku: 'WM-100',
    unitPrice: 29.99,
    costPrice: 15.00,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  final sampleWarehouse = Warehouse(
    id: 'wh-1',
    companyId: 'comp-1',
    name: 'Main Warehouse',
    code: 'WH-MAIN',
    isDefault: true,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  Widget buildTestWidget(Widget child, {
    FakeProductRepository? fakeProductRepo,
    FakeInventoryRepository? fakeInventoryRepo,
  }) {
    final productRepo = fakeProductRepo ?? FakeProductRepository(products: [sampleProduct]);
    final inventoryRepo = fakeInventoryRepo ?? FakeInventoryRepository(warehouses: [sampleWarehouse]);

    return ProviderScope(
      overrides: [
        productRepositoryProvider.overrideWithValue(productRepo),
        inventoryRepositoryProvider.overrideWithValue(inventoryRepo),
        selectedCompanyProvider.overrideWith((ref) => company1),
        selectedCompanyIdProvider.overrideWith((ref) => 'comp-1'),
      ],
      child: MaterialApp(home: child),
    );
  }

  group('Inventory Screens UI Tests', () {
    testWidgets('ProductListScreen renders product items for selected company', (tester) async {
      await tester.pumpWidget(buildTestWidget(const ProductListScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Products - Acme Corp'), findsOneWidget);
      expect(find.text('Wireless Mouse'), findsOneWidget);
      expect(find.textContaining('SKU: WM-100'), findsOneWidget);
    });

    testWidgets('ProductDetailScreen renders product detail information', (tester) async {
      await tester.pumpWidget(buildTestWidget(const ProductDetailScreen(productId: 'prod-1')));
      await tester.pumpAndSettle();

      expect(find.text('Product Details'), findsOneWidget);
      expect(find.text('Wireless Mouse'), findsOneWidget);
      expect(find.text('\$29.99 / pcs'), findsOneWidget);
    });

    testWidgets('CreateProductScreen exposes validated input fields', (tester) async {
      await tester.pumpWidget(buildTestWidget(const CreateProductScreen()));
      await tester.pumpAndSettle();

      expect(find.text('New Product'), findsOneWidget);
      expect(find.text('Product Name *'), findsOneWidget);
      expect(find.text('Selling Price *'), findsOneWidget);
    });

    testWidgets('WarehouseListScreen renders warehouse list items', (tester) async {
      await tester.pumpWidget(buildTestWidget(const WarehouseListScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Warehouses - Acme Corp'), findsOneWidget);
      expect(find.text('Main Warehouse'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);
    });

    testWidgets('StockOverviewScreen renders stock view for company', (tester) async {
      await tester.pumpWidget(buildTestWidget(const StockOverviewScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Stock Overview - Acme Corp'), findsOneWidget);
    });
  });
}

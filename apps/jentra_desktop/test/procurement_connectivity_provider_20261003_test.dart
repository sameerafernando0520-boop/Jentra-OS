import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/procurement/procurement_controller.dart';
import 'package:jentra_desktop/src/features/procurement/sourcing_controller.dart';
import 'package:jentra_desktop/src/features/procurement/purchase_order_controller.dart';
import 'package:jentra_desktop/src/features/procurement/goods_receipt_controller.dart';
import 'package:jentra_desktop/src/features/procurement/supplier_bill_controller.dart';
import 'package:jentra_desktop/src/features/procurement/supplier_payment_controller.dart';
import 'package:jentra_desktop/src/features/procurement/product_unit_controller.dart';
import 'package:jentra_desktop/src/features/procurement/purchase_return_controller.dart';

import 'security_second_procurement_failure_epoch_test.dart'
    show gatewayFor, modules;
import 'security_review_procurement_sealing_test.dart' show scope, slot;
import 'support/procurement_fakes.dart' show Keys;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const permissions = {
    'procurement.requisitions.manage',
    'procurement.rfq.manage',
    'procurement.orders.manage',
    'procurement.receipts.post',
    'procurement.receipts.manage',
    'procurement.bills.manage',
    'procurement.bills.post',
    'finance.payments.manage',
    'finance.payments.post',
    'inventory.catalog.manage',
    'procurement.returns.post',
    'workflow.approvals.decide',
  };
  const verified = AsyncData(ConnectivityState.online);
  for (final name in modules) {
    for (final problem in ['loading', 'error']) {
      for (final initial in [false, true]) {
        test(
          '$name retained-online $problem ${initial ? 'initial' : 'transition'} closes server access and keeps encrypted inputs',
          () async {
            final db = JentraLocalDatabase(NativeDatabase.memory());
            final repository = EncryptedDraftRepository(
              db,
              DraftCipher(keyStore: Keys()),
            );
            final drafts = QuotationDraftStore.procurement(repository);
            final input = <String, Object?>{
              'id': 'original-private-local-input',
              'reason': 'Exact local input 9007199254.740993',
              'lines': <Map<String, Object?>>[],
            };
            await drafts.save(scope, slot(name), input);
            final dynamic gateway = gatewayFor(name);
            final ProcurementGateway scopedGateway = gateway;
            // These calls intentionally construct Riverpod's retained-data
            // states used by actual provider reload and error transitions.
            const loadingState = AsyncLoading<ConnectivityState>();
            // ignore: invalid_use_of_internal_member
            final loading = loadingState.copyWithPrevious(verified);
            final error = AsyncError<ConnectivityState>(
              StateError('Private transport error'),
              StackTrace.current,
            );
            // ignore: invalid_use_of_internal_member
            final failed = error.copyWithPrevious(verified);
            final unverified = problem == 'loading' ? loading : failed;
            expect(unverified.value, ConnectivityState.online);
            expect(unverified.isLoading || unverified.hasError, isTrue);
            AsyncValue<ConnectivityState> network = initial
                ? unverified
                : verified;
            final container = ProviderContainer(
              overrides: [
                activeTenantContextProvider.overrideWithValue(scope),
                businessCapabilitiesProvider.overrideWithValue(
                  const AsyncData(permissions),
                ),
                procurementGatewayProvider.overrideWithValue(scopedGateway),
                encryptedDraftRepositoryProvider.overrideWithValue(repository),
                connectivityStateProvider.overrideWithValue(network),
              ],
            );
            final subscription = switch (name) {
              'requisition' => container.listen<ProcurementController?>(
                procurementControllerProvider,
                (_, _) {},
              ),
              'sourcing' => container.listen<SourcingController?>(
                sourcingControllerProvider,
                (_, _) {},
              ),
              'order' => container.listen<PurchaseOrderController?>(
                purchaseOrderControllerProvider,
                (_, _) {},
              ),
              'receipt' => container.listen<GoodsReceiptController?>(
                goodsReceiptControllerProvider,
                (_, _) {},
              ),
              'bill' => container.listen<SupplierBillController?>(
                supplierBillControllerProvider,
                (_, _) {},
              ),
              'payment' => container.listen<SupplierPaymentController?>(
                supplierPaymentControllerProvider,
                (_, _) {},
              ),
              'unit' => container.listen<ProductUnitController?>(
                productUnitControllerProvider,
                (_, _) {},
              ),
              _ => container.listen<PurchaseReturnController?>(
                purchaseReturnControllerProvider,
                (_, _) {},
              ),
            };
            try {
              final dynamic c = subscription.read();
              expect(c, isNotNull);
              for (var i = 0; i < 1000 && c.busy == true; i++) {
                await Future<void>.delayed(const Duration(milliseconds: 1));
              }
              expect(c.busy, isFalse);
              expect(jsonEncode(c.form), jsonEncode(input));
              final int? origin = name == 'return'
                  ? null
                  : c.readAccessEpoch as int;
              if (!initial) {
                expect(c.online, isTrue);
                c.page = CursorPage<Map<String, Object?>>(
                  items: [
                    {
                      'id': 'private-register',
                      'document_number': 'PRIVATE-SERVER-42',
                    },
                  ],
                  limit: 50,
                );
                network = unverified;
                container.updateOverrides([
                  activeTenantContextProvider.overrideWithValue(scope),
                  businessCapabilitiesProvider.overrideWithValue(
                    const AsyncData(permissions),
                  ),
                  procurementGatewayProvider.overrideWithValue(scopedGateway),
                  encryptedDraftRepositoryProvider.overrideWithValue(
                    repository,
                  ),
                  connectivityStateProvider.overrideWithValue(network),
                ]);
                container.read(connectivityStateProvider);
                await Future<void>.delayed(Duration.zero);
              }
              expect(c.online, isFalse);
              expect(c.page.items, isEmpty);
              if (origin != null) expect(c.currentRead(origin), isFalse);
              expect(jsonEncode(c.form), jsonEncode(input));
              expect(
                jsonEncode((await drafts.load(scope, slot(name)))!.form),
                jsonEncode(input),
              );
              expect(gateway.commands, isEmpty);
              if (initial) expect(gateway.state.called, isFalse);
              container.updateOverrides([
                activeTenantContextProvider.overrideWithValue(scope),
                businessCapabilitiesProvider.overrideWithValue(
                  const AsyncData(permissions),
                ),
                procurementGatewayProvider.overrideWithValue(scopedGateway),
                encryptedDraftRepositoryProvider.overrideWithValue(repository),
                connectivityStateProvider.overrideWithValue(verified),
              ]);
              container.read(connectivityStateProvider);
              await Future<void>.delayed(Duration.zero);
              expect(c.online, isTrue);
              if (origin != null) expect(c.currentRead(origin), isFalse);
              if (origin != null) {
                expect(c.currentRead(c.readAccessEpoch), isTrue);
              }
              expect(jsonEncode(c.form), jsonEncode(input));
              expect(c.page.items, isEmpty);
            } finally {
              subscription.close();
              container.dispose();
              await db.close();
            }
          },
        );
      }
    }
  }
}

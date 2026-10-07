import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/sales/quotation_controller.dart';
import 'package:jentra_desktop/src/features/sales/sales_order_controller.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

import 'quotation_controller_test.dart' as q;
import 'sales_order_controller_test.dart' as o;

class _ColdKeys implements SecretKeyStore {
  _ColdKeys(this.original);
  final q.MemoryKeys original;
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<String?> read(String key) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return original.read(key);
  }

  @override
  Future<void> write(String key, String value) => original.write(key, value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final orders in [false, true]) {
    for (final change in [
      'current',
      'offline pulse',
      'retained loading',
      'retained error',
      'ack pulse',
    ]) {
      test(
        '${orders ? 'order' : 'quotation'} cold recovery observes $change before transport',
        () async {
          final database = JentraLocalDatabase(NativeDatabase.memory());
          final keys = q.MemoryKeys();
          QuotationDraftStore makeStore(SecretKeyStore secret) {
            final drafts = EncryptedDraftRepository(
              database,
              DraftCipher(keyStore: secret),
            );
            return orders
                ? QuotationDraftStore.orders(drafts)
                : QuotationDraftStore(drafts);
          }

          var store = makeStore(keys);
          AsyncValue<ConnectivityState> connection = const AsyncData(
            ConnectivityState.online,
          );
          final quotations = q.FakeQuotations(),
              orderRepository = o.FakeOrders();
          overrides() => [
            activeTenantContextProvider.overrideWithValue(q.scope),
            businessCapabilitiesProvider.overrideWithValue(
              AsyncData(orders ? o.permissions : q.permissions),
            ),
            connectivityStateProvider.overrideWithValue(connection),
            quotationWorkspaceRepositoryProvider.overrideWithValue(quotations),
            leadToCashRepositoryProvider.overrideWithValue(quotations),
            salesOrderRepositoryProvider.overrideWithValue(orderRepository),
            quotationDraftStoreProvider.overrideWithValue(store),
            salesOrderDraftStoreProvider.overrideWithValue(store),
          ];
          final container = ProviderContainer(
            retry: (_, _) => null,
            overrides: overrides(),
          );
          final connectionSubscription = container.listen(
            connectivityStateProvider,
            (_, _) {},
            fireImmediately: true,
          );
          final workspaceSubscription = orders
              ? container.listen(
                  salesOrderProvider,
                  (_, _) {},
                  fireImmediately: true,
                )
              : container.listen(
                  quotationWorkspaceProvider,
                  (_, _) {},
                  fireImmediately: true,
                );
          addTearDown(() async {
            workspaceSubscription.close();
            connectionSubscription.close();
            container.dispose();
            await database.close();
          });
          Future<void> save() => orders
              ? container.read(salesOrderProvider.notifier).save()
              : container.read(quotationWorkspaceProvider.notifier).save();
          if (orders) {
            await container.read(salesOrderProvider.future);
            await container.read(salesOrderProvider.notifier).newDraft();
            await container
                .read(salesOrderProvider.notifier)
                .updateForm(o.orderForm());
          } else {
            await container.read(quotationWorkspaceProvider.future);
            await container
                .read(quotationWorkspaceProvider.notifier)
                .newDraft();
            await container
                .read(quotationWorkspaceProvider.notifier)
                .updateForm(q.form());
          }
          // A fresh cipher must really enter key recovery; memoized warm keys
          // cannot establish an asynchronous encryption/recovery boundary.
          final coldKeys = _ColdKeys(keys);
          store = makeStore(coldKeys);
          container.updateOverrides(overrides());
          final work = save();
          await coldKeys.entered.future.timeout(const Duration(seconds: 5));
          void publish(AsyncValue<ConnectivityState> next) {
            connection = next;
            container.updateOverrides(overrides());
            container.read(connectivityStateProvider);
          }

          if (change == 'offline pulse') {
            publish(const AsyncData(ConnectivityState.offline));
          } else if (change == 'retained loading') {
            publish(
              // Preserve prior online data to reproduce Riverpod's retained state.
              // ignore: invalid_use_of_internal_member
              const AsyncLoading<ConnectivityState>().copyWithPrevious(
                const AsyncData(ConnectivityState.online),
              ),
            );
          } else if (change == 'retained error') {
            publish(
              AsyncError<ConnectivityState>(
                StateError('connection unknown'),
                StackTrace.current,
                // Preserve prior online data to exercise the error-with-value guard.
                // ignore: invalid_use_of_internal_member
              ).copyWithPrevious(const AsyncData(ConnectivityState.online)),
            );
          }
          if (change != 'current') {
            publish(const AsyncData(ConnectivityState.online));
          }
          if (change == 'ack pulse') {
            void pulse() {
              publish(const AsyncData(ConnectivityState.offline));
              publish(const AsyncData(ConnectivityState.online));
            }

            quotations.onCommand = (_) async {
              pulse();
              return CommandResult.success(
                requestId: 'ack',
                entity: q.quotation(),
              );
            };
            orderRepository.onCommand = (_, _) async {
              pulse();
              return CommandResult.success(
                requestId: 'ack',
                entity: orderRepository.detail.order,
              );
            };
          }
          coldKeys.release.complete();
          await work;
          expect(
            orders
                ? orderRepository.commands.length
                : quotations.commands.length,
            change == 'current' || change == 'ack pulse' ? 1 : 0,
          );
          if (change == 'ack pulse') {
            expect(await store.load(q.scope, 'new'), isNull);
            expect(
              orders
                  ? container.read(salesOrderProvider).requireValue.form
                  : container
                        .read(quotationWorkspaceProvider)
                        .requireValue
                        .form,
              isNull,
            );
            await save();
            expect(
              orders
                  ? orderRepository.commands.length
                  : quotations.commands.length,
              1,
            );
          } else if (change != 'current') {
            final retained = await store.load(q.scope, 'new');
            expect(retained, isNotNull);
            expect(retained!.form['customer_id'], 'customer');
            final code = orders
                ? container.read(salesOrderProvider).requireValue.error?.code
                : container
                      .read(quotationWorkspaceProvider)
                      .requireValue
                      .error
                      ?.code;
            expect(code, 'ACCESS_CHANGED');
            // Restoration needs a new explicit attempt; it cannot revive the
            // paused attempt. This also verifies the recovery remains usable.
            await save();
            expect(
              orders
                  ? orderRepository.commands.length
                  : quotations.commands.length,
              1,
            );
            expect(await store.load(q.scope, 'new'), isNull);
          }
        },
      );
    }
  }
}

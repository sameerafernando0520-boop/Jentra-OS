import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/operations/operational_read_access.dart';
import 'package:jentra_desktop/src/features/stock_count/stock_count_controller.dart';
import 'package:jentra_desktop/src/features/disposition/disposition_controller.dart';
import 'package:jentra_desktop/src/features/landed_extension/landed_extension_controller.dart';
import 'package:jentra_desktop/src/features/control_reconciliation/control_reconciliation_controller.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_domain/jentra_domain.dart';

import 'support/procurement_fakes.dart' show Keys;
import 'inventory_control_dialog_access_20261003_test.dart' show scope;
import 'stock_count_workspace_test.dart' as count;
import 'disposition_workspace_test.dart' as disposition;
import 'landed_extension_workspace_test.dart' as landed;
import 'control_reconciliation_workspace_test.dart' as control;

OperationalReadAccess accessOf(dynamic controller) =>
    controller as OperationalReadAccess;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final kind in ['count', 'disposition', 'landed', 'control']) {
    for (final change in ['loading', 'error']) {
      for (final phase in ['entry', 'notification']) {
        test(
          '$kind provider $change at $phase closes retained-online server access',
          () async {
            final db = JentraLocalDatabase(NativeDatabase.memory());
            final encrypted = EncryptedDraftRepository(
              db,
              DraftCipher(keyStore: Keys()),
            );
            final counts = count.Counts(),
                dispositions = disposition.Dispositions();
            final landeds = landed.Landed(), controls = control.Gateway();
            const online = AsyncData(ConnectivityState.online);
            final uncertain = change == 'loading'
                // Deliberately reproduce Riverpod's retained-data uncertain state.
                // ignore: invalid_use_of_internal_member
                ? const AsyncLoading<ConnectivityState>().copyWithPrevious(
                    online,
                  )
                : AsyncError<ConnectivityState>(
                    StateError('Connection observation failed'),
                    StackTrace.current,
                    // Deliberately retain old online data while observing failure.
                    // ignore: invalid_use_of_internal_member
                  ).copyWithPrevious(online);
            expect(uncertain.value, ConnectivityState.online);
            expect(uncertain.isLoading || uncertain.hasError, isTrue);
            overrides(AsyncValue<ConnectivityState> state) => [
              activeTenantContextProvider.overrideWithValue(scope),
              encryptedDraftRepositoryProvider.overrideWithValue(encrypted),
              businessCapabilitiesProvider.overrideWithValue(
                const AsyncData({
                  'inventory.cost.view',
                  'inventory.valuation.post',
                  'inventory.adjustments.post',
                  'inventory.dispositions.post',
                  'finance.view',
                  'finance.controls.reconcile',
                  'finance.receipts.reverse',
                }),
              ),
              connectivityStateProvider.overrideWithValue(state),
              stockCountGatewayProvider.overrideWithValue(counts),
              dispositionGatewayProvider.overrideWithValue(dispositions),
              landedExtensionGatewayProvider.overrideWithValue(landeds),
              controlReconciliationGatewayProvider.overrideWithValue(controls),
            ];
            final container = ProviderContainer(
              overrides: overrides(phase == 'entry' ? uncertain : online),
            );
            final provider = switch (kind) {
              'count' => stockCountControllerProvider,
              'disposition' => dispositionControllerProvider,
              'landed' => landedExtensionControllerProvider,
              _ => controlReconciliationControllerProvider,
            };
            final subscription = container.listen(provider, (_, next) {});
            addTearDown(() async {
              subscription.close();
              container.dispose();
              await db.close();
            });
            final dynamic controller = container.read(provider);
            expect(controller, isNotNull);
            final access = accessOf(controller);
            final retained = QuotationDraftStore(encrypted);
            await retained.save(scope, 'connection-sentinel', {
              'reason': 'Original encrypted input',
            }, expectedVersion: 0);
            for (var i = 0; i < 100 && controller.busy == true; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 5));
            }
            final epoch = access.readAccessEpoch;
            if (phase == 'notification') {
              expect(access.currentRead(epoch), isTrue);
              if (access is StockCountController) {
                access.items = [
                  {'id': 'private-row'},
                ];
              }
              if (access is DispositionController) {
                access.items = [
                  {'id': 'private-row'},
                ];
              }
              if (access is LandedExtensionController) {
                access.preview = {'amount': 'private-value'};
              }
              if (access is ControlReconciliationController) {
                access.summary = {'difference': 'private-value'};
              }
              container.updateOverrides(overrides(uncertain));
              await container.pump();
            }
            expect(controller.online, isFalse);
            expect(access.currentRead(epoch), isFalse);
            if (access is StockCountController) {
              expect(access.items, isEmpty);
            }
            if (access is DispositionController) {
              expect(access.items, isEmpty);
            }
            if (access is LandedExtensionController) {
              expect(access.preview, isNull);
            }
            if (access is ControlReconciliationController) {
              expect(access.summary, isEmpty);
            }
            expect(
              (await retained.load(
                scope,
                'connection-sentinel',
              ))!.form['reason'],
              'Original encrypted input',
            );
          },
        );
      }
    }
  }
}

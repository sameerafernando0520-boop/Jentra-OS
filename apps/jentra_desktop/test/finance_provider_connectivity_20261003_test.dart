import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/manual_journal/manual_journal_controller.dart';
import 'package:jentra_desktop/src/features/period_fx/period_fx_controller.dart';
import 'package:jentra_desktop/src/features/bank_reconciliation/bank_reconciliation_controller.dart';
import 'package:jentra_desktop/src/features/operations/operational_read_access.dart';

import 'manual_journal_workspace_test.dart' show JournalGateway;
import 'period_fx_workspace_test.dart' show PeriodFxFake;
import 'bank_reconciliation_workspace_test.dart' show BankFake;
import 'support/procurement_fakes.dart' show Keys;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  for (final feature in ['journal', 'period', 'bank']) {
    for (final state in ['loading', 'error']) {
      for (final initial in [true, false]) {
        test(
          '$feature provider fails closed on retained online $state ${initial ? 'entry' : 'transition'}',
          () async {
            final db = JentraLocalDatabase(NativeDatabase.memory());
            final repository = EncryptedDraftRepository(
              db,
              DraftCipher(keyStore: Keys()),
            );
            final drafts = QuotationDraftStore(repository);
            final slot = switch (feature) {
              'journal' => ManualJournalController.slot,
              'period' => PeriodFxController.slot,
              _ => BankReconciliationController.slot,
            };
            await drafts.save(scope, slot, {
              'reason': 'Encrypted retained input',
            });
            final previous = const AsyncData(ConnectivityState.online);
            final uncertain = state == 'loading'
                // Model Riverpod cached data retained during a failed or loading refresh.
                // ignore: invalid_use_of_internal_member
                ? const AsyncLoading<ConnectivityState>().copyWithPrevious(
                    previous,
                  )
                : AsyncError<ConnectivityState>(
                    StateError('connection refresh failed'),
                    StackTrace.current,
                    // Model Riverpod cached data retained during a failed or loading refresh.
                    // ignore: invalid_use_of_internal_member
                  ).copyWithPrevious(previous);
            expect(uncertain.value, ConnectivityState.online);
            expect(uncertain.isLoading || uncertain.hasError, isTrue);
            final journal = JournalGateway();
            final period = PeriodFxFake();
            final bank = BankFake();
            overrides(AsyncValue<ConnectivityState> connection) => [
              activeTenantContextProvider.overrideWithValue(scope),
              businessCapabilitiesProvider.overrideWithValue(
                const AsyncData<Set<String>>({'finance.view'}),
              ),
              connectivityStateProvider.overrideWithValue(connection),
              encryptedDraftRepositoryProvider.overrideWithValue(repository),
              manualJournalGatewayProvider.overrideWithValue(journal),
              periodFxGatewayProvider.overrideWithValue(period),
              bankReconciliationGatewayProvider.overrideWithValue(bank),
            ];
            final container = ProviderContainer(
              overrides: overrides(initial ? uncertain : previous),
            );
            final subscription = switch (feature) {
              'journal' => container.listen<ManualJournalController?>(
                manualJournalControllerProvider,
                (_, next) {},
              ),
              'period' => container.listen<PeriodFxController?>(
                periodFxControllerProvider,
                (_, next) {},
              ),
              _ => container.listen<BankReconciliationController?>(
                bankReconciliationControllerProvider,
                (_, next) {},
              ),
            };
            dynamic readController() => switch (feature) {
              'journal' => container.read(manualJournalControllerProvider),
              'period' => container.read(periodFxControllerProvider),
              _ => container.read(bankReconciliationControllerProvider),
            };
            try {
              final dynamic controller = readController();
              expect(controller, isNotNull);
              for (var i = 0; i < 200 && controller.busy == true; i++) {
                await Future<void>.delayed(const Duration(milliseconds: 2));
              }
              expect(controller.busy, false);
              OperationalReadAccess accessOf(dynamic value) =>
                  value as OperationalReadAccess;
              final access = accessOf(controller);
              final originalEpoch = access.readAccessEpoch;
              if (!initial) {
                expect(controller.online, true);
                container.updateOverrides(overrides(uncertain));
                await container.pump();
                expect(identical(readController(), controller), true);
              }
              expect(controller.online, false);
              expect(access.currentRead(originalEpoch), false);
              expect(
                (await drafts.load(scope, slot))?.form['reason'],
                'Encrypted retained input',
              );
              container.updateOverrides(overrides(previous));
              await container.pump();
              expect(identical(readController(), controller), true);
              expect(controller.online, true);
              if (!initial) expect(access.currentRead(originalEpoch), false);
              expect(
                (await drafts.load(scope, slot))?.form['reason'],
                'Encrypted retained input',
              );
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

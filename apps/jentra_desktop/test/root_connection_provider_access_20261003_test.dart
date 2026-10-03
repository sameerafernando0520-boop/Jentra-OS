import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/landed_value/landed_value_controller.dart';
import 'package:jentra_desktop/src/features/receivables/receivables_controller.dart';
import 'package:jentra_desktop/src/features/reservations/reservation_controller.dart';
import 'package:jentra_domain/jentra_domain.dart' show ConnectivityState;
import 'package:jentra_platform/jentra_platform.dart';

import 'landed_value_workspace_test.dart' show LandedGateway;
import 'receivables_controller_test.dart' as ar;
import 'reservation_workspace_test.dart' show Reservations;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final module in ['landed', 'reservation', 'AR']) {
    for (final failure in ['loading', 'error']) {
      for (final phase in ['entry', 'notification']) {
        test('$module rejects retained online $failure at $phase', () async {
          final db = JentraLocalDatabase(NativeDatabase.memory());
          final repository = EncryptedDraftRepository(
            db,
            DraftCipher(keyStore: ar.MemoryKeys()),
          );
          const online = AsyncData(ConnectivityState.online);
          final uncertain = failure == 'loading'
              // Model Riverpod's cached prior value during a connection refresh.
              // ignore: invalid_use_of_internal_member
              ? const AsyncLoading<ConnectivityState>().copyWithPrevious(online)
              : AsyncError<ConnectivityState>(
                  StateError('connection unavailable'),
                  StackTrace.current,
                  // Model cached data retained alongside a real provider failure.
                  // ignore: invalid_use_of_internal_member
                ).copyWithPrevious(online);
          expect(uncertain.value, ConnectivityState.online);
          expect(uncertain.isLoading || uncertain.hasError, true);
          final capabilities = {
            ...ar.permissions,
            'inventory.reservations.manage',
            'inventory.cost.view',
            'inventory.valuation.post',
          };
          final landed = LandedGateway();
          final reservations = Reservations();
          final receivables = ar.FakeReceivables();
          overrides(AsyncValue<ConnectivityState> state) => [
            activeTenantContextProvider.overrideWithValue(ar.scope),
            businessCapabilitiesProvider.overrideWithValue(
              AsyncData(capabilities),
            ),
            encryptedDraftRepositoryProvider.overrideWithValue(repository),
            landedValueGatewayProvider.overrideWithValue(landed),
            reservationGatewayProvider.overrideWithValue(reservations),
            receivablesRepositoryProvider.overrideWithValue(receivables),
            connectivityStateProvider.overrideWithValue(state),
          ];
          final container = ProviderContainer(
            overrides: overrides(phase == 'entry' ? uncertain : online),
          );
          final provider = switch (module) {
            'landed' => landedValueControllerProvider,
            'reservation' => reservationControllerProvider,
            _ => receivablesControllerProvider,
          };
          final subscription = container.listen(provider, (_, _) {});
          addTearDown(() async {
            subscription.close();
            container.dispose();
            await db.close();
          });
          final dynamic controller = container.read(provider);
          expect(controller, isNotNull);
          // Let genuine encrypted recovery and initial scoped reads settle.
          for (var i = 0; i < 100 && controller.busy == true; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          if (phase == 'notification') {
            expect(controller.online, true);
            container.updateOverrides(overrides(uncertain));
            await container.pump();
          }
          expect(controller.online, false);
        });
      }
    }
  }
}

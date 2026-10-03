import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/sales/quotation_controller.dart';
import 'package:jentra_desktop/src/features/sales/quotation_screen.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

import 'quotation_controller_test.dart' as q;
import 'quotation_reference_access_20261003_test.dart' show PopObserver;

void main() {
  setUpAll(_fonts);
  for (final change in ['connection', 'capabilities', 'current']) {
    testWidgets('quotation reason root-pop $change keeps original authority', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final db = JentraLocalDatabase(NativeDatabase.memory());
      final store = QuotationDraftStore(
        EncryptedDraftRepository(db, DraftCipher(keyStore: q.MemoryKeys())),
      );
      final repository = q.FakeQuotations()
        ..detail = q.detail(status: 'pending_approval');
      final observer = PopObserver();
      AsyncValue<ConnectivityState> connection = const AsyncData(
        ConnectivityState.online,
      );
      AsyncValue<Set<String>> capabilities = AsyncData(q.permissions);
      overrides() => [
        activeTenantContextProvider.overrideWithValue(q.scope),
        businessCapabilitiesProvider.overrideWithValue(capabilities),
        connectivityStateProvider.overrideWithValue(connection),
        quotationWorkspaceRepositoryProvider.overrideWithValue(repository),
        leadToCashRepositoryProvider.overrideWithValue(repository),
        quotationDraftStoreProvider.overrideWithValue(store),
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
      final capabilitySubscription = container.listen(
        businessCapabilitiesProvider,
        (_, _) {},
        fireImmediately: true,
      );
      void publish() {
        container.updateOverrides(overrides());
        container.read(connectivityStateProvider);
        container.read(businessCapabilitiesProvider);
      }

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        connectionSubscription.close();
        capabilitySubscription.close();
        container.dispose();
        await db.close();
      });
      container.read(connectivityStateProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: JentraTheme.light(),
            navigatorObservers: [observer],
            home: const Scaffold(body: QuotationScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await container.read(quotationWorkspaceProvider.future);
        await container
            .read(quotationWorkspaceProvider.notifier)
            .selectQuotation(q.quoteId);
      });
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Reject'));
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('quotation-action-reason')),
        'Original governed reason',
      );
      await tester.pump();
      observer.change = () {
        if (change == 'connection') {
          connection = const AsyncData(ConnectivityState.offline);
          publish();
          connection = const AsyncData(ConnectivityState.online);
          publish();
        } else if (change == 'capabilities') {
          // Deliberately reproduce Riverpod's retained-data uncertain state.
          // ignore: invalid_use_of_internal_member
          capabilities = const AsyncLoading<Set<String>>().copyWithPrevious(
            AsyncData(q.permissions),
          );
          publish();
          capabilities = AsyncData(q.permissions);
          publish();
        }
      };
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm reject'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(repository.commands.length, change == 'current' ? 1 : 0);
    });
  }
}

Future<void> _fonts() async {
  const root = 'packages/jentra_design_system/assets/fonts';
  await (FontLoader(JentraTypography.sansFamily)
        ..addFont(rootBundle.load('$root/Manrope-Regular.ttf'))
        ..addFont(rootBundle.load('$root/Manrope-Medium.ttf'))
        ..addFont(rootBundle.load('$root/Manrope-SemiBold.ttf')))
      .load();
  await (FontLoader(
    JentraTypography.monoFamily,
  )..addFont(rootBundle.load('$root/IBMPlexMono-Regular.ttf'))).load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

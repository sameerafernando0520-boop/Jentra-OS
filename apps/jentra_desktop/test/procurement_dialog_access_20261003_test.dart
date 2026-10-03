import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/features/procurement/procurement_picker.dart';
import 'package:jentra_desktop/src/features/procurement/sourcing_controller.dart';
import 'package:jentra_desktop/src/features/procurement/sourcing_screen.dart';
import 'package:jentra_desktop/src/features/procurement/supplier_payment_controller.dart';
import 'package:jentra_desktop/src/features/procurement/supplier_payment_screen.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';

import 'sourcing_interaction_test.dart' show SourcingReferences, issuedRfq;
import 'supplier_payment_interaction_test.dart' show PaymentEvidence;
import 'support/procurement_fakes.dart' show Keys;

const _scope = TenantContext(
  tenantId: 't',
  actorId: 'a',
  legalEntityId: 'e',
  branchId: 'b',
);

class _AfterPop extends NavigatorObserver {
  VoidCallback? onDialogPop;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is DialogRoute) onDialogPop?.call();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late JentraLocalDatabase db;
  late QuotationDraftStore store;
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    store = QuotationDraftStore.procurement(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
  });
  tearDown(() => db.close());

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    _AfterPop? observer,
  }) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [?observer],
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final change in ['offline', 'reconnect', 'denial', 'dispose']) {
    testWidgets('supplier choice reason hides private title after $change', (
      tester,
    ) async {
      final gateway = SourcingReferences()..uncertain = false;
      final c = SourcingController(
        scope: _scope,
        gateway: gateway,
        drafts: store,
        online: true,
      );
      var disposed = false;
      addTearDown(() {
        if (!disposed) c.dispose();
      });
      await tester.runAsync(c.initialize);
      c.selected = issuedRfq();
      await mount(tester, SourcingWorkspace(controller: c));
      final choose = find.text('Select supplier with reason');
      await tester.ensureVisible(choose);
      await tester.tap(choose);
      await tester.pumpAndSettle();
      expect(find.text('Why select Supplier One?'), findsOneWidget);
      if (change == 'dispose') {
        c.dispose();
        disposed = true;
      } else if (change == 'denial') {
        c.denyReadAccess();
      } else {
        c.setOnline(false);
        if (change == 'reconnect') c.setOnline(true);
      }
      await tester.pumpAndSettle();
      expect(find.text('Why select Supplier One?'), findsNothing);
      expect(find.text('Confirm'), findsNothing);
      expect(gateway.commands, isEmpty);
      expect(
        await tester.runAsync(
          () => store.load(_scope, SourcingController.slot),
        ),
        isNull,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final change in ['reconnect', 'denial', 'dispose']) {
    testWidgets(
      'reference result rejects $change between route pop and caller continuation',
      (tester) async {
        final gateway = SourcingReferences();
        final c = SourcingController(
          scope: _scope,
          gateway: gateway,
          drafts: store,
          online: true,
        );
        var disposed = false;
        addTearDown(() {
          if (!disposed) c.dispose();
        });
        final observer = _AfterPop();
        Map<String, Object?>? accepted;
        var returned = false;
        await mount(
          tester,
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                accepted = await pickSourcingReference(
                  context,
                  gateway,
                  _scope,
                  'suppliers',
                  access: c,
                );
                returned = true;
              },
              child: const Text('Open reference'),
            ),
          ),
          observer: observer,
        );
        await tester.tap(find.text('Open reference'));
        await tester.pumpAndSettle();
        expect(find.text('REF · Supplier One'), findsOneWidget);
        observer.onDialogPop = () {
          if (change == 'dispose') {
            c.dispose();
            disposed = true;
          } else if (change == 'denial') {
            c.denyReadAccess();
          } else {
            c.setOnline(false);
            c.setOnline(true);
          }
        };
        await tester.tap(find.text('REF · Supplier One'));
        await tester.pumpAndSettle();
        expect(returned, isTrue);
        expect(
          accepted,
          isNull,
          reason: 'The selecting epoch must survive the awaited route result.',
        );
        expect(gateway.commands, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final change in ['reconnect', 'denial']) {
    testWidgets(
      'AP allocation reversal does not create stale draft after $change on confirmation pop',
      (tester) async {
        final gateway = PaymentEvidence()..uncertain = false;
        final c = SupplierPaymentController(
          scope: _scope,
          gateway: gateway,
          references: gateway,
          drafts: store,
          online: true,
          canReverse: true,
        );
        addTearDown(c.dispose);
        await tester.runAsync(() => c.inspectItem('credit'));
        final observer = _AfterPop();
        await mount(
          tester,
          SupplierPaymentWorkspace(controller: c),
          observer: observer,
        );
        final reverse = find.text('Reverse allocation');
        await tester.ensureVisible(reverse);
        await tester.tap(reverse);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).last,
          'Original linked correction',
        );
        observer.onDialogPop = () {
          if (change == 'denial') {
            c.denyReadAccess();
          } else {
            c.setOnline(false);
            c.setOnline(true);
          }
        };
        await tester.runAsync(() async {
          await tester.tap(find.text('Confirm'));
          while (c.busy) {
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
        });
        await tester.pumpAndSettle();
        expect(c.form, isNull);
        expect(
          await tester.runAsync(
            () => store.load(_scope, SupplierPaymentController.slot),
          ),
          isNull,
        );
        expect(gateway.commands, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'AP current denial cannot prepare a captured allocation correction',
    () async {
      final gateway = PaymentEvidence();
      final c = SupplierPaymentController(
        scope: _scope,
        gateway: gateway,
        references: gateway,
        drafts: store,
        online: true,
        canReverse: true,
      );
      addTearDown(c.dispose);
      await c.inspectItem('credit');
      final allocation = (c.itemDetail!['allocations'] as List).first as Map;
      c.denyReadAccess();
      await c.reverseAllocation(
        allocation.cast<String, Object?>(),
        date: '2026-09-30',
        reason: 'Original linked correction',
      );
      expect(c.form, isNull);
      expect(await store.load(_scope, SupplierPaymentController.slot), isNull);
      expect(gateway.commands, isEmpty);
    },
  );
}

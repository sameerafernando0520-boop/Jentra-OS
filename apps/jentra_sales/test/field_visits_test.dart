import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_sales/src/data/sales_store.dart';
import 'package:jentra_sales/src/field_sales_controller.dart';
import 'package:jentra_sales/src/ui/components.dart';
import 'package:jentra_sales/src/ui/field_sales_workspace.dart';

import 'support/field_sales_fixture.dart';

void main() {
  late FakeFieldSalesGateway gateway;
  late MemorySalesStore store;
  late DateTime clock;
  FieldSalesController make({Future<FieldSalesLocation?> Function()? locate}) =>
      FieldSalesController(
        gateway: gateway,
        store: store,
        now: () => clock,
        locate: locate,
      );
  setUp(() {
    gateway = FakeFieldSalesGateway();
    store = MemorySalesStore();
    clock = DateTime.utc(2026, 11, 17, 9);
  });

  group('controller', () {
    test(
      'plan, check in and complete a visit, one version at a time',
      () async {
        final c = make();
        addTearDown(c.dispose);
        await c.open();
        expect(c.visitsAvailable, isTrue);
        await c.planVisit(
          customerId: 'customer',
          purpose: ' Quarterly review ',
          plannedFor: '2026-11-18',
        );
        final planned = c.visits.single;
        expect(planned['state'], 'planned');
        expect(planned['purpose'], 'Quarterly review');
        expect(gateway.visitCommands.single.expectedVersion, isNull);
        await c.checkInVisit(planned);
        expect(c.visits.single['state'], 'checked_in');
        expect(gateway.visitCommands.last.expectedVersion, 1);
        expect(gateway.visitCommands.last.payload.keys, ['id']);
        await c.completeVisit(
          c.visits.single,
          outcome: 'Met the buyer',
          nextAction: 'Send prices',
          nextActionDue: '2026-11-20',
        );
        expect(c.visits.single['state'], 'completed');
        expect(c.visits.single['outcome'], 'Met the buyer');
        expect(gateway.visitCommands.last.expectedVersion, 2);
        expect(c.pendingVisit, isNull);
        expect(store.values, isEmpty);
      },
    );

    test('location is read once, only when the rep asks for it', () async {
      var reads = 0;
      final c = make(
        locate: () async {
          reads++;
          return FieldSalesLocation.fromDegrees(6.9270786, 79.861243);
        },
      );
      addTearDown(c.dispose);
      await c.open();
      await c.planVisit(customerId: 'customer', purpose: 'Review');
      expect(reads, 0);
      await c.checkInVisit(c.visits.single);
      expect(reads, 0);
      expect(
        gateway.visitCommands.last.payload.containsKey('latitude'),
        isFalse,
      );
      await c.cancelVisit(c.visits.single, 'Closed');
      await c.planVisit(customerId: 'customer', purpose: 'Second');
      final second = c.visits.firstWhere((v) => v['state'] == 'planned');
      await c.checkInVisit(second, withLocation: true);
      expect(reads, 1);
      expect(gateway.visitCommands.last.payload, {
        'id': second['id'],
        'latitude': '6.927079',
        'longitude': '79.861243',
      });
    });

    test(
      'a refused location permission records nothing and keeps the portfolio',
      () async {
        final c = make(
          locate: () async => throw const FieldSalesFailure(
            'LOCATION_PERMISSION_DENIED',
            'Jentra Sales may not read your location.',
          ),
        );
        addTearDown(c.dispose);
        await c.open();
        await c.planVisit(customerId: 'customer', purpose: 'Review');
        final count = gateway.visitCommands.length;
        await c.checkInVisit(c.visits.single, withLocation: true);
        expect(gateway.visitCommands, hasLength(count));
        expect(c.error, 'Jentra Sales may not read your location.');
        expect(c.isOpen, isTrue);
        expect(c.customers, isNotEmpty);
        expect(c.pendingVisit, isNull);
        await c.checkInVisit(c.visits.single);
        expect(c.visits.single['state'], 'checked_in');
      },
    );

    test('an unreadable location records nothing', () async {
      final c = make(locate: () async => null);
      addTearDown(c.dispose);
      await c.open();
      await c.planVisit(customerId: 'customer', purpose: 'Review');
      final count = gateway.visitCommands.length;
      await c.checkInVisit(c.visits.single, withLocation: true);
      expect(gateway.visitCommands, hasLength(count));
      expect(c.visits.single['state'], 'planned');
      expect(c.error, contains('Nothing was recorded'));
    });

    test('a lost response is kept, survives reopening and is confirmed by its receipt', () async {
      final c = make();
      addTearDown(c.dispose);
      await c.open();
      gateway.loseVisitResponse = true;
      await c.planVisit(customerId: 'customer', purpose: 'Review');
      expect(c.pendingVisit, isNotNull);
      expect(store.values.keys.single, contains('visit-command'));
      gateway.loseVisitResponse = false;
      // The same device reopens: the saved update comes back unchanged.
      final reopened = make();
      addTearDown(reopened.dispose);
      await reopened.open();
      expect(reopened.pendingVisit!.commandId, c.pendingVisit!.commandId);
      await reopened.planVisit(customerId: 'customer', purpose: 'Blocked');
      expect(gateway.visitCommands, hasLength(1));
      await reopened.reconcileVisit();
      expect(reopened.pendingVisit, isNull);
      expect(reopened.visits.single['purpose'], 'Review');
      expect(gateway.visitCommands, hasLength(1));
      expect(store.values, isEmpty);
    });

    test('an explicit retry resends the same bytes and key', () async {
      final c = make();
      addTearDown(c.dispose);
      await c.open();
      gateway.visitFailure = const FieldSalesFailure(
        'OUTCOME_UNKNOWN',
        'The response was interrupted.',
      );
      await c.planVisit(customerId: 'customer', purpose: 'Review');
      final first = gateway.visitCommands.single;
      gateway.visitFailure = null;
      await c.reconcileVisit();
      expect(c.pendingVisit, isNotNull);
      expect(c.error, contains('No receipt is visible yet'));
      await c.reconcileVisit(retry: true);
      expect(gateway.visitCommands, hasLength(2));
      expect(gateway.visitCommands.last.key, first.key);
      expect(gateway.visitCommands.last.params, first.params);
      expect(c.pendingVisit, isNull);
      expect(c.visits, hasLength(1));
    });

    test('an update older than a day is not resent, and can be cleared if never received', () async {
      final c = make();
      addTearDown(c.dispose);
      await c.open();
      gateway.visitFailure = const FieldSalesFailure(
        'OUTCOME_UNKNOWN',
        'Lost.',
      );
      await c.planVisit(customerId: 'customer', purpose: 'Review');
      gateway.visitFailure = null;
      expect(c.canDiscardPendingVisit, isFalse);
      clock = clock.add(const Duration(days: 2));
      await c.reconcileVisit(retry: true);
      expect(gateway.visitCommands, hasLength(1));
      expect(c.error, contains('too old'));
      expect(c.canDiscardPendingVisit, isTrue);
      await c.discardVisit();
      expect(c.pendingVisit, isNull);
      expect(c.visits, isEmpty);
      expect(c.error, contains('no record'));
    });

    test(
      'a company refusal clears the update and reloads current visits',
      () async {
        final c = make();
        addTearDown(c.dispose);
        await c.open();
        await c.planVisit(customerId: 'customer', purpose: 'Review');
        final stale = c.visits.single;
        await c.checkInVisit(stale);
        await c.checkInVisit(stale); // version 1 is stale now
        expect(c.pendingVisit, isNull);
        expect(c.visits.single['state'], 'checked_in');
        expect(store.values, isEmpty);
      },
    );

    test(
      'a receipt for another rep is refused and kept for checking',
      () async {
        final c = make();
        addTearDown(c.dispose);
        await c.open();
        gateway.loseVisitResponse = true;
        await c.planVisit(customerId: 'customer', purpose: 'Review');
        gateway.visitReceipts.updateAll(
          (_, r) => {
            ...r,
            'entity': {...r['entity'] as Map, 'rep_id': 'someone-else'},
          },
        );
        await c.reconcileVisit();
        expect(c.pendingVisit, isNotNull);
        expect(c.error, contains('did not match'));
      },
    );

    test('a company without visits still opens the portfolio', () async {
      gateway.visitsRolledOut = false;
      final c = make();
      addTearDown(c.dispose);
      await c.open();
      expect(c.customers, isNotEmpty);
      expect(c.visitsAvailable, isFalse);
      await c.planVisit(customerId: 'customer', purpose: 'Review');
      expect(gateway.visitCommands, isEmpty);
    });
  });

  testWidgets('the Visits page plans, checks in and completes a visit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = make();
    addTearDown(c.dispose);
    await c.open();
    await tester.pumpWidget(
      MaterialApp(
        theme: salesTheme(Brightness.light),
        home: FieldSalesWorkspace(c, onLeave: () async {}),
      ),
    );
    await tester.tap(find.text('Visits').last);
    await tester.pumpAndSettle();
    expect(find.text('No visits yet'), findsOneWidget);
    await tester.tap(find.text('Plan a visit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan visit'));
    await tester.pumpAndSettle();
    expect(find.text('Choose an assigned customer.'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assigned customer with no transactions').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Purpose'),
      'Quarterly review',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Planned date (optional)'),
      '18-11-2026',
    );
    await tester.tap(find.text('Plan visit'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Use a date such as'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Planned date (optional)'),
      '2026-11-18',
    );
    await tester.tap(find.text('Plan visit'));
    await tester.pumpAndSettle();
    expect(find.text('Planned · Quarterly review'), findsOneWidget);
    expect(find.text('Planned for 2026-11-18'), findsOneWidget);
    // No device position is offered, so check in asks nothing about location.
    await tester.tap(find.text('Check in'));
    await tester.pumpAndSettle();
    expect(find.text('Checked in · Quarterly review'), findsOneWidget);
    await tester.tap(find.text('Complete visit').first);
    await tester.pumpAndSettle();
    expect(find.text('Add my current location'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Outcome'),
      'Met the buyer',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Next action date (optional)'),
      '2026-11-20',
    );
    await tester.tap(find.text('Complete visit').last);
    await tester.pumpAndSettle();
    expect(find.text('Add the next action for this date.'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Next action (optional)'),
      'Send prices',
    );
    await tester.tap(find.text('Complete visit').last);
    await tester.pumpAndSettle();
    expect(find.text('Completed · Quarterly review'), findsOneWidget);
    expect(find.text('Outcome: Met the buyer'), findsOneWidget);
    expect(find.text('Next: Send prices by 2026-11-20'), findsOneWidget);
    expect(find.text('Check in'), findsNothing);
    c.clear(); // Ends the access lease timer.
  });

  testWidgets(
    'check in asks before adding a location when the device has one',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = make(
        locate: () async => const FieldSalesLocation('6.9', '79.8'),
      );
      addTearDown(c.dispose);
      await c.open();
      await c.planVisit(customerId: 'customer', purpose: 'Review');
      await tester.pumpWidget(
        MaterialApp(
          theme: salesTheme(Brightness.light),
          home: FieldSalesWorkspace(c, onLeave: () async {}),
        ),
      );
      await tester.tap(find.text('Visits').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check in'));
      await tester.pumpAndSettle();
      expect(find.text('Add your location to this check in?'), findsOneWidget);
      await tester.tap(find.text('Check in without location'));
      await tester.pumpAndSettle();
      expect(
        gateway.visitCommands.last.payload.containsKey('latitude'),
        isFalse,
      );
      expect(find.text('Checked in · Review'), findsOneWidget);
      expect(find.text('Location added at check in'), findsNothing);
      c.clear(); // Ends the access lease timer.
    },
  );

  testWidgets(
    'an unconfirmed visit update offers check and retry, not new work',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = make();
      addTearDown(c.dispose);
      await c.open();
      gateway.loseVisitResponse = true;
      await c.planVisit(customerId: 'customer', purpose: 'Review');
      gateway.loseVisitResponse = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: salesTheme(Brightness.light),
          home: FieldSalesWorkspace(c, onLeave: () async {}),
        ),
      );
      await tester.tap(find.text('Visits').last);
      await tester.pumpAndSettle();
      expect(find.text('Check your last visit update'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Plan a visit'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Check visit update'));
      await tester.pumpAndSettle();
      expect(find.text('Check your last visit update'), findsNothing);
      expect(find.text('Planned · Review'), findsOneWidget);
      c.clear(); // Ends the access lease timer.
    },
  );
}

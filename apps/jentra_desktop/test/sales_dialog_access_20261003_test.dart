import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/sales/quotation_scope_guard.dart';
import 'package:jentra_desktop/src/features/sales/sales_order_dialogs.dart';
import 'package:jentra_desktop/src/features/sales/sales_order_screen.dart';
import 'package:jentra_domain/jentra_domain.dart';

import 'quotation_controller_test.dart' as q;
import 'sales_order_controller_test.dart' as f;
import 'sales_order_workspace_test.dart' as w;

void main() {
  for (final change in ['loading', 'error']) {
    testWidgets(
      'credit connection $change with retained previous value hides evidence',
      (tester) async {
        final connectivity = StreamController<ConnectivityState>.broadcast(
          sync: true,
        );
        addTearDown(connectivity.close);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              connectivityStateProvider.overrideWith(
                (_) => connectivity.stream,
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: OrderCreditDialog(
                  canOverride: false,
                  preview: f.preview(),
                ),
              ),
            ),
          ),
        );
        connectivity.add(ConnectivityState.online);
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(OrderCreditDialog)),
        );
        if (change == 'loading') {
          container.invalidate(connectivityStateProvider);
          container.read(connectivityStateProvider);
        } else {
          connectivity.addError(StateError('Connection observation failed'));
        }
        await tester.pump();
        await tester.pump();
        expect(find.text('Credit limit\nLKR 500.000000'), findsNothing);
        expect(find.text('Record credit hold'), findsNothing);
      },
    );
  }
  testWidgets(
    'scope loss and restoration before frame cannot revive cached dialog',
    (tester) async {
      var currentScope = q.scope;
      final container = ProviderContainer(
        overrides: [
          activeTenantContextProvider.overrideWith((_) => currentScope),
          businessCapabilitiesProvider.overrideWith((_) async => f.permissions),
        ],
      );
      addTearDown(container.dispose);
      await tester.runAsync(
        () => container.read(businessCapabilitiesProvider.future),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: QuotationScopeGuard(
                scope: q.scope,
                capabilities: f.permissions,
                child: const AlertDialog(
                  title: Text('Private original customer'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Private original customer'), findsOneWidget);
      currentScope = q.scope.copyWith(actorId: 'replacement-actor');
      container.invalidate(activeTenantContextProvider);
      container.read(activeTenantContextProvider);
      currentScope = q.scope;
      container.invalidate(activeTenantContextProvider);
      container.read(activeTenantContextProvider);
      await tester.pumpAndSettle();
      expect(find.text('Private original customer'), findsNothing);
      expect(find.text('Business scope or access changed'), findsOneWidget);
    },
  );
  testWidgets(
    'credit permission loss and restoration before frame stays hidden',
    (tester) async {
      var result = Future<Set<String>>.value(f.permissions);
      final h = await w.pump(tester, capabilitySource: () => result);
      await tester.tap(find.text('Review credit & confirm'));
      await w.flush(tester, h);
      final pending = Completer<Set<String>>();
      result = pending.future;
      h.container.invalidate(businessCapabilitiesProvider);
      h.container.read(businessCapabilitiesProvider);
      pending.complete(f.permissions);
      await tester.pumpAndSettle();
      expect(find.byType(OrderCreditDialog), findsNothing);
      expect(h.repository.commands, isEmpty);
    },
  );
  testWidgets(
    'credit originating route disposal clears surviving root evidence',
    (tester) async {
      final h = await w.pump(tester);
      await tester.tap(find.text('Review credit & confirm'));
      await w.flush(tester, h);
      final origin = tester.element(find.byType(SalesOrderScreen));
      final route = ModalRoute.of(origin)!;
      Navigator.of(origin).removeRoute(route);
      await tester.pumpAndSettle();
      expect(
        find.text('Total exposure after confirmation\nLKR 568000.000000'),
        findsNothing,
      );
      expect(find.text('Record credit hold'), findsNothing);
      expect(h.repository.commands, isEmpty);
    },
  );
  testWidgets(
    'credit confirmation stays hidden after permission reauthorization',
    (tester) async {
      var result = Future<Set<String>>.value(f.permissions);
      final h = await w.pump(tester, capabilitySource: () => result);
      await tester.tap(find.text('Review credit & confirm'));
      await w.flush(tester, h);
      expect(find.byType(OrderCreditDialog), findsOneWidget);
      final pending = Completer<Set<String>>();
      result = pending.future;
      h.container.invalidate(businessCapabilitiesProvider);
      await tester.pump();
      await tester.pump();
      expect(find.text('Business scope or access changed'), findsOneWidget);
      pending.complete(f.permissions);
      await tester.pumpAndSettle();
      expect(find.byType(OrderCreditDialog), findsNothing);
      expect(
        find.text('Total exposure after confirmation\nLKR 568000.000000'),
        findsNothing,
      );
      expect(h.repository.commands, isEmpty);
    },
  );

  for (final reconnect in [false, true]) {
    testWidgets('credit preview clears on disconnect reconnect=$reconnect', (
      tester,
    ) async {
      final connectivity = StreamController<ConnectivityState>();
      addTearDown(connectivity.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectivityStateProvider.overrideWith((_) => connectivity.stream),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: OrderCreditDialog(
                canOverride: false,
                preview: SalesOrderCreditPreview.fromJson({
                  'sales_order_id': q.quoteId,
                  'order_version': 7,
                  'currency_code': 'LKR',
                  'credit_currency_code': 'LKR',
                  'credit_limit': '500000.000000',
                  'due_exposure': '450000.000000',
                  'overdue_exposure': '20000.000000',
                  'existing_order_exposure': '0.000000',
                  'current_order_exposure': '118000.000000',
                  'total_exposure': '568000.000000',
                  'projection_available': true,
                  'checked_at': '2026-09-07T01:00:00Z',
                }),
              ),
            ),
          ),
        ),
      );
      connectivity.add(ConnectivityState.online);
      await tester.pumpAndSettle();
      expect(
        find.text('Total exposure after confirmation\nLKR 568000.000000'),
        findsOneWidget,
      );
      connectivity.add(ConnectivityState.offline);
      await tester.pumpAndSettle();
      if (reconnect) {
        connectivity.add(ConnectivityState.online);
        await tester.pumpAndSettle();
      }
      expect(
        find.text('Total exposure after confirmation\nLKR 568000.000000'),
        findsNothing,
      );
      expect(find.text('Confirm order'), findsNothing);
    });
  }

  testWidgets(
    'credit rapid disconnect reconnect before frame clears evidence',
    (tester) async {
      final connectivity = StreamController<ConnectivityState>.broadcast(
        sync: true,
      );
      addTearDown(connectivity.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectivityStateProvider.overrideWith((_) => connectivity.stream),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: OrderCreditDialog(canOverride: false, preview: f.preview()),
            ),
          ),
        ),
      );
      connectivity.add(ConnectivityState.online);
      await tester.pumpAndSettle();
      expect(find.text('Credit limit\nLKR 500.000000'), findsOneWidget);
      connectivity.add(ConnectivityState.offline);
      connectivity.add(ConnectivityState.online);
      await tester.pumpAndSettle();
      expect(find.text('Credit limit\nLKR 500.000000'), findsNothing);
      expect(find.text('Confirm order'), findsNothing);
    },
  );

  testWidgets('scope guard retains offline local discard dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeTenantContextProvider.overrideWithValue(q.scope),
          businessCapabilitiesProvider.overrideWith((_) async => f.permissions),
          connectivityStateProvider.overrideWith(
            (_) => Stream.value(ConnectivityState.offline),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: QuotationScopeGuard(
              scope: q.scope,
              capabilities: f.permissions,
              child: const AlertDialog(title: Text('Discard local edits?')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Discard local edits?'), findsOneWidget);
  });

  testWidgets('fresh credit confirmation transmits one original command', (
    tester,
  ) async {
    final h = await w.pump(tester);
    await tester.tap(find.text('Review credit & confirm'));
    await w.flush(tester, h);
    await tester.tap(find.text('Record credit hold'));
    await w.flush(tester, h);
    expect(h.repository.commands.length, 1);
    expect(h.repository.commands.single.verb, 'confirm');
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/finance/finance_screen.dart';
import 'package:jentra_desktop/src/features/operations/operational_controller.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';

const _scope = TenantContext(
  tenantId: 'tenant-a',
  actorId: 'actor-a',
  legalEntityId: 'entity-a',
  branchId: 'branch-a',
);

final _testScope = StateProvider<TenantContext?>((ref) => _scope);
final _testAccess = StateProvider<Set<String>>((ref) => {'finance.view'});
final _testConnection = StateProvider<ConnectivityState>(
  (ref) => ConnectivityState.online,
);

class _FinanceGateway implements OperationalGateway {
  final scopes = <TenantContext>[];
  Completer<Map<String, Object?>>? held;
  Object? failure;
  Map<String, Object?> data = {
    'generated_at': '2026-10-22T08:30:00Z',
    'cards': [
      {'kind': 'manual_journal', 'count': '4'},
      {'kind': 'customer_receipt', 'count': '2'},
      {'kind': 'lead', 'count': '52'},
    ],
    'metrics': [
      {
        'kind': 'ar_aging',
        'as_of': '2026-10-22',
        'generated_at': '2026-10-22T08:30:00Z',
        'destination': '/receivables',
        'data': {
          'buckets': [
            {
              'currency_code': 'LKR',
              'bucket': '1–30',
              'amount': '900719925474.099999',
              'item_count': '3',
            },
            {
              'currency_code': 'USD',
              'bucket': 'current',
              'amount': '12.300001',
              'item_count': '1',
            },
          ],
        },
      },
      {
        'kind': 'cash_bank',
        'as_of': '2026-10-22',
        'generated_at': '2026-10-22T08:30:00Z',
        'destination': '/finance/bank',
        'data': <Map<String, Object?>>[],
      },
      {
        'kind': 'pipeline',
        'as_of': '2026-10-22',
        'generated_at': '2026-10-22T08:30:00Z',
        'destination': '/crm',
        'data': <String, Object?>{},
      },
    ],
  };

  @override
  Future<Map<String, Object?>> dashboard(TenantContext scope) async {
    scopes.add(scope);
    if (held != null) return held!.future;
    if (failure != null) throw failure!;
    return data;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Override> _overrides(_FinanceGateway gateway) => [
  activeTenantContextProvider.overrideWith((ref) => ref.watch(_testScope)),
  businessCapabilitiesProvider.overrideWith((ref) => ref.watch(_testAccess)),
  connectivityStateProvider.overrideWith(
    (ref) => Stream.value(ref.watch(_testConnection)),
  ),
  operationalGatewayProvider.overrideWithValue(gateway),
];

void main() {
  Future<void> pump(
    WidgetTester tester,
    _FinanceGateway gateway, {
    Set<String> capabilities = const {'finance.view'},
    bool dark = false,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._overrides(gateway),
          _testAccess.overrideWith((ref) => capabilities),
        ],
        child: MaterialApp(
          theme: dark ? JentraTheme.dark() : JentraTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: const Scaffold(body: FinanceScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'loads the selected branch and preserves exact currency amounts',
    (tester) async {
      final gateway = _FinanceGateway();
      await pump(
        tester,
        gateway,
        capabilities: {'finance.view', 'finance.receivables.view'},
      );
      expect(gateway.scopes, [_scope]);
      expect(find.text('Updated 22 Oct 2026 08:30 UTC'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('900719925474.099999'),
        250,
      );
      expect(
        find.text('LKR · 1–30 · 900719925474.099999 · 3 open items'),
        findsOneWidget,
      );
      expect(
        find.text('USD · current · 12.300001 · 1 open items'),
        findsOneWidget,
      );
      expect(find.text('Pipeline and forecast'), findsNothing);
      expect(find.text('52'), findsNothing);
    },
  );

  testWidgets('shows only the financial position permitted to the actor', (
    tester,
  ) async {
    final gateway = _FinanceGateway();
    await pump(tester, gateway, capabilities: {'finance.receipts.view'});
    expect(find.text('Customer receipts'), findsNWidgets(2));
    expect(find.text('Manual journals'), findsNothing);
    expect(find.text('Receivables aging'), findsNothing);
    expect(find.text('Cash and bank reconciliation'), findsNothing);
    expect(find.textContaining('900719925474'), findsNothing);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('no finance access makes no dashboard request', (tester) async {
    final gateway = _FinanceGateway();
    await pump(tester, gateway, capabilities: {'crm.leads.view'});
    expect(find.text('Finance access is required'), findsOneWidget);
    expect(gateway.scopes, isEmpty);
  });

  testWidgets('an incomplete business scope makes no dashboard request', (
    tester,
  ) async {
    final gateway = _FinanceGateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._overrides(gateway),
          _testScope.overrideWith((ref) => _scope.copyWith(clearBranch: true)),
        ],
        child: MaterialApp(
          theme: JentraTheme.light(),
          home: const Scaffold(body: FinanceScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose your finance workspace'), findsOneWidget);
    expect(gateway.scopes, isEmpty);
  });

  testWidgets('failed overview can retry without blocking existing workflows', (
    tester,
  ) async {
    final gateway = _FinanceGateway()..failure = StateError('unavailable');
    await pump(tester, gateway);
    expect(
      find.text('Your finance position could not be loaded'),
      findsOneWidget,
    );
    expect(find.text('Daily work'), findsOneWidget);
    gateway.failure = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(
      find.text('Your finance position could not be loaded'),
      findsNothing,
    );
    expect(find.text('4'), findsOneWidget);
    expect(gateway.scopes.length, 2);
  });

  testWidgets('customer receipts opens its working document tab', (
    tester,
  ) async {
    final gateway = _FinanceGateway()..data = {'cards': [], 'metrics': []};
    final router = GoRouter(
      initialLocation: '/finance',
      routes: [
        GoRoute(
          path: '/finance',
          builder: (_, _) => const Scaffold(body: FinanceScreen()),
        ),
        GoRoute(
          path: '/receivables',
          builder: (_, state) => Scaffold(
            body: Text('Document tab: ${state.uri.queryParameters['kind']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._overrides(gateway),
          _testAccess.overrideWith((ref) => {'finance.receipts.view'}),
        ],
        child: MaterialApp.router(
          theme: JentraTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Open customer receipts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open customer receipts').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Document tab: customer_receipt'), findsOneWidget);
  });

  test('late results cannot restore balances after going offline', () async {
    final gateway = _FinanceGateway()..held = Completer();
    final container = ProviderContainer(overrides: _overrides(gateway));
    addTearDown(container.dispose);
    final listener = container.listen(financeOverviewProvider, (_, _) {});
    addTearDown(listener.close);
    await container.read(businessCapabilitiesProvider.future);
    await container.read(connectivityStateProvider.future);
    // Let the overview begin with the resolved access and connection.
    await Future<void>.delayed(Duration.zero);
    expect(gateway.scopes, [_scope]);
    container.read(_testConnection.notifier).state = ConnectivityState.offline;
    await container.read(connectivityStateProvider.future);
    await container.read(financeOverviewProvider.future);
    gateway.held!.complete(gateway.data);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(financeOverviewProvider).value, isEmpty);
    expect(gateway.scopes.length, 1);
  });

  test(
    'access revocation drops finance data and stops further reads',
    () async {
      final gateway = _FinanceGateway();
      final container = ProviderContainer(overrides: _overrides(gateway));
      addTearDown(container.dispose);
      final listener = container.listen(financeOverviewProvider, (_, _) {});
      addTearDown(listener.close);
      await container.read(businessCapabilitiesProvider.future);
      await container.read(connectivityStateProvider.future);
      await container.read(financeOverviewProvider.future);
      expect(
        container.read(financeOverviewProvider).value?['cards'],
        isNotEmpty,
      );
      final reads = gateway.scopes.length;
      container.read(_testAccess.notifier).state = {};
      await container.read(businessCapabilitiesProvider.future);
      await container.read(financeOverviewProvider.future);
      expect(container.read(financeOverviewProvider).value, isEmpty);
      expect(gateway.scopes.length, reads);
    },
  );

  for (final dark in [false, true]) {
    testWidgets('finance wraps at 200 percent in ${dark ? 'dark' : 'light'}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(700, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = _FinanceGateway();
      await pump(
        tester,
        gateway,
        dark: dark,
        textScale: 2,
        capabilities: {
          'finance.view',
          'finance.receivables.view',
          'finance.receipts.view',
          'finance.payments.manage',
          'finance.controls.reconcile',
          'inventory.stock.view',
          'inventory.cost.view',
        },
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Open tax review'), 400);
      expect(tester.takeException(), isNull);
    });
  }
}

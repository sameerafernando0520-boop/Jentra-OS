import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/financial_dimensions/financial_dimension_screen.dart';

import 'financial_dimension_workspace_test.dart' show DimensionFake;

class Reads extends DimensionFake {
  int reads = 0;
  Completer<Map<String, Object?>>? delayed;
  @override
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String kind, {
    String? after,
    String search = '',
    bool activeOnly = true,
  }) {
    reads++;
    final pause = delayed;
    if (pause != null) {
      delayed = null;
      return pause.future;
    }
    return super.page(
      scope,
      kind,
      after: after,
      search: search,
      activeOnly: activeOnly,
    );
  }
}

void main() {
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  const other = TenantContext(
    tenantId: 't',
    actorId: 'other',
    legalEntityId: 'e',
    branchId: 'b',
  );
  const choice = 'CC-1 · Distribution and logistics';
  late ProviderContainer container;
  late Reads gateway;
  TenantContext? currentScope;
  late ConnectivityState connection;
  late Set<String> capabilities;
  Map<String, Object?>? chosen;
  void update() => container.updateOverrides([
    activeTenantContextProvider.overrideWithValue(currentScope),
    connectivityStateProvider.overrideWithValue(AsyncData(connection)),
    businessCapabilitiesProvider.overrideWithValue(AsyncData(capabilities)),
  ]);
  setUp(() {
    currentScope = scope;
    connection = ConnectivityState.online;
    capabilities = {'finance.view'};
    chosen = null;
    gateway = Reads();
    container = ProviderContainer(
      overrides: [
        activeTenantContextProvider.overrideWithValue(currentScope),
        connectivityStateProvider.overrideWithValue(AsyncData(connection)),
        businessCapabilitiesProvider.overrideWithValue(AsyncData(capabilities)),
      ],
    );
  });
  tearDown(() => container.dispose());

  Future<void> render(
    WidgetTester tester, {
    ValueNotifier<bool>? visible,
    bool expectChoice = true,
  }) async {
    final button = FinancialDimensionButton(
      scope: scope,
      gateway: gateway,
      kind: 'cost_centre',
      label: 'Pick dimension',
      enabled: true,
      onSelected: (row) => chosen = row,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: visible == null
                ? button
                : ValueListenableBuilder<bool>(
                    valueListenable: visible,
                    builder: (context, shown, _) =>
                        shown ? button : const Text('Route removed'),
                  ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick dimension'));
    await tester.pumpAndSettle();
    if (expectChoice) expect(find.text(choice), findsOneWidget);
  }

  for (final kind in ['connection', 'actor', 'denial']) {
    testWidgets('dimension selector cannot revive after $kind', (tester) async {
      await render(tester);
      if (kind == 'actor') {
        currentScope = other;
      } else if (kind == 'denial') {
        capabilities = {};
      } else {
        connection = ConnectivityState.offline;
      }
      update();
      await tester.pumpAndSettle();
      expect(find.text(choice), findsNothing);
      currentScope = scope;
      capabilities = {'finance.view'};
      connection = ConnectivityState.online;
      update();
      await tester.pumpAndSettle();
      expect(find.text(choice), findsNothing);
      expect(find.text('Reference access changed'), findsOneWidget);
      expect(gateway.reads, 1);
      expect(chosen, isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pick dimension'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(choice));
      await tester.pumpAndSettle();
      expect(chosen?['id'], 'centre');
      expect(gateway.reads, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final kind in ['actor', 'denial', 'disconnect']) {
    testWidgets('dimension post-pop $kind rejects returned private choice', (
      tester,
    ) async {
      await render(tester);
      final row = tester.widget<ListTile>(
        find.widgetWithText(ListTile, choice),
      );
      row.onTap!();
      if (kind == 'actor') {
        currentScope = other;
      } else if (kind == 'denial') {
        capabilities = {};
      } else {
        connection = ConnectivityState.offline;
      }
      update();
      await tester.pumpAndSettle();
      expect(chosen, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('dimension origin disposal hides surviving root choices', (
    tester,
  ) async {
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await render(tester, visible: visible);
    visible.value = false;
    await tester.pumpAndSettle();
    expect(find.text(choice), findsNothing);
    expect(find.text('Reference access changed'), findsOneWidget);
    expect(chosen, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final kind in [
    'capability loading',
    'capability error',
    'connection loading',
    'connection error',
  ]) {
    testWidgets('dimension rejects retained allowed value during $kind', (
      tester,
    ) async {
      await render(tester);
      final previousCaps = AsyncData<Set<String>>({'finance.view'});
      final previousConnection = const AsyncData(ConnectivityState.online);
      final caps = kind == 'capability loading'
          // Model Riverpod cached data retained during a failed or loading refresh.
          // ignore: invalid_use_of_internal_member
          ? const AsyncLoading<Set<String>>().copyWithPrevious(previousCaps)
          : kind == 'capability error'
          ? AsyncError<Set<String>>(
              StateError('refresh failed'),
              StackTrace.current,
              // Model Riverpod cached data retained during a failed or loading refresh.
              // ignore: invalid_use_of_internal_member
            ).copyWithPrevious(previousCaps)
          : previousCaps;
      final network = kind == 'connection loading'
          // Model Riverpod cached data retained during a failed or loading refresh.
          // ignore: invalid_use_of_internal_member
          ? const AsyncLoading<ConnectivityState>().copyWithPrevious(
              previousConnection,
            )
          : kind == 'connection error'
          ? AsyncError<ConnectivityState>(
              StateError('refresh failed'),
              StackTrace.current,
              // Model Riverpod cached data retained during a failed or loading refresh.
              // ignore: invalid_use_of_internal_member
            ).copyWithPrevious(previousConnection)
          : previousConnection;
      container.updateOverrides([
        activeTenantContextProvider.overrideWithValue(scope),
        connectivityStateProvider.overrideWithValue(network),
        businessCapabilitiesProvider.overrideWithValue(caps),
      ]);
      await tester.pumpAndSettle();
      expect(find.text(choice), findsNothing);
      expect(chosen, isNull);
      update();
      await tester.pumpAndSettle();
      expect(find.text(choice), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'dimension old denied search cannot invalidate newly opened selector',
    (tester) async {
      await render(tester);
      final delayed = Completer<Map<String, Object?>>();
      gateway.delayed = delayed;
      await tester.enterText(find.byType(TextField), 'pending');
      await tester.pump();
      connection = ConnectivityState.offline;
      update();
      await tester.pumpAndSettle();
      connection = ConnectivityState.online;
      update();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pick dimension'));
      await tester.pumpAndSettle();
      expect(find.text(choice), findsOneWidget);
      delayed.completeError(
        const DomainError(
          code: 'PERMISSION_DENIED',
          message: 'Old access denied',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(choice), findsOneWidget);
      await tester.tap(find.text(choice));
      await tester.pumpAndSettle();
      expect(chosen?['id'], 'centre');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final kind in [
    'capability loading',
    'capability error',
    'connection loading',
    'connection error',
  ]) {
    testWidgets('dimension opening rejects retained initial $kind', (
      tester,
    ) async {
      final previousCaps = AsyncData<Set<String>>({'finance.view'});
      final previousConnection = const AsyncData(ConnectivityState.online);
      final caps = kind == 'capability loading'
          // Model Riverpod cached data retained during a failed or loading refresh.
          // ignore: invalid_use_of_internal_member
          ? const AsyncLoading<Set<String>>().copyWithPrevious(previousCaps)
          : kind == 'capability error'
          ? AsyncError<Set<String>>(
              StateError('refresh failed'),
              StackTrace.current,
              // Model Riverpod cached data retained during a failed or loading refresh.
              // ignore: invalid_use_of_internal_member
            ).copyWithPrevious(previousCaps)
          : previousCaps;
      final network = kind == 'connection loading'
          // Model Riverpod cached data retained during a failed or loading refresh.
          // ignore: invalid_use_of_internal_member
          ? const AsyncLoading<ConnectivityState>().copyWithPrevious(
              previousConnection,
            )
          : kind == 'connection error'
          ? AsyncError<ConnectivityState>(
              StateError('refresh failed'),
              StackTrace.current,
              // Model Riverpod cached data retained during a failed or loading refresh.
              // ignore: invalid_use_of_internal_member
            ).copyWithPrevious(previousConnection)
          : previousConnection;
      expect(
        kind.startsWith('capability') ? caps.value : network.value,
        isNotNull,
      );
      expect(
        kind.startsWith('capability')
            ? caps.isLoading || caps.hasError
            : network.isLoading || network.hasError,
        isTrue,
      );
      container.updateOverrides([
        activeTenantContextProvider.overrideWithValue(scope),
        connectivityStateProvider.overrideWithValue(network),
        businessCapabilitiesProvider.overrideWithValue(caps),
      ]);
      await render(tester, expectChoice: false);
      expect(find.text(choice), findsNothing);
      expect(gateway.reads, 0);
      expect(chosen, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/sales/quotation_reference_picker.dart';
import 'package:jentra_domain/jentra_domain.dart';

import 'quotation_controller_test.dart' as q;

class References implements QuotationReferenceRepository {
  int reads = 0;
  @override
  Future<CursorPage<QuotationReference>> pageReferences({
    required TenantContext context,
    required QuotationReferenceKind kind,
    required QuotationReferenceQuery query,
  }) async {
    reads++;
    return CursorPage(
      items: [
        QuotationReference(
          id: 'private-customer',
          label: 'Private original customer',
          values: {},
        ),
      ],
      limit: 50,
    );
  }
}

class PopObserver extends NavigatorObserver {
  VoidCallback? change;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is DialogRoute) change?.call();
  }
}

class Harness {
  final references = References(), observer = PopObserver();
  late ProviderContainer container;
  TenantContext scope = q.scope;
  AsyncValue<ConnectivityState> connection = const AsyncData(
    ConnectivityState.online,
  );
  AsyncValue<Set<String>> capabilities = const AsyncData({
    'sales.quotations.manage',
  });
  final selected = <QuotationReference>[];
  List<Override> overrides() => [
    activeTenantContextProvider.overrideWithValue(scope),
    businessCapabilitiesProvider.overrideWithValue(capabilities),
    connectivityStateProvider.overrideWithValue(connection),
    quotationReferenceRepositoryProvider.overrideWithValue(references),
  ];
  void publish() {
    container.updateOverrides(overrides());
    container.read(activeTenantContextProvider);
    container.read(businessCapabilitiesProvider);
    container.read(connectivityStateProvider);
  }

  void disconnect({bool reconnect = false}) {
    connection = const AsyncData(ConnectivityState.offline);
    publish();
    if (reconnect) {
      connection = const AsyncData(ConnectivityState.online);
      publish();
    }
  }

  void actor({bool restore = false}) {
    scope = q.scope.copyWith(actorId: 'replacement-actor');
    publish();
    if (restore) {
      scope = q.scope;
      publish();
    }
  }
}

Future<Harness> open(WidgetTester tester) async {
  final h = Harness();
  h.container = ProviderContainer(overrides: h.overrides());
  final connection = h.container.listen(
    connectivityStateProvider,
    (_, _) {},
    fireImmediately: true,
  );
  final capabilities = h.container.listen(
    businessCapabilitiesProvider,
    (_, _) {},
    fireImmediately: true,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    connection.close();
    capabilities.close();
    h.container.dispose();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: h.container,
      child: MaterialApp(
        navigatorObservers: [h.observer],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final result = await showQuotationReferencePicker(
                  context,
                  title: 'Customer',
                  kind: QuotationReferenceKind.customer,
                );
                if (result != null) h.selected.add(result);
              },
              child: const Text('Choose customer'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(
    h.container.read(connectivityStateProvider).value,
    ConnectivityState.online,
  );
  expect(
    h.container.read(businessCapabilitiesProvider).value,
    contains('sales.quotations.manage'),
  );
  await tester.tap(find.text('Choose customer'));
  await tester.pumpAndSettle();
  expect(find.text('Private original customer'), findsOneWidget);
  return h;
}

void main() {
  for (final change in [
    'disconnect',
    'reconnect',
    'rapid_connection',
    'rapid_actor',
    'rapid_capabilities',
  ]) {
    testWidgets('quotation reference $change cannot revive private rows', (
      tester,
    ) async {
      final h = await open(tester);
      if (change == 'rapid_actor') {
        h.actor(restore: true);
      } else if (change == 'rapid_capabilities') {
        final original = h.capabilities;
        // Deliberately reproduce Riverpod's retained-data uncertain state.
        // ignore: invalid_use_of_internal_member
        h.capabilities = const AsyncLoading<Set<String>>().copyWithPrevious(
          original,
        );
        h.publish();
        h.capabilities = original;
        h.publish();
      } else {
        h.disconnect(reconnect: change == 'rapid_connection');
        if (change == 'reconnect') {
          await tester.pumpAndSettle();
          h.connection = const AsyncData(ConnectivityState.online);
          h.publish();
        }
      }
      await tester.pumpAndSettle();
      expect(find.text('Private original customer'), findsNothing);
      expect(h.selected, isEmpty);
    });
  }
  for (final change in ['connection', 'actor']) {
    testWidgets('quotation reference rejects $change during root pop', (
      tester,
    ) async {
      final h = await open(tester);
      h.observer.change = () {
        if (change == 'connection') {
          h.disconnect(reconnect: true);
        } else {
          h.actor(restore: true);
        }
      };
      await tester.tap(find.text('Private original customer'));
      await tester.pumpAndSettle();
      expect(h.selected, isEmpty);
    });
  }
  testWidgets('fresh quotation reference returns one original customer', (
    tester,
  ) async {
    final h = await open(tester);
    await tester.tap(find.text('Private original customer'));
    await tester.pumpAndSettle();
    expect(h.selected.single.id, 'private-customer');
    expect(h.references.reads, 1);
  });
}

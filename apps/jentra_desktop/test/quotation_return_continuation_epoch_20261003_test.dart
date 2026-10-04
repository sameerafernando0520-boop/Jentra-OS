import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/sales/quotation_editor.dart';
import 'package:jentra_desktop/src/features/sales/sales_order_screen.dart';
import 'package:jentra_domain/jentra_domain.dart';

import 'quotation_controller_test.dart' as q;
import 'quotation_reference_access_20261003_test.dart' show References;

class ContinuationObserver extends NavigatorObserver {
  VoidCallback? change;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is DialogRoute) change?.call();
  }
}

void main() {
  setUpAll(_fonts);
  for (final fulfillment in [false, true]) {
    for (final kind in ['connection', 'actor', 'capabilities']) {
      for (final depth in [1, 2, 3]) {
        testWidgets(
          '${fulfillment ? 'fulfillment' : 'quotation'} editor consumes current reference before later $kind restoration at microtask depth $depth',
          (tester) async {
            await _exercise(
              tester,
              kind: kind,
              depth: depth,
              fulfillment: fulfillment,
            );
          },
        );
      }
    }
    testWidgets(
      '${fulfillment ? 'fulfillment' : 'quotation'} editor attaches one current reference after unchanged continuation',
      (tester) async {
        await _exercise(tester, fulfillment: fulfillment);
      },
    );
  }
}

Future<void> _exercise(
  WidgetTester tester, {
  String? kind,
  int depth = 0,
  bool fulfillment = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final references = ContinuationReferences();
  final observer = ContinuationObserver();
  final events = <String>[];
  final changed = <Map<String, Object?>>[];
  var scope = q.scope;
  var network = const AsyncData<ConnectivityState>(ConnectivityState.online);
  var caps = const AsyncData<Set<String>>({
    ...q.permissions,
    'sales.orders.manage',
  });
  overrides() => [
    activeTenantContextProvider.overrideWithValue(scope),
    connectivityStateProvider.overrideWithValue(network),
    businessCapabilitiesProvider.overrideWithValue(caps),
    quotationReferenceRepositoryProvider.overrideWithValue(references),
  ];
  final container = ProviderContainer(overrides: overrides());
  final connectionSubscription = container
      .listen<AsyncValue<ConnectivityState>>(
        connectivityStateProvider,
        (_, next) => events.add('connection observed ${next.value}'),
      );
  final capsSubscription = container.listen<AsyncValue<Set<String>>>(
    businessCapabilitiesProvider,
    (_, next) => events.add('capabilities observed ${next.value?.length}'),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    connectionSubscription.close();
    capsSubscription.close();
    container.dispose();
  });
  void publish() {
    container.updateOverrides(overrides());
    container.read(activeTenantContextProvider);
    container.read(connectivityStateProvider);
    container.read(businessCapabilitiesProvider);
  }

  void restoreChange() {
    events.add('loss begins');
    final originalScope = scope;
    final originalNetwork = network;
    final originalCaps = caps;
    if (kind == 'connection') {
      network = const AsyncData(ConnectivityState.offline);
    } else if (kind == 'actor') {
      scope = scope.copyWith(actorId: 'replacement');
    } else {
      caps = const AsyncData<Set<String>>({});
    }
    publish();
    events.add('loss published');
    scope = originalScope;
    network = originalNetwork;
    caps = originalCaps;
    publish();
    events.add('restoration published');
  }

  void schedule(int remaining) {
    if (remaining == 0) {
      restoreChange();
    } else {
      Future<void>.microtask(() => schedule(remaining - 1));
    }
  }

  if (kind != null) observer.change = () => schedule(depth);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: JentraTheme.light(),
        navigatorObservers: [observer],
        home: Scaffold(
          body: SingleChildScrollView(
            child: fulfillment
                ? SalesOrderFulfillmentEditor(
                    form: q.detail().draft.toJson(),
                    onChanged: (form) async {
                      events.add('result consumed');
                      changed.add(Map<String, Object?>.from(form));
                    },
                    enabled: true,
                    online: true,
                  )
                : QuotationEditor(
                    form: q.detail().draft.toJson(),
                    onChanged: (form) async {
                      events.add('result consumed');
                      changed.add(Map<String, Object?>.from(form));
                    },
                    enabled: true,
                    online: true,
                    baseCurrency: 'LKR',
                  ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final readsBeforePicker = references.reads;
  await tester.tap(
    fulfillment
        ? find.text('Choose warehouse')
        : find.byKey(const Key('pick-customer_id')),
  );
  await tester.pumpAndSettle();
  final privateLabel = fulfillment
      ? 'Private original warehouse'
      : 'Private original customer';
  expect(find.text(privateLabel), findsOneWidget);
  expect(
    references.reads,
    readsBeforePicker + 1,
    reason: 'Opening this picker reads one reference page; editor labels have independent reads.',
  );
  await tester.tap(find.text(privateLabel));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  expect(
    changed.single[fulfillment ? 'warehouse_id' : 'customer_id'],
    fulfillment ? 'private-warehouse' : 'private-customer',
  );
  if (kind != null) {
    final consumed = events.indexOf('result consumed');
    final loss = events.indexOf('loss begins');
    expect(consumed, greaterThanOrEqualTo(0));
    expect(
      loss,
      greaterThan(consumed),
      reason: 'This scheduled change occurs after result consumption, not in its authorization lifetime.',
    );
  }
  await tester.pumpWidget(const SizedBox.shrink());
}

class ContinuationReferences extends References {
  @override
  Future<CursorPage<QuotationReference>> pageReferences({
    required TenantContext context,
    required QuotationReferenceKind kind,
    required QuotationReferenceQuery query,
  }) async {
    if (kind != QuotationReferenceKind.warehouse) {
      return super.pageReferences(context: context, kind: kind, query: query);
    }
    reads++;
    return CursorPage(
      items: [
        QuotationReference(
          id: 'private-warehouse',
          label: 'Private original warehouse',
          values: {},
        ),
      ],
      limit: 50,
    );
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/sales/quotation_editor.dart';
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
  for (final kind in ['connection', 'actor', 'capabilities']) {
    for (final depth in [1, 2, 3]) {
      testWidgets(
        'quotation editor rejects $kind restoration at continuation microtask depth $depth',
        (tester) async {
          await _exercise(tester, kind: kind, depth: depth);
        },
      );
    }
  }
  testWidgets(
    'quotation editor attaches one current reference after unchanged continuation',
    (tester) async {
      await _exercise(tester);
    },
  );
}

Future<void> _exercise(
  WidgetTester tester, {
  String? kind,
  int depth = 0,
}) async {
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final references = References();
  final observer = ContinuationObserver();
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
        (_, _) {},
      );
  final capsSubscription = container.listen<AsyncValue<Set<String>>>(
    businessCapabilitiesProvider,
    (_, _) {},
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
    scope = originalScope;
    network = originalNetwork;
    caps = originalCaps;
    publish();
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
            child: QuotationEditor(
              form: q.detail().draft.toJson(),
              onChanged: (form) async =>
                  changed.add(Map<String, Object?>.from(form)),
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
  await tester.tap(find.byKey(const Key('pick-customer_id')));
  await tester.pumpAndSettle();
  expect(find.text('Private original customer'), findsOneWidget);
  await tester.tap(find.text('Private original customer'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  if (kind == null) {
    expect(changed.single['customer_id'], 'private-customer');
  } else {
    expect(
      changed,
      isEmpty,
      reason: 'A restored provider cannot authorize the result of the original open selector.',
    );
  }
  expect(references.reads, 1);
  await tester.pumpWidget(const SizedBox.shrink());
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

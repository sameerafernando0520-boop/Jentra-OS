import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/app.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/router.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

void main() {
  Future<ProviderContainer> start(
    WidgetTester tester, {
    Set<String> Function()? capabilities,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            const RuntimeConfig(
              environment: 'preview',
              supabaseUrl: '',
              supabasePublishableKey: '',
            ),
          ),
          foundationGatewayProvider.overrideWithValue(null),
          businessCapabilitiesProvider.overrideWith(
            (ref) async => capabilities?.call() ?? {},
          ),
          connectivityStateProvider.overrideWith(
            (ref) => Stream.value(ConnectivityState.online),
          ),
          appPreferencesProvider.overrideWithBuild(
            (ref, notifier) async => const AppPreferences(
              themeMode: ThemeMode.light,
              density: JentraDensity.comfortable,
            ),
          ),
          tenantListProvider.overrideWithBuild(
            (ref, notifier) async => const [
              TenantSummary(
                id: 'keyboard-fixture',
                name: 'Keyboard fixture',
                slug: 'keyboard-fixture',
                status: 'active',
                membershipStatus: 'active',
              ),
            ],
          ),
        ],
        child: const JentraApp(),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(JentraApp)),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    return container;
  }

  String location(ProviderContainer container) =>
      container.read(routerProvider).routeInformationProvider.value.uri.path;
  Finder getTiles() =>
      find.descendant(of: find.byType(Dialog), matching: find.byType(ListTile));

  testWidgets(
    'arrow selection and Enter open the selected visible destination',
    (tester) async {
      final container = await start(tester);
      final tiles = tester.widgetList<ListTile>(getTiles()).toList();
      expect(tiles.first.selected, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final selected = tester.widgetList<ListTile>(getTiles()).toList();
      expect(selected[1].selected, isTrue);
      final selectedTitle = (selected[1].title! as Text).data;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(location(container), isNot('/dashboard'));
      expect(find.text(selectedTitle!), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Up wraps to the last command and scrolls it into view', (
    tester,
  ) async {
    final container = await start(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    final selected = getTiles()
        .evaluate()
        .where((e) => (e.widget as ListTile).selected)
        .single;
    expect(
      ((selected.widget as ListTile).title! as Text).data,
      'Design system',
    );
    final viewport = tester.getRect(
      find
          .descendant(
            of: find.byType(Dialog),
            matching: find.byType(SingleChildScrollView),
          )
          .first,
    );
    expect(
      viewport.contains(tester.getCenter(find.byWidget(selected.widget))),
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.pumpAndSettle();
    expect(location(container), '/catalogue');
    expect(tester.takeException(), isNull);
  });

  testWidgets('search resets selection and Enter opens its first match', (
    tester,
  ) async {
    final container = await start(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.enterText(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      ),
      'Design',
    );
    await tester.pumpAndSettle();
    expect(getTiles(), findsOneWidget);
    expect(tester.widget<ListTile>(getTiles()).selected, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(location(container), '/catalogue');
  });

  testWidgets('empty results ignore navigation and Escape closes the palette', (
    tester,
  ) async {
    final container = await start(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      ),
      'no-such-command',
    );
    await tester.pumpAndSettle();
    for (final key in [
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.enter,
    ]) {
      await tester.sendKeyEvent(key);
    }
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(location(container), '/dashboard');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('permission revocation removes a selected command before Enter', (
    tester,
  ) async {
    var permissions = {'analytics.view', 'crm.opportunities.view'};
    final container = await start(tester, capabilities: () => permissions);
    await tester.enterText(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      ),
      'Analytics',
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(getTiles(), findsOneWidget);
    permissions = {};
    container.invalidate(businessCapabilitiesProvider);
    await tester.pumpAndSettle();
    expect(getTiles(), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(location(container), '/dashboard');
  });

  testWidgets('Enter on a document link retains destination scope checks', (
    tester,
  ) async {
    final container = await start(tester);
    const documentLink =
        '/operations/documents?tenant=00000000-0000-4000-8000-000000000001&entity=00000000-0000-4000-8000-000000000002&branch=00000000-0000-4000-8000-000000000003&kind=supplier_bill&id=00000000-0000-4000-8000-000000000004';
    await tester.enterText(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      ),
      documentLink,
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(location(container), '/operations/documents');
    expect(
      find.text(
        'This document destination is unavailable in the selected business scope.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

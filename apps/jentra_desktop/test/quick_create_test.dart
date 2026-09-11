import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/app.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/setup/business_setup_controller.dart';
import 'package:jentra_desktop/src/router.dart';
import 'package:jentra_desktop/src/shell/quick_create_dialog.dart';
import 'package:jentra_domain/jentra_domain.dart';

final createPermissions = {
  BusinessSetupResource.parties.viewPermission,
  BusinessSetupResource.parties.managePermission,
  'sales.quotations.view',
  'sales.quotations.manage',
  'sales.invoices.view',
  'sales.invoices.manage',
};

Future<ProviderContainer> pumpCreate(
  WidgetTester tester, {
  Set<String>? permissions,
  Set<String> Function()? readPermissions,
}) async {
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appPreferencesProvider.overrideWithBuild(
          (ref, notifier) async => const AppPreferences(
            themeMode: ThemeMode.light,
            density: JentraDensity.comfortable,
          ),
        ),
        businessCapabilitiesProvider.overrideWith(
          (ref) async =>
              readPermissions?.call() ?? permissions ?? createPermissions,
        ),
      ],
      child: const JentraApp(),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(JentraApp)),
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Create'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUpAll(() async {
    const fonts = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${fonts}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${fonts}Manrope-Medium.ttf'))
          ..addFont(rootBundle.load('${fonts}Manrope-SemiBold.ttf')))
        .load();
    await (FontLoader(
      JentraTypography.monoFamily,
    )..addFont(rootBundle.load('${fonts}IBMPlexMono-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'customer quick create opens the party workspace and its create control',
    (tester) async {
      final container = await pumpCreate(tester);
      expect(find.text('Purchase request'), findsNothing);
      expect(find.text('Task'), findsNothing);
      expect(find.text('Service ticket'), findsNothing);
      await expectLater(
        find.byType(JentraApp),
        matchesGoldenFile('goldens/quick_create_workspace_links.png'),
      );
      await tester.tap(find.widgetWithText(ListTile, 'Customer'));
      await tester.pumpAndSettle();
      expect(find.byType(QuickCreateDialog), findsNothing);
      expect(
        container
            .read(routerProvider)
            .routeInformationProvider
            .value
            .uri
            .toString(),
        '/setup?resource=parties',
      );
      expect(
        container.read(businessSetupControllerProvider).requireValue.resource,
        BusinessSetupResource.parties,
      );
      expect(find.text('Create party'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('quotation quick create leaves the menu and opens sales', (
    tester,
  ) async {
    final container = await pumpCreate(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Quotation'));
    await tester.pumpAndSettle();
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/sales',
    );
    expect(find.byType(QuickCreateDialog), findsNothing);
  });
  testWidgets(
    'invoice quick create routes with an explicit invoice selection',
    (tester) async {
      final container = await pumpCreate(tester);
      await tester.tap(find.widgetWithText(ListTile, 'Invoice draft'));
      await tester.pumpAndSettle();
      expect(
        container
            .read(routerProvider)
            .routeInformationProvider
            .value
            .uri
            .toString(),
        '/receivables?kind=sales_invoice',
      );
      expect(find.byType(QuickCreateDialog), findsNothing);
    },
  );
  testWidgets('create actions are hidden when the role cannot manage records', (
    tester,
  ) async {
    await pumpCreate(tester, permissions: {'parties.view'});
    expect(
      find.text('Your current role has no available create actions.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(ListTile, 'Customer'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Quotation'), findsNothing);
  });
  testWidgets('an open create menu drops actions when access changes', (
    tester,
  ) async {
    var granted = createPermissions;
    final container = await pumpCreate(tester, readPermissions: () => granted);
    granted = <String>{};
    container.invalidate(businessCapabilitiesProvider);
    await container.read(businessCapabilitiesProvider.future);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Customer'), findsNothing);
    expect(
      find.text('Your current role has no available create actions.'),
      findsOneWidget,
    );
  });
}

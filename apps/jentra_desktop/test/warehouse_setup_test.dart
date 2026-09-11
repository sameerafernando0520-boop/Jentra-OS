import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/app.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/setup/business_setup_controller.dart';
import 'package:jentra_desktop/src/router.dart';
import 'package:jentra_platform/jentra_platform.dart';

class _Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

Future<ProviderContainer> pumpWarehouse(
  WidgetTester tester, {
  bool manage = true,
}) async {
  final db = JentraLocalDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await tester.binding.setSurfaceSize(const Size(1440, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localDatabaseProvider.overrideWithValue(db),
        draftCipherProvider.overrideWithValue(DraftCipher(keyStore: _Keys())),
        appPreferencesProvider.overrideWithBuild(
          (ref, notifier) async => const AppPreferences(
            themeMode: ThemeMode.light,
            density: JentraDensity.comfortable,
          ),
        ),
        businessCapabilitiesProvider.overrideWith(
          (ref) async => {'core.setup.view', if (manage) 'core.setup.manage'},
        ),
      ],
      child: const JentraApp(),
    ),
  );
  await tester.pumpAndSettle();
  final c = ProviderScope.containerOf(tester.element(find.byType(JentraApp)));
  c.listen(authenticatedActorProvider, (_, _) {});
  await tester.pumpAndSettle();
  c.read(routerProvider).go('/setup?resource=warehouses');
  await tester.pumpAndSettle();
  return c;
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
    'warehouse form uses selected branch and preserves scope on save',
    (tester) async {
      final c = await pumpWarehouse(tester);
      await tester.tap(find.text('Create warehouse'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Warehouse code'),
        'ACPT-WH',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Warehouse name'),
        'Acceptance warehouse',
      );
      final branch = c.read(businessScopeProvider).requireValue.branch!;
      await tester.pumpAndSettle();
      expect(find.text('${branch.code} · ${branch.name}'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Branch'), findsNothing);
      await expectLater(
        find.byType(JentraApp),
        matchesGoldenFile('goldens/warehouse_setup_form.png'),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Save to server'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      final rows = c.read(businessSetupControllerProvider).requireValue.items;
      final saved = rows.singleWhere((r) => r.code == 'ACPT-WH');
      expect(saved.fields['branch_id'], branch.id);
      expect(
        saved.legalEntityId,
        c.read(activeTenantContextProvider)!.legalEntityId,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('warehouse viewer cannot create records', (tester) async {
    final c = await pumpWarehouse(tester, manage: false);
    expect(
      c.read(businessSetupControllerProvider).requireValue.canManage,
      isFalse,
    );
    expect(find.text('Create warehouse'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

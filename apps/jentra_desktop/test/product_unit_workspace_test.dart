import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:jentra_desktop/src/features/procurement/product_unit_controller.dart';
import 'package:jentra_desktop/src/features/procurement/product_unit_screen.dart';

import 'support/procurement_fakes.dart';

class UnitGateway extends Gateway implements ProductUnitGateway {
  @override
  Future<Map<String, Object?>> saveProductUnit(
    CommandEnvelope<Map<String, Object?>> command,
  ) => source(command);
}

void main() {
  setUpAll(() async {
    const base = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${base}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${base}Manrope-SemiBold.ttf')))
        .load();
  });
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late UnitGateway gateway;
  late ProductUnitController c;
  ProductUnitController controller() => ProductUnitController(
    scope: scope,
    gateway: gateway,
    references: gateway,
    drafts: drafts,
    online: true,
  );
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore.procurement(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = UnitGateway();
    c = controller();
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Future<void> draft() async {
    await c.initialize();
    await c.edit();
    c.update('product_id', 'paper');
    c.update('_product_name', 'Office paper');
    c.update('unit_id', 'carton');
    c.update('_unit_name', 'Carton');
    c.update('numerator', '12');
  }

  test(
    'unit command restores exact positive integer strings after restart',
    () async {
      await draft();
      await c.saveServer();
      final original = jsonEncode(gateway.commands.single.toJson((p) => p));
      c.dispose();
      c = controller();
      await c.initialize();
      c.update('numerator', '24');
      expect(c.form!['numerator'], '12');
      gateway.uncertain = false;
      await c.saveServer();
      expect(jsonEncode(gateway.commands.last.toJson((p) => p)), original);
      expect(c.form, isNull);
    },
  );
  test('fractional or numeric ratio never enters command transport', () async {
    await draft();
    c.update('numerator', '1.5');
    await c.saveServer();
    expect(gateway.commands, isEmpty);
    expect(c.error, contains('positive integer'));
    c.update('numerator', 12);
    await c.saveServer();
    expect(gateway.commands, isEmpty);
  });
  for (final dark in [false, true]) {
    testWidgets('product unit ${dark ? 'dark' : 'light'} at 200%', (
      tester,
    ) async {
      await tester.runAsync(draft);
      tester.view.physicalSize = const Size(1024, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? JentraTheme.dark() : JentraTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(body: ProductUnitWorkspace(controller: c)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/product_unit_${dark ? 'dark' : 'light'}_200.png',
        ),
      );
      await tester.ensureVisible(find.text('Save on this device'));
      await tester.pumpAndSettle();
      expect(find.text('Save on this device').hitTestable(), findsOneWidget);
    });
  }
}

import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/features/procurement/sourcing_screen.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:jentra_desktop/src/features/procurement/sourcing_controller.dart';

import 'support/procurement_fakes.dart';

void main() {
  setUpAll(() async {
    const base = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${base}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${base}Manrope-SemiBold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late Gateway gateway;
  late SourcingController c;
  SourcingController controller() => SourcingController(
    scope: scope,
    gateway: gateway,
    drafts: drafts,
    online: true,
  );
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore.procurement(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = Gateway();
    c = controller();
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Future<void> quote() async {
    await c.initialize();
    c.select({
      'id': 'rfq',
      'version': 1,
      'status': 'issued',
      'quotes': [],
      'lines': [
        {'source_line_id': 'line', 'description': 'Paper', 'quantity': '3'},
      ],
    });
    await c.quote({'id': 'supplier', 'name': 'Supplier One'});
    c.update('lines', [
      {
        'source_line_id': 'line',
        'description': 'Paper',
        'quantity': '3',
        'unit_price': '123.456789',
        'discount_percent': '0',
        'tax_definition_id': null,
        '_tax_label': 'Display only',
      },
    ]);
  }

  test(
    'uncertain quotation survives controller restart with exact envelope and frozen values',
    () async {
      await quote();
      await c.saveServer();
      final original = jsonEncode(gateway.commands.single.toJson((p) => p));
      c.dispose();
      c = controller();
      await c.initialize();
      c.update('payment_terms', 'modified');
      expect(c.form!['payment_terms'], '');
      gateway.uncertain = false;
      await c.saveServer();
      expect(jsonEncode(gateway.commands.last.toJson((p) => p)), original);
      expect(c.form, isNull);
      expect(await drafts.load(scope, SourcingController.slot), isNull);
    },
  );
  test('quotation command excludes UI labels at every level', () async {
    await quote();
    await c.saveServer();
    expect(
      jsonEncode(gateway.commands.single.payload),
      isNot(contains('_tax_label')),
    );
    expect(gateway.commands.single.payload['lines'], [
      {
        'source_line_id': 'line',
        'quantity': '3',
        'unit_price': '123.456789',
        'discount_percent': '0',
        'tax_definition_id': null,
      },
    ]);
  });
  test(
    'confirmed save remains confirmed when register refresh fails',
    () async {
      await quote();
      gateway.uncertain = false;
      gateway.failRefresh = true;
      await c.saveServer();
      expect(c.form, isNull);
      expect(c.local, isNull);
      expect(c.message, contains('saved'));
      expect(c.error, contains('refresh'));
      expect(await drafts.load(scope, SourcingController.slot), isNull);
    },
  );
  test('offline quote edits persist on navigation without sending', () async {
    await quote();
    c.setOnline(false);
    await c.saveServer();
    expect(gateway.commands, isEmpty);
    expect(await c.canLeave(), isTrue);
    expect(
      (await drafts.load(scope, SourcingController.slot))!.form['lines'],
      c.form!['lines'],
    );
  });
  for (final dark in [false, true]) {
    testWidgets(
      'supplier quote editor ${dark ? 'dark' : 'light'} retains controls at 200%',
      (tester) async {
        await tester.runAsync(quote);
        c.update('quote_date', '2026-09-13');
        c.update('valid_until', '2026-09-30');
        c.update('rate_date', '2026-09-13');
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
              child: Scaffold(body: SourcingWorkspace(controller: c)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/supplier_quote_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
        await tester.ensureVisible(find.text('Save on this device'));
        await tester.pumpAndSettle();
        expect(find.text('Save on this device').hitTestable(), findsOneWidget);
        expect(find.text('Discard local draft').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

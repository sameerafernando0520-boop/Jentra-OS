import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:jentra_desktop/src/features/procurement/purchase_return_controller.dart';
import 'package:jentra_desktop/src/features/procurement/purchase_return_screen.dart';

import 'support/procurement_fakes.dart';

class ReturnGateway extends Gateway implements PurchaseReturnGateway {
  @override
  Future<CursorPage<Map<String, Object?>>> returns(
    TenantContext scope, {
    String? after,
  }) => rfqs(scope, after: after);
  @override
  Future<Map<String, Object?>> postReturn(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    await source(command);
    return {
      ...command.payload,
      'status': 'posted',
      'document_number': 'RT-0042',
      'total': '16.67',
      'tax_total': '0',
      'currency_code': 'LKR',
    };
  }

  @override
  Future<Map<String, Object?>> returnSources(
    TenantContext scope,
    String kind, {
    String? after,
    String search = '',
  }) async => {'items': []};
  @override
  Future<Map<String, Object?>> returnSource(
    TenantContext scope,
    String kind,
    String sourceId,
  ) async => {
    'document_number': 'SB-0042',
    'supplier_name': 'Office Supplies Lanka',
    'currency_code': 'LKR',
    'rounding_scale': 2,
    'lines': [
      {
        'source_line_id': 'source-line',
        'description': 'Recycled office paper',
        'eligible_quantity': '0.45',
        'quantity': '0.45',
        'returned_quantity': '0',
        'net_amount': '50',
        'tax_amount': '0',
        'conversion_numerator': '12',
        'conversion_denominator': '1',
        'serial_options': [],
        'lot_code': 'LOT-0042',
      },
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
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
  late ReturnGateway gateway;
  late PurchaseReturnController c;
  PurchaseReturnController controller({TenantContext context = scope}) =>
      PurchaseReturnController(
        scope: context,
        gateway: gateway,
        drafts: drafts,
        online: true,
      );
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore.procurement(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = ReturnGateway();
    c = controller();
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Future<void> draft() async {
    await c.initialize();
    await c.create('bill', 'bill');
    c.update('document_date', '2026-09-15');
    c.update('reference', 'Supplier authorization RET-0042');
    c.update('reason', 'Supplier accepted damaged packaging');
    c.line(0, 'quantity', '0.15');
  }

  test(
    'return retains sealed posting and exact quantity across uncertain restart',
    () async {
      await draft();
      await c.post();
      final original = jsonEncode(gateway.commands.single.toJson((p) => p));
      expect(gateway.commands.single.payload['lines'], [
        {
          'line_id': (c.form!['lines'] as List).single['line_id'],
          'source_line_id': 'source-line',
          'quantity': '0.15',
          'serial_ids': [],
        },
      ]);
      c.dispose();
      c = controller();
      await c.initialize();
      c.line(0, 'quantity', '0.2');
      expect((c.form!['lines'] as List).single['quantity'], '0.15');
      gateway.uncertain = false;
      await c.post();
      expect(jsonEncode(gateway.commands.last.toJson((p) => p)), original);
      expect(c.form, isNull);
    },
  );
  test('over-return is stopped before any command is sealed', () async {
    await draft();
    c.line(0, 'quantity', '0.450001');
    await c.post();
    expect(c.error, contains('exceeds'));
    expect(gateway.commands, isEmpty);
    expect(c.local?.pending, isNull);
  });
  test('scope switch does not load another branch return draft', () async {
    await draft();
    await c.saveLocal();
    c.dispose();
    c = controller(
      context: const TenantContext(
        tenantId: 't',
        actorId: 'a',
        legalEntityId: 'e',
        branchId: 'other',
      ),
    );
    await c.initialize();
    expect(c.form, isNull);
  });
  test('offline navigation persists latest line edits', () async {
    await draft();
    c.setOnline(false);
    c.line(0, 'quantity', '0.123456');
    expect(await c.canLeave(), isTrue);
    c.dispose();
    c = controller();
    await c.initialize();
    expect((c.form!['lines'] as List).single['quantity'], '0.123456');
  });
  test(
    'successful posting is not presented as failed when refresh fails',
    () async {
      await draft();
      gateway.uncertain = false;
      gateway.failRefresh = true;
      await c.post();
      expect(c.form, isNull);
      expect(c.local, isNull);
      expect(c.error, contains('Posted successfully'));
      expect(c.message, contains('posted'));
    },
  );
  for (final dark in [false, true]) {
    testWidgets('return editor ${dark ? 'dark' : 'light'} at 200 percent', (
      tester,
    ) async {
      await draft();
      tester.view.physicalSize = const Size(1024, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? JentraTheme.dark() : JentraTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(body: PurchaseReturnWorkspace(controller: c)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/purchase_return_${dark ? 'dark' : 'light'}_200.png',
        ),
      );
    });
  }
}

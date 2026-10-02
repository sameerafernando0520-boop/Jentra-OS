import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:jentra_desktop/src/features/procurement/purchase_return_controller.dart';
import 'package:jentra_desktop/src/features/procurement/purchase_return_screen.dart';

import 'purchase_return_workspace_test.dart' show ReturnGateway;
import 'support/procurement_fakes.dart' show Keys;

class ReturnReferences extends ReturnGateway {
  bool serial = false;
  final reads = <Map<String, Object?>>[];
  @override
  Future<Map<String, Object?>> returnSources(
    TenantContext scope,
    String kind, {
    String? after,
    String search = '',
  }) async {
    reads.add({'kind': kind, 'after': after, 'search': search});
    return {
      'items': [
        {
          'id': 'original${after ?? ''}',
          'document_number': 'SOURCE-42${after ?? ''}',
          'supplier_name': 'Supplier',
          'document_date': '2026-09-20',
          'currency_code': 'LKR',
        },
      ],
      'next_cursor': after == null ? 'cursor' : null,
    };
  }

  @override
  Future<Map<String, Object?>> returnSource(
    TenantContext scope,
    String kind,
    String sourceId,
  ) async => {
    'id': sourceId,
    'document_number': 'SOURCE-42',
    'supplier_name': 'Supplier',
    'currency_code': 'LKR',
    'rounding_scale': 6,
    'lines': [
      {
        'source_line_id': 'original-line',
        'description': 'Original paper',
        'eligible_quantity': '1',
        'quantity': '1',
        'returned_quantity': '0',
        'net_amount': '9007199254.740993',
        'tax_amount': '0.000001',
        'conversion_numerator': '1',
        'conversion_denominator': '1',
        'lot_code': serial ? null : 'LOT-42',
        'serial_options': serial
            ? [
                {'id': 'available', 'code': 'SN-42', 'available': true},
                {'id': 'retired', 'code': 'SN-RET', 'available': false},
              ]
            : [],
      },
    ],
  };
}

void main() {
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late ReturnReferences gateway;
  late PurchaseReturnController c;
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore.procurement(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = ReturnReferences()..uncertain = false;
    c = PurchaseReturnController(
      scope: scope,
      gateway: gateway,
      drafts: drafts,
      online: true,
    );
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<void> enter(WidgetTester t, String label, String value) async {
    await t.ensureVisible(field(label));
    await t.enterText(field(label), value);
    await t.pump();
  }

  Future<void> tap(WidgetTester t, String text) async {
    final f = find.text(text);
    await t.ensureVisible(f);
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Future<void> render(WidgetTester t) async {
    t.view.physicalSize = const Size(1440, 2300);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PurchaseReturnWorkspace(controller: c)),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> draft(WidgetTester t, String kind) async {
    await c.initialize();
    await render(t);
    await tap(
      t,
      kind == 'bill' ? 'Return against bill' : 'Return unbilled receipt',
    );
    await t.tap(find.text('SOURCE-42 · Supplier'));
    await t.pumpAndSettle();
    await enter(t, 'Posting date (YYYY-MM-DD)', '2026-09-30');
    await enter(t, 'Supplier return reference', 'RT-42');
    await enter(t, 'Reason for return', 'Damaged original goods');
  }

  for (final kind in ['bill', 'receipt']) {
    testWidgets(
      '$kind return retains original prices and exact micro quantity',
      (t) async {
        await draft(t, kind);
        await enter(t, 'Return quantity', '0.000001');
        expect(c.preview.total, '9007.199255');
        expect(c.preview.tax, '0.000000');
        await tap(t, 'Save on this device');
        expect(
          (await drafts.load(
            scope,
            PurchaseReturnController.slot,
          ))!.form['source_id'],
          'original',
        );
        await tap(t, 'Post purchase return');
        expect(c.error, isNull);
        expect(c.form, isNull);
        final payload = gateway.commands.single.payload;
        expect(payload['source_kind'], kind);
        expect(payload['source_id'], 'original');
        final line = (payload['lines'] as List).single as Map;
        expect(line['quantity'], '0.000001');
        expect(line['source_line_id'], 'original-line');
        expect(line['net_amount'], isNull);
        await tap(t, 'Posting evidence');
        expect(find.textContaining('Journal:'), findsOneWidget);
        expect(find.textContaining('Original $kind:'), findsOneWidget);
        c.setOnline(false);
        await t.pumpAndSettle();
        expect(find.textContaining('Journal:'), findsNothing);
      },
    );
  }
  testWidgets(
    'serial return permits only available original serials and retains original posting on retry',
    (t) async {
      gateway.serial = true;
      await draft(t, 'bill');
      await enter(t, 'Return quantity', '1');
      final disabled = t.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'SN-RET'),
      );
      expect(disabled.onChanged, isNull);
      await tap(t, 'SN-42');
      gateway.uncertain = true;
      await tap(t, 'Post purchase return');
      expect(c.local!.pending, isNotNull);
      final first = jsonEncode(gateway.commands.single.toJson((v) => v));
      expect(t.widget<TextField>(field('Return quantity')).enabled, isFalse);
      gateway.uncertain = false;
      await tap(t, 'Retry saved posting');
      expect(jsonEncode(gateway.commands.last.toJson((v) => v)), first);
      expect(
        (gateway.commands.last.payload['lines'] as List).single['serial_ids'],
        ['available'],
      );
      expect(await drafts.load(scope, PurchaseReturnController.slot), isNull);
    },
  );
  testWidgets(
    'return source paging and submitted search remain independent; local discard sends no command',
    (t) async {
      await c.initialize();
      await render(t);
      await tap(t, 'Return against bill');
      await tap(t, 'Load more sources');
      expect(gateway.reads.last['after'], 'cursor');
      await enter(t, 'Search supplier or document number', 'SOURCE-42');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(gateway.reads.last, {
        'kind': 'bill',
        'after': null,
        'search': 'SOURCE-42',
      });
      await t.tap(find.text('SOURCE-42 · Supplier'));
      await t.pumpAndSettle();
      await tap(t, 'Discard local draft');
      expect(c.form, isNull);
      expect(gateway.commands, isEmpty);
      expect(await drafts.load(scope, PurchaseReturnController.slot), isNull);
    },
  );
}

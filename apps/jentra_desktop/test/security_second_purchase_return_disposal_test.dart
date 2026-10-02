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

const _scope = TenantContext(
  tenantId: 't', actorId: 'a', legalEntityId: 'e', branchId: 'b',
);
const _posted = <String, Object?>{
  'id': 'posted-return', 'document_number': 'RT-PRIVATE',
  'document_date': '2026-09-15', 'currency_code': 'LKR',
  'total': '16.67', 'reference': 'Private posted reference',
};
const _eligible = <String, Object?>{
  'id': 'eligible-bill', 'document_number': 'SB-PRIVATE',
  'supplier_name': 'Private eligible supplier',
  'document_date': '2026-09-14', 'currency_code': 'LKR',
};

class _Gateway extends ReturnGateway {
  @override
  Future<CursorPage<Map<String, Object?>>> returns(
    TenantContext scope, {String? after},
  ) async => CursorPage(items: [_posted], limit: 50, nextCursor: 'posted-next');

  @override
  Future<Map<String, Object?>> returnSources(
    TenantContext scope, String kind, {String? after, String search = ''},
  ) async => {'items': [_eligible], 'next_cursor': 'source-next'};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late JentraLocalDatabase db;
  late QuotationDraftStore store;
  late _Gateway gateway;
  late PurchaseReturnController c;
  var disposed = false;
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    store = QuotationDraftStore.procurement(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = _Gateway();
    c = PurchaseReturnController(
      scope: _scope, gateway: gateway, drafts: store, online: true,
    );
    disposed = false;
  });
  tearDown(() async {
    if (!disposed) c.dispose();
    await db.close();
  });

  test('disposal clears current return evidence while retaining the original uncertain command', () async {
    await c.initialize();
    await c.create('bill', 'eligible-bill');
    c.update('document_date', '2026-09-15');
    c.update('reason', 'Original exact supplier return');
    c.line(0, 'quantity', '0.15');
    gateway.uncertain = true;
    await c.post();
    expect(gateway.commands, hasLength(1));
    final before = (await store.load(_scope, PurchaseReturnController.slot))!;
    expect(before.pending, isNotNull);
    final original = jsonEncode(before.pending!.envelope.toJson((x) => x));
    expect(c.page.items, [_posted]);
    final notices = <bool>[];
    c.addListener(() => notices.add(c.locked));

    c.dispose();
    disposed = true;

    expect(c.page.items, isEmpty);
    expect(c.page.nextCursor, isNull);
    expect(c.selected, isNull);
    expect(c.sources, isEmpty);
    expect(c.sourceCursor, isNull);
    expect(c.sourceKind, isNull);
    expect(notices, [true]);
    final after = (await store.load(_scope, PurchaseReturnController.slot))!;
    expect(after.form, before.form);
    expect(jsonEncode(after.pending!.envelope.toJson((x) => x)), original);
    expect(gateway.commands, hasLength(1));
  });

  testWidgets('already visible eligible source and posted return vanish when their controller is disposed', (tester) async {
    await tester.runAsync(() async {
      await c.initialize();
      await c.findSources('bill');
    });
    tester.view.physicalSize = const Size(1024, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PurchaseReturnWorkspace(controller: c)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('SB-PRIVATE · Private eligible supplier'), findsOneWidget);
    expect(find.text('RT-PRIVATE · posted'), findsOneWidget);

    c.dispose();
    disposed = true;
    await tester.pumpAndSettle();

    expect(find.text('SB-PRIVATE · Private eligible supplier'), findsNothing);
    expect(find.text('RT-PRIVATE · posted'), findsNothing);
    expect(find.text('Choose an eligible bill'), findsNothing);
    expect(gateway.commands, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

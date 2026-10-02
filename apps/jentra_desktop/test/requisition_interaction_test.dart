import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:jentra_desktop/src/features/procurement/procurement_controller.dart';
import 'package:jentra_desktop/src/features/procurement/procurement_screen.dart';

import 'support/procurement_fakes.dart';

class RequisitionEvidence extends Gateway {
  List<Map<String, Object?>> documents = [];
  final pageCursors = <String?>[];
  @override
  Future<Map<String, Object?>> references(
    TenantContext scope,
    String resource, {
    String? after,
    String search = '',
  }) async => {
    'base_currency': 'LKR',
    'items': [
      if (resource == 'products')
        {'id': 'p', 'name': 'Paper', 'code': 'P', 'unit_id': 'u'}
      else
        {
          'id': 'u',
          'name': 'Pack',
          'code': 'PK',
          'conversion_numerator': '3',
          'conversion_denominator': '2',
        },
    ],
  };
  @override
  Future<CursorPage<Map<String, Object?>>> page(
    TenantContext scope, {
    String? after,
  }) async {
    pageCursors.add(after);
    return CursorPage(
      items: after == null
          ? documents
          : [
              {...documents.first, 'id': 'second'},
            ],
      limit: 50,
      nextCursor: after == null && documents.isNotEmpty ? 'cursor' : null,
    );
  }

  @override
  Future<Map<String, Object?>> save(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    if (uncertain) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Retry original request.',
      );
    }
    return {...command.payload, 'status': 'draft', 'version': 2};
  }

  @override
  Future<Map<String, Object?>> transition(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    return {
      'id': command.payload['document_id'],
      'status': 'approved',
      'version': 5,
    };
  }
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
  late RequisitionEvidence gateway;
  late ProcurementController c;
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore.procurement(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = RequisitionEvidence()..uncertain = false;
    c = ProcurementController(
      scope: scope,
      gateway: gateway,
      store: drafts,
      online: true,
      canApprove: true,
    );
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProcurementWorkspace(controller: c)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<void> settleCommand(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && c.busy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(c.busy, isFalse);
    });
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final target = find.text(label);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump();
    await settleCommand(tester);
  }

  Future<void> draft() async {
    await c.initialize();
    await c.create('LKR');
    c.update('need_by', '2026-09-30');
    c.update('justification', 'Exact physical replenishment');
    c.update('lines', [
      {
        'line_id': 'l',
        'description': 'Paper',
        'unit_id': 'u',
        'quantity': '0.000002',
        'estimated_unit_price': '9007199254.740993',
        'conversion_numerator': '3',
        'conversion_denominator': '2',
      },
    ]);
  }

  testWidgets(
    'requisition entry uses catalogue conversion and exact micro quantity through encrypted save',
    (tester) async {
      await tester.runAsync(c.initialize);
      await pump(tester);
      await tap(tester, 'New requisition');
      await tester.enterText(field('Need-by date'), '2026-09-30');
      await tester.enterText(field('Base currency'), 'LKR');
      await tester.enterText(
        field('Why is this purchase needed?'),
        'Exact physical replenishment',
      );
      await tap(tester, 'Add item');
      await tester.enterText(
        field('Item 1 description'),
        'Initial free-text paper',
      );
      await tap(tester, 'Choose catalogue product (optional)');
      await tester.tap(find.text('P · Paper'));
      await tester.pumpAndSettle();
      await tap(tester, 'Pack');
      await tester.tap(find.text('PK · Pack'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Quantity'), '0.000002');
      await tester.enterText(field('Unit estimate'), '9007199254.740993');
      await tester.pumpAndSettle();
      expect(find.text('Estimated total · LKR 18014.398509'), findsOneWidget);
      await tap(tester, 'Save on this device');
      final saved = (await drafts.load(scope, ProcurementController.slot))!;
      expect(
        (saved.form['lines'] as List).single['estimated_unit_price'],
        '9007199254.740993',
      );
      await tap(tester, 'Save to server');
      final line =
          (gateway.commands.single.payload['lines'] as List).single as Map;
      expect(line['product_id'], 'p');
      expect(line['quantity'], '0.000002');
      expect(line['conversion_numerator'], '3');
      expect(line['conversion_denominator'], '2');
      expect(line.containsKey('unit_label'), isFalse);
      expect(c.error, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'incomplete entry exposes advisory validation and removal without sealing a request',
    (tester) async {
      await tester.runAsync(() async {
        await c.initialize();
        await c.create('LKR');
      });
      await pump(tester);
      await tap(tester, 'Add item');
      expect(
        find.text(
          'Estimated total · Complete the item values to calculate an estimate.',
        ),
        findsOneWidget,
      );
      await tap(tester, 'Save to server');
      expect(c.error, contains('valid need-by date and justification'));
      expect(gateway.commands, isEmpty);
      await tester.tap(find.byTooltip('Remove item 1'));
      await tester.pumpAndSettle();
      expect(c.form!['lines'], isEmpty);
      expect(
        (await drafts.load(scope, ProcurementController.slot))!.pending,
        isNull,
      );
    },
  );
  testWidgets(
    'offline draft action remains local and uncertain retry retains exact wire payload',
    (tester) async {
      await tester.runAsync(draft);
      await pump(tester);
      c.setOnline(false);
      await tester.pumpAndSettle();
      await tap(tester, 'Save on this device');
      expect(gateway.commands, isEmpty);
      expect(
        (await drafts.load(
          scope,
          ProcurementController.slot,
        ))!.form['justification'],
        'Exact physical replenishment',
      );
      c.setOnline(true);
      gateway.uncertain = true;
      await tester.pumpAndSettle();
      await tap(tester, 'Save to server');
      final original = jsonEncode(gateway.commands.single.toJson((p) => p));
      expect(find.text('Retry saved command'), findsOneWidget);
      gateway.uncertain = false;
      await tap(tester, 'Retry saved command');
      expect(jsonEncode(gateway.commands.last.toJson((p) => p)), original);
      expect(c.form, isNull);
      expect(await drafts.load(scope, ProcurementController.slot), isNull);
    },
  );
  for (final verb in ['submit', 'approve', 'reject', 'recall', 'cancel']) {
    testWidgets(
      'requisition $verb uses the selected version and governed reason',
      (tester) async {
        final status = verb == 'submit' || verb == 'cancel'
            ? 'draft'
            : 'pending_approval';
        gateway.documents = [
          {
            'id': 'request',
            'version': 4,
            'status': status,
            'justification': 'Physical replenishment',
            'need_by': '2026-09-30',
            'currency_code': 'LKR',
            'estimated_total': '9007199254.740993',
            'created_by': 'other',
            'lines': [],
          },
        ];
        await tester.runAsync(c.initialize);
        await pump(tester);
        await tap(tester, 'Physical replenishment');
        final label = {
          'submit': 'Submit for approval',
          'approve': 'Approve',
          'reject': 'Reject',
          'recall': 'Recall to draft',
          'cancel': 'Cancel requisition',
        }[verb]!;
        await tap(tester, label);
        if (['reject', 'recall', 'cancel'].contains(verb)) {
          await tester.enterText(field('Reason'), '  Reasoned $verb  ');
          await tap(tester, 'Confirm');
        }
        final command = gateway.commands.single;
        expect(command.expectedEntityVersion, 4);
        expect(command.context.toJson(), scope.toJson());
        expect(command.payload['document_id'], 'request');
        if (['approve', 'reject'].contains(verb)) {
          expect(
            command.payload['decision'],
            verb == 'approve' ? 'approved' : 'rejected',
          );
        }
        if (['reject', 'recall', 'cancel'].contains(verb)) {
          expect(command.payload['reason'], 'Reasoned $verb');
        }
        expect(await drafts.load(scope, ProcurementController.slot), isNull);
        expect(c.error, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'requester segregation and paged edit preserve original revision',
    (tester) async {
      gateway.documents = [
        {
          'id': 'request',
          'version': 4,
          'status': 'pending_approval',
          'justification': 'Physical replenishment',
          'need_by': '2026-09-30',
          'currency_code': 'LKR',
          'estimated_total': '1.000001',
          'requester_id': 'a',
          'lines': [],
        },
      ];
      await tester.runAsync(c.initialize);
      await pump(tester);
      await tap(tester, 'Load more');
      expect(gateway.pageCursors.last, 'cursor');
      expect(c.page.items.length, 2);
      c.select(gateway.documents.single);
      await tester.pumpAndSettle();
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
      await c.transition('approve');
      expect(gateway.commands, isEmpty);
      c.setOnline(false);
      await tester.pumpAndSettle();
      expect(c.selected, isNull);
      c.setOnline(true);
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => c.edit({...gateway.documents.single, 'status': 'draft'}),
      );
      await tester.pumpAndSettle();
      expect(find.text('Edit requisition · v4'), findsOneWidget);
      expect(c.version, 4);
      await tap(tester, 'Discard local edits');
      await tap(tester, 'Discard');
      expect(c.form, isNull);
      expect(await drafts.load(scope, ProcurementController.slot), isNull);
    },
  );
}

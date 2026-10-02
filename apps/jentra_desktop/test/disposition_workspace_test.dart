import 'dart:convert';
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/disposition.dart';
import 'package:jentra_platform/disposition.dart';
import 'package:jentra_desktop/src/features/disposition/disposition_controller.dart';
import 'package:jentra_desktop/src/features/disposition/disposition_screen.dart';

import 'support/procurement_fakes.dart' show Keys;

class Dispositions implements DispositionGateway {
  bool uncertain = false;
  bool denied = false;
  Completer<Map<String, Object?>>? pageReply, commandReply;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  @override
  Future<Map<String, Object?>> page(
    TenantContext scope, {
    String? after,
  }) async {
    if (denied) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Access removed.',
      );
    }
    return pageReply?.future ?? Future.value({'items': []});
  }

  @override
  Future<Map<String, Object?>> detail(TenantContext scope, String id) async => {
    'id': id,
    'status': 'posted',
    'version': 4,
    'warehouse_id': 'w',
    'offset_account_id': 'expense',
    'document_date': '2026-09-30',
    'reason': 'Expired stock',
    'lines': [
      {
        'line_id': 'l',
        'product_id': 'p',
        'product_name': 'Paper',
        'quantity': '3',
        'tracking_mode': 'lot',
        'lot_id': 'lot',
        'serial_ids': [],
        'carrying_value': '30.037037',
      },
    ],
  };
  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? warehouse,
    String? product,
    String? after,
  }) async => {'items': []};
  @override
  Future<Map<String, Object?>> execute(
    String verb,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    if (commandReply != null) return commandReply!.future;
    if (uncertain) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Retry the saved command.',
      );
    }
    return {
      ...command.payload,
      'id': command.payload['id'] ?? command.payload['document_id'],
      'status': 'draft',
      'version': (command.expectedEntityVersion ?? 0) + 1,
      'currency_code': 'LKR',
      'grand_total': '30.037037',
      'lines': [
        for (final raw in command.payload['lines'] as List? ?? [])
          {
            ...raw as Map,
            'tracking_mode': 'none',
            'product_name': 'Paper',
            'carrying_value': '30.037037',
          },
      ],
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late JentraLocalDatabase database;
  late QuotationDraftStore drafts;
  late Dispositions gateway;
  late DispositionController controller;
  DispositionController make() => DispositionController(
    scope: scope,
    gateway: gateway,
    drafts: drafts,
    online: true,
    permissions: {
      'inventory.dispositions.post',
      'inventory.cost.view',
      'workflow.approvals.decide',
    },
  );
  setUp(() {
    database = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(database, DraftCipher(keyStore: Keys())),
    );
    gateway = Dispositions();
    controller = make();
  });
  tearDown(() async {
    controller.dispose();
    await database.close();
  });
  Future<void> populate() async {
    await controller.initialize();
    await controller.create();
    controller.update('warehouse_id', 'w');
    controller.update('offset_account_id', 'expense');
    controller.update('reason', 'Expired stock');
    controller.addProduct({
      'id': 'p',
      'name': 'Paper',
      'base_unit_id': 'u',
      'tracking_mode': 'none',
    });
    controller.updateLine(0, 'quantity', '3');
  }

  test(
    'uncertain command survives controller restart with the same wire identity',
    () async {
      await populate();
      gateway.uncertain = true;
      await controller.act('save');
      final original = jsonEncode(gateway.commands.single.toJson((p) => p));
      expect(controller.local!.pending, isNotNull);
      controller.dispose();
      controller = make();
      await controller.initialize();
      controller.update('reason', 'Changed while uncertain');
      expect(controller.form!['reason'], 'Expired stock');
      gateway.uncertain = false;
      await controller.act('retry');
      expect(jsonEncode(gateway.commands.last.toJson((p) => p)), original);
      expect(controller.local!.pending, isNull);
      expect(controller.form!['grand_total'], '30.037037');
      final raw = await database.select(database.encryptedDrafts).getSingle();
      expect(
        latin1.decode(raw.encryptedPayload),
        isNot(contains('Expired stock')),
      );
    },
  );
  test(
    'linked reverse uses server-owned lines and preserves immutable source',
    () async {
      await controller.open({'id': 'source'});
      await controller.correct(reverse: true);
      expect(controller.form!['reverses_disposition_id'], 'source');
      controller.update('reason', 'Recorded against wrong holding');
      await controller.act('save');
      expect(
        gateway.commands.single.payload['reverses_disposition_id'],
        'source',
      );
      expect(gateway.commands.single.payload.containsKey('lines'), false);
    },
  );
  testWidgets('rendered editor exposes exact preview and approval actions', (
    tester,
  ) async {
    await populate();
    await controller.act('save');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DispositionWorkspace(controller: controller)),
      ),
    );
    await tester.pump();
    expect(find.text('Stock disposition'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(
      find.text('Saved carrying value for approval: LKR 30.037037'),
      findsOneWidget,
    );
    expect(find.text('Submit for approval'), findsOneWidget);
    expect(find.text('Select held serials'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test('disconnected read cannot repopulate register and access denial hides saved work', () async {
    gateway.pageReply = Completer();
    final loading = controller.initialize();
    await Future<void>.delayed(Duration.zero);
    controller.setOnline(false);
    gateway.pageReply!.complete({
      'items': [
        {'id': 'stale', 'grand_total': '10'},
      ],
    });
    await loading;
    expect(controller.items, isEmpty);
    gateway.pageReply = null;
    controller.setOnline(true);
    await populate();
    await controller.saveLocal();
    gateway.denied = true;
    await controller.refresh();
    expect(controller.accessDenied, isTrue);
    expect(controller.locked, isTrue);
    controller.update('reason', 'Hidden mutation');
    expect(controller.form!['reason'], 'Expired stock');
    expect(
      (await drafts.load(scope, DispositionController.slot))!.form['reason'],
      'Expired stock',
    );
    gateway.denied = false;
    await controller.refresh();
    expect(controller.accessDenied, isFalse);
  });
  test('confirmed late command persists securely without restoring offline financial evidence', () async {
    await populate();
    gateway.commandReply = Completer();
    final action = controller.act('save');
    while (gateway.commands.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    controller.setOnline(false);
    gateway.commandReply!.complete({
      ...controller.form!,
      'version': 1,
      'status': 'draft',
      'grand_total': '30.037037',
    });
    await action;
    expect(controller.form, isNull);
    expect(controller.local, isNull);
    final saved = await drafts.load(scope, DispositionController.slot);
    expect(saved!.pending, isNull);
    expect(saved.form['grand_total'], isNull);
    await controller.initialize();
    expect(controller.form!['grand_total'], isNull);
  });
}

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:jentra_desktop/src/features/inventory_valuation/inventory_valuation_controller.dart';

import 'inventory_valuation_workspace_test.dart' show ValuationGateway, report;
import 'support/procurement_fakes.dart' show Keys;

class DelayedValuation extends ValuationGateway {
  Completer<void>? optionPause, pagePause, generationPause;
  Completer<void> entered = Completer<void>();
  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? after,
  }) async {
    if (optionPause != null) {
      if (!entered.isCompleted) entered.complete();
      await optionPause!.future;
    }
    return super.options(scope, resource, after: after);
  }

  @override
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String id,
    String section, {
    String? after,
    String? evidenceKey,
  }) async {
    if (pagePause != null) {
      if (!entered.isCompleted) entered.complete();
      await pagePause!.future;
    }
    return super.page(
      scope,
      id,
      section,
      after: after,
      evidenceKey: evidenceKey,
    );
  }

  @override
  Future<Map<String, Object?>> generate(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    if (generationPause != null) {
      if (!entered.isCompleted) entered.complete();
      await generationPause!.future;
    }
    return super.generate(command);
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
  late DelayedValuation gateway;
  late InventoryValuationController c;
  InventoryValuationController make() => InventoryValuationController(
    scope: scope,
    gateway: gateway,
    drafts: drafts,
    online: true,
  );
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = DelayedValuation();
    c = make();
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Future<void> ready() async {
    await c.initialize();
    c.date('2026-09-20');
    c.account('account', true);
  }

  test('offline clears report costs and late options cannot restore current evidence', () async {
    await ready();
    await c.generate();
    expect(c.summary, isNotEmpty);
    gateway.optionPause = Completer<void>();
    final read = c.refresh('accounts');
    await gateway.entered.future;
    c.setOnline(false);
    expect(c.summary, isEmpty);
    expect(c.rows, isEmpty);
    expect(c.accounts, isEmpty);
    expect(c.reports, isEmpty);
    gateway.optionPause!.complete();
    await read;
    expect(c.accounts, isEmpty);
    expect(c.accountCursor, isNull);
    expect(c.reportCursor, isNull);
  });
  test('late report page cannot restore costs after access denial', () async {
    await ready();
    gateway.pagePause = Completer<void>();
    final read = c.open(report('saved'));
    await gateway.entered.future;
    c.deny(const DomainError(code: 'MFA_REQUIRED', message: 'Access changed'));
    gateway.pagePause!.complete();
    await read;
    expect(c.accessDenied, isTrue);
    expect(c.summary, isEmpty);
    expect(c.rows, isEmpty);
    expect(c.cursor, isNull);
  });
  test('confirmation while offline stores report identity before optional reads and survives restart', () async {
    await ready();
    gateway.generationPause = Completer<void>();
    final generate = c.generate();
    await gateway.entered.future;
    c.setOnline(false);
    gateway.generationPause!.complete();
    await generate;
    final saved = await drafts.load(scope, InventoryValuationController.slot);
    expect(saved!.pending, isNull);
    expect(saved.form['status'], 'generated');
    expect(saved.form['report_id'], isNotNull);
    expect(saved.form.containsKey('summary'), isFalse);
    expect(saved.form.containsKey('inventory_value'), isFalse);
    expect(c.summary, isEmpty);
    expect(gateway.reads, isEmpty);
    c.dispose();
    c = make();
    await c.initialize();
    expect(c.summary['inventory_value'], '120.000001');
    expect(gateway.commands, hasLength(1));
  });
  test('legacy recovery drops cached server costs and denied current access never exposes them', () async {
    await drafts.save(scope, InventoryValuationController.slot, {
      'id': 'legacy',
      'status': 'generated',
      'summary': report('legacy'),
      'account_ids': ['account'],
      'as_of': '2026-09-20',
    }, expectedVersion: 0);
    gateway.readFailure = 'PERMISSION_DENIED';
    await c.initialize();
    expect(c.accessDenied, isTrue);
    expect(c.summary, isEmpty);
    expect(c.form.containsKey('summary'), isFalse);
    final saved = await drafts.load(scope, InventoryValuationController.slot);
    expect(saved!.form.containsKey('summary'), isFalse);
    expect(saved.form['report_id'], 'legacy');
  });
  test(
    'cancelled valuation persists receipt and leaves no current cost evidence',
    () async {
      await ready();
      gateway.generationPause = Completer<void>();
      final work = c.generate();
      await gateway.entered.future;
      c.cancelReportWait();
      expect(await c.canLeave(), isTrue);
      gateway.generationPause!.complete();
      await work;
      final saved = await drafts.load(scope, InventoryValuationController.slot);
      expect(saved!.pending, isNull);
      expect(saved.form['report_id'], isNotNull);
      expect(c.summary, isEmpty);
      expect(c.rows, isEmpty);
      expect(gateway.reads, isEmpty);
      c.dispose();
      c = make();
      await c.initialize();
      expect(c.summary['inventory_value'], '120.000001');
      expect(gateway.commands, hasLength(1));
    },
  );
}

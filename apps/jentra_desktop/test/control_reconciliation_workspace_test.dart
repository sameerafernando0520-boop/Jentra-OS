import 'dart:convert';
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/features/control_reconciliation/control_reconciliation_controller.dart';
import 'package:jentra_desktop/src/features/control_reconciliation/control_reconciliation_screen.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';

import 'support/procurement_fakes.dart' show Keys;

Map<String, Object?> report(String id) => {
  'id': id,
  'kind': 'AR',
  'as_of': '2026-09-21',
  'generated_at': '2026-09-24 08:30 UTC',
  'entity_name': 'Jentra Trading',
  'branch_name': 'Colombo',
  'currency_code': 'LKR',
  'status': 'generated',
  'version': 1,
  'subledger_value': '9007199254.740993',
  'gl_value': '9007199254.740990',
  'difference': '0.000003',
  'difference_count': 1,
  'accounts': [
    {'id': 'control', 'code': '1100', 'name': 'Receivables control'},
  ],
};
const allocation = {
  'id': 'allocation',
  'source_document_number': 'REC-2026-0042',
  'target_document_number': 'INV-2026-0107',
  'source_amount': '1250.00',
  'transaction_amount': '1250.00',
  'exchange_difference': '0.000003',
  'write_off': '0.00',
  'discount_amount': '0.00',
  'posting_date': '2026-09-20',
};

class Gateway implements ControlReconciliationGateway {
  String kind = 'AR';
  Completer<void>? generationPause, pagePause, reportsPause;
  final generationEntered = Completer<void>(),
      pageEntered = Completer<void>(),
      reportsEntered = Completer<void>();
  String? failure, readFailure;
  bool failAfterGenerate = false;
  final commands = <CommandEnvelope<Map<String, Object?>>>[],
      reversals = <CommandEnvelope<Map<String, Object?>>>[];
  final reads = <Map<String, Object?>>[];
  final kinds = <String>[];
  void check() {
    if (readFailure != null) {
      throw DomainError(code: readFailure!, message: 'Access/read failed');
    }
  }

  @override
  Future<Map<String, Object?>> reports(
    TenantContext scope, {
    String? after,
  }) async {
    check();
    if (!reportsEntered.isCompleted) reportsEntered.complete();
    await reportsPause?.future;
    return {'items': <Object?>[]};
  }

  @override
  Future<Map<String, Object?>> generate(
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    commands.add(c);
    if (!generationEntered.isCompleted) generationEntered.complete();
    await generationPause?.future;
    if (failure != null) throw DomainError(code: failure!, message: failure!);
    if (failAfterGenerate) readFailure = 'READ_FAILED';
    return {...report(c.payload['id'] as String), 'kind': c.payload['kind']};
  }

  @override
  Future<Map<String, Object?>> reverse(
    String kind,
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    kinds.add(kind);
    reversals.add(c);
    if (failure != null) throw DomainError(code: failure!, message: failure!);
    return {'id': 'reversal'};
  }

  @override
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String id,
    String section, {
    String? after,
    String? accountId,
  }) async {
    check();
    if (!pageEntered.isCompleted) pageEntered.complete();
    await pagePause?.future;
    reads.add({
      'id': id,
      'section': section,
      'after': after,
      'account': accountId,
    });
    return {
      'summary': {...report(id), 'kind': kind},
      'section': section,
      'evidence_key': accountId,
      'next_cursor': after == null ? '50' : null,
      'items': [
        if (section == 'accounts')
          {
            'id': 'control',
            'evidence_key': 'control',
            'code': kind == 'GRNI' ? '2300' : '1100',
            'name': kind == 'GRNI'
                ? 'Goods received, not invoiced'
                : 'Receivables control',
            'subledger_value': '9007199254.740993',
            'gl_value': '9007199254.740990',
            'difference': '0.000003',
          },
        if (section == 'allocations') allocation,
        if (kind == 'GRNI' && section == 'items')
          {
            'id': 'receipt-42',
            'document_number': 'GR-2026-0042',
            'party_name': 'Western Supplies',
            'currency_code': 'USD',
            'original_amount': '0.330000',
            'settled_amount': '0.330000',
            'open_amount': '0.000000',
            'original_base_amount': '1.100000',
            'open_base_amount': '0.000000',
            'posting_date': '2026-09-22',
            'source_type': 'goods_receipt',
            'source_id': 'receipt-42',
            'journal_entry_id': 'receipt-journal-42',
          },
        if (kind == 'GRNI' && section == 'entries')
          {
            'id': 'supplier_bill:bill-line-42',
            'source_type': 'supplier_bill',
            'source_id': 'bill-42',
            'posting_date': '2026-09-24',
            'value': '-0.730000',
            'transaction_value': '-0.220000',
            'receipt_id': 'receipt-42',
            'journal_entry_id': 'bill-journal-42',
            'command_id': 'bill-command-42',
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
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late Gateway gateway;
  late ControlReconciliationController c;
  ControlReconciliationController make({
    TenantContext context = scope,
    bool online = true,
    Set<String>? caps,
  }) => ControlReconciliationController(
    scope: context,
    gateway: gateway,
    drafts: drafts,
    capabilities:
        caps ??
        {
          'finance.view',
          'finance.controls.reconcile',
          'finance.receipts.reverse',
          'finance.payments.reverse',
        },
    online: online,
  );
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
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = Gateway();
    c = make();
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Future<void> ready() async {
    await c.initialize();
    c.form = {...c.form, 'id': 'control-report-0042'};
    c.field('as_of', '2026-09-21');
  }

  Future<void> correction() async {
    await ready();
    await c.generate();
    await c.selectSection('allocations');
    await c.chooseAllocation(allocation);
    c.correctionField('posting_date', '2026-09-24');
    c.correctionField('reason', 'Correct invoice selection');
  }

  test('navigation requires finance and reconciliation capabilities', () {
    bool visible(Set<String> caps) =>
        visibleJentraDestinations(caps)
            .any((x) => x.path == '/finance/controls');
    expect(visible({'finance.view'}), isFalse);
    expect(visible({'finance.controls.reconcile'}), isFalse);
    expect(visible({'finance.view', 'finance.controls.reconcile'}), isTrue);
  });
  test('generation persists cutoff, kind and exact totals', () async {
    await ready();
    await c.generate();
    expect(c.error, isNull);
    expect(gateway.commands.single.payload['as_of'], '2026-09-21');
    expect(gateway.commands.single.expectedEntityVersion, 0);
    expect(c.summary['difference'], '0.000003');
  });
  test(
    'GRNI generation keeps exact totals and has no allocation reversal',
    () async {
      await ready();
      c.field('kind', 'GRNI');
      gateway.kind = 'GRNI';
      await c.generate();
      expect(c.summary['kind'], 'GRNI');
      expect(gateway.commands.single.payload['kind'], 'GRNI');
      expect(c.canReverse('GRNI'), false);
      await c.selectSection('allocations');
      expect(c.section, 'accounts');
      await c.chooseAllocation(allocation);
      expect(c.correction, isEmpty);
      await c.sources('control');
      expect(gateway.reads.last['account'], 'control');
    },
  );
  test(
    'GRNI uncertain request survives restart with identical cutoff and kind',
    () async {
      await ready();
      c.field('kind', 'GRNI');
      gateway.kind = 'GRNI';
      gateway.failure = 'UNCERTAIN_RESULT';
      await c.generate();
      final sealed = jsonEncode(gateway.commands.single.toJson((x) => x));
      c.dispose();
      c = make();
      await c.initialize();
      c.field('kind', 'AR');
      c.field('as_of', '2026-09-20');
      gateway.failure = null;
      await c.generate();
      expect(jsonEncode(gateway.commands.last.toJson((x) => x)), sealed);
    },
  );
  test(
    'late GRNI page cannot restore evidence after disconnect and reconnect',
    () async {
      await ready();
      c.field('kind', 'GRNI');
      gateway.kind = 'GRNI';
      await c.generate();
      gateway.pagePause = Completer<void>();
      final reading = c.selectSection('entries');
      await Future<void>.delayed(Duration.zero);
      c.setOnline(false);
      c.setOnline(true);
      gateway.pagePause!.complete();
      await reading;
      expect(c.verified, false);
      expect(c.rows, isEmpty);
      expect(c.summary, isEmpty);
      expect(c.reports, isEmpty);
      await c.generate();
      expect(gateway.commands, hasLength(1));
      gateway.pagePause = null;
      await c.initialize();
      expect(c.verified, true);
    },
  );
  test('late access refresh cannot reverify an earlier online epoch', () async {
    gateway.reportsPause = Completer<void>();
    final reading = c.initialize();
    await gateway.reportsEntered.future;
    c.setOnline(false);
    c.setOnline(true);
    gateway.reportsPause!.complete();
    await reading;
    expect(c.verified, false);
    expect(c.summary, isEmpty);
  });
  test(
    'expired MFA clears GRNI evidence until a fresh scoped read succeeds',
    () async {
      await ready();
      c.field('kind', 'GRNI');
      gateway.kind = 'GRNI';
      await c.generate();
      gateway.readFailure = 'MFA_REQUIRED';
      await c.refreshPage();
      expect(c.accessDenied, true);
      expect(c.verified, false);
      expect(c.rows, isEmpty);
      expect(c.summary, isEmpty);
      expect(
        (await drafts.load(
          scope,
          ControlReconciliationController.slot,
        ))!.form['status'],
        'generated',
      );
      gateway.readFailure = null;
      await c.initialize();
      expect(c.verified, true);
      expect(c.summary['kind'], 'GRNI');
    },
  );
  test(
    'confirmation while disconnected persists encrypted GRNI identity',
    () async {
      await ready();
      c.field('kind', 'GRNI');
      gateway.kind = 'GRNI';
      gateway.generationPause = Completer<void>();
      final posting = c.generate();
      await gateway.generationEntered.future;
      c.setOnline(false);
      gateway.generationPause!.complete();
      await posting;
      final stored = (await drafts.load(
        scope,
        ControlReconciliationController.slot,
      ))!;
      expect(stored.pending, isNull);
      expect(stored.form['kind'], 'GRNI');
      expect(stored.form['status'], 'generated');
      expect(c.summary, isEmpty);
      expect(c.rows, isEmpty);
      expect(c.verified, false);
      c.setOnline(true);
      await c.initialize();
      expect(c.summary['id'], stored.form['report_id']);
      expect(gateway.commands, hasLength(1));
    },
  );
  test(
    'confirmation after route disposal retains GRNI identity for reopen',
    () async {
      await ready();
      c.field('kind', 'GRNI');
      gateway.kind = 'GRNI';
      gateway.generationPause = Completer<void>();
      final posting = c.generate();
      await gateway.generationEntered.future;
      c.dispose();
      c = make();
      gateway.generationPause!.complete();
      await posting;
      await c.initialize();
      expect(c.form['status'], 'generated');
      expect(c.summary['kind'], 'GRNI');
      expect(gateway.commands, hasLength(1));
    },
  );
  test('failed encrypted confirmation keeps the exact GRNI retry', () async {
    await ready();
    c.field('kind', 'GRNI');
    gateway.kind = 'GRNI';
    gateway.generationPause = Completer<void>();
    final posting = c.generate();
    await gateway.generationEntered.future;
    await db.customStatement(
      "create trigger fail_grni_confirmation before update on encrypted_drafts begin select raise(abort, 'CONFIRMATION_WRITE_FAILURE'); end;",
    );
    gateway.generationPause!.complete();
    await posting;
    final sealed = jsonEncode(gateway.commands.single.toJson((x) => x));
    expect(
      (await drafts.load(scope, ControlReconciliationController.slot))!.pending,
      isNotNull,
    );
    expect(c.summary, isEmpty);
    await db.customStatement('drop trigger fail_grni_confirmation');
    c.dispose();
    c = make();
    await c.initialize();
    await c.generate();
    expect(jsonEncode(gateway.commands.last.toJson((x) => x)), sealed);
    expect(c.form['status'], 'generated');
  });
  test('uncertain report retry survives restart byte-identically', () async {
    await ready();
    gateway.failure = 'UNCERTAIN_RESULT';
    await c.generate();
    final sealed = jsonEncode(gateway.commands.single.toJson((x) => x));
    await c.newReport();
    expect(c.local?.pending, isNotNull);
    c.dispose();
    c = make();
    await c.initialize();
    c.field('kind', 'AP');
    gateway.failure = null;
    await c.generate();
    expect(jsonEncode(gateway.commands.last.toJson((x) => x)), sealed);
  });
  test(
    'confirmed report survives failed evidence refresh and restart',
    () async {
      await ready();
      gateway.failAfterGenerate = true;
      await c.generate();
      expect(c.form['status'], 'generated');
      expect(c.local?.pending, isNull);
      gateway.readFailure = null;
      c.dispose();
      c = make();
      await c.initialize();
      expect(c.summary, isNotEmpty);
      expect(gateway.commands, hasLength(1));
    },
  );
  test('source filter and pagination preserve report identity', () async {
    await ready();
    await c.generate();
    final id = c.summary['id'];
    await c.sources('control');
    await c.selectSection('journals');
    await c.refreshPage(more: true);
    expect(gateway.reads.last, {
      'id': id,
      'section': 'journals',
      'after': '50',
      'account': 'control',
    });
  });
  test(
    'AR reversal uncertain envelope and ledger kind survive restart',
    () async {
      await correction();
      gateway.failure = 'UNCERTAIN_RESULT';
      await c.reverse();
      final sealed = jsonEncode(gateway.reversals.single.toJson((x) => x));
      c.dispose();
      c = make();
      await c.initialize();
      c.correctionField('reason', 'changed');
      await c.clearCorrection();
      gateway.failure = null;
      await c.reverse();
      expect(jsonEncode(gateway.reversals.last.toJson((x) => x)), sealed);
      expect(gateway.kinds, ['AR', 'AR']);
      expect(c.correction, isEmpty);
      c.dispose();
      c = make();
      await c.initialize();
      expect(c.correction, isEmpty);
    },
  );
  test(
    'AP reversal calls AP gateway and requires separate permission',
    () async {
      await correction();
      c.correction = {...c.correction, 'kind': 'AP'};
      await c.reverse();
      expect(gateway.kinds, ['AP']);
      c.dispose();
      c = make(caps: {'finance.view', 'finance.controls.reconcile'});
      await c.initialize();
      await c.open(report('old'));
      await c.chooseAllocation(allocation);
      expect(c.correction, isEmpty);
      expect(c.canReverse('AR'), isFalse);
    },
  );
  test('blank reason and invalid calendar date do not send', () async {
    await correction();
    c.correctionField('reason', ' ');
    await c.reverse();
    expect(gateway.reversals, isEmpty);
    c.correctionField('reason', 'Correction');
    c.correctionField('posting_date', '2026-02-30');
    await c.reverse();
    expect(gateway.reversals, isEmpty);
  });
  test(
    'offline restart hides source evidence and preserves sealed correction',
    () async {
      await correction();
      gateway.failure = 'UNCERTAIN_RESULT';
      await c.reverse();
      c.dispose();
      c = make(online: false);
      await c.initialize();
      expect(c.summary, isEmpty);
      expect(c.correction, isEmpty);
      expect(c.correctionLocal?.pending, isNotNull);
      await c.reverse();
      expect(gateway.reversals, hasLength(1));
    },
  );
  test('drafts and pending corrections are branch isolated', () async {
    await correction();
    gateway.failure = 'UNCERTAIN_RESULT';
    await c.reverse();
    final other = make(
      context: const TenantContext(
        tenantId: 't',
        actorId: 'a',
        legalEntityId: 'e',
        branchId: 'other',
      ),
    );
    await other.initialize();
    expect(other.correction, isEmpty);
    expect(other.pending, isFalse);
    other.dispose();
  });
  test(
    'revocation clears evidence and correction but retains encrypted recovery',
    () async {
      await correction();
      gateway.readFailure = 'PERMISSION_DENIED';
      await c.refreshPage();
      expect(c.accessDenied, isTrue);
      expect(c.summary, isEmpty);
      expect(c.correction, isEmpty);
      expect(c.rows, isEmpty);
      expect(
        await drafts.load(
          scope,
          ControlReconciliationController.correctionSlot,
        ),
        isNotNull,
      );
    },
  );
  Future<void> render(
    WidgetTester tester, {
    bool dark = false,
    double height = 1500,
  }) async {
    tester.view.physicalSize = Size(1024, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? JentraTheme.dark() : JentraTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: ControlReconciliationWorkspace(controller: c)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    testWidgets(
      'GRNI receipts and sources ${dark ? 'dark' : 'light'} 200 percent',
      (tester) async {
        await ready();
        c.field('kind', 'GRNI');
        gateway.kind = 'GRNI';
        await c.generate();
        await c.selectSection('items');
        await render(tester, dark: dark);
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Western Supplies'), findsOneWidget);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            'goldens/grni_receipts_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
        await c.sources('control');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Receipt receipt-42'), findsOneWidget);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            'goldens/grni_sources_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
      },
    );
    testWidgets('GRNI ${dark ? 'dark' : 'light'} 200 percent', (tester) async {
      await ready();
      c.field('kind', 'GRNI');
      gateway.kind = 'GRNI';
      await c.generate();
      await render(tester, dark: dark);
      expect(tester.takeException(), isNull);
      expect(find.text('Receipts'), findsOneWidget);
      expect(find.text('Allocations'), findsNothing);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          'goldens/grni_control_${dark ? 'dark' : 'light'}_200.png',
        ),
      );
    });
    testWidgets('controls ${dark ? 'dark' : 'light'} 200 percent', (
      tester,
    ) async {
      await ready();
      await c.generate();
      await render(tester, dark: dark);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          'goldens/control_reconciliation_${dark ? 'dark' : 'light'}_200.png',
        ),
      );
    });
  }
  testWidgets(
    'correction confirmation reachable at desktop 200 percent and cancellation sends nothing',
    (tester) async {
      await correction();
      await render(tester, height: 720);
      await tester.scrollUntilVisible(
        find.text('Review reversal'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Review reversal'));
      await tester.pumpAndSettle();
      expect(find.text('Reverse this allocation?'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(gateway.reversals, isEmpty);
    },
  );
}

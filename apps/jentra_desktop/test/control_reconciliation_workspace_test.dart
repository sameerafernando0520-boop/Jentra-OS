import 'dart:convert';
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
    return {'items': <Object?>[]};
  }

  @override
  Future<Map<String, Object?>> generate(
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    commands.add(c);
    if (failure != null) throw DomainError(code: failure!, message: failure!);
    if (failAfterGenerate) readFailure = 'READ_FAILED';
    return report(c.payload['id'] as String);
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
    reads.add({
      'id': id,
      'section': section,
      'after': after,
      'account': accountId,
    });
    return {
      'summary': report(id),
      'section': section,
      'evidence_key': accountId,
      'next_cursor': after == null ? '50' : null,
      'items': [
        if (section == 'accounts')
          {
            'id': 'control',
            'evidence_key': 'control',
            'code': '1100',
            'name': 'Receivables control',
            'subledger_value': '9007199254.740993',
            'gl_value': '9007199254.740990',
            'difference': '0.000003',
          },
        if (section == 'allocations') allocation,
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
    bool visible(Set<String> caps) => visibleJentraDestinations(
      caps,
    ).any((x) => x.path == '/finance/controls');
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

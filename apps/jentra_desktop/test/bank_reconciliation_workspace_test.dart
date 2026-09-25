import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_desktop/src/features/bank_reconciliation/bank_reconciliation_controller.dart';
import 'package:jentra_desktop/src/features/bank_reconciliation/bank_reconciliation_screen.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';
import 'support/procurement_fakes.dart' show Keys;

class BankFake implements BankReconciliationGateway {
  String? failure, readFailure;
  bool failRefresh = false;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  @override
  Future<Map<String, Object?>> options(
    TenantContext s,
    String resource, {
    String? bankId,
    String? after,
  }) async {
    if (readFailure != null) {
      throw DomainError(code: readFailure!, message: readFailure!);
    }
    return {
      'items': [
        if (resource == 'accounts')
          {
            'id': 'bank',
            'code': 'MAIN',
            'name': 'Operating bank',
            'currency_code': 'LKR',
          },
        if (resource == 'statement_lines')
          {
            'id': 's1',
            'reference': 'BNK-001',
            'posting_date': '2026-09-21',
            'description': 'Customer deposit',
            'amount': '9007199254.740993',
          },
        if (resource == 'journal_lines')
          {
            'id': 'j1',
            'document_number': 'REC-001',
            'posting_date': '2026-09-21',
            'source_type': 'customer_receipt',
            'amount': '9007199254.740993',
          },
        if (resource == 'matches')
          {
            'id': 'match',
            'posting_date': '2026-09-21',
            'statement_total': '100.000000',
            'difference': '0.000000',
            'currency_code': 'LKR',
            'reason': 'Customer deposit',
            'statement_line_ids': ['s1'],
            'journal_line_ids': ['j1'],
          },
      ],
    };
  }

  @override
  Future<Map<String, Object?>> execute(
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    commands.add(c);
    if (failure != null) throw DomainError(code: failure!, message: failure!);
    if (failRefresh) readFailure = 'READ_FAILED';
    return {'id': c.payload['id']};
  }
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
  late QuotationDraftStore store;
  late BankFake gateway;
  late BankReconciliationController c;
  BankReconciliationController make({
    bool online = true,
    TenantContext s = scope,
    Set<String>? caps,
  }) => BankReconciliationController(
    scope: s,
    gateway: gateway,
    drafts: store,
    capabilities:
        caps ??
        {'finance.view', 'finance.bank.import', 'finance.bank.reconcile'},
    online: online,
  );
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    store = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = BankFake();
    c = make();
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Future<void> ready() async {
    await c.initialize();
    await c.selectBank('bank');
    c.field('posting_date', '2026-09-21');
    c.field('reason', 'Customer deposit');
    c.toggle('statement_lines', 's1', true);
    c.toggle('journal_lines', 'j1', true);
  }

  test(
    'matching preserves exact selected totals and sealed request across restart',
    () async {
      await ready();
      expect(
        c.selectedTotal('statement_lines').toDecimalString(),
        '9007199254.740993',
      );
      gateway.failure = 'UNCERTAIN_RESULT';
      await c.execute('match');
      expect(c.pending, true);
      final first = gateway.commands.single.toJson((v) => v);
      c.dispose();
      c = make();
      await c.initialize();
      c.field('reason', 'Changed');
      expect(c.form['reason'], 'Customer deposit');
      gateway.failure = null;
      await c.retry();
      expect(gateway.commands.last.toJson((v) => v), first);
      expect(c.pending, false);
    },
  );
  test('confirmed mutation cleared before optional refresh failure', () async {
    await ready();
    gateway.failRefresh = true;
    await c.execute('match');
    expect(c.pending, false);
    expect(c.message, contains('confirmed'));
    expect(
      (await store.load(scope, BankReconciliationController.slot))?.pending,
      isNull,
    );
  });
  test('offline recovery hides bank evidence and disables mutations', () async {
    await ready();
    await c.save();
    c.dispose();
    c = make(online: false);
    await c.initialize();
    expect(c.verified, false);
    expect(c.form, isEmpty);
    expect(c.pages, isEmpty);
    await c.execute('match');
    expect(gateway.commands, isEmpty);
  });
  test('permission revocation clears source evidence', () async {
    await ready();
    gateway.readFailure = 'PERMISSION_DENIED';
    await c.refresh();
    expect(c.denied, true);
    expect(c.pages, isEmpty);
    expect(c.form, isEmpty);
  });
  test('another actor cannot restore the encrypted bank editor', () async {
    await ready();
    await c.save();
    c.dispose();
    c = make(
      s: const TenantContext(
        tenantId: 't',
        actorId: 'other',
        legalEntityId: 'e',
        branchId: 'b',
      ),
    );
    await c.initialize();
    expect(c.bankId, isNull);
  });
  test('view-only client cannot submit import or match', () async {
    c.dispose();
    c = make(caps: {'finance.view'});
    await ready();
    await c.execute('match');
    expect(gateway.commands, isEmpty);
  });
  test('preview validates exact statement balance before dispatch', () async {
    await ready();
    await c.preview(
      Uint8List.fromList(
        utf8.encode(
          'date,reference,description,amount\n2026-09-21,R1,Fee,-0.000001',
        ),
      ),
      'csv',
      'statement.csv',
    );
    c.field('identity', 'STMT-1');
    c.field('start_date', '2026-09-21');
    c.field('end_date', '2026-09-21');
    c.field('closing', '0');
    await c.execute('import');
    expect(gateway.commands, isEmpty);
    expect(c.error, contains('closing'));
    c.field('closing', '-0.000001');
    await c.execute('import');
    expect(gateway.commands.single.payload['action'], 'import');
  });
  test('navigation requires finance access', () {
    expect(
      visibleJentraDestinations({}).any((d) => d.path == '/finance/bank'),
      false,
    );
    expect(
      visibleJentraDestinations({
        'finance.view',
      }).any((d) => d.path == '/finance/bank'),
      true,
    );
  });
  testWidgets(
    '200 percent text keeps reversal confirmation reachable and cancellable',
    (tester) async {
      await ready();
      tester.view.physicalSize = const Size(1024, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: JentraTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(body: BankReconciliationWorkspace(controller: c)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Reverse match'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Reverse match'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reverse match'));
      await tester.pumpAndSettle();
      expect(find.text('Reverse this match?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(gateway.commands, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      '${dark ? 'dark' : 'light'} bank workspace renders at 200 percent text',
      (tester) async {
        await ready();
        tester.view.physicalSize = const Size(1024, 1500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? JentraTheme.dark() : JentraTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(body: BankReconciliationWorkspace(controller: c)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(BankReconciliationWorkspace),
          matchesGoldenFile(
            'goldens/bank_reconciliation_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
      },
    );
  }
}

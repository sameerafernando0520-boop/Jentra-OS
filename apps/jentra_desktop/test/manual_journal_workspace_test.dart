import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/features/manual_journal/manual_journal_controller.dart';
import 'package:jentra_desktop/src/features/manual_journal/manual_journal_screen.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';

import 'support/procurement_fakes.dart' show Keys;

Map<String, Object?> journal({
  String id = 'journal',
  String status = 'draft',
  int version = 1,
}) => {
  'id': id,
  'status': status,
  'version': version,
  'tenant_id': 't',
  'legal_entity_id': 'e',
  'branch_id': 'b',
  'document_date': '2026-09-20',
  'document_number': 'MJ-0042',
  'description': 'Accrued warehouse freight',
  'reason': 'Month-end estimate agreed',
  'currency_code': 'LKR',
  'base_currency_code': 'LKR',
  'grand_total': '123.456789',
  'base_total': '123.456789',
  'exchange_rate': '1.0000000000',
  'attachment_ids': <String>[],
  'attachments': <Object?>[],
  'lines': [
    {
      'line_id': 'line1',
      'account_id': 'a',
      'account_code': '5100',
      'account_name': 'Freight expense',
      'debit': '123.456789',
      'credit': '0',
      'amount': '123.456789',
      'base_amount': '123.456789',
      'description': 'Inbound freight',
      'cost_center': 'Distribution',
      'project': 'Warehouse',
    },
    {
      'line_id': 'line2',
      'account_id': 'b',
      'account_code': '2200',
      'account_name': 'Accrued expenses',
      'debit': '0',
      'credit': '123.456789',
      'amount': '-123.456789',
      'base_amount': '-123.456789',
      'description': 'Accrual',
      'cost_center': 'Distribution',
      'project': 'Warehouse',
    },
  ],
  if (status == 'posted') 'journal_entry_id': 'ledger',
};

class JournalGateway implements ManualJournalGateway {
  String? failure, readFailure;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  final verbs = <String>[];
  Map<String, Object?> saved = journal();
  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? after,
    String search = '',
    String? documentDate,
  }) async {
    if (readFailure != null) {
      throw DomainError(code: readFailure!, message: 'Read failed');
    }
    return {'items': <Object?>[], 'base_currency_code': 'LKR'};
  }

  @override
  Future<Map<String, Object?>> detail(TenantContext scope, String id) async {
    if (readFailure != null) {
      throw DomainError(code: readFailure!, message: 'Read failed');
    }
    return saved;
  }

  @override
  Future<Map<String, Object?>> execute(
    String verb,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    verbs.add(verb);
    if (failure != null) throw DomainError(code: failure!, message: failure!);
    saved = journal(
      id: (command.payload['id'] ?? command.payload['document_id']) as String,
      status: switch (verb) {
        'post' => 'posted',
        'submit' => 'pending_approval',
        'approve' => 'approved',
        _ => 'draft',
      },
      version: (command.expectedEntityVersion ?? 0) + 1,
    );
    return saved;
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
  const permissions = {
    'finance.view',
    'finance.journals.post',
    'finance.reversals.post',
    'workflow.approvals.decide',
    'core.files.view',
  };
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late JournalGateway gateway;
  late ManualJournalController c;
  ManualJournalController make({TenantContext context = scope}) =>
      ManualJournalController(
        scope: context,
        gateway: gateway,
        drafts: drafts,
        permissions: permissions,
        online: true,
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
    gateway = JournalGateway();
    c = make();
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Future<void> ready() async {
    await c.initialize();
    c.form = {...journal(), 'version': null, 'document_number': null};
    await c.saveLocal();
  }

  test('save and submit retain exact amounts and expected versions', () async {
    await ready();
    await c.act('save');
    expect(c.error, isNull);
    expect(gateway.commands.single.expectedEntityVersion, 0);
    expect(
      (gateway.commands.single.payload['lines'] as List).first['debit'],
      '123.456789',
    );
    await c.act('submit');
    expect(c.form!['status'], 'pending_approval');
    expect(gateway.commands.last.expectedEntityVersion, 1);
  });
  test('unbalanced local journal cannot send', () async {
    await ready();
    c.line(1, 'credit', '123.456788');
    await c.act('save');
    expect(gateway.commands, isEmpty);
    expect(c.error, contains('balance'));
  });
  const withholding = {
    'id': 'tax',
    'code': 'WHT25',
    'name': 'Configured withholding',
    'kind': 'withholding',
    'rate': '25.000000',
    'version': 3,
    'inclusive': false,
    'rounding_scale': 2,
  };
  Future<void> readyTax() async {
    await ready();
    c.line(0, 'debit', '25');
    c.line(1, 'credit', '25');
    c.taxDefinition(1, withholding);
    c.line(1, 'taxable_amount', '100');
    c.form = {
      ...c.form!,
      'grand_total': '25',
      'base_total': '25',
      'lines': <Object?>[
        {
          ...(c.form!['lines'] as List)[0] as Map,
          'amount': '25',
          'base_amount': '25',
        },
        {
          ...(c.form!['lines'] as List)[1] as Map,
          'amount': '-25',
          'base_amount': '-25',
          'tax_basis_date': '2026-09-20',
          'tax_direction': -1,
          'expected_tax_base': '25',
        },
      ],
    };
  }

  test('tax amount mismatch stops a balanced journal before sending', () async {
    await readyTax();
    c.line(1, 'taxable_amount', '99');
    await c.act('save');
    expect(gateway.commands, isEmpty);
    expect(c.error, contains('taxable basis'));
    c.taxDefinition(1, null);
    expect(
      (c.form!['lines'] as List)[1].containsKey('tax_definition_id'),
      false,
    );
    expect((c.form!['lines'] as List)[1].containsKey('taxable_amount'), false);
  });

  test(
    'uncertain withholding save seals its definition and basis across recovery',
    () async {
      await readyTax();
      gateway.failure = 'UNCERTAIN_RESULT';
      await c.act('save');
      final sealed = jsonEncode(gateway.commands.single.toJson((x) => x));
      final line = (gateway.commands.single.payload['lines'] as List)[1] as Map;
      expect(line['tax_definition_id'], 'tax');
      expect(line['taxable_amount'], '100');
      c.dispose();
      c = make();
      await c.initialize();
      c.taxDefinition(1, null);
      c.line(1, 'taxable_amount', '999');
      expect((c.form!['lines'] as List)[1]['taxable_amount'], '100');
      gateway.failure = null;
      await c.act('retry');
      expect(jsonEncode(gateway.commands.last.toJson((x) => x)), sealed);
    },
  );
  test('uncertain save survives restart and seals identical retry', () async {
    await ready();
    gateway.failure = 'UNCERTAIN_RESULT';
    await c.act('save');
    final sealed = jsonEncode(gateway.commands.single.toJson((x) => x));
    await c.close();
    expect(c.local?.pending, isNotNull);
    c.dispose();
    c = make();
    await c.initialize();
    c.update('reason', 'must not change');
    gateway.failure = null;
    await c.act('retry');
    expect(jsonEncode(gateway.commands.last.toJson((x) => x)), sealed);
    expect(c.local?.pending, isNull);
  });
  test('dirty input blocks submit until saved', () async {
    await ready();
    await c.act('save');
    c.update('reason', 'Changed reason');
    await c.act('submit');
    expect(gateway.commands, hasLength(1));
    expect(c.error, contains('Save journal'));
  });
  Future<void> readyMovement() async {
    await ready();
    c.form = {
      ...c.form!,
      'lines': <Object?>[
        (c.form!['lines'] as List)[0],
        {...(c.form!['lines'] as List)[1] as Map, 'is_tax_control': true},
      ],
    };
    c.taxControlMovement(1, 'settlement');
  }

  test(
    'tax-control movement and account remain sealed across recovery',
    () async {
      await readyMovement();
      gateway.failure = 'UNCERTAIN_RESULT';
      await c.act('save');
      final sealed = jsonEncode(gateway.commands.single.toJson((x) => x));
      expect(
        (gateway.commands.single.payload['lines']
            as List)[1]['tax_control_movement'],
        'settlement',
      );
      c.dispose();
      c = make();
      await c.initialize();
      c.taxControlMovement(1, 'adjustment');
      expect(
        (c.form!['lines'] as List)[1]['tax_control_movement'],
        'settlement',
      );
      gateway.failure = null;
      await c.act('retry');
      expect(jsonEncode(gateway.commands.last.toJson((x) => x)), sealed);
    },
  );
  test('reversal is a new draft with original link', () async {
    await c.initialize();
    c.form = journal(status: 'posted', version: 4);
    await c.reverse();
    expect(c.form!['reversal_of_id'], 'journal');
    expect(c.form!['version'], isNull);
    c.update('reason', 'Correct freight estimate');
    await c.act('save');
    expect(gateway.commands.single.payload['reversal_of_id'], 'journal');
  });
  test('read failure after save retains confirmed state', () async {
    await ready();
    gateway.readFailure = 'READ_FAILED';
    await c.act('save');
    expect(c.form!['version'], 1);
    expect(c.local?.pending, isNull);
    expect(c.message, contains('confirmed'));
  });
  test('scope isolates encrypted local journals', () async {
    await ready();
    final other = make(
      context: const TenantContext(
        tenantId: 't',
        actorId: 'a',
        legalEntityId: 'e',
        branchId: 'other',
      ),
    );
    await other.initialize();
    expect(other.form, isNull);
    other.dispose();
  });
  test(
    'confirmed posting persists before optional source read fails',
    () async {
      await c.initialize();
      c.form = journal(status: 'approved', version: 3);
      gateway.readFailure = 'READ_FAILED';
      await c.act('post');
      expect(c.form!['status'], 'posted');
      expect(c.local?.pending, isNull);
      c.dispose();
      gateway.readFailure = null;
      c = make();
      await c.initialize();
      expect(c.form!['status'], 'posted');
      expect(c.form!['version'], 4);
    },
  );
  test('navigation requires finance view', () {
    expect(
      visibleJentraDestinations({}).any((d) => d.path == '/finance/journals'),
      isFalse,
    );
    expect(
      visibleJentraDestinations({'finance.view'})
          .any((d) => d.path == '/finance/journals'),
      isTrue,
    );
  });
  Future<void> render(
    WidgetTester tester, {
    bool dark = false,
    double height = 1800,
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
          child: Scaffold(body: ManualJournalWorkspace(controller: c)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'permission rejection hides financial fields but retains encrypted work',
    (tester) async {
      await ready();
      gateway.readFailure = 'PERMISSION_DENIED';
      await c.refresh();
      await render(tester);
      expect(find.text('Recheck access'), findsOneWidget);
      expect(find.textContaining('123.456789'), findsNothing);
      expect(await drafts.load(scope, ManualJournalController.slot), isNotNull);
    },
  );
  for (final dark in [false, true]) {
    testWidgets('control settlement ${dark ? 'dark' : 'light'} 200 percent', (
      tester,
    ) async {
      await readyMovement();
      c.form = {...c.form!, 'status': 'approved', 'version': 3};
      await render(tester, dark: dark, height: 1400);
      await tester.ensureVisible(find.textContaining('Tax-control settlement'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          'goldens/journal_control_${dark ? 'dark' : 'light'}_200.png',
        ),
      );
    });
    testWidgets('declared withholding ${dark ? 'dark' : 'light'} 200 percent', (
      tester,
    ) async {
      await readyTax();
      c.form = {...c.form!, 'status': 'approved', 'version': 3};
      await render(tester, dark: dark, height: 1400);
      await tester.ensureVisible(find.textContaining('Taxable basis 100'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          'goldens/journal_tax_${dark ? 'dark' : 'light'}_200.png',
        ),
      );
    });
    testWidgets('manual journal ${dark ? 'dark' : 'light'} 200 percent', (
      tester,
    ) async {
      await c.initialize();
      c.form = journal(status: 'approved', version: 3);
      await render(tester, dark: dark);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          'goldens/manual_journal_${dark ? 'dark' : 'light'}_200.png',
        ),
      );
    });
  }
  testWidgets(
    'minimum desktop reaches posting confirmation without immediate write',
    (tester) async {
      await c.initialize();
      c.form = journal(status: 'approved', version: 3);
      await render(tester, height: 720);
      await tester.scrollUntilVisible(
        find.text('Post journal').hitTestable(),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Post journal'));
      await tester.pumpAndSettle();
      expect(find.text('Post approved journal?'), findsOneWidget);
      expect(gateway.commands, isEmpty);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(gateway.commands, isEmpty);
    },
  );
  testWidgets(
    'tax-control movement selection is reachable at desktop 200 percent',
    (tester) async {
      await readyMovement();
      await render(tester, height: 720);
      final movement = find.byType(DropdownButtonFormField<String>);
      expect(movement, findsOneWidget);
      await tester.ensureVisible(movement);
      await tester.pumpAndSettle();
      expect(find.text('Recorded settlement'), findsOneWidget);
      await tester.tap(movement);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reviewed adjustment').last);
      await tester.pumpAndSettle();
      expect(
        (c.form!['lines'] as List)[1]['tax_control_movement'],
        'adjustment',
      );
      expect(gateway.commands, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

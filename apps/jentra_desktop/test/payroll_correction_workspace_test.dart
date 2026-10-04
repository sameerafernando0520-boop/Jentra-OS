import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_domain/jentra_payroll.dart';
import 'package:jentra_platform/jentra_payroll_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_desktop/src/features/people/payroll_correction_controller.dart';
import 'package:jentra_desktop/src/features/people/payroll_correction_screen.dart';

const scope = TenantContext(
  tenantId: '10000000-0000-0000-0000-000000000001',
  legalEntityId: '10000000-0000-0000-0000-000000000002',
  branchId: '10000000-0000-0000-0000-000000000003',
  actorId: '10000000-0000-0000-0000-000000000004',
);
const id = '20000000-0000-0000-0000-000000000001',
    originalId = '30000000-0000-0000-0000-000000000001',
    sealId = '40000000-0000-0000-0000-000000000001';
Map<String, Object?> summary({String status = 'prepared', String? actor}) => {
  'id': id,
  'tenant_id': scope.tenantId,
  'legal_entity_id': scope.legalEntityId,
  'branch_id': scope.branchId,
  'version': 1,
  'status': status,
  'digest': 'a' * 64,
  'prepared_by': actor ?? originalId,
  'posting_date': '2026-10-02',
  'currency_code': 'LKR',
  'original_calculation_id': originalId,
};

class Keys implements SecretKeyStore {
  final values = <String, String>{};
  bool forbid = false;
  @override
  Future<String?> read(String key) async {
    if (forbid) {
      throw StateError('Synthetic cleanup failure');
    }
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class Server implements PayrollCorrectionRepository {
  @override
  Future<WorkforcePage<Map<String, Object?>>> correctionCredits(
    TenantContext scope,
    String revision, {
    String? after,
  }) async => const WorkforcePage([], null);
  List<Map<String, Object?>> rows = [summary()];
  List<Map<String, Object?>>? sourceRows;
  final sections = <String, List<Map<String, Object?>>>{};
  String? failure;
  bool deny = false, uncertain = false;
  Completer<void>? gate;
  Map<String, Object?>? last;
  int writes = 0;
  void Function()? onWrite;
  @override
  Future<void> authorize(TenantContext scope, String cap) async {
    if (deny) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Access changed',
      );
    }
  }

  @override
  Future<WorkforcePage<Map<String, Object?>>> corrections(
    TenantContext scope, {
    String? after,
  }) async => WorkforcePage(rows, null);
  @override
  Future<WorkforcePage<Map<String, Object?>>> correctionOriginals(
    TenantContext scope, {
    String? after,
  }) async => const WorkforcePage([
    {
      'id': originalId,
      'employee_name': 'SYNTHETIC_EMPLOYEE',
      'employee_code': 'SYN-001',
      'start_date': '2026-10-01',
      'end_date_exclusive': '2026-10-02',
      'original_net': '100.000000',
      'currency_code': 'LKR',
    },
  ], null);
  @override
  Future<WorkforcePage<Map<String, Object?>>> correctionSources(
    TenantContext scope,
    String calculation, {
    String? after,
  }) async => WorkforcePage(
    sourceRows ??
        [
          {
            'id': sealId,
            'seal_id': sealId,
            'revision_id': originalId,
            'version': 1,
            'paid_seconds': 3600,
            'source_kind': 'attendance',
            'start_utc': '2026-10-01T03:30:00Z',
            'end_utc': '2026-10-01T04:30:00Z',
            'operational': {
              'source_version': 3,
              'before': {
                'start_local': '2026-10-01T09:00:00',
                'end_local': '2026-10-01T10:00:00',
                'start_offset_seconds': 19800,
                'end_offset_seconds': 19800,
                'breaks': <Object?>[],
              },
            },
          },
        ],
    null,
  );
  @override
  Future<Map<String, Object?>> correctionDetail(
    TenantContext scope,
    String correction,
    String section, {
    String? after,
  }) async {
    await gate?.future;
    return {
      'correction': rows.first,
      'section': section,
      'items':
          sections[section] ??
          [
            {
              'id': id,
              'before': {
                'gross': '100.000000',
                'deductions': '0.000000',
                'employer_cost': '0.000000',
                'net': '100.000000',
              },
              'after': {
                'gross': '50.000000',
                'deductions': '0.000000',
                'employer_cost': '0.000000',
                'net': '50.000000',
              },
              'difference': {
                'gross': '-50.000000',
                'deductions': '0.000000',
                'employer_cost': '0.000000',
                'net': '-50.000000',
                'lines': <Object?>[],
              },
            },
          ],
      'next_cursor': null,
    };
  }

  @override
  Future<Map<String, Object?>?> ownReceipt(
    TenantContext scope,
    String command,
    String capability,
  ) async => null;
  @override
  Future<Map<String, Object?>> executeCorrection(
    PayrollCorrectionCommandKind kind,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    writes++;
    last = command.payload;
    if (failure != null) {
      throw DomainError(code: failure!, message: 'Compare current fixture');
    }
    if (uncertain) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Retry',
        retryable: true,
      );
    }
    onWrite?.call();
    return {
      'command_id': command.commandId,
      'entity': {
        ...summary(),
        'id': command.payload['id'],
        'version': command.expectedEntityVersion! + 1,
      },
      'warnings': <Object?>[],
    };
  }
}

class Base implements PayrollRepository {
  int bankVersion = 1;
  @override
  Future<WorkforcePage<Map<String, Object?>>> accounts(
    TenantContext scope,
    String kind, {
    String? after,
  }) async => WorkforcePage([
    {
      'id': sealId,
      'name': 'Synthetic scoped bank',
      'currency_code': 'LKR',
      'version': bankVersion,
    },
  ], null);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    const base = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${base}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${base}Manrope-SemiBold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  late JentraLocalDatabase db;
  late Keys keys;
  late Server server;
  late PayrollCorrectionController c;
  late Base base;
  final caps = {
    'people.payroll.view',
    'people.payroll.correction.prepare',
    'people.payroll.correction.approve',
    'people.payroll.post',
    'people.payroll.reverse',
    'people.payroll.settle',
  };
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    keys = Keys();
    server = Server();
    base = Base();
    final drafts = SensitivePayrollCorrectionDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
      server.authorize,
    );
    c = PayrollCorrectionController(
      scope: scope,
      repository: server,
      base: base,
      drafts: drafts,
      permissions: caps,
      online: true,
      monitor: false,
    );
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  test('named original selection loads current seals instead of stopping on busy state', () async {
    await c.initialize();
    await c.beginPrepare();
    await c.selectOriginal(c.originals.single);
    expect(c.sources, hasLength(1));
    expect(c.form!['original_calculation_id'], originalId);
    c.replaceSource(c.sources.single, 1800);
    c.update('reason', 'Synthetic correction');
    await c.submit();
    expect(c.confirmed, isNotNull);
    expect(server.last!['replacements'], hasLength(1));
  });
  test('uncertain source proposal retains exact sealed request and cannot be replaced', () async {
    await c.beginPrepare();
    await c.selectOriginal(c.originals.single);
    c.replaceSource(c.sources.single, 1800);
    c.update('reason', 'Synthetic correction');
    server.uncertain = true;
    await c.submit();
    final pending = c.local!.pending!.toJson();
    c.update('reason', 'mutated');
    expect(c.form!['reason'], 'Synthetic correction');
    await c.submit();
    expect(c.local!.pending!.toJson(), pending);
    expect(c.confirmed, isNull);
  });
  test('reverse retains current direct and allocation credit identities in exact encrypted retry', () async {
    server.rows = [summary(status: 'posted')];
    server.sourceRows = [
      {
        'id': sealId,
        'seal_id': sealId,
        'source_kind': 'attendance',
        'operational': {
          'source_id': originalId,
          'source_version': 4,
          'allocations': [
            {
              'operational': {
                'entry_id': id,
                'source_id': sealId,
                'source_version': 5,
                'before': <String, Object?>{},
              },
            },
          ],
        },
      },
    ];
    await c.initialize();
    await c.open(c.rows.single, 'calculation');
    await c.beginAction('reverse');
    c.currentBillingCredits(
      c.sources.single,
      {id},
      allocation: {
        'entry_id': id,
        'source_id': sealId,
        'source_version': 5,
        'before': <String, Object?>{},
      },
    );
    c.update('reason', 'Synthetic current credit reversal');
    await c.save();
    final saved = await c.drafts.load(
      scope,
      PayrollCorrectionCommandKind.correction,
      id,
    );
    expect(saved!.form['current_billing_impacts'], [
      {
        'seal_id': sealId,
        'source_revision_id': originalId,
        'expected_source_version': 4,
        'billing_credit_line_ids': <String>[],
        'allocation_credits': [
          {
            'entry_id': id,
            'source_revision_id': sealId,
            'expected_source_version': 5,
            'billing_credit_line_ids': [id],
          },
        ],
      },
    ]);
    server.uncertain = true;
    await c.submit();
    final request = c.local!.pending!.toJson();
    c.currentBillingCredits(c.sources.single, <String>{});
    await c.submit();
    expect(c.local!.pending!.toJson(), request);
    expect(
      server.last!['current_billing_impacts'],
      saved.form['current_billing_impacts'],
    );
  });
  test(
    'verified confirmation survives encrypted receipt cleanup failure',
    () async {
      await c.beginPrepare();
      await c.selectOriginal(c.originals.single);
      c.replaceSource(c.sources.single, 1800);
      c.update('reason', 'Synthetic correction');
      server.onWrite = () => keys.forbid = true;
      await c.submit();
      expect(c.confirmed, isNotNull);
      expect(c.message, contains('confirmed'));
      expect(server.writes, 1);
    },
  );
  test('recorded settlement recovery reloads named banks and compares current bank version without correction digest', () async {
    server.rows = [summary(status: 'posted')];
    server.sections['balances'] = [
      {'id': sealId, 'kind': 'net', 'outstanding': '50.000000'},
    ];
    await c.initialize();
    await c.open(c.rows.single, 'balances');
    await c.beginAction('record');
    c.update('bank_id', sealId);
    c.update('bank_version', 1);
    c.update('direction', 'recover');
    c.update('evidence_reference', 'SYNTHETIC');
    c.allocate(sealId, '20.000000');
    c.update('reason', 'Synthetic recorded recovery');
    await c.save();
    await c.closeForm();
    await c.resume(c.recovery.single);
    expect(c.banks.single['name'], 'Synthetic scoped bank');
    expect(c.detail!['section'], 'balances');
    server.failure = 'VERSION_CONFLICT';
    await c.submit();
    expect(c.conflict, isTrue);
    base.bankVersion = 2;
    await c.compare();
    await c.acceptComparison();
    expect(c.form!.containsKey('digest'), isFalse);
    expect(c.form!['bank_version'], 2);
    expect(c.expectedVersion, 0);
    server.failure = null;
    await c.submit();
    expect(c.confirmed, isNotNull);
  });
  test('settlement reversal comparison uses recorded settlement version and original identity', () async {
    server.rows = [summary(status: 'posted')];
    server.sections['settlements'] = [
      {'id': sealId, 'version': 1, 'status': 'recorded'},
    ];
    await c.initialize();
    await c.open(c.rows.single, 'settlements');
    await c.beginAction(
      'settlement_reverse',
      settlement: server.sections['settlements']!.single,
    );
    c.update('reason', 'Synthetic original settlement reversal');
    server.failure = 'VERSION_CONFLICT';
    await c.submit();
    server.sections['settlements'] = [
      {'id': sealId, 'version': 2, 'status': 'recorded'},
    ];
    await c.compare();
    await c.acceptComparison();
    expect(c.expectedVersion, 2);
    expect(c.form!['id'], sealId);
    expect(c.form!.containsKey('digest'), isFalse);
    server.failure = null;
    await c.submit();
    expect(c.confirmed, isNotNull);
  });
  test('current access loss clears private visible data', () async {
    await c.initialize();
    await c.open(c.rows.single, 'calculation');
    expect(c.detail, isNotNull);
    server.deny = true;
    await c.checkAccess();
    expect(c.denied, isTrue);
    expect(c.detail, isNull);
    expect(c.rows, isEmpty);
    expect(c.form, isNull);
  });
  test(
    'late old-scope response is discarded after controller disposal',
    () async {
      await c.initialize();
      server.gate = Completer<void>();
      final old = c.open(c.rows.single, 'calculation');
      await Future<void>.delayed(Duration.zero);
      c.dispose();
      server.gate!.complete();
      await old;
      expect(c.detail, isNull);
    },
  );
  testWidgets(
    'native review exposes signed difference and independent actions',
    (tester) async {
      await c.initialize();
      await c.open(c.rows.single, 'calculation');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PayrollCorrectionWorkspace(controller: c)),
        ),
      );
      expect(find.text('Approve independently'), findsOneWidget);
      expect(find.textContaining('difference -50.000000'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'reopened source editor displays saved eligibility geometry and exact break fields',
    (tester) async {
      await c.beginPrepare();
      await c.selectOriginal(c.originals.single);
      c.replaceSource(
        c.sources.single,
        2700,
        impact: {
          'mode': 'geometry',
          'expected_source_version': 3,
          'start_local': '2026-10-01T09:00:00',
          'end_local': '2026-10-01T10:00:00',
          'start_offset_seconds': 19800,
          'end_offset_seconds': 19800,
          'breaks': [
            {
              'start_utc': '2026-10-01T04:00:00Z',
              'end_utc': '2026-10-01T04:15:00Z',
            },
          ],
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PayrollCorrectionSourceEditor(
                controller: c,
                source: c.sources.single,
              ),
            ),
          ),
        ),
      );
      final fields = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .toList();
      expect(fields.any((field) => field.initialValue == '2700'), isTrue);
      expect(
        fields.any((field) => field.initialValue == '2026-10-01T04:00:00Z'),
        isTrue,
      );
      expect(
        fields.any((field) => field.initialValue == '2026-10-01T04:15:00Z'),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'reversal exposes current removed allocation evidence without adding a preparation edit',
    (tester) async {
      server.rows = [summary(status: 'posted')];
      server.sourceRows = [
        {
          'id': sealId,
          'seal_id': sealId,
          'source_kind': 'attendance',
          'paid_seconds': 3600,
          'operational': {
            'source_id': originalId,
            'source_version': 4,
            'before': <String, Object?>{},
            'allocations': [
              {
                'active': false,
                'source_kind': 'project',
                'operational': {
                  'entry_id': id,
                  'project_name': 'Synthetic removed time',
                  'source_id': sealId,
                  'source_version': 5,
                  'before': <String, Object?>{},
                },
              },
            ],
          },
        },
      ];
      await c.initialize();
      await c.open(c.rows.single, 'calculation');
      await c.beginAction('reverse');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PayrollCorrectionReverseCredits(
              controller: c,
              source: c.sources.single,
            ),
          ),
        ),
      );
      expect(find.textContaining('removed allocation'), findsOneWidget);
      final picker = tester.widget<PayrollCorrectionCreditPicker>(
        find.byType(PayrollCorrectionCreditPicker),
      );
      expect(picker.sourceRevision, sealId);
      picker.onChanged({originalId});
      final impacts = c.form!['current_billing_impacts'] as List;
      expect((impacts.single as Map)['allocation_credits'], [
        {
          'entry_id': id,
          'source_revision_id': sealId,
          'expected_source_version': 5,
          'billing_credit_line_ids': [originalId],
        },
      ]);
      c.form = {
        'action': 'prepare',
        'id': id,
        'replacements': [
          {
            'seal_id': sealId,
            'paid_seconds': 3600,
            'impact': {
              'mode': 'geometry',
              'start_local': '2026-10-01T09:00:00',
              'end_local': '2026-10-01T10:00:00',
              'start_offset_seconds': 19800,
              'end_offset_seconds': 19800,
              'breaks': <Map<String, Object?>>[],
            },
          },
        ],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PayrollCorrectionSourceEditor(
              controller: c,
              source: c.sources.single,
            ),
          ),
        ),
      );
      expect(find.byType(PayrollCorrectionAllocationEditor), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('preparer cannot see independent approval action', (
    tester,
  ) async {
    server.rows = [summary(actor: scope.actorId)];
    await c.initialize();
    await c.open(c.rows.single, 'calculation');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PayrollCorrectionWorkspace(controller: c)),
      ),
    );
    expect(find.text('Approve independently'), findsNothing);
  });
  for (final dark in [false, true]) {
    testWidgets(
      'correction editor scrolls at 1024 by 720 and 200 percent ${dark ? 'dark' : 'light'}',
      (tester) async {
        tester.view.physicalSize = const Size(1024, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await c.beginPrepare();
        await c.selectOriginal(c.originals.single);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? JentraTheme.dark() : JentraTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(body: PayrollCorrectionEditor(controller: c)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('SYNTHETIC_EMPLOYEE · SYN-001'), findsOneWidget);
        await tester.ensureVisible(find.text('Include source replacement'));
        await tester.pumpAndSettle();
        expect(find.text('Submit exact proposal'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            'goldens/payroll_correction_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
      },
    );
  }
}

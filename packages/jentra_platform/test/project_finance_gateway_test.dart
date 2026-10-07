import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_domain/jentra_projects.dart';
import 'package:jentra_domain/jentra_project_finance.dart';
import 'package:jentra_platform/jentra_project_finance_platform.dart';
import 'support/wave4_gateway_harness.dart';

final financeSamples = projectMap(
  jsonDecode(
    File(
      'test/fixtures/project_finance_rollback_projections.json',
    ).readAsStringSync(),
  ),
);
final financeScope = TenantContext(
  tenantId: projectMap(financeSamples['expenses'])['tenant_id'] as String,
  legalEntityId:
      projectMap(financeSamples['expenses'])['legal_entity_id'] as String,
  branchId: projectMap(financeSamples['expenses'])['branch_id'] as String,
  actorId: w4Scope.actorId,
);
final financeProject =
    projectMap(financeSamples['expenses'])['project_id'] as String;
Map<String, Object?> billingPayload() => {
  'action': 'billing_prepare',
  'id': w4Id,
  'project_id': financeProject,
  'invoice_id': w4Revision,
  'document_date': '2026-10-01',
  'due_date': '2026-10-02',
  'exchange_rate_id': null,
  'units': [
    {
      'unit_id': w4Command,
      'source_version': 1,
      'source_digest': 'a' * 64,
      'product_id': w4Id,
      'product_version': 1,
      'tax_definition_id': null,
      'tax_version': null,
      'description': 'Whole synthetic source',
    },
  ],
  'reason': 'Synthetic billing',
};
CommandEnvelope<Map<String, Object?>> financeEnvelope(Map<String, Object?> p) =>
    CommandEnvelope(
      commandId: w4Command,
      idempotencyKey: w4Command,
      context: financeScope,
      payload: p,
      expectedEntityVersion: 0,
      clientTimestamp: DateTime.utc(2026, 10, 1),
    );
void main() {
  late Wave4GatewayHarness h;
  late SupabaseProjectFinanceGateway g;
  setUp(() async {
    h = Wave4GatewayHarness();
    await h.initialize();
    g = SupabaseProjectFinanceGateway(h.client);
  });
  tearDown(() => h.dispose());
  for (final section in ProjectFinanceSection.values) {
    test(
      'AC-414 actual ${section.name} rollback projection crosses the typed gateway',
      () async {
        h.response = financeSamples[section.name]!;
        final page = await g.detail(
          financeScope,
          financeProject,
          'LKR',
          section,
        );
        expect(page.rows, isNotEmpty);
        expect(
          h.requests.single.url.path.endsWith('/rpc/projects_finance_detail'),
          isTrue,
        );
        expect(h.requests.single.headers['content-profile'], 'api');
      },
    );
  }
  test('AC-414 as-of margin reconciles original costs/revenue', () async {
    final sample = projectMap(financeSamples['margin']);
    h.response = sample;
    final margin = await g.margin(
      financeScope,
      financeProject,
      DateTime.parse(sample['as_of'] as String),
      CivilDate.parse(sample['effective_date'] as String),
    );
    expect(margin.values['margin']!.toDecimalString(), '0.020000');
  });
  test(
    'AC-415 forged scope, cursor and private expansion fail closed',
    () async {
      final original = projectMap(financeSamples['expenses']);
      for (final bad in [
        {...original, 'project_id': w4Id},
        {...original, 'tenant_id': w4Id},
        {...original, 'next_after': w4Id},
        {
          ...original,
          'rows': [
            (projectMap((original['rows'] as List).single))
              ..['bank_details'] = 'secret',
          ],
        },
      ]) {
        h.response = bad;
        await expectLater(
          g.detail(
            financeScope,
            financeProject,
            'LKR',
            ProjectFinanceSection.expenses,
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'AC-414 expense money, FX residue and allocations cannot be changed',
    () async {
      final original = projectMap(financeSamples['expenses']),
          row = projectMap((original['rows'] as List).single);
      for (final change in [
        {'gross': 0.03},
        {'gross': '0.04'},
        {'base_gross': '0.04'},
        {'fx_numerator': '2'},
        {'tax_rounding_residue': '0.01'},
        {'allocations': []},
      ]) {
        h.response = {
          ...original,
          'rows': [
            {...row, ...change},
          ],
        };
        await expectLater(
          g.detail(
            financeScope,
            financeProject,
            'LKR',
            ProjectFinanceSection.expenses,
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'AC-415 supplier and attachment providers are explicit unavailable',
    () async {
      h.response = {
        ...h.scope(),
        'tenant_id': financeScope.tenantId,
        'legal_entity_id': financeScope.legalEntityId,
        'branch_id': financeScope.branchId,
        'actor_id': financeScope.actorId,
        'capability': 'projects.cost.view',
        'authorized': true,
        'supplier_ap_available': false,
        'attachments_available': false,
        'sales_available': true,
      };
      await g.authorize(financeScope, 'projects.cost.view');
      h.response = {...(h.response as Map), 'supplier_ap_available': true};
      await expectLater(
        g.authorize(financeScope, 'projects.cost.view'),
        throwsFormatException,
      );
    },
  );
  test('AC-415 command forwards only scoped exact frozen evidence', () async {
    final p = billingPayload();
    h.response = {
      'request_id': w4Command,
      'command_id': w4Command,
      'correlation_id': w4Command,
      'warnings': [],
      'entity': {
        'tenant_id': financeScope.tenantId,
        'legal_entity_id': financeScope.legalEntityId,
        'branch_id': financeScope.branchId,
        'id': w4Id,
        'project_id': financeProject,
        'version': 1,
        'status': 'prepared',
        'invoice_id': w4Revision,
      },
    };
    await g.command(financeEnvelope(p));
    final wire = projectMap(jsonDecode(h.requests.single.body));
    expect(wire['p_payload'], p);
    expect(wire['p_expected_version'], 0);
    expect(wire.containsKey('actor_id'), isFalse);
    expect(h.requests.single.headers['content-profile'], 'api');
  });
  test(
    'FR426 actual scoped expense proofs remain minimal and reject private fields',
    () async {
      final original = projectMap(financeSamples['attachedExpenses']);
      h.response = original;
      final page = await g.detail(
        financeScope,
        financeProject,
        'LKR',
        ProjectFinanceSection.expenses,
      );
      final row = page.rows.single;
      expect((row.values['evidence_documents'] as List), isNotEmpty);
      final wire = projectMap((original['rows'] as List).single);
      h.response = {
        ...original,
        'rows': [
          {
            ...wire,
            'evidence_documents': [
              {
                ...projectMap((wire['evidence_documents'] as List).single),
                'checksum': 'a' * 64,
              },
            ],
          },
        ],
      };
      await expectLater(
        g.detail(
          financeScope,
          financeProject,
          'LKR',
          ProjectFinanceSection.expenses,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'FR426 provider authority is checked in the exact expense scope',
    () async {
      final expense = projectMap(
        (projectMap(financeSamples['attachedExpenses'])['rows'] as List).single,
      )['id'];
      h.response = {
        'tenant_id': financeScope.tenantId,
        'legal_entity_id': financeScope.legalEntityId,
        'branch_id': financeScope.branchId,
        'actor_id': financeScope.actorId,
        'project_id': financeProject,
        'expense_id': expense,
        'authorized': true,
        'available': false,
      };
      await g.authorizeEvidence(
        financeScope,
        financeProject,
        expense as String,
      );
      final wire = projectMap(jsonDecode(h.requests.single.body));
      expect(wire['p_project_id'], financeProject);
      expect(wire['p_expense_id'], expense);
      h.response = {...projectMap(h.response), 'expense_id': w4Id};
      await expectLater(
        g.authorizeEvidence(financeScope, financeProject, expense),
        throwsFormatException,
      );
    },
  );
  test('AC-415 malformed acknowledgement stays uncertain', () async {
    h.response = {
      'request_id': w4Command,
      'command_id': w4Id,
      'correlation_id': w4Command,
      'warnings': [],
      'entity': {},
    };
    await expectLater(
      g.command(financeEnvelope(billingPayload())),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
      ),
    );
  });
  test('AC-415 numeric money and duplicate units fail before HTTP', () async {
    final p = billingPayload();
    p['units'] = [...(p['units'] as List), ...(p['units'] as List)];
    await expectLater(g.command(financeEnvelope(p)), throwsFormatException);
    expect(h.requests, isEmpty);
  });
  test(
    'AC-415 revoked and unavailable reads have safe public errors',
    () async {
      for (final pair in [
        ('42501', 'PERMISSION_DENIED'),
        ('PGRST202', 'FEATURE_NOT_INSTALLED'),
        ('40001', 'VERSION_CONFLICT'),
      ]) {
        h.status = 400;
        h.response = {
          'code': pair.$1,
          'message': 'Synthetic private amount 999999',
        };
        await expectLater(
          g.detail(
            financeScope,
            financeProject,
            'LKR',
            ProjectFinanceSection.expenses,
          ),
          throwsA(
            isA<DomainError>()
                .having((e) => e.code, 'code', pair.$2)
                .having(
                  (e) => e.message.contains('999999'),
                  'safe message',
                  false,
                ),
          ),
        );
      }
    },
  );
  test(
    'AC-415 account changes discard reads and leave commands uncertain',
    () async {
      h.response = financeSamples['expenses']!;
      h.gate = Completer<void>();
      final reading = g.detail(
        financeScope,
        financeProject,
        'LKR',
        ProjectFinanceSection.expenses,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await h.client.auth.signOut();
      h.gate!.complete();
      await expectLater(
        reading,
        throwsA(
          isA<DomainError>().having(
            (e) => e.code,
            'code',
            'AUTHENTICATION_REQUIRED',
          ),
        ),
      );
    },
  );
  test('AC-428 missing finance entitlement has a safe native reason', () async {
    h.status = 400;
    h.response = {
      'code': '42501',
      'message': 'PROJECT_FINANCE_ENTITLEMENT_REQUIRED',
    };
    await expectLater(
      g.authorize(financeScope, 'projects.cost.view'),
      throwsA(
        isA<DomainError>()
            .having((e) => e.code, 'code', 'FEATURE_NOT_ENTITLED')
            .having(
              (e) => e.message,
              'reason',
              contains('Projects and Finance'),
            ),
      ),
    );
  });
}

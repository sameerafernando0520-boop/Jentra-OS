import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_domain/jentra_projects.dart';
import 'package:jentra_platform/jentra_projects_platform.dart';
import 'support/wave4_gateway_harness.dart';

Map<String, Object?> createPayload() => {
  'action': 'create',
  'id': w4Id,
  'code': 'LAB',
  'name': 'Synthetic project',
  'customer_id': null,
  'manager_id': w4Revision,
  'currency_code': 'LKR',
  'start_date': '2026-10-01',
  'end_date_exclusive': '2026-10-03',
  'reason': 'Synthetic plan',
};
CommandEnvelope<Map<String, Object?>> envelope(Map<String, Object?> p) =>
    CommandEnvelope(
      commandId: w4Command,
      idempotencyKey: w4Command,
      context: w4Scope,
      payload: p,
      expectedEntityVersion: 0,
      clientTimestamp: DateTime.utc(2026, 10, 1),
    );
TypeMatcher<DomainError> errorCode(String code) =>
    isA<DomainError>().having((e) => e.code, 'code', code);
void main() {
  late Wave4GatewayHarness h;
  late SupabaseProjectGateway g;
  setUp(() async {
    h = Wave4GatewayHarness();
    await h.initialize();
    g = SupabaseProjectGateway(h.client);
  });
  tearDown(() async {
    await h.dispose();
  });
  final samples = projectMap(
    jsonDecode(
      File(
        'test/fixtures/projects_rollback_projections.json',
      ).readAsStringSync(),
    ),
  );
  for (final key in ['resolution', 'second_resolution']) {
    test('actual $key keeps the published exact local second', () async {
      final response = projectMap(samples[key]);
      final value = projectMap(response['resolution']);
      final scope = TenantContext(
        tenantId: response['tenant_id'] as String,
        legalEntityId: response['legal_entity_id'] as String,
        branchId: response['branch_id'] as String,
        actorId: w4Scope.actorId,
      );
      final date = CivilDate.parse(value['date'] as String);
      final version = CalendarCoverage(
        id: value['calendar_version_id'] as String,
        startDate: date.value,
        endDateExclusive: date.utc
            .add(const Duration(days: 1))
            .toIso8601String()
            .substring(0, 10),
        timezone: value['timezone'] as String,
      );
      h.response = response;
      final result = await g.localCandidates(
        scope,
        version,
        date,
        value['minute'] as int,
        second: value['second'] as int,
      );
      expect(result.second, key == 'second_resolution' ? 1 : 0);
      expect(result.candidates.single.utc.second, result.second);
      expect(
        projectMap(jsonDecode(h.requests.last.body))['p_second'],
        result.second,
      );
    });
  }
  for (final section in ProjectSection.values.where(
    (v) => v != ProjectSection.timeEvents,
  )) {
    test(
      'actual rollback ${section.wire} projection crosses typed project gateway',
      () async {
        final response = projectMap(samples[section.wire]),
            project = projectMap(response['project']);
        final scope = TenantContext(
          tenantId: project['tenant_id'] as String,
          legalEntityId: project['legal_entity_id'] as String,
          branchId: project['branch_id'] as String,
          actorId: w4Scope.actorId,
        );
        h.response = response;
        final detail = await g.detail(scope, project['id'] as String, section);
        expect(detail.project.name, 'Synthetic Project');
        expect(detail.rows, isNotEmpty);
        switch (section) {
          case ProjectSection.plans:
            expect(
              (detail.rows.first as ProjectPlan).decision!.decision,
              'approved',
            );
          case ProjectSection.tasks:
            expect(
              detail.rows
                  .whereType<ProjectTask>()
                  .map((v) => v.basis.plannedSeconds)
                  .reduce((a, b) => a + b),
              7200,
            );
          case ProjectSection.resources:
            expect((detail.rows.single as ProjectResource).span.seconds, 7200);
          case ProjectSection.cost:
            expect(
              (detail.rows.single as ProjectBudget).budget.toDecimalString(),
              '1000.000000',
            );
          case ProjectSection.resourceCost:
            expect(
              (detail.rows.single as ProjectResourceCost).hourlyRate
                  .toDecimalString(),
              '18.000000',
            );
          case ProjectSection.time:
            expect(
              (detail.rows.single as ProjectTime).work.payableSeconds,
              3600,
            );
          case ProjectSection.timeCost:
            expect(
              (detail.rows.single as ProjectTimeCost).amount.toDecimalString(),
              '18.000000',
            );
          case ProjectSection.units:
            expect(
              (detail.rows.single as ProjectUnit).basis.salesQuantity,
              '1.000000',
            );
          case ProjectSection.timeEvents:
            break;
        }
        expect(
          h.requests.single.url.path.endsWith('/rpc/projects_detail'),
          isTrue,
        );
        expect(h.requests.single.method, 'POST');
        expect(h.requests.single.headers['content-profile'], 'api');
      },
    );
  }
  test(
    'actual directory and named paged choices retain scope and continuation',
    () async {
      final r = projectMap(samples['directory']),
          p = projectMap((r['rows'] as List).single),
          s = TenantContext(
            tenantId: p['tenant_id'] as String,
            legalEntityId: p['legal_entity_id'] as String,
            branchId: p['branch_id'] as String,
            actorId: w4Scope.actorId,
          );
      h.response = r;
      expect((await g.directory(s)).rows.single.name, 'Synthetic Project');
      h.response = {
        'rows': [
          {'id': w4Id, 'name': 'Synthetic worker', 'code': 'LAB', 'version': 1},
        ],
        'next_after': null,
      };
      expect(
        (await g.choices(s, 'employees')).rows.single.name,
        'Synthetic worker',
      );
      h.response = {
        'rows': [
          {'id': w4Id, 'name': 'Synthetic worker', 'code': 'LAB', 'version': 1},
        ],
        'next_after': w4Id,
      };
      await expectLater(g.choices(s, 'employees'), throwsFormatException);
    },
  );
  test(
    'private fields, altered UTC duration, child ownership and excess pages are rejected',
    () async {
      final response = projectMap(samples['time']),
          p = projectMap(response['project']),
          s = TenantContext(
            tenantId: p['tenant_id'] as String,
            legalEntityId: p['legal_entity_id'] as String,
            branchId: p['branch_id'] as String,
            actorId: w4Scope.actorId,
          ),
          row = projectMap((response['rows'] as List).single);
      for (final altered in [
        {...row, 'hourly_rate': '999.00'},
        {...row, 'payable_seconds': 3599},
        {...row, 'project_id': w4Id},
        {...row, 'start_offset_seconds': 0},
        {...row, 'bill_amount': 54.0},
      ]) {
        h.response = {
          ...response,
          'rows': [altered],
        };
        await expectLater(
          g.detail(s, p['id'] as String, ProjectSection.time),
          throwsFormatException,
        );
      }
      h.response = {...response, 'rows': List.filled(51, row)};
      await expectLater(
        g.detail(s, p['id'] as String, ProjectSection.time),
        throwsFormatException,
      );
      h.response = {
        ...response,
        'rows': [row, row],
      };
      await expectLater(
        g.detail(s, p['id'] as String, ProjectSection.time),
        throwsFormatException,
      );
    },
  );
  test(
    'authorization validates actor, capability, explicit provider gates and published precision',
    () async {
      final r = {
        ...h.scope(),
        'actor_id': w4Scope.actorId,
        'capability': 'projects.view',
        'authorized': true,
        'currency_code': 'LKR',
        'precision': 2,
        'expense_evidence_provider': false,
        'supplier_bill_provider': false,
      };
      h.response = r;
      final state = await g.authorize(w4Scope, 'projects.view');
      expect(state.expenseEvidence, isFalse);
      expect(state.precision, 2);
      for (final altered in [
        {...r, 'actor_id': w4Id},
        {...r, 'precision': 7},
        {...r, 'capability': 'projects.manage'},
        {...r, 'supplier_bill_provider': null},
      ]) {
        h.response = altered;
        await expectLater(
          g.authorize(w4Scope, 'projects.view'),
          throwsFormatException,
        );
      }
    },
  );
  test('confirmed response is minimal and action/version-bound', () async {
    final e = {
      ...h.scope(),
      'id': w4Id,
      'version': 1,
      'status': 'open',
      'current_plan_id': null,
    };
    h.response = h.confirmed(e);
    expect(
      (await g.command(envelope(createPayload()), 'LKR', 2))['command_id'],
      w4Command,
    );
    for (final altered in [
      {...e, 'version': 2},
      {...e, 'status': 'closed'},
      {...e, 'budget': '1000.00'},
      {...e, 'branch_id': w4Id},
      {...e, 'current_plan_id': w4Revision},
    ]) {
      h.response = h.confirmed(altered);
      await expectLater(
        g.command(envelope(createPayload()), 'LKR', 2),
        throwsA(errorCode('UNCERTAIN_RESULT')),
      );
    }
  });
  test(
    'original actor key and action gate govern receipt reconciliation',
    () async {
      h.response = {
        'command_id': w4Command,
        'idempotency_key': w4Command,
        'request_hash': 'a' * 64,
        'response': h.confirmed({
          ...h.scope(),
          'id': w4Id,
          'version': 1,
          'status': 'open',
          'current_plan_id': null,
        }),
      };
      expect(await g.ownReceipt(w4Scope, w4Command, 'create'), isNotNull);
      h.response = {...h.response as Map, 'idempotency_key': w4Id};
      await expectLater(
        g.ownReceipt(w4Scope, w4Command, 'create'),
        throwsFormatException,
      );
      await expectLater(
        g.ownReceipt(w4Scope, w4Command, 'private_export'),
        throwsFormatException,
      );
    },
  );
  test(
    'payload is frozen before an awaited issuance and late account loss stays uncertain',
    () async {
      final p = createPayload();
      h.gate = Completer<void>();
      h.response = h.confirmed({
        ...h.scope(),
        'id': w4Id,
        'version': 1,
        'status': 'open',
        'current_plan_id': null,
      });
      final request = g.command(envelope(p), 'LKR', 2);
      await Future<void>.delayed(Duration.zero);
      p['name'] = 'Changed later';
      expect(
        (jsonDecode(h.requests.single.body)['p_payload'] as Map)['name'],
        'Synthetic project',
      );
      await h.client.auth.signOut();
      h.gate!.complete();
      await expectLater(request, throwsA(errorCode('UNCERTAIN_RESULT')));
    },
  );
  test(
    'lost response timeout preserves an uncertain original command',
    () async {
      g = SupabaseProjectGateway(
        h.client,
        timeout: const Duration(milliseconds: 20),
      );
      h.gate = Completer<void>();
      final c = envelope(createPayload());
      await expectLater(
        g.command(c, 'LKR', 2),
        throwsA(errorCode('UNCERTAIN_RESULT')),
      );
      h.gate!.complete();
      expect(c.commandId, w4Command);
      expect(c.payload['name'], 'Synthetic project');
    },
  );
  test(
    'validation precedes network and server errors expose no raw private evidence',
    () async {
      await expectLater(
        g.command(
          envelope(createPayload()..['currency_code'] = 'USD'),
          'LKR',
          2,
        ),
        throwsFormatException,
      );
      expect(h.requests, isEmpty);
      h.status = 400;
      h.response = {
        'code': '55000',
        'message': 'PAYROLL_INPUT_SEALED',
        'details': 'private compensation secret',
        'hint': 'bank details',
      };
      await expectLater(
        g.command(envelope(createPayload()), 'LKR', 2),
        throwsA(
          errorCode('PAYROLL_INPUT_SEALED').having(
            (e) => e.message.contains('secret'),
            'raw server evidence',
            isFalse,
          ),
        ),
      );
    },
  );
}

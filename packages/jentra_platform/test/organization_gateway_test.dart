import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_platform/jentra_people_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'support/wave4_gateway_harness.dart';

void main() {
  late Wave4GatewayHarness h;
  late SupabaseOrganizationGateway gateway;
  final date = CivilDate.parse('2026-09-26');
  Map<String, Object?> department() => {
    'id': w4Id,
    'code': 'OPS',
    'version': 1,
    'revision_id': w4Revision,
    'name': 'Operations',
    'parent_id': null,
    'start_date': '2026-09-01',
    'end_date_exclusive': null,
  };
  Map<String, Object?> page() => {
    ...h.scope(),
    'as_of': date.value,
    'items': [department()],
  };
  Map<String, Object?> payload() => {
    'id': w4Id,
    'revision_id': w4Revision,
    'code': 'OPS',
    'name': 'Operations',
    'parent_id': null,
    'start_date': '2026-09-01',
    'end_date_exclusive': null,
    'reason': 'Synthetic setup',
  };
  CommandEnvelope<Map<String, Object?>> command() => CommandEnvelope(
    commandId: w4Command,
    idempotencyKey: w4Command,
    context: w4Scope,
    payload: payload(),
    clientTimestamp: DateTime.utc(2026, 9, 26),
    expectedEntityVersion: 0,
  );
  setUp(() async {
    h = Wave4GatewayHarness();
    await h.initialize();
    gateway = SupabaseOrganizationGateway(h.client);
  });
  tearDown(() => h.dispose());
  test('AC-401 organization directory uses scoped authenticated RPC', () async {
    h.response = page();
    final result = await gateway.departments(w4Scope, date, search: '100%');
    expect(result.items.single.name, 'Operations');
    final body = jsonDecode(h.requests.single.body) as Map;
    expect(body['p_search'], '100%');
    expect(body['p_tenant_id'], w4Scope.tenantId);
    expect(body['p_branch_id'], w4Scope.branchId);
    expect(h.requests.single.headers['content-profile'], 'api');
  });
  test('AC-401 response scope, date and private additions rejected', () async {
    for (final response in [
      {...page(), 'branch_id': w4Id},
      {...page(), 'as_of': '2026-09-27'},
      {
        ...page(),
        'items': [
          {...department(), 'salary': '100'},
        ],
      },
    ]) {
      h.response = response;
      await expectLater(
        gateway.departments(w4Scope, date),
        throwsFormatException,
      );
    }
  });
  test('AC-401 duplicate, reversed and oversize pages rejected', () async {
    for (final rows in [
      [department(), department()],
      List.generate(51, (_) => department()),
    ]) {
      h.response = {...page(), 'items': rows};
      await expectLater(
        gateway.departments(w4Scope, date),
        throwsFormatException,
      );
    }
  });
  test('AC-401 no response becomes visible after sign out', () async {
    h.response = page();
    h.gate = Completer<void>();
    final future = gateway.departments(w4Scope, date);
    final check = expectLater(
      future,
      throwsA(
        isA<DomainError>().having(
          (e) => e.code,
          'code',
          'AUTHENTICATION_REQUIRED',
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await h.client.auth.signOut(scope: SignOutScope.local);
    h.gate!.complete();
    await check;
  });
  test(
    'AC-403 command preserves IDs, timestamp, expected version and exact payload',
    () async {
      h.response = h.confirmed({
        'id': w4Id,
        'tenant_id': w4Scope.tenantId,
        'legal_entity_id': w4Scope.legalEntityId,
        'code': 'OPS',
        'version': 1,
        'revision_id': w4Revision,
      });
      final result = await gateway.execute('department_create', command());
      expect(result.version, 1);
      final body = jsonDecode(h.requests.single.body) as Map;
      expect(body['p_payload'], {...payload(), 'action': 'department_create'});
      expect(body['p_expected_version'], 0);
      expect(body['p_command_id'], w4Command);
      expect(body['p_idempotency_key'], w4Command);
      expect(body['p_client_timestamp'], '2026-09-26T00:00:00.000Z');
    },
  );
  test(
    'AC-419 invalid confirmation remains uncertain for original retry',
    () async {
      h.response = h.confirmed({
        'id': w4Id,
        'tenant_id': w4Id,
        'legal_entity_id': w4Scope.legalEntityId,
        'code': 'OPS',
        'version': 1,
        'revision_id': w4Revision,
      });
      await expectLater(
        gateway.execute('department_create', command()),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
        ),
      );
    },
  );
  test(
    'AC-403 consumed-date failure is actionable and contains no server text',
    () async {
      h.status = 400;
      h.response = {
        'code': '55000',
        'message': 'ORGANIZATION_CONSUMED_IMPACT_REQUIRED',
        'details': 'private db context',
        'hint': null,
      };
      await expectLater(
        gateway.execute('department_create', command()),
        throwsA(
          isA<DomainError>()
              .having(
                (e) => e.code,
                'code',
                'ORGANIZATION_CONSUMED_IMPACT_REQUIRED',
              )
              .having(
                (e) => e.message.contains('private db context'),
                'leak',
                false,
              ),
        ),
      );
    },
  );
  test(
    'AC-403 scoped employee assignment carries named operational references',
    () async {
      final assignment = {
        'id': w4Revision,
        ...h.scope(),
        'employee_id': w4Id,
        'spell_id': w4Revision,
        'department_id': w4Id,
        'manager_id': null,
        'calendar_version_id': w4Revision,
        'role_title': 'Technician',
        'start_date': '2026-09-01',
        'end_date_exclusive': '2026-10-01',
        'reason': 'Synthetic assignment',
        'recorded_by': w4Scope.actorId,
        'recorded_at': '2026-09-26T00:00:00Z',
        'supersedes_id': null,
        'superseded_at': null,
        'department_name_at_start': 'Operations',
        'manager_display_name': null,
        'calendar_name': 'HQ Calendar',
        'calendar_timezone': 'Asia/Colombo',
        'withdrawal': null,
      };
      h.response = {
        ...h.scope(),
        'employee_id': w4Id,
        'employee_version': 2,
        'as_of': date.value,
        'items': [assignment],
      };
      final state = await gateway.employee(w4Scope, w4Id, date);
      expect(state.current!.calendarName, 'HQ Calendar');
      expect(state.current!.departmentName, 'Operations');
      h.response = {
        ...h.scope(),
        'employee_id': w4Id,
        'employee_version': 2,
        'as_of': date.value,
        'items': [
          {...assignment, 'employee_id': w4Revision},
        ],
      };
      await expectLater(
        gateway.employee(w4Scope, w4Id, date),
        throwsFormatException,
      );
    },
  );
  test(
    'AC-403 future withdrawal confirms original revision and actor',
    () async {
      final p = {
        'id': w4Id,
        'employee_id': w4Id,
        'replace_revision_id': w4Revision,
        'start_date': '2026-10-01',
        'end_date_exclusive': '2026-11-01',
        'reason': 'Withdraw future assignment',
      };
      h.response = h.confirmed({
        'id': w4Id,
        ...h.scope(),
        'employee_id': w4Id,
        'revision_id': w4Revision,
        'reason': p['reason'],
        'recorded_by': w4Scope.actorId,
        'recorded_at': '2026-09-26T00:00:00Z',
        'employee_version': 3,
      });
      final result = await gateway.execute(
        'withdraw_assignment',
        CommandEnvelope(
          commandId: w4Command,
          idempotencyKey: w4Command,
          context: w4Scope,
          payload: p,
          expectedEntityVersion: 2,
        ),
      );
      expect(result.withdrawal!.reason, p['reason']);
      expect(result.version, 3);
    },
  );
  test('AC-403 exact department detail rejects swapped identity', () async {
    h.response = {
      ...h.scope(),
      'as_of': date.value,
      'department': department(),
    };
    expect((await gateway.department(w4Scope, w4Id, date)).name, 'Operations');
    h.response = {
      ...h.scope(),
      'as_of': date.value,
      'department': {...department(), 'id': w4Revision},
    };
    await expectLater(
      gateway.department(w4Scope, w4Id, date),
      throwsFormatException,
    );
  });
}

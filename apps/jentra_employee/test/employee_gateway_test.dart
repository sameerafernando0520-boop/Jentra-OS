import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:jentra_employee/src/data/employee_gateway.dart';

const tenant = '10000000-0000-0000-0000-000000000001';
const entity = '10000000-0000-0000-0000-000000000002';
const branch = '10000000-0000-0000-0000-000000000003';
const actor = '10000000-0000-0000-0000-000000000004';
const employee = '20000000-0000-0000-0000-000000000001';
const record = '30000000-0000-0000-0000-000000000001';
const ws = EmployeeWorkspace(
  tenantId: tenant,
  legalEntityId: entity,
  branchId: branch,
  tenantName: 'Business',
  entityName: 'Entity',
  branchName: 'Branch',
  timeZone: 'Asia/Colombo',
);
const person = EmployeeIdentity(
  workspace: ws,
  actorId: actor,
  employeeId: employee,
  displayName: 'Employee',
);

Map<String, Object?> scope() => {
  'tenant_id': tenant,
  'legal_entity_id': entity,
  'branch_id': branch,
};

void main() {
  late SupabaseClient client;
  late SupabaseEmployeeGateway gateway;
  late List<http.Request> requests;
  Object? response;
  var status = 200;
  var serverActor = actor;
  var logoutStatus = 200;
  Completer<void>? gate;
  setUp(() async {
    requests = [];
    status = 200;
    serverActor = actor;
    logoutStatus = 200;
    gate = null;
    response = {
      ...scope(),
      'employee_id': employee,
      'display_name': 'Employee',
    };
    client = SupabaseClient(
      'https://employee.example.test',
      'synthetic-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/token')) {
          final claims = base64Url.encode(
            utf8.encode(
              jsonEncode({
                'sub': actor,
                'role': 'authenticated',
                'exp': 4102444800,
              }),
            ),
          );
          return http.Response(
            jsonEncode({
              'access_token': 'e30.$claims.synthetic',
              'refresh_token': 'synthetic',
              'expires_in': 3600,
              'token_type': 'bearer',
              'user': {
                'id': actor,
                'aud': 'authenticated',
                'app_metadata': {},
                'user_metadata': {},
                'created_at': '2026-09-01T00:00:00Z',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.endsWith('/user')) {
          return http.Response(
            jsonEncode({
              'id': serverActor,
              'aud': 'authenticated',
              'app_metadata': {},
              'user_metadata': {},
              'created_at': '2026-09-01T00:00:00Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.endsWith('/logout')) {
          return http.Response(
            jsonEncode({'message': 'network failure'}),
            logoutStatus,
            headers: {'content-type': 'application/json'},
          );
        }
        requests.add(request);
        if (request.url.path.contains('/rpc/')) await gate?.future;
        if (request.url.path.endsWith('/rpc/people_hr_self') &&
            status == 200 &&
            response is Map &&
            !(response as Map).containsKey('display_name')) {
          return http.Response(
            jsonEncode({
              ...scope(),
              'employee_id': employee,
              'display_name': 'Employee',
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response(
          jsonEncode(response),
          status,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'synthetic@example.test',
      password: 'synthetic',
    );
    gateway = SupabaseEmployeeGateway(client);
  });
  tearDown(() => client.dispose());

  test(
    'identity uses accepted self only and rejects scope substitution',
    () async {
      expect((await gateway.resolveIdentity(ws)).employeeId, employee);
      expect(requests.single.url.path, endsWith('/rpc/people_hr_self'));
      response = {
        ...scope(),
        'branch_id': employee,
        'employee_id': employee,
        'display_name': 'Other',
      };
      await expectLater(
        gateway.resolveIdentity(ws),
        throwsA(isA<EmployeeFailure>()),
      );
    },
  );

  test(
    'missing accepted link is explicit and provider text stays private',
    () async {
      status = 403;
      response = {
        'code': '42501',
        'message': 'HR_ACTIVE_LINK_REQUIRED',
        'details': 'secret sql',
      };
      await expectLater(
        gateway.resolveIdentity(ws),
        throwsA(
          isA<EmployeeFailure>().having(
            (e) => e.code,
            'code',
            'SELF_LINK_REQUIRED',
          ),
        ),
      );
      response = {
        'code': '42501',
        'message': 'sensitive internal text',
        'details': 'secret',
      };
      await expectLater(
        gateway.listLinks(ws),
        throwsA(
          isA<EmployeeFailure>().having(
            (e) => e.message,
            'safe message',
            isNot(contains('sensitive')),
          ),
        ),
      );
    },
  );

  test('reviews filter unpublished rows through real private HR adapter', () async {
    var n = 1;
    response = {
      ...scope(),
      'employee_id': employee,
      'next_cursor': null,
      'items': ['draft', 'submitted', 'reviewed', 'acknowledged', 'closed']
          .map(
            (state) => {
              'id':
                  '30000000-0000-0000-0000-${(n++).toString().padLeft(12, '0')}',
              'version': 1,
              'revision_id': record,
              'reviewer_id': actor,
              'status': state,
              'start_date': '2026-10-01',
              'end_date_exclusive': '2026-11-01',
              'body': {
                'objectives': ['Own shared objective'],
                'comments': null,
              },
              'recorded_by': actor,
              'recorded_at': '2026-10-01T00:00:00Z',
            },
          )
          .toList(),
    };
    final page = await gateway.listReviews(person);
    expect(page.items.map((e) => e.status), [
      'reviewed',
      'acknowledged',
      'closed',
    ]);
    expect(requests.last.url.path, endsWith('/rpc/people_hr_reviews'));
    final body = jsonDecode(requests.last.body) as Map;
    expect(body['p_employee_id'], employee);
    expect(requests.any((r) => r.url.path.contains('history')), isFalse);
  });

  test(
    'receipt must match original action employee target and version',
    () async {
      final pending = EmployeePendingCommand.create(
        workspace: ws,
        actorId: actor,
        employeeId: employee,
        action: 'review_acknowledge',
        targetId: record,
        expectedVersion: 1,
        now: DateTime.utc(2026, 10, 9),
      );
      final cmd = pending.envelope;
      response = {
        'request_id': cmd.commandId,
        'command_id': cmd.commandId,
        'correlation_id': cmd.commandId,
        'warnings': [],
        'entity': {
          ...scope(),
          'id': record,
          'employee_id': employee,
          'version': 2,
          'action': 'link_accept',
          'revision_id': null,
          'digest': null,
        },
      };
      await expectLater(
        gateway.hasReceipt(pending),
        throwsA(isA<EmployeeFailure>()),
      );
      (response as Map)['entity']['action'] = 'review_acknowledge';
      expect(await gateway.hasReceipt(pending), isTrue);
    },
  );

  test('network/provider failure is not an empty successful list', () async {
    status = 500;
    response = {'code': 'XX000', 'message': 'server internals'};
    await expectLater(gateway.listLinks(ws), throwsA(isA<EmployeeFailure>()));
  });

  test(
    'staff permissions cannot select another employee through mobile reviews',
    () async {
      const other = EmployeeIdentity(
        workspace: ws,
        actorId: actor,
        employeeId: record,
        displayName: 'Other',
      );
      await expectLater(
        gateway.listReviews(other),
        throwsA(isA<EmployeeFailure>()),
      );
      expect(
        requests.any((r) => r.url.path.endsWith('/rpc/people_hr_reviews')),
        isFalse,
      );
    },
  );

  test('account change invalidates delayed self response', () async {
    gate = Completer();
    final pending = gateway.resolveIdentity(ws);
    await Future<void>.delayed(Duration.zero);
    await client.auth.signOut(scope: SignOutScope.local);
    gate!.complete();
    await expectLater(pending, throwsA(isA<EmployeeFailure>()));
  });

  test('online getUser mismatch blocks accepted-self RPC', () async {
    serverActor = record;
    await expectLater(
      gateway.resolveIdentity(ws),
      throwsA(
        isA<EmployeeFailure>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
      ),
    );
    expect(requests, isEmpty);
  });

  test(
    'local sign-out removes actor even when remote revocation fails',
    () async {
      logoutStatus = 503;
      await expectLater(gateway.signOut(), throwsA(isA<EmployeeFailure>()));
      expect(gateway.actorId, isNull);
    },
  );
}

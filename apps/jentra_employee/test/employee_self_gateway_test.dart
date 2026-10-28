import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_employee/src/data/employee_gateway.dart';
import 'package:jentra_employee/src/data/employee_self_service.dart';
import 'package:jentra_employee/src/employee_self_service_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/employee_fixture.dart';
import 'support/employee_self_fixture.dart';

class _DelayedIdentityGateway extends FixtureGateway {
  final entered = Completer<void>();
  final result = Completer<EmployeeIdentity>();
  @override
  Future<EmployeeIdentity> resolveIdentity(EmployeeWorkspace workspace) {
    entered.complete();
    return result.future;
  }
}

void main() {
  late SupabaseClient client;
  late FixtureGateway identity;
  late SupabaseEmployeeSelfServiceGateway gateway;
  late List<http.Request> requests;
  var corruptBytes = false;
  var mfaRequired = false;
  setUp(() async {
    requests = [];
    corruptBytes = false;
    mfaRequired = false;
    final claims = base64Url.encode(
      utf8.encode(
        jsonEncode({
          'sub': fixtureActor,
          'exp': 4102444800,
          'role': 'authenticated',
        }),
      ),
    );
    client = SupabaseClient(
      'https://employee-self.example.test',
      'synthetic-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/token')) {
          return http.Response(
            jsonEncode({
              'access_token': 'e30.$claims.synthetic',
              'refresh_token': 'synthetic',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': fixtureActor,
                'aud': 'authenticated',
                'app_metadata': {},
                'user_metadata': {},
                'created_at': '2026-10-26T00:00:00Z',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (request.url.path.endsWith('/people-private-documents')) {
          return http.Response.bytes(
            corruptBytes ? [1, 2, 4] : [1, 2, 3],
            200,
            headers: {'content-type': 'application/octet-stream'},
            request: request,
          );
        }
        if (request.url.path.endsWith('/my_notifications')) {
          return http.Response(
            jsonEncode([
              {...selfEnvelope(), ...serviceRow(EmployeeService.inbox)},
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (mfaRequired) {
          return http.Response(
            jsonEncode({
              'code': '42501',
              'message': 'EMPLOYEE_MFA_REQUIRED',
              'details': null,
              'hint': null,
            }),
            403,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response(
          jsonEncode({...selfEnvelope(), 'items': [], 'next_cursor': null}),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'fixture@example.test',
      password: 'synthetic',
    );
    identity = FixtureGateway(withReview: false);
    gateway = SupabaseEmployeeSelfServiceGateway(
      client,
      identityGateway: identity,
    );
  });
  tearDown(() async {
    await client.dispose();
    await identity.close();
  });

  test('a private-state lock during authorization prevents delayed command dispatch', () async {
    await identity.close();
    final delayed = _DelayedIdentityGateway();
    identity = delayed;
    gateway = SupabaseEmployeeSelfServiceGateway(
      client,
      identityGateway: delayed,
    );
    EmployeeIdentity? current = selfIdentity;
    final controller = EmployeeSelfServiceController(
      gateway: gateway,
      store: FixtureStore(),
      currentIdentity: () => current,
    );
    addTearDown(controller.dispose);
    final sending = controller.submit('employee_case_command', {
      'p_action': 'create',
      'p_payload': {
        'id': selfRecordId,
        'category': 'general',
        'subject': 'Private subject',
        'body': 'Private body',
      },
    });
    await delayed.entered.future;
    current = null;
    controller.synchronize();
    delayed.result.complete(selfIdentity);
    expect(await sending, isFalse);
    expect(
      requests.any((request) => request.url.path.contains('/rpc/')),
      isFalse,
    );
  });

  for (final action in ['receipt', 'mark_read']) {
    test(
      'revoked local intent blocks $action after authorization await',
      () async {
        await identity.close();
        final delayed = _DelayedIdentityGateway();
        identity = delayed;
        gateway = SupabaseEmployeeSelfServiceGateway(
          client,
          identityGateway: delayed,
        );
        var active = true;
        final Future<void> sending = action == 'receipt'
            ? gateway
                  .receipt(
                    selfIdentity,
                    'employee_case_command',
                    selfCommandId,
                    selfRecordId,
                    stillAuthorized: () => active,
                  )
                  .then<void>((_) {})
            : gateway.markNoticeRead(
                selfIdentity,
                EmployeeServiceRecord(serviceRow(EmployeeService.inbox)),
                selfCommandId,
                stillAuthorized: () => active,
              );
        await delayed.entered.future;
        active = false;
        delayed.result.complete(selfIdentity);
        await expectLater(
          sending,
          throwsA(
            isA<EmployeeFailure>().having(
              (failure) => failure.code,
              'code',
              'SESSION_CHANGED',
            ),
          ),
        );
        expect(
          requests.any((request) => request.url.path.contains('/rpc/')),
          isFalse,
        );
      },
    );
  }

  test(
    'private download pins publication and verifies exact binary digest',
    () async {
      final row = EmployeeServiceRecord(serviceRow(EmployeeService.documents));
      final bytes = await gateway.document(selfIdentity, row);
      expect(bytes.bytes, [1, 2, 3]);
      final request = requests.last;
      final metadata = jsonDecode(
        utf8.decode(base64Decode(request.headers['x-jentra-hr-request']!)),
      ) as Map;
      expect(metadata['operation'], 'employee_download');
      expect(metadata['publication_version'], 3);
      expect(metadata['document_version'], 2);
      expect(metadata.containsKey('employee_id'), isFalse);
      corruptBytes = true;
      await expectLater(
        gateway.document(selfIdentity, row),
        throwsA(
          isA<EmployeeFailure>().having(
            (error) => error.code,
            'code',
            'INVALID_RESPONSE',
          ),
        ),
      );
    },
  );
  test(
    'recipient inbox request includes exact workplace and recipient filters',
    () async {
      final page = await gateway.page(selfIdentity, EmployeeService.inbox);
      expect(page.items.single.id, selfRecordId);
      final query = requests.last.url.queryParameters;
      expect(query['tenant_id'], 'eq.${fixtureWorkspace.tenantId}');
      expect(query['legal_entity_id'], 'eq.${fixtureWorkspace.legalEntityId}');
      expect(query['branch_id'], 'eq.${fixtureWorkspace.branchId}');
      expect(query['recipient_id'], 'eq.$fixtureActor');
      expect(query['notification_type'], 'like.people.%');
    },
  );
  test(
    'MFA-specific rejection survives as actionable fixed category',
    () async {
      mfaRequired = true;
      await expectLater(
        gateway.page(selfIdentity, EmployeeService.payslips),
        throwsA(
          isA<EmployeeFailure>().having(
            (error) => error.code,
            'code',
            'MFA_REQUIRED',
          ),
        ),
      );
    },
  );
  test(
    'client command cannot override the server-derived employee scope',
    () async {
      final before = requests.length;
      await expectLater(
        gateway.command(selfIdentity, 'employee_case_command', {
          'p_command_id': selfCommandId,
          'p_action': 'create',
          'p_payload': {'id': selfRecordId},
          'p_tenant_id': selfSecondId,
        }),
        throwsA(
          isA<EmployeeFailure>().having(
            (error) => error.code,
            'code',
            'INVALID_RESPONSE',
          ),
        ),
      );
      expect(requests.length, before);
    },
  );
}

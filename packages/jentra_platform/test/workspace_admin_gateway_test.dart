import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_workspace_admin.dart';
import 'package:jentra_platform/jentra_workspace_admin_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const tenant = '10000000-0000-0000-0000-000000000001';
const actor = '10000000-0000-0000-0000-000000000002';
const id = '10000000-0000-0000-0000-000000000003';
const scope = TenantContext(tenantId: tenant, actorId: actor);
CommandEnvelope<Map<String, Object?>> command() => CommandEnvelope(
  commandId: '10000000-0000-0000-0000-000000000004',
  idempotencyKey: '10000000-0000-0000-0000-000000000005',
  context: scope,
  payload: {'id': id, 'name': 'Renamed'},
  expectedEntityVersion: 1,
);
void main() {
  test('CA-10 actor mismatch refuses before transport', () async {
    var calls = 0;
    final g = SupabaseWorkspaceAdminGateway.withRpc((_, _) async {
      calls++;
      return null;
    }, currentActor: () => id);
    await expectLater(
      g.list(scope, WorkspaceAdminResource.entities),
      throwsA(isA<DomainError>()),
    );
    expect(calls, 0);
  });
  test(
    'CA-10 actor changed during transport rejects a late private page',
    () async {
      var current = actor;
      final response = Completer<Object?>();
      final g = SupabaseWorkspaceAdminGateway.withRpc(
        (_, _) => response.future,
        currentActor: () => current,
      );
      final future = g.list(scope, WorkspaceAdminResource.entities);
      current = id;
      response.complete({
        'tenant_id': tenant,
        'resource': 'entities',
        'items': [],
        'next_cursor': null,
      });
      await expectLater(future, throwsA(isA<DomainError>()));
    },
  );
  test('CA-N1 list transports only named API and bounded context', () async {
    final calls = <String>[];
    final g = SupabaseWorkspaceAdminGateway.withRpc((name, p) async {
      calls.add(name);
      expect(p, {
        'p_tenant_id': tenant,
        'p_resource': 'entities',
        'p_after': null,
        'p_limit': 50,
      });
      return {
        'tenant_id': tenant,
        'resource': 'entities',
        'items': [],
        'next_cursor': null,
      };
    }, currentActor: () => actor);
    expect(
      (await g.list(scope, WorkspaceAdminResource.entities)).items,
      isEmpty,
    );
    expect(calls, ['workspace_admin_list']);
    await expectLater(
      g.list(scope, WorkspaceAdminResource.entities, limit: 201),
      throwsFormatException,
    );
    expect(calls.length, 1);
  });
  test(
    'CA-08 sends stable command envelope and verifies exact confirmation',
    () async {
      final c = command();
      final g = SupabaseWorkspaceAdminGateway.withRpc((name, p) async {
        expect(name, 'workspace_admin_command');
        expect(p['p_idempotency_key'], c.idempotencyKey);
        expect(p['p_command_id'], c.commandId);
        expect(p.containsKey('p_actor_id'), isFalse);
        expect(p['p_expected_version'], 1);
        return {
          'request_id': c.commandId,
          'warnings': [],
          'entity': {
            'id': id,
            'tenant_id': tenant,
            'action': 'update_branch',
            'version': 2,
            'name': 'Renamed',
          },
        };
      }, currentActor: () => actor);
      expect(
        (await g.command(WorkspaceAdminAction.updateBranch, c))['request_id'],
        c.commandId,
      );
    },
  );
  test('CA-08 mismatched success stays uncertain', () async {
    final g = SupabaseWorkspaceAdminGateway.withRpc(
      (_, _) async => {'request_id': id, 'entity': {}, 'warnings': []},
      currentActor: () => actor,
    );
    await expectLater(
      g.command(WorkspaceAdminAction.updateBranch, command()),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
      ),
    );
  });
  test('CA-E8 backend absence and SQL denials use safe messages', () async {
    for (final code in [
      '42501',
      'PGRST202',
      '40001',
      '23505',
      '22023',
      '23514',
    ]) {
      final g = SupabaseWorkspaceAdminGateway.withRpc(
        (_, _) async => throw PostgrestException(
          message: 'PRIVATE_DATABASE_VALUE',
          code: code,
        ),
        currentActor: () => actor,
      );
      await expectLater(
        g.command(WorkspaceAdminAction.updateBranch, command()),
        throwsA(
          isA<DomainError>().having(
            (e) => e.message,
            'safe message',
            isNot(contains('PRIVATE_DATABASE_VALUE')),
          ),
        ),
      );
    }
  });
  test(
    'CA-08 known business refusals are definite rejections, not uncertain access loss',
    () async {
      for (final message in [
        'ADMIN_MEMBERSHIP_RESTORE_REQUIRED',
        'ADMIN_ROLE_NOT_DELEGABLE',
        'ADMIN_PROTECTED_MEMBERSHIP',
        'ADMIN_PROTECTED_ROLE',
      ]) {
        final g = SupabaseWorkspaceAdminGateway.withRpc(
          (_, _) async =>
              throw PostgrestException(message: message, code: '42501'),
          currentActor: () => actor,
        );
        await expectLater(
          g.command(WorkspaceAdminAction.updateBranch, command()),
          throwsA(
            isA<DomainError>().having(
              (e) => e.code,
              'code',
              'VALIDATION_ERROR',
            ),
          ),
        );
      }
    },
  );
  test('CA-E7 invitation secret projection is refused', () async {
    final g = SupabaseWorkspaceAdminGateway.withRpc(
      (_, _) async => {
        'items': [
          {
            'id': id,
            'tenant_id': tenant,
            'tenant_name': 'Pilot Group',
            'role_name': 'Reader',
            'token': 'secret',
          },
        ],
        'next_cursor': null,
      },
      currentActor: () => actor,
    );
    await expectLater(g.myInvitations(), throwsFormatException);
  });
  test('CA-07 acceptance binds the invitation and current actor', () async {
    var wrong = false;
    final g = SupabaseWorkspaceAdminGateway.withRpc((name, p) async {
      expect(name, 'workspace_accept_invitation');
      return {
        'entity': {
          'id': id,
          'tenant_id': tenant,
          'invitation_id': id,
          'user_id': wrong ? tenant : actor,
          'status': 'active',
          'action': 'accept_invitation',
        },
      };
    }, currentActor: () => actor);
    await g.acceptInvitation(id, tenant);
    wrong = true;
    await expectLater(
      g.acceptInvitation(id, tenant),
      throwsA(isA<DomainError>()),
    );
  });
}

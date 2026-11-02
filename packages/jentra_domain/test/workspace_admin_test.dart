import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_workspace_admin.dart';
import 'package:test/test.dart';

const tenant = '10000000-0000-0000-0000-000000000001';
const actor = '10000000-0000-0000-0000-000000000002';
const id = '10000000-0000-0000-0000-000000000003';
const scope = TenantContext(tenantId: tenant, actorId: actor);
CommandEnvelope<Map<String, Object?>> command(
  Map<String, Object?> p, {
  int? version,
}) => CommandEnvelope(
  commandId: '10000000-0000-0000-0000-000000000004',
  idempotencyKey: '10000000-0000-0000-0000-000000000005',
  context: scope,
  payload: p,
  expectedEntityVersion: version,
);
Map<String, Object?> page(List<Object?> rows, {Object? cursor}) => {
  'tenant_id': tenant,
  'resource': 'entities',
  'items': rows,
  'next_cursor': cursor,
};
Map<String, Object?> row() => {
  'id': id,
  'tenant_id': tenant,
  'version': 1,
  'name': 'Pilot company',
};
void main() {
  test('CA-A1 page rejects a different tenant', () {
    expect(
      () => WorkspaceAdminPage.parse(
        {
          ...page([row()]),
          'tenant_id': actor,
        },
        scope,
        WorkspaceAdminResource.entities,
      ),
      throwsFormatException,
    );
  });
  test('CA-A1 page rejects foreign rows and malformed names', () {
    for (final r in [
      {...row(), 'tenant_id': actor},
      {...row(), 'name': 42},
    ]) {
      expect(
        () => WorkspaceAdminPage.parse(
          page([r]),
          scope,
          WorkspaceAdminResource.entities,
        ),
        throwsFormatException,
      );
    }
  });
  test('CA-N1 page rejects duplicate order and invalid cursors', () {
    expect(
      () => WorkspaceAdminPage.parse(
        page([row(), row()]),
        scope,
        WorkspaceAdminResource.entities,
      ),
      throwsFormatException,
    );
    expect(
      () => WorkspaceAdminPage.parse(
        page([row()], cursor: id),
        scope,
        WorkspaceAdminResource.entities,
      ),
      throwsFormatException,
    );
  });
  test('CA-E7 secrets are rejected and snapshots are immutable', () {
    expect(
      () => WorkspaceAdminPage.parse(
        page([
          {...row(), 'token': 'private'},
        ]),
        scope,
        WorkspaceAdminResource.entities,
      ),
      throwsFormatException,
    );
    final data = row(),
        parsed = WorkspaceAdminPage.parse(
          page([data]),
          scope,
          WorkspaceAdminResource.entities,
        );
    data['name'] = 'changed';
    parsed.items.first.data['name'] = 'changed again';
    expect(parsed.items.first.name, 'Pilot company');
  });
  test('CA-08 rejects unexpected command fields and missing versions', () {
    expect(
      () => validateWorkspaceAdminCommand(
        WorkspaceAdminAction.updateBranch,
        command({'id': id, 'name': 'Branch'}),
      ),
      throwsFormatException,
    );
    expect(
      () => validateWorkspaceAdminCommand(
        WorkspaceAdminAction.updateBranch,
        command({'id': id, 'name': 'Branch', 'role': 'owner'}, version: 1),
      ),
      throwsFormatException,
    );
  });
  test('CA-02 branch and assignment scope are explicit', () {
    expect(
      () => validateWorkspaceAdminCommand(
        WorkspaceAdminAction.createBranch,
        command({'name': 'Branch', 'code': 'HQ', 'timezone': 'UTC'}),
      ),
      throwsFormatException,
    );
    expect(
      () => validateWorkspaceAdminCommand(
        WorkspaceAdminAction.setAssignment,
        command({
          'id': id,
          'role_id': actor,
          'branch_id': tenant,
          'granted': true,
        }, version: 1),
      ),
      throwsFormatException,
    );
  });
  test('CA-04 role permissions and MFA decision are typed', () {
    for (final permissions in [
      <String>[],
      ['sales.view', 'sales.view'],
      ['bad permission'],
    ]) {
      expect(
        () => validateWorkspaceAdminCommand(
          WorkspaceAdminAction.createRole,
          command({
            'name': 'Role',
            'code': 'reader',
            'permissions': permissions,
            'requires_mfa': true,
          }),
        ),
        throwsFormatException,
      );
    }
  });
  test('CA-N1 rejects control characters and oversized payloads', () {
    expect(
      () => validateWorkspaceAdminCommand(
        WorkspaceAdminAction.updateBranch,
        command({'id': id, 'name': 'Branch\nsecret'}, version: 1),
      ),
      throwsFormatException,
    );
    expect(
      () => validateWorkspaceAdminCommand(
        WorkspaceAdminAction.updateBranch,
        command({'id': id, 'name': 'x' * 17000}, version: 1),
      ),
      throwsFormatException,
    );
  });
  test(
    'CA-08 receipt binds request action scope identity fields and version',
    () {
      final c = command({'id': id, 'name': 'Renamed'}, version: 1);
      final result = {
        'request_id': c.commandId,
        'warnings': <Object?>[],
        'entity': {
          'id': id,
          'tenant_id': tenant,
          'version': 2,
          'name': 'Renamed',
          'action': 'update_branch',
        },
      };
      expect(
        workspaceAdminReceiptConfirms(
          result,
          WorkspaceAdminAction.updateBranch,
          c,
        ),
        isTrue,
      );
      for (final e in [
        {...result['entity']! as Map, 'tenant_id': actor},
        {...result['entity']! as Map, 'version': 1},
        {...result['entity']! as Map, 'action': 'create_branch'},
        {...result['entity']! as Map, 'name': 'Different'},
      ]) {
        expect(
          workspaceAdminReceiptConfirms(
            {...result, 'entity': e},
            WorkspaceAdminAction.updateBranch,
            c,
          ),
          isFalse,
        );
      }
      expect(
        workspaceAdminReceiptConfirms(
          {...result, 'request_id': id},
          WorkspaceAdminAction.updateBranch,
          c,
        ),
        isFalse,
      );
    },
  );
  test('CA-05 assignment confirmation binds the complete exact change', () {
    final p = {
      'id': id,
      'role_id': actor,
      'legal_entity_id': tenant,
      'branch_id': null,
      'granted': false,
    };
    final c = command(p, version: 3),
        e = {
          'id': id,
          'tenant_id': tenant,
          'version': 4,
          'action': 'set_assignment',
          'change': p,
        };
    expect(
      workspaceAdminReceiptConfirms(
        {'request_id': c.commandId, 'warnings': [], 'entity': e},
        WorkspaceAdminAction.setAssignment,
        c,
      ),
      isTrue,
    );
    expect(
      workspaceAdminReceiptConfirms(
        {
          'request_id': c.commandId,
          'warnings': [],
          'entity': {
            ...e,
            'change': {...p, 'granted': true},
          },
        },
        WorkspaceAdminAction.setAssignment,
        c,
      ),
      isFalse,
    );
  });
}

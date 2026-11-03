import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_workspace_admin.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef WorkspaceAdminRpc =
    Future<Object?> Function(String name, Map<String, Object?> parameters);

final class SupabaseWorkspaceAdminGateway implements WorkspaceAdminRepository {
  SupabaseWorkspaceAdminGateway(SupabaseClient client)
    : this.withRpc(
        (name, p) async => client.schema('api').rpc(name, params: p),
        currentActor: () => client.auth.currentUser?.id,
      );
  SupabaseWorkspaceAdminGateway.withRpc(
    this._rpc, {
    required String? Function() currentActor,
  }) : _actor = currentActor;
  final WorkspaceAdminRpc _rpc;
  final String? Function() _actor;

  Future<Object?> _call(
    String name,
    Map<String, Object?> p,
    String actor,
  ) async {
    if (_actor() != actor) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Sign in again before administering this company.',
      );
    }
    try {
      final r = await _rpc(name, p);
      if (_actor() != actor) {
        throw const DomainError(
          code: 'PERMISSION_DENIED',
          message: 'Your account changed. Reload this workspace.',
        );
      }
      return r;
    } on PostgrestException catch (e) {
      const rejectedChanges = {
        'ADMIN_MEMBERSHIP_RESTORE_REQUIRED':
            'Restore this existing membership in Staff before creating or accepting another invitation.',
        'ADMIN_ROLE_NOT_DELEGABLE':
            'Choose a role and scope within your current authority. Owner roles require a separate transfer workflow.',
        'ADMIN_PERMISSION_NOT_DELEGABLE':
            'The custom role includes a permission you cannot delegate.',
        'ADMIN_PRIVILEGED_ROLE_REQUIRES_MFA':
            'A role with privileged permissions must require MFA.',
        'ADMIN_PROTECTED_ROLE':
            'System roles and roles assigned to your own account are protected.',
        'ADMIN_PROTECTED_MEMBERSHIP':
            'Owner memberships and your own access are protected from this change.',
        'ADMIN_SUBSCRIPTION_UNAVAILABLE':
            'The company subscription needs administrator review before this change.',
      };
      if (e.code == '42501' && rejectedChanges.containsKey(e.message)) {
        throw DomainError(
          code: 'VALIDATION_ERROR',
          message: rejectedChanges[e.message]!,
        );
      }
      throw switch (e.code) {
        '42501' => DomainError(
          code: 'PERMISSION_DENIED',
          message: e.message == 'ADMIN_RECENT_MFA_REQUIRED'
              ? 'Verify your sign-in with your authenticator before administering company access.'
              : 'Your current account or scope cannot perform this administration action.',
        ),
        '40001' => const DomainError(
          code: 'VERSION_CONFLICT',
          message:
              'This record changed. Reload it and review the current version.',
        ),
        '23505' => const DomainError(
          code: 'CONFLICT',
          message: 'This code or pending invitation already exists.',
        ),
        '23514' => const DomainError(
          code: 'VALIDATION_ERROR',
          message: 'The company, seat or record limit would be exceeded.',
        ),
        '22023' || '22P02' => const DomainError(
          code: 'VALIDATION_ERROR',
          message:
              'Review the fields and use the original request for a retry.',
        ),
        'P0002' => const DomainError(
          code: 'NOT_FOUND',
          message:
              'This record is no longer available in the selected company group.',
        ),
        '42883' || 'PGRST202' => const DomainError(
          code: 'PROVIDER_UNAVAILABLE',
          message:
              'Company administration is not enabled in this backend release.',
        ),
        _ => const DomainError(
          code: 'UNCERTAIN_RESULT',
          message:
              'The result was not confirmed. Keep and retry the saved request.',
        ),
      };
    }
  }

  @override
  Future<WorkspaceAdminPage> list(
    TenantContext s,
    WorkspaceAdminResource resource, {
    String? after,
    int limit = 50,
  }) async {
    workspaceAdminId(s.actorId);
    workspaceAdminId(s.tenantId);
    if (limit < 1 || limit > 200 || after != null && after.length > 100) {
      throw const FormatException('Invalid administration page.');
    }
    final r = await _call('workspace_admin_list', {
      'p_tenant_id': s.tenantId,
      'p_resource': resource.name,
      'p_after': after,
      'p_limit': limit,
    }, s.actorId);
    return WorkspaceAdminPage.parse(r, s, resource, after: after, limit: limit);
  }

  @override
  Future<Map<String, Object?>> command(
    WorkspaceAdminAction action,
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    validateWorkspaceAdminCommand(action, c);
    final r = await _call('workspace_admin_command', {
      'p_tenant_id': c.context.tenantId,
      'p_command_id': c.commandId,
      'p_idempotency_key': c.idempotencyKey,
      'p_client_timestamp': c.clientTimestamp.toIso8601String(),
      'p_action': action.wire,
      'p_payload': c.payload,
      'p_expected_version': c.expectedEntityVersion,
    }, c.context.actorId);
    if (!workspaceAdminReceiptConfirms(r, action, c)) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'The confirmation differs from the saved request. Retry the original request.',
      );
    }
    return (r as Map).cast<String, Object?>();
  }

  @override
  Future<Map<String, Object?>> myInvitations({String? after}) async {
    final actor = _actor();
    workspaceAdminId(actor);
    if (after != null) workspaceAdminId(after);
    final r = await _call('workspace_my_invitations', {
      'p_after': after,
    }, actor!);
    if (r is! Map || r['items'] is! List || (r['items'] as List).length > 50) {
      throw const FormatException('Invalid invitation page.');
    }
    String? previous = after;
    for (final row in r['items'] as List) {
      if (row is! Map) throw const FormatException('Invalid invitation.');
      workspaceAdminId(row['id']);
      workspaceAdminId(row['tenant_id']);
      for (final key in ['tenant_name', 'role_name']) {
        if (row[key] is! String ||
            (row[key] as String).isEmpty ||
            (row[key] as String).length > 180) {
          throw const FormatException('Invalid invitation label.');
        }
      }
      for (final key in ['legal_entity_name', 'branch_name']) {
        if (row[key] != null &&
            (row[key] is! String || (row[key] as String).length > 180)) {
          throw const FormatException('Invalid invitation scope label.');
        }
      }
      final id = row['id'] as String;
      if (previous != null && id.compareTo(previous) <= 0 ||
          row.containsKey('token') ||
          row.containsKey('token_hash')) {
        throw const FormatException('Invalid invitation scope/order.');
      }
      previous = id;
    }
    if (r['next_cursor'] != null &&
        ((r['items'] as List).length != 50 || r['next_cursor'] != previous)) {
      throw const FormatException('Invalid invitation cursor.');
    }
    return r.cast<String, Object?>();
  }

  @override
  Future<Map<String, Object?>> acceptInvitation(
    String invitationId,
    String idempotencyKey,
  ) async {
    final actor = _actor();
    workspaceAdminId(actor);
    workspaceAdminId(invitationId);
    workspaceAdminId(idempotencyKey);
    final r = await _call('workspace_accept_invitation', {
      'p_invitation_id': invitationId,
      'p_idempotency_key': idempotencyKey,
    }, actor!);
    if (r is! Map || r['entity'] is! Map) {
      throw const FormatException('Invalid acceptance confirmation.');
    }
    final e = r['entity'] as Map;
    if (e['invitation_id'] != invitationId ||
        e['user_id'] != actor ||
        e['status'] != 'active' ||
        e['action'] != 'accept_invitation') {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Acceptance was not confirmed. Retry this invitation.',
      );
    }
    workspaceAdminId(e['tenant_id']);
    workspaceAdminId(e['id']);
    return r.cast<String, Object?>();
  }
}

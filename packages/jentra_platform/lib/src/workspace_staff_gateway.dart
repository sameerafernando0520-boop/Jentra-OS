import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Credentials are sent directly to the server function. They must never enter
/// the administration command receipts or encrypted draft/recovery stores.
abstract interface class WorkspaceStaffGateway {
  Future<void> create({
    required TenantContext scope,
    required String requestId,
    required String username,
    required String displayName,
    required Set<String> roleIds,
    required String password,
  });
}

final class SupabaseWorkspaceStaffGateway implements WorkspaceStaffGateway {
  SupabaseWorkspaceStaffGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<void> create({
    required TenantContext scope,
    required String requestId,
    required String username,
    required String displayName,
    required Set<String> roleIds,
    required String password,
  }) async {
    void requireActor() {
      if (_client.auth.currentUser?.id != scope.actorId) {
        throw const DomainError(
          code: 'PERMISSION_DENIED',
          message: 'Your account changed. Reopen staff administration.',
        );
      }
    }

    requireActor();
    try {
      final response = await _client.functions.invoke(
        'workspace-staff',
        body: {
          'operation': 'create',
          'tenant_id': scope.tenantId,
          'request_id': requestId,
          'username': username.trim().toLowerCase(),
          'display_name': displayName.trim(),
          'role_ids': roleIds.toList()..sort(),
          'password': password,
        },
      );
      requireActor();
      final data = response.data;
      if (response.status != 200 ||
          data is! Map ||
          data['request_id'] != requestId ||
          data['tenant_id'] != scope.tenantId ||
          data['username'] != username.trim().toLowerCase() ||
          data['status'] != 'active' ||
          data['membership_id'] is! String ||
          data['user_id'] is! String) {
        throw const DomainError(
          code: 'UNCERTAIN_RESULT',
          message:
              'Creation is not confirmed. Retry with the original details.',
        );
      }
    } on FunctionException catch (error) {
      final code = error.details is Map ? (error.details as Map)['code'] : null;
      throw DomainError(
        code: switch (code) {
          'STAFF_ACCESS_CHANGED' => 'ACCESS_CHANGED',
          'USERNAME_UNAVAILABLE' => 'CONFLICT',
          'STAFF_ACCESS_DENIED' ||
          'AUTHENTICATION_REQUIRED' => 'PERMISSION_DENIED',
          'PASSWORD_TOO_WEAK' => 'PASSWORD_TOO_WEAK',
          'STAFF_ORIGINAL_PASSWORD_REQUIRED' => 'PASSWORD_REQUIRED',
          'STAFF_LIMIT_REACHED' => 'CAPACITY_ERROR',
          'INVALID_STAFF_ACCOUNT' => 'VALIDATION_ERROR',
          _ => 'UNCERTAIN_RESULT',
        },
        message: switch (code) {
          'STAFF_ACCESS_CHANGED' =>
            'This account already exists and its access has changed. Review it in Staff or start a different account.',
          'USERNAME_UNAVAILABLE' =>
            'This username is unavailable. Choose another.',
          'STAFF_ACCESS_DENIED' || 'AUTHENTICATION_REQUIRED' =>
            'Current administrator access and authenticator verification are required.',
          'STAFF_LIMIT_REACHED' => 'Your staff seat limit has been reached.',
          'STAFF_ORIGINAL_PASSWORD_REQUIRED' =>
            'Enter the original password for this saved staff account. Retrying does not change its password.',
          'INVALID_STAFF_ACCOUNT' || 'PASSWORD_TOO_WEAK' =>
            'Review the staff details, selected roles and password.',
          _ => 'Creation is not confirmed. Retry with the original details.',
        },
      );
    }
  }
}

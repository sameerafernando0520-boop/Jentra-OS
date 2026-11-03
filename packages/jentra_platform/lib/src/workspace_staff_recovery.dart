import 'dart:convert';

import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_workspace_admin.dart';

import 'draft_repository.dart';

/// Request recovery deliberately excludes passwords and authenticator material.
final class StaffAccountRequest {
  StaffAccountRequest({
    required this.requestId,
    required this.username,
    required this.displayName,
    required Set<String> roleIds,
  }) : roleIds = Set.unmodifiable(roleIds) {
    workspaceAdminId(requestId);
    for (final id in roleIds) {
      workspaceAdminId(id);
    }
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{2,39}$').hasMatch(username) ||
        displayName.trim().isEmpty ||
        displayName.length > 100 ||
        roleIds.isEmpty ||
        roleIds.length > 16) {
      throw const FormatException('Invalid saved staff request.');
    }
  }
  final String requestId, username, displayName;
  final Set<String> roleIds;
  Map<String, Object?> toJson() => {
    'request_id': requestId,
    'username': username,
    'display_name': displayName,
    'role_ids': roleIds.toList()..sort(),
  };
  factory StaffAccountRequest.fromJson(Map<String, Object?> value) =>
      StaffAccountRequest(
        requestId: value['request_id']! as String,
        username: value['username']! as String,
        displayName: value['display_name']! as String,
        roleIds: (value['role_ids']! as List).cast<String>().toSet(),
      );
}

abstract interface class StaffAccountRecovery {
  Future<StaffAccountRequest?> load(TenantContext scope);
  Future<void> save(TenantContext scope, StaffAccountRequest request);
  Future<void> complete(TenantContext scope, String requestId);
}

final class EncryptedStaffAccountRecovery implements StaffAccountRecovery {
  EncryptedStaffAccountRecovery(this.repository);
  final EncryptedDraftRepository repository;
  String _key(TenantContext scope) =>
      'workspace-staff:${base64Url.encode(utf8.encode(jsonEncode(scope.toJson())))}';

  @override
  Future<StaffAccountRequest?> load(TenantContext scope) async {
    final row = await repository.find(_key(scope));
    if (row == null) return null;
    if (row.tenantId != scope.tenantId ||
        row.entityType != 'workspace.staff.request' ||
        TenantContext.fromJson(
              (row.payload['scope']! as Map).cast<String, Object?>(),
            ) !=
            scope) {
      throw const FormatException(
        'Staff recovery belongs to another account or scope.',
      );
    }
    return StaffAccountRequest.fromJson(
      (row.payload['request']! as Map).cast<String, Object?>(),
    );
  }

  @override
  Future<void> save(
    TenantContext scope,
    StaffAccountRequest request,
  ) => repository.transaction(() async {
    final old = await load(scope);
    if (old != null) {
      if (workspaceAdminCanonical(old.toJson()) !=
          workspaceAdminCanonical(request.toJson())) {
        throw const DomainError(
          code: 'COMMAND_PENDING',
          message:
              'Finish the saved staff request before creating another account.',
        );
      }
      return;
    }
    await repository.save(
      id: _key(scope),
      tenantId: scope.tenantId,
      entityType: 'workspace.staff.request',
      payload: {'scope': scope.toJson(), 'request': request.toJson()},
      localVersion: 1,
    );
  });
  @override
  Future<void> complete(TenantContext scope, String requestId) =>
      repository.transaction(() async {
        final old = await load(scope);
        if (old == null) return;
        if (old.requestId != requestId) {
          throw const FormatException('Staff recovery identity differs.');
        }
        await repository.delete(_key(scope));
      });
}

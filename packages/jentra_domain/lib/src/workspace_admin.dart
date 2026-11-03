import 'dart:convert';

import 'commands.dart';
import 'tenant_context.dart';

enum WorkspaceAdminResource {
  entities('Companies', 'core.tenant.manage'),
  branches('Branches', 'core.tenant.manage'),
  members('Staff', 'core.roles.manage'),
  roles('Roles', 'core.roles.manage'),
  invitations('Invitations', 'core.members.invite'),
  permissions('Permissions', 'core.roles.manage');

  const WorkspaceAdminResource(this.label, this.permission);
  final String label, permission;
}

enum WorkspaceAdminAction {
  createEntity('create_entity', WorkspaceAdminResource.entities, true),
  updateEntity('update_entity', WorkspaceAdminResource.entities, false),
  createBranch('create_branch', WorkspaceAdminResource.branches, true),
  updateBranch('update_branch', WorkspaceAdminResource.branches, false),
  createRole('create_role', WorkspaceAdminResource.roles, true),
  updateRole('update_role', WorkspaceAdminResource.roles, false),
  setAssignment('set_assignment', WorkspaceAdminResource.members, false),
  setMemberStatus('set_member_status', WorkspaceAdminResource.members, false),
  createInvitation(
    'create_invitation',
    WorkspaceAdminResource.invitations,
    true,
  ),
  revokeInvitation(
    'revoke_invitation',
    WorkspaceAdminResource.invitations,
    false,
  );

  const WorkspaceAdminAction(this.wire, this.resource, this.creates);
  final String wire;
  final WorkspaceAdminResource resource;
  final bool creates;
}

final _id = RegExp(
  r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
);
final _permission = RegExp(r'^[a-z][a-z0-9_.-]{2,99}$');
void workspaceAdminId(Object? value) {
  if (value is! String || !_id.hasMatch(value)) {
    throw const FormatException('A valid record identity is required.');
  }
}

Object? _sorted(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _sorted(value[key])};
  }
  if (value is List) return value.map(_sorted).toList();
  return value;
}

String workspaceAdminCanonical(Object? value) => jsonEncode(_sorted(value));

/// Immutable snapshot; callers cannot change a confirmed row or sealed request.
final class WorkspaceAdminRecord {
  WorkspaceAdminRecord(Map<String, Object?> value) : _json = jsonEncode(value);
  final String _json;
  Map<String, Object?> get data =>
      (jsonDecode(_json) as Map).cast<String, Object?>();
  String get id => data['id']! as String;
  String get name =>
      (data['name'] ?? data['email'] ?? data['code'] ?? id) as String;
  int get version => data['version'] as int? ?? 0;
  bool get protected => data['owner'] == true || data['is_system'] == true;
}

final class WorkspaceAdminPage {
  WorkspaceAdminPage({
    required List<WorkspaceAdminRecord> items,
    this.nextCursor,
  }) : items = List.unmodifiable(items);
  final List<WorkspaceAdminRecord> items;
  final String? nextCursor;

  factory WorkspaceAdminPage.parse(
    Object? value,
    TenantContext scope,
    WorkspaceAdminResource resource, {
    String? after,
    int limit = 50,
  }) {
    if (value is! Map ||
        value['tenant_id'] != scope.tenantId ||
        value['resource'] != resource.name ||
        value['items'] is! List ||
        (value['items'] as List).length > limit) {
      throw const FormatException(
        'The administration page could not be verified.',
      );
    }
    final records = <WorkspaceAdminRecord>[];
    String? previous = after;
    for (final item in value['items'] as List) {
      if (item is! Map || item['id'] is! String) {
        throw const FormatException('Invalid administration record.');
      }
      final row = item.cast<String, Object?>(), id = row['id']! as String;
      for (final key in [
        'name',
        'email',
        'code',
        'status',
        'timezone',
        'currency_code',
      ]) {
        if (row[key] != null &&
            (row[key] is! String || (row[key]! as String).length > 1000)) {
          throw const FormatException('Invalid administration display value.');
        }
      }
      for (final key in [
        'user_id',
        'role_id',
        'legal_entity_id',
        'branch_id',
      ]) {
        if (row[key] != null) workspaceAdminId(row[key]);
      }
      if (resource == WorkspaceAdminResource.permissions) {
        if (!_permission.hasMatch(id)) {
          throw const FormatException('Invalid permission.');
        }
      } else {
        workspaceAdminId(id);
        if (row['tenant_id'] != scope.tenantId ||
            row['version'] is! int ||
            (row['version']! as int) < 1) {
          throw const FormatException('Record scope or version differs.');
        }
      }
      if (previous != null && id.compareTo(previous) <= 0 ||
          row.containsKey('token') ||
          row.containsKey('token_hash')) {
        throw const FormatException(
          'Invalid administration page order or fields.',
        );
      }
      previous = id;
      records.add(WorkspaceAdminRecord(row));
    }
    final cursor = value['next_cursor'];
    if (cursor != null &&
        (cursor is! String ||
            records.length != limit ||
            cursor != records.last.id)) {
      throw const FormatException('Invalid administration cursor.');
    }
    return WorkspaceAdminPage(items: records, nextCursor: cursor as String?);
  }
}

void validateWorkspaceAdminCommand(
  WorkspaceAdminAction action,
  CommandEnvelope<Map<String, Object?>> command,
) {
  workspaceAdminId(command.context.tenantId);
  workspaceAdminId(command.context.actorId);
  workspaceAdminId(command.commandId);
  workspaceAdminId(command.idempotencyKey);
  final p = command.payload;
  if (utf8.encode(jsonEncode(p)).length > 16384 ||
      (action.creates
          ? command.expectedEntityVersion != null
          : command.expectedEntityVersion == null ||
                command.expectedEntityVersion! < 1)) {
    throw const FormatException(
      'Use a bounded, versioned administration request.',
    );
  }
  final allowed = switch (action) {
    WorkspaceAdminAction.createEntity => {
      'name',
      'code',
      'currency_code',
      'timezone',
      'registration_number',
      'tax_identifier',
    },
    WorkspaceAdminAction.updateEntity => {
      'id',
      'name',
      'registration_number',
      'tax_identifier',
    },
    WorkspaceAdminAction.createBranch => {
      'name',
      'code',
      'legal_entity_id',
      'timezone',
    },
    WorkspaceAdminAction.updateBranch => {'id', 'name'},
    WorkspaceAdminAction.createRole => {
      'name',
      'code',
      'permissions',
      'requires_mfa',
    },
    WorkspaceAdminAction.updateRole => {
      'id',
      'name',
      'permissions',
      'requires_mfa',
    },
    WorkspaceAdminAction.setAssignment => {
      'id',
      'role_id',
      'legal_entity_id',
      'branch_id',
      'granted',
    },
    WorkspaceAdminAction.setMemberStatus => {'id', 'status'},
    WorkspaceAdminAction.createInvitation => {
      'email',
      'role_id',
      'legal_entity_id',
      'branch_id',
    },
    WorkspaceAdminAction.revokeInvitation => {'id'},
  };
  if (!allowed.containsAll(p.keys)) {
    throw const FormatException('Unexpected request field.');
  }
  final optional = {
    'registration_number',
    'tax_identifier',
    'legal_entity_id',
    'branch_id',
  };
  for (final key in allowed.difference(optional)) {
    if (!p.containsKey(key)) {
      throw FormatException('Complete $key before submitting.');
    }
  }
  if (action == WorkspaceAdminAction.createBranch &&
      p['legal_entity_id'] == null) {
    throw const FormatException('Select the branch company.');
  }
  for (final key in ['id', 'role_id', 'legal_entity_id', 'branch_id']) {
    if (p[key] != null) workspaceAdminId(p[key]);
  }
  if (p['branch_id'] != null && p['legal_entity_id'] == null) {
    throw const FormatException('A branch must belong to a company.');
  }
  for (final key in [
    'name',
    'code',
    'currency_code',
    'timezone',
    'email',
    'status',
    'registration_number',
    'tax_identifier',
  ]) {
    final v = p[key];
    if (v == null && optional.contains(key)) continue;
    if (!allowed.contains(key)) continue;
    if (v is! String ||
        v != v.trim() ||
        v.isEmpty && !optional.contains(key) ||
        v.runes.length >
            (key == 'email'
                ? 254
                : key == 'name'
                ? 180
                : 100) ||
        RegExp(r'[\u0000-\u001f\u007f-\u009f\u2028\u2029]').hasMatch(v)) {
      throw FormatException('Enter a valid $key.');
    }
  }
  if (allowed.contains('requires_mfa') && p['requires_mfa'] is! bool ||
      allowed.contains('granted') && p['granted'] is! bool) {
    throw const FormatException('An explicit access decision is required.');
  }
  if (allowed.contains('permissions')) {
    final permissions = p['permissions'];
    if (permissions is! List ||
        permissions.isEmpty ||
        permissions.length > 200 ||
        permissions.any((v) => v is! String || !_permission.hasMatch(v)) ||
        permissions.toSet().length != permissions.length) {
      throw const FormatException(
        'Select distinct permissions for the custom role.',
      );
    }
  }
}

bool workspaceAdminReceiptConfirms(
  Object? response,
  WorkspaceAdminAction action,
  CommandEnvelope<Map<String, Object?>> command,
) {
  if (response is! Map ||
      response['warnings'] is! List ||
      response['request_id'] != command.commandId ||
      response['entity'] is! Map) {
    return false;
  }
  final e = response['entity'] as Map, p = command.payload;
  if (e['tenant_id'] != command.context.tenantId ||
      e['action'] != action.wire ||
      e['id'] is! String ||
      !_id.hasMatch(e['id'] as String) ||
      e['version'] !=
          (action.creates ? 1 : command.expectedEntityVersion! + 1)) {
    return false;
  }
  if (p['id'] != null && e['id'] != p['id']) return false;
  if (action == WorkspaceAdminAction.setAssignment) {
    return workspaceAdminCanonical(e['change']) == workspaceAdminCanonical(p);
  }
  for (final key in p.keys.where((k) => k != 'id')) {
    if (key == 'permissions') {
      if (e[key] is! List ||
          (e[key] as List).length != (p[key] as List).length ||
          !(e[key] as List).toSet().containsAll(p[key] as List)) {
        return false;
      }
    } else if (e[key] != p[key] && !(p[key] == '' && e[key] == null)) {
      return false;
    }
  }
  return true;
}

abstract interface class WorkspaceAdminRepository {
  Future<WorkspaceAdminPage> list(
    TenantContext scope,
    WorkspaceAdminResource resource, {
    String? after,
    int limit = 50,
  });
  Future<Map<String, Object?>> command(
    WorkspaceAdminAction action,
    CommandEnvelope<Map<String, Object?>> command,
  );
  Future<Map<String, Object?>> myInvitations({String? after});
  Future<Map<String, Object?>> acceptInvitation(
    String invitationId,
    String idempotencyKey,
  );
}

import 'dart:convert';

import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_platform/runtime_configuration.dart';
// The shared barrels also export native SQLite and desktop draft services.
// Keep this app's dependency graph limited to the installed gateway modules.
// ignore: implementation_imports
import 'package:jentra_platform/src/supabase_foundation_gateway.dart';
// ignore: implementation_imports
import 'package:jentra_platform/src/supabase_private_hr_gateway.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'employee_storage.dart';

enum EmployeePhase {
  unconfigured,
  signedOut,
  loading,
  changeTemporaryPassword,
  staffUnavailable,
  chooseWorkspace,
  linkRequired,
  ready,
  locked,
}

final class EmployeeWorkspace {
  const EmployeeWorkspace({
    required this.tenantId,
    required this.legalEntityId,
    required this.branchId,
    required this.tenantName,
    required this.entityName,
    required this.branchName,
    required this.timeZone,
  });
  final String tenantId,
      legalEntityId,
      branchId,
      tenantName,
      entityName,
      branchName,
      timeZone;
  String get key => '$tenantId/$legalEntityId/$branchId';
  TenantContext context(String actorId) => TenantContext(
    tenantId: tenantId,
    actorId: actorId,
    legalEntityId: legalEntityId,
    branchId: branchId,
  );
}

final class EmployeeIdentity {
  const EmployeeIdentity({
    required this.workspace,
    required this.actorId,
    required this.employeeId,
    required this.displayName,
  });
  final EmployeeWorkspace workspace;
  final String actorId, employeeId, displayName;
  String get key => '${workspace.key}/$actorId/$employeeId';
}

final class EmployeeLink {
  const EmployeeLink({
    required this.id,
    required this.employeeId,
    required this.displayName,
    required this.version,
    required this.expiresAt,
  });
  final String id, employeeId, displayName;
  final int version;
  final DateTime expiresAt;
}

final class EmployeeReview {
  const EmployeeReview({
    required this.id,
    required this.status,
    required this.version,
    required this.startDate,
    required this.endDateExclusive,
    required this.objectives,
    this.comments,
  });
  final String id, status;
  final int version;
  final DateTime startDate, endDateExclusive;
  final List<String> objectives;
  final String? comments;
  bool get canAcknowledge => status == 'reviewed';
}

final class EmployeeLeaveDraft {
  const EmployeeLeaveDraft({
    required this.leaveType,
    required this.reason,
    required this.startDate,
    required this.endDate,
  });
  final String leaveType, reason;
  final DateTime startDate, endDate;
  String? get validationError {
    if (leaveType.trim().isEmpty || leaveType.length > 80) {
      return 'Enter a leave type of up to 80 characters.';
    }
    if (reason.trim().isEmpty || reason.length > 1000) {
      return 'Enter a reason of up to 1,000 characters.';
    }
    final a = DateTime.utc(startDate.year, startDate.month, startDate.day);
    final b = DateTime.utc(endDate.year, endDate.month, endDate.day);
    if (b.isBefore(a)) {
      return 'The end date must be on or after the start date.';
    }
    if (b.difference(a).inDays + 1 > 366) {
      return 'A draft can cover at most 366 calendar days.';
    }
    return null;
  }
}

final class EmployeeFailure implements Exception {
  const EmployeeFailure(this.code, this.message);
  final String code, message;
  @override
  String toString() => message;
}

EmployeeFailure employeeFailure(Object error) {
  if (error is EmployeeFailure) return error;
  final code = error is DomainError
      ? error.code
      : error is AuthException
      ? 'SIGN_IN_FAILED'
      : error is AccountSecurityException
      ? switch (error.code) {
          'invalid_login' => 'SIGN_IN_FAILED',
          'invalid_password' || 'weak_password' => 'INVALID_NEW_PASSWORD',
          'invalid_current_password' ||
          'incorrect_password' => 'INVALID_CURRENT_PASSWORD',
          'invalid_code' ||
          'invalid_or_expired_code' => 'INVALID_PASSWORD_CODE',
          'try_again_later' => 'PASSWORD_RETRY_LATER',
          _ => 'ACCOUNT_SECURITY_UNAVAILABLE',
        }
      : error is PostgrestException
      ? switch (error.code) {
          '42501' => 'PERMISSION_DENIED',
          'PGRST301' || 'PGRST302' => 'AUTHENTICATION_REQUIRED',
          'PGRST202' => 'FEATURE_NOT_INSTALLED',
          _ => 'SERVICE_UNAVAILABLE',
        }
      : error is FormatException
      ? 'INVALID_RESPONSE'
      : 'UNCERTAIN_RESULT';
  return EmployeeFailure(code, switch (code) {
    'SIGN_IN_FAILED' =>
      'Sign-in failed. Check your account details and connection.',
    'INVALID_NEW_PASSWORD' => 'Choose a password that meets the requirements.',
    'INVALID_CURRENT_PASSWORD' =>
      'Check your temporary password and try again.',
    'INVALID_PASSWORD_CODE' => 'The recovery code is incorrect or has expired.',
    'PASSWORD_RETRY_LATER' => 'Wait before trying again.',
    'ACCOUNT_SECURITY_UNAVAILABLE' =>
      'Account security could not be verified. Try again or contact HR.',
    'SELF_LINK_REQUIRED' =>
      'HR must propose an exact account link before self service is available.',
    'PERMISSION_DENIED' => 'HR access is missing or has changed. Ask HR to check your existing account permissions.',
    'MFA_REQUIRED' => 'Your organization requires verified MFA. Complete it through your supported Jentra sign-in flow.',
    'AUTHENTICATION_REQUIRED' || 'SESSION_CHANGED' =>
      'Your session changed. Sign in and select your workspace again.',
    'FEATURE_NOT_ENTITLED' =>
      'People self service is not enabled for this business.',
    'FEATURE_NOT_INSTALLED' =>
      'This employee service is unavailable in the connected environment.',
    'VERSION_CONFLICT' =>
      'This record changed. Refresh it before trying again.',
    'VALIDATION_ERROR' => 'The server rejected the record or its current workflow state. Refresh and check it.',
    'IDEMPOTENCY_MISMATCH' => 'The saved request identity does not match the server request. Ask support to reconcile it.',
    'HR_LINK_ALREADY_EXISTS' =>
      'An employee link already exists. Refresh and ask HR to check it.',
    'INVALID_RESPONSE' => 'The service returned an unexpected or mismatched response. Refresh or contact support.',
    'SERVICE_UNAVAILABLE' => 'The service is unavailable. Check your connection and refresh. A saved action must be reconciled before retrying.',
    _ => 'The result could not be confirmed. Keep the saved request and check its receipt before retrying.',
  });
}

final class EmployeeReviewPage {
  const EmployeeReviewPage(this.items, this.nextCursor);
  final List<EmployeeReview> items;
  final String? nextCursor;
}

/// IDs, scope, version and timestamp are sealed before persistence or dispatch.
/// Only the three employee intents can cross this app's write boundary.
final class EmployeePendingCommand {
  EmployeePendingCommand._(this._wire);
  static const actions = {'link_accept', 'link_reject', 'review_acknowledge'};
  final String _wire;
  factory EmployeePendingCommand.create({
    required EmployeeWorkspace workspace,
    required String actorId,
    required String employeeId,
    required String action,
    required String targetId,
    required int expectedVersion,
    required DateTime now,
  }) {
    final command = CommandEnvelope<Map<String, Object?>>(
      commandId: const Uuid().v4(),
      idempotencyKey: const Uuid().v4(),
      context: workspace.context(actorId),
      clientTimestamp: now,
      expectedEntityVersion: expectedVersion,
      payload: {'action': action, 'id': targetId, 'employee_id': employeeId},
    );
    return EmployeePendingCommand.fromJson(command.toJson((x) => x));
  }
  factory EmployeePendingCommand.fromJson(Map<String, Object?> json) {
    calendarFields(json, {
      'command_id',
      'idempotency_key',
      'context',
      'client_timestamp',
      'expected_entity_version',
      'payload',
    });
    calendarUuid(json['command_id']);
    calendarUuid(json['idempotency_key']);
    organizationVersion(json['expected_entity_version']);
    organizationTimestamp(json['client_timestamp']);
    final scope = hrMap(json['context']);
    calendarFields(scope, {
      'tenant_id',
      'actor_id',
      'legal_entity_id',
      'branch_id',
      'warehouse_id',
      'project_id',
    });
    for (final f in ['tenant_id', 'actor_id', 'legal_entity_id', 'branch_id']) {
      calendarUuid(scope[f]);
    }
    if (scope['warehouse_id'] != null || scope['project_id'] != null) {
      throw const FormatException('Unexpected scope.');
    }
    final payload = hrMap(json['payload']);
    final action = payload['action'];
    if (!actions.contains(action)) {
      throw const FormatException('Unsupported employee action.');
    }
    HrCommands.validate(action as String, payload);
    return EmployeePendingCommand._(jsonEncode(json));
  }
  Map<String, Object?> toJson() => hrMap(jsonDecode(_wire));
  CommandEnvelope<Map<String, Object?>> get envelope {
    final json = toJson();
    return CommandEnvelope(
      commandId: json['command_id'] as String,
      idempotencyKey: json['idempotency_key'] as String,
      context: TenantContext.fromJson(hrMap(json['context'])),
      payload: Map.unmodifiable(hrMap(json['payload'])),
      expectedEntityVersion: json['expected_entity_version'] as int,
      clientTimestamp: DateTime.parse(json['client_timestamp'] as String),
    );
  }

  String get ownerKey {
    final c = envelope.context;
    return '${c.tenantId}/${c.legalEntityId}/${c.branchId}/${c.actorId}';
  }
}

abstract interface class EmployeeGateway {
  String? get actorId;
  Stream<String?> get actorChanges;
  Future<void> signIn(String login, String password);
  Future<void> signOut();
  Future<List<EmployeeWorkspace>> listWorkspaces();
  Future<EmployeeIdentity> resolveIdentity(EmployeeWorkspace workspace);
  Future<List<EmployeeLink>> listLinks(EmployeeWorkspace workspace);
  Future<EmployeeReviewPage> listReviews(
    EmployeeIdentity identity, {
    String? after,
  });
  Future<void> execute(EmployeePendingCommand command);
  Future<bool> hasReceipt(EmployeePendingCommand command);
}

typedef ManagedEmployeeAccount = ({
  String kind,
  String? status,
  bool mustChangePassword,
});

abstract interface class ManagedEmployeeIdentityGateway {
  Future<ManagedEmployeeAccount?> managedAccount();
  Future<List<EmployeeWorkspace>> listManagedWorkspaces();
  Future<void> changeTemporaryPassword(
    String currentPassword,
    String newPassword,
  );
  Future<void> requestManagedPasswordReset(String login);
  Future<void> resetManagedPassword(
    String login,
    String code,
    String newPassword,
  );
}

final class SupabaseEmployeeGateway
    implements EmployeeGateway, ManagedEmployeeIdentityGateway {
  SupabaseEmployeeGateway(this.client, {this.authStorage})
    : _foundation = SupabaseFoundationGateway(client),
      _hr = SupabasePrivateHrGateway(client);
  final SupabaseClient client;
  final EmployeeAuthStorage? authStorage;
  final SupabaseFoundationGateway _foundation;
  final SupabasePrivateHrGateway _hr;
  @override
  String? get actorId => client.auth.currentUser?.id;
  @override
  Stream<String?> get actorChanges => client.auth.onAuthStateChange
      .map((state) => state.session?.user.id)
      .distinct();
  String _actor() =>
      actorId ??
      (throw const EmployeeFailure(
        'AUTHENTICATION_REQUIRED',
        'Sign in to continue.',
      ));
  void _check(String expected) {
    if (actorId != expected) {
      throw const EmployeeFailure(
        'SESSION_CHANGED',
        'Your session changed. Sign in again.',
      );
    }
  }

  Future<String> _onlineActor() async {
    final actor = _actor();
    final result = await client.auth.getUser();
    _check(actor);
    if (result.user?.id != actor) {
      throw const EmployeeFailure(
        'SESSION_CHANGED',
        'The online account does not match your saved session. Sign in again.',
      );
    }
    return actor;
  }

  Future<T> _safe<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on Object catch (e) {
      throw employeeFailure(e);
    }
  }

  @override
  Future<void> signIn(String login, String password) => _safe(() async {
    authStorage?.beginSignIn();
    if (organizationControlCandidateEnabled) {
      await _foundation.signInWithAccountLogin(
        login: login,
        password: password,
      );
    } else {
      await _foundation.signInWithPassword(
        email: login.trim(),
        password: password,
      );
    }
  });

  @override
  Future<ManagedEmployeeAccount?> managedAccount() => _safe(() async {
    if (!_foundation.usesManagedUsername) return null;
    final actor = _actor();
    final profile = await _foundation.accountSecurityProfile();
    _check(actor);
    final kind = profile.accountKind;
    if (kind == null) return null;
    return (
      kind: kind,
      status: profile.staffStatus,
      mustChangePassword: profile.mustChangePassword,
    );
  });

  @override
  Future<List<EmployeeWorkspace>> listManagedWorkspaces() => _safe(() async {
    final actor = await _onlineActor();
    final response = await client
        .schema('api')
        .rpc('managed_employee_workspaces');
    _check(actor);
    if (response is! List)
      throw const FormatException('Invalid workspace list.');
    return [for (final raw in response) _managedWorkspace(hrMap(raw))];
  });

  EmployeeWorkspace _managedWorkspace(Map<String, Object?> row) {
    final tenant = row['tenant_id'];
    final entity = row['legal_entity_id'];
    final branch = row['branch_id'];
    calendarUuid(tenant);
    calendarUuid(entity);
    calendarUuid(branch);
    return EmployeeWorkspace(
      tenantId: tenant as String,
      legalEntityId: entity as String,
      branchId: branch as String,
      tenantName: row['tenant_name'] as String,
      entityName: row['entity_name'] as String,
      branchName: row['branch_name'] as String,
      timeZone: row['timezone'] as String,
    );
  }

  @override
  Future<void> changeTemporaryPassword(
    String currentPassword,
    String newPassword,
  ) => _safe(
    () => _foundation.changeOrganizationPassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    ),
  );

  @override
  Future<void> requestManagedPasswordReset(String login) =>
      _safe(() => _foundation.requestPasswordReset(login));

  @override
  Future<void> resetManagedPassword(
    String login,
    String code,
    String newPassword,
  ) => _safe(
    () => _foundation.resetPassword(
      login: login,
      code: code,
      newPassword: newPassword,
    ),
  );
  @override
  Future<void> signOut() => _safe(() async {
    authStorage?.blockPersistenceForLogout();
    Object? remoteFailure;
    try {
      await _foundation.signOut();
    } on Object catch (error) {
      remoteFailure = error;
    }
    // SupabaseFlutter's listener catches its own persistence errors. This
    // explicit serialized barrier is the app's durable logout confirmation.
    await authStorage?.clearForLogout();
    if (remoteFailure != null) throw employeeFailure(remoteFailure);
  });
  @override
  Future<List<EmployeeWorkspace>> listWorkspaces() => _safe(() async {
    final actor = await _onlineActor();
    final tenants = await _foundation.listMyTenants();
    _check(actor);
    final result = <EmployeeWorkspace>[];
    for (final t in tenants.where(
      (t) => t.status == 'active' && t.membershipStatus == 'active',
    )) {
      calendarUuid(t.id);
      final entities = await _foundation.listLegalEntities(t.id);
      _check(actor);
      for (final e in entities.where((e) => e.status == 'active')) {
        if (e.tenantId != t.id) {
          throw const FormatException('Entity scope mismatch.');
        }
        calendarUuid(e.id);
        final branches = await _foundation.listBranches(
          tenantId: t.id,
          legalEntityId: e.id,
        );
        _check(actor);
        for (final b in branches.where((b) => b.status == 'active')) {
          if (b.tenantId != t.id || b.legalEntityId != e.id) {
            throw const FormatException('Branch scope mismatch.');
          }
          calendarUuid(b.id);
          result.add(
            EmployeeWorkspace(
              tenantId: t.id,
              legalEntityId: e.id,
              branchId: b.id,
              tenantName: t.name,
              entityName: e.name,
              branchName: b.name,
              timeZone: b.timezone,
            ),
          );
        }
      }
    }
    if (result.map((x) => x.key).toSet().length != result.length) {
      throw const FormatException('Duplicate workspace.');
    }
    return List.unmodifiable(result);
  });
  @override
  Future<EmployeeIdentity> resolveIdentity(EmployeeWorkspace workspace) =>
      _safe(() async {
        final actor = await _onlineActor();
        final record = await _hr.self(workspace.context(actor));
        _check(actor);
        return EmployeeIdentity(
          workspace: workspace,
          actorId: actor,
          employeeId: record.id,
          displayName: record.text('display_name')!,
        );
      });
  @override
  Future<List<EmployeeLink>> listLinks(
    EmployeeWorkspace workspace,
  ) => _safe(() async {
    final actor = await _onlineActor();
    final page = await _hr.page(workspace.context(actor), HrCollection.inbox);
    _check(actor);
    // A live link inbox is scoped to the current authenticated user by the RPC.
    return List.unmodifiable(
      page.items.map(
        (r) => EmployeeLink(
          id: r.id,
          employeeId: r.text('employee_id')!,
          displayName: r.text('employee_name')!,
          version: r.version,
          expiresAt: DateTime.parse(r.text('expires_at')!),
        ),
      ),
    );
  });
  @override
  Future<EmployeeReviewPage> listReviews(
    EmployeeIdentity identity, {
    String? after,
  }) => _safe(() async {
    _check(identity.actorId);
    final accepted = await resolveIdentity(identity.workspace);
    _check(identity.actorId);
    if (accepted.key != identity.key) {
      throw const EmployeeFailure(
        'INVALID_RESPONSE',
        'The requested employee does not match your accepted account link.',
      );
    }
    final json = hrMap(
      await client
          .schema('api')
          .rpc(
            'employee_self_reviews',
            params: {
              'p_tenant_id': identity.workspace.tenantId,
              'p_legal_entity_id': identity.workspace.legalEntityId,
              'p_branch_id': identity.workspace.branchId,
              'p_after': after,
            },
          ),
    );
    _check(identity.actorId);
    if (json['tenant_id'] != identity.workspace.tenantId ||
        json['legal_entity_id'] != identity.workspace.legalEntityId ||
        json['branch_id'] != identity.workspace.branchId ||
        json['employee_id'] != identity.employeeId ||
        json['items'] is! List ||
        (json['items'] as List).length > 50) {
      throw const FormatException('Own-review scope mismatch.');
    }
    final items = <EmployeeReview>[];
    for (final value in json['items']! as List) {
      final row = hrMap(value);
      if (row['employee_id'] != null &&
              row['employee_id'] != identity.employeeId ||
          !{'reviewed', 'acknowledged', 'closed'}.contains(row['status'])) {
        throw const FormatException('Unpublished or foreign review.');
      }
      final body = hrMap(row['body']);
      final objectives = body['objectives'];
      if (objectives is! List ||
          objectives.length > 100 ||
          objectives.any((item) => item is! String || item.length > 1000)) {
        throw const FormatException('Invalid review objectives.');
      }
      items.add(
        EmployeeReview(
          id: calendarUuid(row['id']),
          status: row['status']! as String,
          version: organizationVersion(row['version']),
          startDate: DateTime.parse(row['start_date']! as String),
          endDateExclusive: DateTime.parse(
            row['end_date_exclusive']! as String,
          ),
          objectives: List.unmodifiable(objectives.cast<String>()),
          comments: body['comments'] as String?,
        ),
      );
    }
    final cursor = json['next_cursor'] == null
        ? null
        : calendarUuid(json['next_cursor']);
    return EmployeeReviewPage(List.unmodifiable(items), cursor);
  });
  void _confirmation(EmployeePendingCommand command, HrConfirmation receipt) {
    final c = command.envelope;
    final e = receipt.entity;
    final p = c.payload;
    if (receipt.commandId != c.commandId ||
        e['tenant_id'] != c.context.tenantId ||
        e['legal_entity_id'] != c.context.legalEntityId ||
        e['branch_id'] != c.context.branchId ||
        e['employee_id'] != p['employee_id'] ||
        e['id'] != p['id'] ||
        e['action'] != p['action'] ||
        receipt.version != c.expectedEntityVersion! + 1) {
      throw const EmployeeFailure(
        'UNCERTAIN_RESULT',
        'The receipt does not match the saved request. Keep it for reconciliation.',
      );
    }
  }

  @override
  Future<void> execute(EmployeePendingCommand command) => _safe(() async {
    final c = command.envelope;
    _check(c.context.actorId);
    final result = await _hr.command(c);
    _check(c.context.actorId);
    _confirmation(command, result);
  });
  @override
  Future<bool> hasReceipt(EmployeePendingCommand command) => _safe(() async {
    final c = command.envelope;
    _check(c.context.actorId);
    final result = await _hr.receipt(c.context, c.commandId);
    _check(c.context.actorId);
    if (result == null) return false;
    _confirmation(command, result);
    return true;
  });
}

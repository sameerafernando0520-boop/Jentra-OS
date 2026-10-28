import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_platform/jentra_people_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import 'private_hr_controller.dart';

/// These APIs enforce current scoped capability, session, MFA and retention.
/// The tenant capability set only decides which controls can be offered.
abstract interface class EmployeeCaseRepository {
  Future<Map<String, Object?>> page(TenantContext scope, {String? after});
  Future<Map<String, Object?>> detail(TenantContext scope, String id);
  Future<Map<String, Object?>> owners(TenantContext scope, {String? after});
  Future<Map<String, Object?>> command(
    TenantContext scope,
    Map<String, Object?> request,
  );
  Future<Map<String, Object?>> publication(TenantContext scope, String id);
  Future<Map<String, Object?>> publish(
    TenantContext scope,
    Map<String, Object?> request,
  );
}

final employeeCaseRepositoryProvider = Provider<EmployeeCaseRepository?>((ref) {
  final base = ref.watch(privateHrRepositoryProvider);
  return base is SupabasePrivateHrGateway
      ? SupabaseEmployeeCaseRepository(base.client)
      : null;
});

final employeeCaseControllerProvider =
    Provider.autoDispose<EmployeeCaseController?>((ref) {
      // Every auth event invalidates private state, including same-user refresh.
      final revision = ref.watch(authSessionRevisionProvider);
      final assurance = ref.watch(sessionAssuranceProvider);
      final scope = ref.watch(activeTenantContextProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      final repository = ref.watch(employeeCaseRepositoryProvider);
      final permissions = caps.value ?? const <String>{};
      if (revision.isLoading ||
          revision.hasError ||
          assurance != MfaAssurance.aal2 ||
          scope == null ||
          !scope.hasOperationalScope ||
          repository == null ||
          caps.isLoading ||
          caps.hasError ||
          !permissions.contains('people.view') ||
          !(permissions.contains('people.cases.manage') ||
              (permissions.contains('people.hr.documents.view') &&
                  permissions.contains('people.hr.documents.publish')))) {
        return null;
      }
      final controller = EmployeeCaseController(
        scope: scope,
        repository: repository,
        permissions: permissions,
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
      );
      ref.listen(
        connectivityStateProvider,
        (_, next) =>
            controller.setOnline(next.value == ConnectivityState.online),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

final class SupabaseEmployeeCaseRepository implements EmployeeCaseRepository {
  SupabaseEmployeeCaseRepository(this.client);
  final SupabaseClient client;

  Future<Map<String, Object?>> _rpc(
    TenantContext scope,
    String name,
    Map<String, Object?> args,
  ) async {
    void requireScope() {
      if (!scope.hasOperationalScope ||
          client.auth.currentUser?.id != scope.actorId ||
          client.auth.currentSession == null) {
        throw const DomainError(
          code: 'AUTHENTICATION_REQUIRED',
          message: 'Sign in and select the current entity and branch.',
        );
      }
      calendarUuid(scope.tenantId);
      calendarUuid(scope.legalEntityId);
      calendarUuid(scope.branchId);
    }

    requireScope();
    try {
      final raw = await client
          .schema('api')
          .rpc(
            name,
            params: {
              'p_tenant_id': scope.tenantId,
              'p_legal_entity_id': scope.legalEntityId,
              'p_branch_id': scope.branchId,
              ...args,
            },
          )
          .timeout(const Duration(seconds: 20));
      requireScope();
      return hrMap(raw);
    } on PostgrestException catch (error) {
      final code = switch ((error.code, error.message)) {
        ('PGRST202', _) => 'FEATURE_NOT_INSTALLED',
        ('42501', 'HR_MFA_REQUIRED') => 'MFA_REQUIRED',
        ('42501', 'EMPLOYEE_SESSION_REQUIRED') => 'AUTHENTICATION_REQUIRED',
        ('42501', 'EMPLOYEE_CASE_OWNER_REQUIRED') => 'OWNER_REQUIRED',
        ('42501', _) => 'PERMISSION_DENIED',
        ('40001', _) => 'VERSION_CONFLICT',
        ('55000', 'HR_CONTENT_EXPIRED') => 'HR_CONTENT_EXPIRED',
        ('55000', 'HR_RETENTION_WORKER_UNAVAILABLE') => 'RETENTION_UNAVAILABLE',
        ('22023', 'EMPLOYEE_COMMAND_REUSED') => 'COMMAND_REUSED',
        ('22023' || '23503' || '23514' || '23505' || '54000', _) =>
          'VALIDATION_ERROR',
        _ => 'UNCERTAIN_RESULT',
      };
      // Never expose backend messages, details, SQL or private payloads.
      throw DomainError(code: code, message: employeeCaseError(code));
    }
  }

  @override
  Future<Map<String, Object?>> page(TenantContext scope, {String? after}) =>
      _rpc(scope, 'employee_hr_cases_list', {'p_after': after});

  @override
  Future<Map<String, Object?>> detail(TenantContext scope, String id) =>
      _rpc(scope, 'employee_hr_case_detail', {'p_case_id': id});

  @override
  Future<Map<String, Object?>> owners(TenantContext scope, {String? after}) =>
      _rpc(scope, 'employee_hr_case_owners', {'p_after': after});

  @override
  Future<Map<String, Object?>> command(
    TenantContext scope,
    Map<String, Object?> request,
  ) => _rpc(scope, 'employee_hr_case_command', request);

  @override
  Future<Map<String, Object?>> publication(TenantContext scope, String id) =>
      _rpc(scope, 'employee_hr_document_publication', {'p_document_id': id});

  @override
  Future<Map<String, Object?>> publish(
    TenantContext scope,
    Map<String, Object?> request,
  ) => _rpc(scope, 'employee_hr_document_publish', request);
}

String employeeCaseError(String code) => switch (code) {
  'FEATURE_NOT_INSTALLED' => 'This workspace needs the reviewed HR update.',
  'AUTHENTICATION_REQUIRED' => 'Sign in again to verify private HR access.',
  'MFA_REQUIRED' => 'Complete MFA before opening the staff HR console.',
  'PERMISSION_DENIED' || 'FEATURE_NOT_ENTITLED' =>
    'Current staff permission for this entity and branch is required.',
  'HR_CONTENT_EXPIRED' => 'This private content is no longer available.',
  'RETENTION_UNAVAILABLE' =>
    'Private changes are unavailable until retention checks recover.',
  'OWNER_REQUIRED' => 'Only the accountable owner can perform this action.',
  'VERSION_CONFLICT' =>
    'This record changed. Load its current version before choosing an action.',
  'COMMAND_REUSED' => 'The original request could not be verified.',
  'VALIDATION_ERROR' => 'Check the fields and the current workflow state.',
  _ => 'The result is unconfirmed. Retry the exact original request.',
};

int _version(Object? value, {bool zero = false}) {
  if (value is! int || value < (zero ? 0 : 1) || value > 9007199254740991) {
    throw const FormatException('Invalid HR version.');
  }
  return value;
}

void _text(Object? value, int limit, {bool nullable = false}) {
  if (nullable && value == null) return;
  if (value is! String || value.trim().isEmpty || value.length > limit) {
    throw const FormatException('Invalid HR text.');
  }
}

void _instant(Object? value) {
  if (value is! String || DateTime.tryParse(value) == null) {
    throw const FormatException('Invalid HR timestamp.');
  }
}

Map<String, Object?> _case(Map<String, Object?> value, {bool detail = false}) {
  calendarFields(value, {
    'id',
    'employee_id',
    'version',
    'category',
    'subject',
    'status',
    'owner_user_id',
    'owner_available',
    'payslip_id',
    'payslip_revision_id',
    'created_at',
    'updated_at',
    if (detail) ...{'messages', 'history'},
  });
  calendarUuid(value['id']);
  calendarUuid(value['employee_id']);
  _version(value['version']);
  _text(value['subject'], 160, nullable: true);
  if (value['owner_available'] is! bool ||
      (value['owner_user_id'] == null && value['owner_available'] == true)) {
    throw const FormatException('Invalid case owner availability.');
  }
  if (!{'general', 'payroll'}.contains(value['category']) ||
      !{
        'open',
        'in_progress',
        'resolved',
        'closed',
      }.contains(value['status'])) {
    throw const FormatException('Invalid case state.');
  }
  for (final key in ['owner_user_id', 'payslip_id', 'payslip_revision_id']) {
    if (value[key] != null) calendarUuid(value[key]);
  }
  if (value['category'] == 'payroll'
      ? value['payslip_id'] == null || value['payslip_revision_id'] == null
      : value['payslip_id'] != null || value['payslip_revision_id'] != null) {
    throw const FormatException('Invalid payroll case.');
  }
  _instant(value['created_at']);
  _instant(value['updated_at']);
  if (detail) {
    final messages = value['messages'], history = value['history'];
    if (messages is! List ||
        messages.length > 200 ||
        history is! List ||
        history.length > 1000) {
      throw const FormatException('HR history exceeds its bound.');
    }
    for (final raw in messages) {
      final row = hrMap(raw);
      calendarFields(row, {'id', 'body', 'author_kind', 'created_at'});
      calendarUuid(row['id']);
      _text(row['body'], 4000, nullable: true);
      _instant(row['created_at']);
      if (!{'employee', 'hr'}.contains(row['author_kind'])) {
        throw const FormatException('Invalid case author.');
      }
    }
    for (final raw in history) {
      final row = hrMap(raw);
      calendarFields(row, {'id', 'status', 'owner_user_id', 'created_at'});
      calendarUuid(row['id']);
      if (row['owner_user_id'] != null) calendarUuid(row['owner_user_id']);
      _instant(row['created_at']);
      if (!{
        'open',
        'in_progress',
        'resolved',
        'closed',
      }.contains(row['status'])) {
        throw const FormatException('Invalid case history.');
      }
    }
  }
  return Map.unmodifiable(value);
}

final class EmployeeCaseController extends ChangeNotifier {
  EmployeeCaseController({
    required this.scope,
    required this.repository,
    required Set<String> permissions,
    required this.online,
    bool monitor = true,
  }) : permissions = Set.unmodifiable(permissions) {
    if (monitor) {
      _timer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(checkAccess()),
      );
    }
  }

  final TenantContext scope;
  final EmployeeCaseRepository repository;
  final Set<String> permissions;
  static const _uuid = Uuid();
  Timer? _timer;
  int _epoch = 0;
  bool _disposed = false;
  bool busy = false, denied = false, online;
  String? error, message, cursor;
  bool conflict = false;
  List<Map<String, Object?>> rows = [];
  Map<String, Object?>? selected, publication;
  Map<String, Object?>? pendingCase, pendingPublication;
  String? _documentId;
  int? _documentVersion;

  bool get current => !_disposed && !denied;
  bool get canManage => permissions.contains('people.cases.manage');
  bool get canPublish =>
      permissions.contains('people.hr.documents.view') &&
      permissions.contains('people.hr.documents.publish');
  bool get locked =>
      busy ||
      !online ||
      !current ||
      pendingCase != null ||
      pendingPublication != null;
  bool get isOwner => selected?['owner_user_id'] == scope.actorId;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int epoch) => current && online && _epoch == epoch;
  void _clearVisible() {
    rows = [];
    cursor = null;
    selected = null;
    publication = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    _timer?.cancel();
    _clearVisible();
    pendingCase = null;
    pendingPublication = null;
    _documentId = null;
    _documentVersion = null;
    super.dispose();
  }

  void setOnline(bool value) {
    if (online == value) return;
    online = value;
    _epoch++;
    _clearVisible();
    message =
        'Reconnect and load current access before viewing private content.';
    _notify();
  }

  bool _revoked(String code) => {
    'AUTHENTICATION_REQUIRED',
    'MFA_REQUIRED',
    'PERMISSION_DENIED',
    'FEATURE_NOT_ENTITLED',
    'HR_CONTENT_EXPIRED',
  }.contains(code);

  Future<void> _run(Future<void> Function(int epoch) work) async {
    if (busy || !current || !online) return;
    final epoch = _epoch;
    busy = true;
    error = null;
    message = null;
    _notify();
    try {
      await work(epoch);
    } catch (failure) {
      if (!_current(epoch)) return;
      final code = failure is DomainError ? failure.code : 'UNCERTAIN_RESULT';
      if (_revoked(code)) {
        denied = true;
        _epoch++;
        _clearVisible();
        pendingCase = null;
        pendingPublication = null;
      } else if (code == 'VERSION_CONFLICT') {
        // A rejected expected version cannot be silently rebased or resubmitted.
        conflict = true;
        pendingCase = null;
        pendingPublication = null;
        _clearVisible();
      } else if (code == 'OWNER_REQUIRED') {
        pendingCase = null;
        selected = null;
      } else if (code == 'VALIDATION_ERROR' || code == 'COMMAND_REUSED') {
        pendingCase = null;
        pendingPublication = null;
      } else if (pendingCase == null && pendingPublication == null) {
        // A failed read must never leave an old body on screen.
        _clearVisible();
      }
      error = failure is FormatException
          ? 'The HR response could not be verified. Load the current record again.'
          : employeeCaseError(code);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> _loadPage(int epoch, {bool more = false}) async {
    if (!canManage) return;
    final after = more ? cursor : null;
    final result = await repository.page(scope, after: after);
    calendarFields(result, {'items', 'next_cursor'});
    final items = result['items'];
    if (items is! List || items.length > 50) {
      throw const FormatException('Invalid case page.');
    }
    final nextRows = items.map((raw) => _case(hrMap(raw))).toList();
    String? previous = after;
    for (final row in nextRows) {
      final id = row['id']! as String;
      if (previous != null && id.compareTo(previous) <= 0) {
        throw const FormatException('Invalid case page order.');
      }
      previous = id;
    }
    final next = result['next_cursor'] == null
        ? null
        : calendarUuid(result['next_cursor']);
    if (next != null && (nextRows.length != 50 || next != previous)) {
      throw const FormatException('Invalid case continuation.');
    }
    if (!_current(epoch)) return;
    rows = [if (more) ...rows, ...nextRows];
    cursor = next;
  }

  Future<void> initialize() => refresh();
  Future<void> refresh() => _run((epoch) async {
    await _loadPage(epoch);
    if (!_current(epoch)) return;
    if (selected != null) await _loadDetail(epoch, selected!['id']! as String);
    conflict = false;
  });
  Future<void> more() => _run((epoch) async {
    if (cursor != null) await _loadPage(epoch, more: true);
  });

  Future<void> _loadDetail(int epoch, String id) async {
    final result = _case(await repository.detail(scope, id), detail: true);
    if (result['id'] != id) {
      throw const FormatException('Case identity changed.');
    }
    if (_current(epoch)) selected = result;
  }

  Future<void> open(String id) => _run((epoch) async {
    if (!canManage || pendingCase != null) return;
    calendarUuid(id);
    selected = null;
    await _loadDetail(epoch, id);
    if (_current(epoch)) {
      conflict = false;
      message = null;
    }
  });

  Future<void> checkAccess() => _run((epoch) async {
    await _loadPage(epoch);
    if (!_current(epoch)) return;
    if (selected != null) await _loadDetail(epoch, selected!['id']! as String);
    if (_documentId != null) {
      await _loadPublication(epoch, detectChange: pendingPublication == null);
    }
  });

  Future<(List<Map<String, Object?>>, String?)> ownerChoices({
    String? after,
  }) async {
    (List<Map<String, Object?>>, String?)? page;
    await _run((epoch) async {
      if (!canManage ||
          !isOwner ||
          pendingCase != null ||
          pendingPublication != null ||
          conflict) {
        return;
      }
      if (after != null) calendarUuid(after);
      final result = await repository.owners(scope, after: after);
      calendarFields(result, {
        'tenant_id',
        'legal_entity_id',
        'branch_id',
        'items',
        'next_cursor',
      });
      if (result['tenant_id'] != scope.tenantId ||
          result['legal_entity_id'] != scope.legalEntityId ||
          result['branch_id'] != scope.branchId ||
          result['items'] is! List ||
          (result['items']! as List).length > 50) {
        throw const FormatException('Invalid permitted HR owner page.');
      }
      String? previous = after;
      final rows = <Map<String, Object?>>[];
      for (final item in result['items']! as List) {
        final row = hrMap(item);
        calendarFields(row, {'id', 'user_id', 'label'});
        final id = calendarUuid(row['id']);
        calendarUuid(row['user_id']);
        _text(row['label'], 160);
        if (previous != null && id.compareTo(previous) <= 0) {
          throw const FormatException('Invalid HR owner page order.');
        }
        previous = id;
        rows.add(Map.unmodifiable(row));
      }
      final next = result['next_cursor'] == null
          ? null
          : calendarUuid(result['next_cursor']);
      if (next != null && (rows.length != 50 || next != previous)) {
        throw const FormatException('Invalid HR owner continuation.');
      }
      if (_current(epoch)) page = (rows, next);
    });
    if (page == null) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Current permitted HR owners are unavailable.',
      );
    }
    return page!;
  }

  Future<void> act(String action, {String? body, String? ownerUserId}) => _run((
    epoch,
  ) async {
    final row = selected;
    if (!canManage ||
        row == null ||
        pendingCase != null ||
        pendingPublication != null ||
        conflict) {
      return;
    }
    if (!{'claim', 'assign', 'reply', 'resolve', 'close'}.contains(action)) {
      return;
    }
    if (row['status'] == 'closed' ||
        (action == 'claim' ? row['owner_available'] == true : !isOwner)) {
      throw const DomainError(code: 'OWNER_REQUIRED', message: '');
    }
    if (action == 'reply') _text(body, 4000);
    if (action == 'assign') calendarUuid(ownerUserId);
    if ((action == 'resolve' &&
            !{'open', 'in_progress'}.contains(row['status'])) ||
        (action == 'close' && row['status'] != 'resolved')) {
      throw const DomainError(code: 'VALIDATION_ERROR', message: '');
    }
    // Immutable in-memory envelope; no body is written to local storage.
    pendingCase = Map.unmodifiable({
      'p_case_id': row['id'],
      'p_command_id': _uuid.v4(),
      'p_expected_version': row['version'],
      'p_action': action,
      'p_body': action == 'reply' ? body!.trim() : null,
      'p_owner_user_id': action == 'assign' ? ownerUserId : null,
    });
    await _sendCase(epoch);
  });

  Future<void> retryCase() => _run(_sendCase);
  Future<void> _sendCase(int epoch) async {
    final request = pendingCase;
    if (request == null) return;
    final employee = selected?['employee_id'];
    final response = await repository.command(scope, request);
    calendarFields(response, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'employee_id',
      'id',
      'version',
      'status',
      'command_id',
    });
    if (response['tenant_id'] != scope.tenantId ||
        response['legal_entity_id'] != scope.legalEntityId ||
        response['branch_id'] != scope.branchId ||
        (employee != null && response['employee_id'] != employee) ||
        response['id'] != request['p_case_id'] ||
        response['command_id'] != request['p_command_id'] ||
        _version(response['version']) !=
            (request['p_expected_version']! as int) + 1 ||
        !{
          'open',
          'in_progress',
          'resolved',
          'closed',
        }.contains(response['status'])) {
      throw const FormatException('Case confirmation could not be verified.');
    }
    calendarUuid(response['employee_id']);
    if (!_current(epoch)) return;
    pendingCase = null;
    message = 'HR action confirmed by the server.';
    await _loadPage(epoch);
    if (_current(epoch)) {
      await _loadDetail(epoch, request['p_case_id']! as String);
    }
  }

  Future<void> openPublication(String documentId, int documentVersion) =>
      _run((epoch) async {
        if (!canPublish || pendingPublication != null) return;
        calendarUuid(documentId);
        _version(documentVersion);
        _documentId = documentId;
        _documentVersion = documentVersion;
        publication = null;
        message = null;
        await _loadPublication(epoch);
        if (_current(epoch)) conflict = false;
      });

  Future<void> _loadPublication(int epoch, {bool detectChange = false}) async {
    if (!canPublish || _documentId == null) return;
    final result = await repository.publication(scope, _documentId!);
    calendarFields(result, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'document_id',
      'document_version',
      'publication_version',
      'visible',
      'label',
    });
    if (result['tenant_id'] != scope.tenantId ||
        result['legal_entity_id'] != scope.legalEntityId ||
        result['branch_id'] != scope.branchId ||
        result['document_id'] != _documentId ||
        _version(result['document_version']) != _documentVersion ||
        result['visible'] is! bool) {
      throw const FormatException('Document publication identity changed.');
    }
    _version(result['publication_version'], zero: true);
    _text(result['label'], 160, nullable: true);
    if (result['visible'] == true && result['label'] == null) {
      throw const FormatException('Published document label is missing.');
    }
    if (detectChange &&
        publication != null &&
        result['publication_version'] != publication!['publication_version']) {
      // A periodic access check must not silently rebase an unsaved title.
      throw const DomainError(code: 'VERSION_CONFLICT', message: '');
    }
    if (_current(epoch)) publication = Map.unmodifiable(result);
  }

  Future<void> reloadPublication() => _run((epoch) async {
    await _loadPublication(epoch);
    if (_current(epoch)) conflict = false;
  });

  Future<void> setPublication({required bool visible, String? label}) =>
      _run((epoch) async {
        final row = publication;
        if (!canPublish ||
            row == null ||
            pendingPublication != null ||
            pendingCase != null ||
            conflict) {
          return;
        }
        if (visible) _text(label, 160);
        pendingPublication = Map.unmodifiable({
          'p_document_id': row['document_id'],
          'p_document_version': row['document_version'],
          'p_expected_version': row['publication_version'],
          'p_command_id': _uuid.v4(),
          'p_visible': visible,
          'p_label': visible ? label!.trim() : null,
        });
        await _sendPublication(epoch);
      });

  Future<void> retryPublication() => _run(_sendPublication);
  Future<void> _sendPublication(int epoch) async {
    final request = pendingPublication;
    if (request == null) return;
    final response = await repository.publish(scope, request);
    calendarFields(response, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'id',
      'version',
      'document_version',
      'visible',
      'command_id',
    });
    if (response['tenant_id'] != scope.tenantId ||
        response['legal_entity_id'] != scope.legalEntityId ||
        response['branch_id'] != scope.branchId ||
        response['id'] != request['p_document_id'] ||
        response['document_version'] != request['p_document_version'] ||
        response['command_id'] != request['p_command_id'] ||
        response['visible'] != request['p_visible'] ||
        _version(response['version']) !=
            (request['p_expected_version']! as int) + 1) {
      throw const FormatException(
        'Publication confirmation could not be verified.',
      );
    }
    if (!_current(epoch)) return;
    pendingPublication = null;
    message = response['visible'] == true
        ? 'Employee visibility confirmed by the server.'
        : 'Employee visibility removed by the server.';
    await _loadPublication(epoch);
  }
}

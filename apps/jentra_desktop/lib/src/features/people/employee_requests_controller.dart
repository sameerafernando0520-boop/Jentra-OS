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
import 'workforce_controller.dart';

abstract interface class EmployeeRequestsRepository {
  Future<Map<String, Object?>> access(TenantContext scope, String kind);
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String kind,
    String? after,
  );
  Future<Map<String, Object?>> resolve(
    TenantContext scope,
    Map<String, Object?> request,
  );
}

final employeeRequestsControllerProvider =
    Provider.autoDispose<EmployeeRequestsController?>((ref) {
      final revision = ref.watch(authSessionRevisionProvider);
      final assurance = ref.watch(sessionAssuranceProvider);
      final scope = ref.watch(activeTenantContextProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      final base = ref.watch(privateHrRepositoryProvider);
      final workforce = ref.watch(workforceRepositoryProvider);
      final permissions = caps.value ?? const <String>{};
      if (revision.isLoading ||
          revision.hasError ||
          assurance != MfaAssurance.aal2 ||
          scope == null ||
          !scope.hasOperationalScope ||
          caps.isLoading ||
          caps.hasError ||
          base is! SupabasePrivateHrGateway ||
          !permissions.contains('people.view') ||
          !{
            'people.attendance.view',
            'people.leave.view',
          }.any(permissions.contains)) {
        return null;
      }
      final controller = EmployeeRequestsController(
        scope: scope,
        repository: SupabaseEmployeeRequestsRepository(base.client),
        workforce: workforce,
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

String employeeRequestError(String code) => switch (code) {
  'FEATURE_NOT_INSTALLED' => 'This workspace needs the reviewed HR update.',
  'MFA_REQUIRED' => 'Complete MFA before reviewing employee requests.',
  'AUTHENTICATION_REQUIRED' => 'Sign in again to verify HR access.',
  'PERMISSION_DENIED' =>
    'Current permission for this entity and branch is required.',
  'INDEPENDENT_REVIEW_REQUIRED' =>
    'A different authorized colleague must review this request.',
  'VERSION_CONFLICT' =>
    'The record changed. Reload it before making a new decision.',
  'CANONICAL_RECORD_REQUIRED' =>
    'Choose the matching, independently approved attendance record.',
  'VALIDATION_ERROR' => 'Check the decision, reason and current record state.',
  _ => 'The result is unconfirmed. Retry the original decision to verify it.',
};

final class SupabaseEmployeeRequestsRepository
    implements EmployeeRequestsRepository {
  SupabaseEmployeeRequestsRepository(this.client);
  final SupabaseClient client;
  Future<Map<String, Object?>> _rpc(
    TenantContext scope,
    String name,
    Map<String, Object?> args,
  ) async {
    void requireActor() {
      if (!scope.hasOperationalScope ||
          client.auth.currentUser?.id != scope.actorId ||
          client.auth.currentSession == null) {
        throw const DomainError(code: 'AUTHENTICATION_REQUIRED', message: '');
      }
    }

    requireActor();
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
      requireActor();
      return hrMap(raw);
    } on PostgrestException catch (failure) {
      final code = switch ((failure.code, failure.message)) {
        ('PGRST202', _) => 'FEATURE_NOT_INSTALLED',
        ('42501', 'EMPLOYEE_MFA_REQUIRED') => 'MFA_REQUIRED',
        ('42501', 'EMPLOYEE_SESSION_REQUIRED') => 'AUTHENTICATION_REQUIRED',
        ('42501', 'EMPLOYEE_INDEPENDENT_REVIEW_REQUIRED') =>
          'INDEPENDENT_REVIEW_REQUIRED',
        (_, 'EMPLOYEE_CANONICAL_RECORD_REQUIRED') =>
          'CANONICAL_RECORD_REQUIRED',
        ('42501', _) => 'PERMISSION_DENIED',
        ('40001', _) => 'VERSION_CONFLICT',
        ('22023' || '23503' || '23514' || '23505', _) => 'VALIDATION_ERROR',
        _ => 'UNCERTAIN_RESULT',
      };
      throw DomainError(code: code, message: employeeRequestError(code));
    }
  }

  @override
  Future<Map<String, Object?>> access(TenantContext scope, String kind) =>
      _rpc(scope, 'employee_staff_request_access', {'p_kind': kind});
  @override
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String kind,
    String? after,
  ) => _rpc(scope, 'employee_staff_requests', {
    'p_kind': kind,
    'p_after': after,
  });
  @override
  Future<Map<String, Object?>> resolve(
    TenantContext scope,
    Map<String, Object?> request,
  ) => _rpc(scope, 'employee_staff_request_resolve', request);
}

final class EmployeeRequestsController extends ChangeNotifier {
  EmployeeRequestsController({
    required this.scope,
    required this.repository,
    required this.workforce,
    required Set<String> permissions,
    required this.online,
    bool monitor = true,
  }) : permissions = Set.unmodifiable(permissions) {
    kind = kinds.first;
    if (monitor) {
      _timer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(checkAccess()),
      );
    }
  }
  final TenantContext scope;
  final EmployeeRequestsRepository repository;
  final WorkforceRepository? workforce;
  final Set<String> permissions;
  Timer? _timer;
  bool _disposed = false, denied = false, busy = false, online;
  int _epoch = 0;
  late String kind;
  String? error, message, cursor, attendanceCursor;
  List<Map<String, Object?>> rows = [];
  List<AttendanceEntry> attendance = [];
  Map<String, Object?>? selected, pending;
  String? _pendingEmployeeId;
  bool _pendingCanonicalChanged = false;
  AttendanceEntry? canonical;
  List<String> get kinds => [
    if (permissions.contains('people.attendance.view')) 'attendance',
    if (permissions.contains('people.leave.view')) 'leave_cancel',
  ];
  bool get current => !_disposed && !denied;
  bool get locked => !current || !online || busy || pending != null;
  bool get canDecide => permissions.contains(
    kind == 'attendance' ? 'people.attendance.approve' : 'people.leave.approve',
  );
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _valid(int epoch) => current && online && _epoch == epoch;
  void _clear() {
    rows = [];
    selected = null;
    attendance = [];
    canonical = null;
    cursor = null;
    attendanceCursor = null;
  }

  void _dropPending() {
    pending = null;
    _pendingEmployeeId = null;
    _pendingCanonicalChanged = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _timer?.cancel();
    _clear();
    _dropPending();
    super.dispose();
  }

  void setOnline(bool value) {
    if (online == value) return;
    online = value;
    _epoch++;
    _clear();
    _notify();
  }

  void _scope(Map<String, Object?> row, {bool actor = true}) {
    if (row['tenant_id'] != scope.tenantId ||
        row['legal_entity_id'] != scope.legalEntityId ||
        row['branch_id'] != scope.branchId ||
        (actor && row['actor_id'] != scope.actorId)) {
      throw const FormatException('Employee request scope changed.');
    }
  }

  Future<void> _run(Future<void> Function(int) action) async {
    if (busy || !current || !online) return;
    final epoch = _epoch;
    busy = true;
    error = null;
    message = null;
    _notify();
    try {
      await action(epoch);
    } catch (failure) {
      if (!_valid(epoch)) return;
      final code = failure is DomainError ? failure.code : 'UNCERTAIN_RESULT';
      if ({
        'AUTHENTICATION_REQUIRED',
        'MFA_REQUIRED',
        'PERMISSION_DENIED',
      }.contains(code)) {
        denied = true;
        _epoch++;
        _dropPending();
        _clear();
      } else if ({
        'VERSION_CONFLICT',
        'VALIDATION_ERROR',
        'CANONICAL_RECORD_REQUIRED',
        'INDEPENDENT_REVIEW_REQUIRED',
      }.contains(code)) {
        _dropPending();
        _clear();
      } else if (pending == null) {
        _clear();
      }
      error = failure is FormatException
          ? 'The HR response could not be verified. Reload current access.'
          : employeeRequestError(code);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> _access() async {
    final result = await repository.access(scope, kind);
    calendarFields(result, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'actor_id',
      'authorized',
      'kind',
    });
    _scope(result);
    if (result['authorized'] != true || result['kind'] != kind) {
      throw const FormatException('Employee request access changed.');
    }
  }

  Future<void> checkAccess() => _run((_) => _access());
  Future<void> changeKind(String value) async {
    if (locked || !kinds.contains(value)) return;
    kind = value;
    _clear();
    await refresh();
  }

  Future<void> refresh({bool more = false}) => _run((epoch) async {
    if (pending != null) return;
    final after = more ? cursor : null;
    final page = await repository.page(scope, kind, after);
    calendarFields(page, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'actor_id',
      'kind',
      'items',
      'next_cursor',
    });
    _scope(page);
    final raw = page['items'];
    if (page['kind'] != kind || raw is! List || raw.length > 50) {
      throw const FormatException('Invalid request page.');
    }
    final result = <Map<String, Object?>>[];
    String? prior = after;
    for (final value in raw) {
      final row = hrMap(value);
      calendarFields(row, {
        'id',
        'kind',
        'employee_id',
        'employee_name',
        'version',
        'status',
        'reason',
        'created_at',
        if (kind == 'attendance') ...{
          'action',
          'entry_id',
          'source_version',
          'observed_at',
        } else ...{
          'source_id',
          'source_version',
          'source_status',
          'requested_source_version',
          'balance_version',
          'start_local',
          'end_local',
        },
      });
      final id = calendarUuid(row['id']);
      calendarUuid(row['employee_id']);
      if (prior != null && id.compareTo(prior) <= 0 ||
          row['kind'] != kind ||
          row['version'] != 1 ||
          row['employee_name'] is! String ||
          (row['employee_name']! as String).length > 200 ||
          row['reason'] is! String ||
          (row['reason']! as String).length > 1000 ||
          DateTime.tryParse(row['created_at'].toString()) == null) {
        throw const FormatException('Invalid employee request.');
      }
      if (kind == 'attendance') {
        if (!{'capture', 'correction'}.contains(row['action']) ||
            row['status'] != 'pending_evidence' ||
            DateTime.tryParse(row['observed_at'].toString()) == null) {
          throw const FormatException('Invalid attendance evidence.');
        }
        if (row['action'] == 'correction') {
          calendarUuid(row['entry_id']);
          _version(row['source_version']);
        }
      } else {
        calendarUuid(row['source_id']);
        _version(row['source_version']);
        _version(row['requested_source_version']);
        _version(row['balance_version'], zero: true);
        if (!{'approved', 'cancelled'}.contains(row['source_status']) ||
            row['status'] != 'cancellation_requested' ||
            DateTime.tryParse(row['start_local'].toString()) == null ||
            DateTime.tryParse(row['end_local'].toString()) == null) {
          throw const FormatException('Invalid cancellation request.');
        }
      }
      result.add(Map.unmodifiable(row));
      prior = id;
    }
    final next = page['next_cursor'];
    if (next != null && (calendarUuid(next) != prior || result.length != 50)) {
      throw const FormatException('Invalid request cursor.');
    }
    if (!_valid(epoch)) return;
    rows = [if (more) ...rows, ...result];
    cursor = next as String?;
    selected = null;
    attendance = [];
    canonical = null;
    attendanceCursor = null;
  });
  static int _version(Object? value, {bool zero = false}) {
    if (value is! int || value < (zero ? 0 : 1) || value > 9007199254740991) {
      throw const FormatException('Invalid version.');
    }
    return value;
  }

  Future<void> open(Map<String, Object?> row) => _run((epoch) async {
    if (pending != null || !rows.contains(row)) return;
    selected = null;
    canonical = null;
    attendance = [];
    attendanceCursor = null;
    await _access();
    if (!_valid(epoch)) return;
    selected = row;
    if (kind == 'attendance' && workforce != null) await _attendance(epoch);
  });
  Future<void> _attendance(int epoch, {bool more = false}) async {
    final row = selected;
    if (row == null || workforce == null) return;
    final page = await workforce!.attendance(
      scope,
      row['employee_id']! as String,
      after: more ? attendanceCursor : null,
    );
    final observed = DateTime.parse(row['observed_at']! as String);
    final matching = page.items.where((entry) {
      entry.assertScope(scope, row['employee_id']! as String);
      return entry.status == 'approved' &&
          !observed.isBefore(entry.revision.span.startUtc) &&
          !observed.isAfter(entry.revision.span.endUtc) &&
          (row['action'] != 'correction' ||
              entry.id == row['entry_id'] &&
                  entry.version > (row['source_version']! as int));
    });
    if (!_valid(epoch)) return;
    attendance = [if (more) ...attendance, ...matching];
    attendanceCursor = page.nextCursor;
  }

  Future<void> moreAttendance() => _run((epoch) async {
    if (pending == null) await _attendance(epoch, more: true);
  });
  void chooseAttendance(AttendanceEntry entry) {
    if (locked || !attendance.contains(entry)) return;
    canonical = entry;
    _notify();
  }

  Future<void> decide({required bool approve, required String reason}) => _run((
    epoch,
  ) async {
    final row = selected;
    if (pending != null || row == null || !canDecide) return;
    if (reason.trim().isEmpty ||
        reason.trim().length > 1000 ||
        approve && kind == 'attendance' && canonical == null) {
      throw const DomainError(code: 'VALIDATION_ERROR', message: '');
    }
    _pendingEmployeeId = row['employee_id']! as String;
    _pendingCanonicalChanged =
        approve && kind == 'leave_cancel' && row['source_status'] == 'approved';
    pending = Map.unmodifiable({
      'p_command_id': const Uuid().v4(),
      'p_kind': kind,
      'p_request_id': row['id'],
      'p_decision': approve ? 'resolved' : 'declined',
      'p_expected_version': row['version'],
      'p_canonical_id': !approve
          ? null
          : kind == 'attendance'
          ? canonical!.id
          : row['source_id'],
      'p_expected_canonical_version': !approve
          ? null
          : kind == 'attendance'
          ? canonical!.version
          : row['source_version'],
      'p_expected_balance_version': approve && kind == 'leave_cancel'
          ? row['balance_version']
          : null,
      'p_reason': reason.trim(),
    });
    await _send(epoch);
  });
  Future<void> retry() => _run(_send);
  Future<void> _send(int epoch) async {
    final request = pending;
    if (request == null) return;
    await _access();
    if (!_valid(epoch)) return;
    final response = await repository.resolve(scope, request);
    calendarFields(response, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'employee_id',
      'command_id',
      'request_id',
      'kind',
      'version',
      'status',
      'canonical_id',
      'canonical_version',
      'canonical_changed',
      'payable_time_changed',
    });
    _scope(response, actor: false);
    calendarUuid(response['employee_id']);
    if (response['employee_id'] != _pendingEmployeeId ||
        response['command_id'] != request['p_command_id'] ||
        response['request_id'] != request['p_request_id'] ||
        response['kind'] != request['p_kind'] ||
        response['version'] != 2 ||
        response['status'] != request['p_decision'] ||
        response['canonical_id'] != request['p_canonical_id'] ||
        response['canonical_changed'] != _pendingCanonicalChanged ||
        response['payable_time_changed'] != false) {
      throw const FormatException('Employee decision confirmation changed.');
    }
    if (request['p_decision'] == 'resolved') {
      final expectedCanonicalVersion =
          _version(request['p_expected_canonical_version']) +
          (_pendingCanonicalChanged ? 1 : 0);
      if (_version(response['canonical_version']) != expectedCanonicalVersion) {
        throw const FormatException('Canonical revision changed.');
      }
    } else if (response['canonical_version'] != null) {
      throw const FormatException(
        'Declined request changed a canonical record.',
      );
    }
    if (!_valid(epoch)) return;
    _dropPending();
    _clear();
    message = 'Decision confirmed. Reload to review the remaining requests.';
  }
}

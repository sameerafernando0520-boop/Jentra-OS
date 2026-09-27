import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_platform/jentra_people_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:uuid/uuid.dart';
import '../../app_providers.dart';
import 'employee_controller.dart';
import 'calendar_controller.dart';

ScopedCommandDraftStore organizationDrafts(
  EncryptedDraftRepository repository,
) => ScopedCommandDraftStore(
  repository,
  entityType: 'people.organization',
  fields: organizationPayloadFields,
  validate: validateOrganizationPayload,
  definiteFailures: {
    'VERSION_CONFLICT',
    'VALIDATION_ERROR',
    'ORGANIZATION_OVERLAP',
    'ORGANIZATION_ID_EXISTS',
    'ORGANIZATION_IMPACT_REQUIRED',
    'ORGANIZATION_CONSUMED_IMPACT_REQUIRED',
    'ORGANIZATION_FUTURE_WITHDRAWAL_REQUIRED',
  },
);
final organizationRepositoryProvider = Provider<OrganizationRepository?>(
  (ref) => null,
);
final organizationControllerProvider =
    Provider.autoDispose<OrganizationController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider);
      final repository = ref.watch(organizationRepositoryProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          repository == null ||
          caps.isLoading ||
          caps.hasError ||
          !{
            'people.view',
            'people.organization.view',
          }.every((p) => caps.value?.contains(p) ?? false)) {
        return null;
      }
      final c = OrganizationController(
        scope: scope,
        repository: repository,
        employees: ref.watch(employeeRepositoryProvider),
        calendars: ref.watch(calendarRepositoryProvider),
        drafts: organizationDrafts(ref.watch(encryptedDraftRepositoryProvider)),
        permissions: caps.value!,
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
      );
      ref.listen(
        connectivityStateProvider,
        (_, value) => c.setOnline(value.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

final class OrganizationController extends ChangeNotifier {
  OrganizationController({
    required this.scope,
    required this.repository,
    required this.employees,
    required this.calendars,
    required this.drafts,
    required Set<String> permissions,
    required this.online,
  }) : permissions = Set.unmodifiable(permissions);
  final TenantContext scope;
  final OrganizationRepository repository;
  final EmployeeRepository? employees;
  final WorkCalendarRepository? calendars;
  final ScopedCommandDraftStore drafts;
  final Set<String> permissions;
  static const uuid = Uuid();
  bool online, busy = false, accessDenied = false, _disposed = false;
  String asOfDate = DateTime.now().toIso8601String().substring(0, 10),
      search = '';
  String? error,
      message,
      departmentCursor,
      historyCursor,
      assignmentCursor,
      recoveryCursor;
  List<DepartmentEntry> departments = [];
  List<DepartmentRevision> history = [];
  List<OrganizationAssignment> assignments = [];
  List<ScopedCommandDraft> recovery = [];
  DepartmentEntry? selectedDepartment;
  EmployeeRecord? selectedEmployee;
  OrganizationEmployeeState? employeeState;
  Map<String, Object?>? form;
  String? action;
  int expectedVersion = 0;
  ScopedCommandDraft? local;
  int? comparedVersion;
  OrganizationConfirmation? confirmed;
  bool get current => !_disposed && !accessDenied;
  bool get canManage => permissions.contains('people.organization.manage');
  bool get canAssign =>
      canManage &&
      employees != null &&
      calendars != null &&
      permissions.contains('people.employees.view') &&
      permissions.contains('people.calendars.view');
  bool get conflict => local?.errorCode == 'VERSION_CONFLICT';
  bool get locked => busy || !current || local?.pending != null || conflict;
  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void setOnline(bool value) {
    online = value;
    _notify();
  }

  void _clear() {
    departments = [];
    history = [];
    assignments = [];
    recovery = [];
    selectedDepartment = null;
    selectedEmployee = null;
    employeeState = null;
    form = null;
    local = null;
    action = null;
    comparedVersion = null;
    confirmed = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _clear();
    super.dispose();
  }

  bool _denied(Object e) =>
      e is DomainError &&
      {
        'PERMISSION_DENIED',
        'FEATURE_NOT_ENTITLED',
        'AUTHENTICATION_REQUIRED',
      }.contains(e.code);
  Future<void> _run(Future<void> Function() work) async {
    if (_disposed || busy) {
      return;
    }
    busy = true;
    error = null;
    _notify();
    try {
      await work();
    } catch (e) {
      if (_denied(e)) {
        accessDenied = true;
        _clear();
      }
      error = e is DomainError
          ? e.message
          : e is FormatException
          ? e.message
          : 'Organization is unavailable. Encrypted work is retained.';
    } finally {
      busy = false;
      _notify();
    }
  }

  void _connected() {
    if (!online || !current) {
      throw const DomainError(
        code: 'OFFLINE',
        message: 'Connect with current organization access.',
      );
    }
  }

  Future<void> _refresh({bool more = false}) async {
    _connected();
    final page = await repository.departments(
      scope,
      CivilDate.parse(asOfDate),
      search: search,
      after: more ? departmentCursor : null,
    );
    if (_disposed) {
      return;
    }
    departments = [if (more) ...departments, ...page.items];
    departmentCursor = page.nextCursor;
  }

  Future<void> _recover({bool more = false}) async {
    if (!canManage || !current) {
      return;
    }
    final page = await drafts.page(scope, after: more ? recoveryCursor : null);
    if (_disposed) {
      return;
    }
    recovery = [if (more) ...recovery, ...page.items];
    recoveryCursor = page.nextCursor;
  }

  Future<void> initialize() => _run(() async {
    if (online) {
      await _refresh();
    }
    await _recover();
  });
  Future<void> refresh({bool more = false}) => _run(() => _refresh(more: more));
  Future<void> moreRecovery() => _run(() => _recover(more: true));
  Future<void> filter(String date, String query) => _run(() async {
    CivilDate.parse(date);
    if (query.length > 160) {
      throw const FormatException('Search is limited to 160 characters.');
    }
    asOfDate = date;
    search = query;
    history = [];
    selectedDepartment = null;
    assignments = [];
    selectedEmployee = null;
    employeeState = null;
    await _refresh();
  });
  Future<void> openDepartment(DepartmentEntry item, {bool more = false}) =>
      _run(() async {
        _connected();
        final page = await repository.departmentHistory(
          scope,
          item.id,
          after: more ? historyCursor : null,
        );
        if (_disposed) {
          return;
        }
        selectedDepartment = item;
        history = [if (more) ...history, ...page.items];
        historyCursor = page.nextCursor;
      });
  Future<List<Map<String, Object?>>> employeeChoices(
    String query,
    String date, {
    String? after,
  }) async {
    _connected();
    if (employees == null) {
      throw const DomainError(
        code: 'FEATURE_NOT_INSTALLED',
        message: 'Employee directory is unavailable.',
      );
    }
    final row = await employees!.directory(
      scope,
      asOfDate: date,
      search: query,
      after: after,
    );
    if (!current) {
      return [];
    }
    return (row['items'] as List)
        .map((e) => Map<String, Object?>.from(e as Map))
        .toList();
  }

  Future<void> openEmployee(String id, {bool more = false}) => _run(() async {
    _connected();
    if (employees == null) {
      return;
    }
    final detail = EmployeeRecord.fromJson(
      await employees!.detail(scope, id, asOfDate, 'employed'),
    );
    final state = await repository.employee(
      scope,
      id,
      CivilDate.parse(asOfDate),
      after: more ? assignmentCursor : null,
    );
    if (_disposed) {
      return;
    }
    selectedEmployee = detail;
    employeeState = state;
    assignments = [if (more) ...assignments, ...state.assignments.items];
    assignmentCursor = state.assignments.nextCursor;
  });
  Future<List<CalendarDirectoryEntry>> calendarChoices(
    String query,
    String date, {
    String? after,
  }) async {
    _connected();
    if (calendars == null) {
      return [];
    }
    final page = await calendars!.directory(
      scope,
      asOfDate: date,
      search: query,
      after: after,
    );
    return current
        ? page.page.items.where((e) => e.coverage != null).toList()
        : [];
  }

  void beginDepartment({bool revise = false}) {
    if (!canManage ||
        locked ||
        form != null ||
        revise && selectedDepartment == null) {
      return;
    }
    final d = selectedDepartment;
    action = revise ? 'department_revise' : 'department_create';
    expectedVersion = revise ? d!.version : 0;
    form = {
      'id': revise ? d!.id : uuid.v4(),
      'revision_id': uuid.v4(),
      if (!revise) 'code': '',
      'name': revise ? d!.name : '',
      'parent_id': revise ? d!.parentId : null,
      'start_date': revise ? d!.dates.start.value : asOfDate,
      'end_date_exclusive': revise ? d!.dates.endExclusive?.value : null,
      'reason': '',
      if (revise) 'replace_revision_id': d!.revisionId,
    };
    local = null;
    message = null;
    confirmed = null;
    comparedVersion = null;
    _notify();
  }

  void beginAssignment({
    OrganizationAssignment? replace,
    bool end = false,
    bool withdraw = false,
  }) {
    if (!canAssign ||
        locked ||
        form != null ||
        selectedEmployee == null ||
        employeeState == null) {
      return;
    }
    final e = selectedEmployee!;
    final a = replace;
    final spell = e.assignments
        .where(
          (row) => EmploymentInterval(
            row['start_date'] as String,
            row['end_date_exclusive'] as String?,
          ).contains(CivilDate.parse(asOfDate)),
        )
        .firstOrNull;
    if (a == null && spell == null) {
      error = 'Employment has no compatible interval on this date.';
      _notify();
      return;
    }
    action = withdraw
        ? 'withdraw_assignment'
        : end
        ? 'end_assignment'
        : a == null
        ? 'assign'
        : 'replace';
    expectedVersion = employeeState!.version;
    final start = a?.dates.start.value ?? asOfDate;
    form = {
      'id': uuid.v4(),
      'employee_id': e.id,
      'start_date': start,
      'end_date_exclusive':
          a?.dates.endExclusive?.value ??
          CivilDate.parse(start).utc
              .add(const Duration(days: 30))
              .toIso8601String()
              .substring(0, 10),
      'reason': '',
      if (a != null) 'replace_revision_id': a.id,
      if (!end && !withdraw) ...{
        'spell_id': a?.spellId ?? spell!['spell_id'],
        'department_id': a?.departmentId,
        'manager_id': a?.managerId,
        'calendar_version_id': a?.calendarVersionId,
        'role_title': a?.roleTitle ?? e.assignments.first['job_title'],
      },
    };
    local = null;
    message = null;
    confirmed = null;
    comparedVersion = null;
    _notify();
  }

  void edit(String key, Object? value) {
    if (form == null || locked || !canManage) {
      return;
    }
    if (!organizationPayloadFields(action!).contains(key)) {
      return;
    }
    form = {...form!, key: value};
    _notify();
  }

  Future<void> resume(ScopedCommandDraft draft) => _run(() async {
    if (!canManage || !current || form != null) {
      return;
    }
    final row = await drafts.load(scope, draft.aggregateId);
    if (_disposed || row == null) {
      return;
    }
    local = row;
    action = row.action;
    expectedVersion = row.version;
    form = Map.from(row.form);
    comparedVersion = null;
  });
  Future<void> save() => _run(() async {
    if (!canManage ||
        !current ||
        form == null ||
        local?.pending != null ||
        conflict) {
      return;
    }
    await drafts.save(
      scope,
      form!['id'] as String,
      action!,
      form!,
      expectedVersion,
    );
    if (_disposed) {
      return;
    }
    local = await drafts.load(scope, form!['id'] as String);
    await _recover();
    message = 'Encrypted organization draft saved.';
  });
  Future<void> discard() => _run(() async {
    if (!canManage || !current || form == null) {
      return;
    }
    await drafts.discard(scope, form!['id'] as String);
    if (_disposed) {
      return;
    }
    form = null;
    local = null;
    action = null;
    message = null;
    await _recover();
  });
  Future<bool> canLeave() async {
    if (!current || local?.pending != null || conflict) {
      return true;
    }
    if (busy) {
      return false;
    }
    if (form != null && canManage) {
      try {
        await drafts.save(
          scope,
          form!['id'] as String,
          action!,
          form!,
          expectedVersion,
        );
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  Future<void> compare() => _run(() async {
    _connected();
    if (!conflict || form == null) {
      return;
    }
    if (action!.startsWith('department_')) {
      final date = CivilDate.parse(form!['start_date'] as String);
      final d = await repository.department(scope, form!['id'] as String, date);
      final rows = await repository.departmentHistory(scope, d.id);
      if (_disposed) {
        return;
      }
      selectedDepartment = d;
      history = rows.items;
      comparedVersion = d.version;
    } else {
      final state = await repository.employee(
        scope,
        form!['employee_id'] as String,
        CivilDate.parse(form!['start_date'] as String),
      );
      if (_disposed) {
        return;
      }
      employeeState = state;
      assignments = state.assignments.items;
      comparedVersion = state.version;
    }
    message =
        'Current history loaded. Compare the dates and references before retaining these edits.';
  });
  Future<void> replaceConflict() => _run(() async {
    if (!canManage ||
        !current ||
        !conflict ||
        form == null ||
        comparedVersion == null ||
        comparedVersion! <= expectedVersion) {
      return;
    }
    if (action == 'department_revise') {
      final d = selectedDepartment!;
      final dates = OrganizationDates(
        form!['start_date'],
        form!['end_date_exclusive'],
      );
      if (dates.start.compareTo(d.dates.start) < 0 ||
          d.dates.endExclusive != null &&
              (dates.endExclusive == null ||
                  dates.endExclusive!.compareTo(d.dates.endExclusive!) > 0)) {
        throw const FormatException(
          'The compared department revision must cover all requested dates.',
        );
      }
      form = {...form!, 'replace_revision_id': d.revisionId};
    } else if ({
      'replace',
      'end_assignment',
      'withdraw_assignment',
    }.contains(action)) {
      if (!assignments.any(
        (a) => a.id == form!['replace_revision_id'] && a.active,
      )) {
        throw const FormatException(
          'The original revision was superseded. Discard this draft and select its current successor.',
        );
      }
    }
    await drafts.save(
      scope,
      form!['id'] as String,
      action!,
      form!,
      comparedVersion!,
      resolveConflict: true,
    );
    if (_disposed) {
      return;
    }
    expectedVersion = comparedVersion!;
    local = await drafts.load(scope, form!['id'] as String);
    comparedVersion = null;
    message =
        'Edits retained against the compared version. Review before confirming.';
  });
  Future<void> submit() => _run(() async {
    _connected();
    if (!canManage || form == null || conflict) {
      return;
    }
    final id = form!['id'] as String;
    final pending =
        local?.pending ??
        await drafts.prepare(scope, id, action!, form!, expectedVersion);
    final saved = await drafts.load(scope, id);
    if (!current) {
      return;
    }
    local = saved;
    _notify();
    OrganizationConfirmation result;
    try {
      result = await repository.execute(pending.action, pending.envelope);
    } on DomainError catch (e) {
      await drafts.recordFailure(scope, id, pending.envelope.commandId, e);
      if (!_disposed) {
        local = await drafts.load(scope, id);
      }
      rethrow;
    }
    if (_disposed) {
      return;
    }
    confirmed = result;
    message = 'Organization change confirmed.';
    try {
      await drafts.complete(scope, id, pending.envelope.commandId);
    } catch (_) {
      error =
          'The change is confirmed. Local cleanup needs a retry of the saved request.';
      return;
    }
    if (_disposed) {
      return;
    }
    form = null;
    local = null;
    action = null;
    try {
      await _refresh();
      await _recover();
      if (selectedEmployee != null) {
        final state = await repository.employee(
          scope,
          selectedEmployee!.id,
          CivilDate.parse(asOfDate),
        );
        if (!_disposed) {
          employeeState = state;
          assignments = state.assignments.items;
          assignmentCursor = state.assignments.nextCursor;
        }
      }
    } catch (e) {
      if (_denied(e)) {
        accessDenied = true;
        _clear();
      } else {
        error = 'The change is confirmed. Reload to refresh its history.';
      }
    }
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

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
import 'organization_controller.dart';

enum WorkforceView { attendance, leave, policies, rawEvents, workClaims }

final class WorkforceSavedDraft {
  const WorkforceSavedDraft(this.kind, this.draft);
  final WorkforceCommandKind kind;
  final ScopedCommandDraft draft;
}

String workforceCapability(WorkforceCommandKind kind, String action) =>
    switch (kind) {
      WorkforceCommandKind.attendance =>
        {'raw_import', 'raw_import_batch'}.contains(action)
            ? 'people.attendance.import'
            : {'approve', 'reject', 'cancel'}.contains(action)
            ? 'people.attendance.approve'
            : 'people.attendance.manage',
      WorkforceCommandKind.leavePolicy => 'people.leave.policy.manage',
      WorkforceCommandKind.leaveGrant =>
        action == 'adjust'
            ? 'people.leave.adjust'
            : 'people.leave.policy.manage',
      WorkforceCommandKind.leaveRequest =>
        {'approve', 'reject', 'cancel'}.contains(action)
            ? 'people.leave.approve'
            : 'people.leave.manage',
    };
ScopedCommandDraftStore workforceDrafts(
  EncryptedDraftRepository repository,
  WorkforceCommandKind kind,
) => ScopedCommandDraftStore(
  repository,
  entityType: 'people.workforce.${kind.name}',
  fields: (action) =>
      WorkforceCommands.fields[kind]?[action] ??
      (throw const FormatException('Workforce action is invalid.')),
  validate: (action, payload) =>
      WorkforceCommands.validate(kind, action, payload),
  definiteFailures: {
    'VERSION_CONFLICT',
    'VALIDATION_ERROR',
    'STATE_CONFLICT',
    'WORK_INTERVAL_CONFLICT',
    'LEAVE_BALANCE_INSUFFICIENT',
    'IDENTITY_EXISTS',
    'WORK_ALLOCATION_IMPACT_REQUIRED',
    'PAYROLL_INPUT_SEALED',
    'CLOCK_SOURCE_CONFLICT',
  },
);
final workforceRepositoryProvider = Provider<WorkforceRepository?>(
  (ref) => null,
);
final workforceControllerProvider = Provider.autoDispose<WorkforceController?>((
  ref,
) {
  final scope = ref.watch(activeTenantContextProvider);
  final caps = ref.watch(businessCapabilitiesProvider);
  final repository = ref.watch(workforceRepositoryProvider);
  if (scope == null ||
      !scope.hasOperationalScope ||
      repository == null ||
      caps.isLoading ||
      caps.hasError ||
      !(caps.value?.contains('people.view') ?? false) ||
      !{
        'people.attendance.view',
        'people.leave.view',
        'people.work_claims.view',
      }.any((p) => caps.value!.contains(p))) {
    return null;
  }
  final local = ref.watch(encryptedDraftRepositoryProvider);
  final c = WorkforceController(
    scope: scope,
    repository: repository,
    employees: ref.watch(employeeRepositoryProvider),
    organizations: ref.watch(organizationRepositoryProvider),
    calendars: ref.watch(calendarRepositoryProvider),
    drafts: {
      for (final kind in [
        WorkforceCommandKind.attendance,
        WorkforceCommandKind.leavePolicy,
        WorkforceCommandKind.leaveGrant,
      ])
        kind: workforceDrafts(local, kind),
    },
    leaveDrafts: SensitiveLeaveDraftStore(
      local,
      (s, id) => repository.authorize(s, id, 'people.leave.view'),
    ),
    permissions: caps.value!,
    online:
        ref.read(connectivityStateProvider).value == ConnectivityState.online,
  );
  ref.listen(
    connectivityStateProvider,
    (_, value) => c.setOnline(value.value == ConnectivityState.online),
  );
  ref.onDispose(c.dispose);
  unawaited(c.initialize());
  return c;
});

final class WorkforceController extends ChangeNotifier {
  WorkforceController({
    required this.scope,
    required this.repository,
    required this.employees,
    required this.organizations,
    required this.calendars,
    required this.drafts,
    required this.leaveDrafts,
    required Set<String> permissions,
    required this.online,
    DateTime Function()? clock,
    bool monitor = true,
    ClockImportFiles? clockFiles,
  }) : permissions = Set.unmodifiable(permissions),
       clockFiles = clockFiles ?? const NativeClockImportFiles(),
       clock = clock ?? (() => DateTime.now().toUtc()) {
    view = views.first;
    if (monitor) {
      _timer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(checkAccess()),
      );
    }
  }
  final TenantContext scope;
  final WorkforceRepository repository;
  final EmployeeRepository? employees;
  final OrganizationRepository? organizations;
  final WorkCalendarRepository? calendars;
  final Map<WorkforceCommandKind, ScopedCommandDraftStore> drafts;
  final SensitiveLeaveDraftStore leaveDrafts;
  final ClockImportFiles clockFiles;
  final Set<String> permissions;
  final DateTime Function() clock;
  static const _uuid = Uuid();
  Timer? _timer;
  bool online, busy = false, accessDenied = false, _disposed = false;
  late WorkforceView view;
  String asOfDate = DateTime.now().toIso8601String().substring(0, 10);
  String? error,
      message,
      employeeId,
      employeeName,
      cursor,
      historyCursor,
      policyCursor;
  OrganizationAssignment? assignment;
  CalendarDetail? assignedCalendar;
  List<AttendanceEntry> attendance = [];
  List<LeaveRequest> leave = [];
  List<LeavePolicy> policies = [];
  List<LeavePolicyVersion> policyHistory = [];
  List<RawClockEvent> rawEvents = [];
  List<RawClockBatch> clockBatches = [];
  List<ClockBatchLineage> clockLineage = [];
  RawClockBatch? selectedClockBatch;
  String? clockBatchCursor;
  int? clockLineageCursor;
  List<WorkClaim> workClaims = [];
  List<AttendanceHistoryEntry> attendanceHistory = [];
  List<LeaveHistoryEntry> leaveHistory = [];
  AttendanceEntry? selectedAttendance;
  LeaveRequest? selectedLeave;
  LeavePolicy? selectedPolicy;
  LeavePolicyVersion? selectedPolicyVersion;
  LeaveBalance? balance;
  List<LeaveGrantSource> balanceGrants = [];
  List<WorkforceSavedDraft> recovery = [];
  List<SensitiveLeaveRecovery> leaveRecovery = [];
  final recoveryCursors = <WorkforceCommandKind, String?>{};
  WorkforceCommandKind? kind;
  Map<String, Object?>? form, confirmed;
  int expectedVersion = 0;
  ScopedCommandDraft? local;
  SensitiveLeaveDraft? privateLocal;
  DateTime? _privateExpiry;
  int? comparedVersion;
  CalendarLocalResolution? startResolution, endResolution;
  bool get current => !_disposed && !accessDenied;
  bool has(String permission) => permissions.contains(permission);
  List<WorkforceView> get views => [
    if (has('people.attendance.view')) WorkforceView.attendance,
    if (has('people.leave.view')) WorkforceView.leave,
    if (has('people.leave.view')) WorkforceView.policies,
    if (has('people.attendance.view')) WorkforceView.rawEvents,
    if (has('people.work_claims.view')) WorkforceView.workClaims,
  ];
  String get viewCapability => switch (view) {
    WorkforceView.attendance ||
    WorkforceView.rawEvents => 'people.attendance.view',
    WorkforceView.workClaims => 'people.work_claims.view',
    _ => 'people.leave.view',
  };
  bool get conflict =>
      (local?.errorCode ?? privateLocal?.errorCode) == 'VERSION_CONFLICT';
  ScopedPendingCommand? get pending => local?.pending ?? privateLocal?.pending;
  bool get locked =>
      busy || !current || pending != null || conflict || confirmed != null;
  bool get canCreate =>
      employeeId != null &&
      assignment != null &&
      assignedCalendar != null &&
      has('people.employees.view') &&
      has('people.organization.view') &&
      has('people.calendars.view');
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void setOnline(bool value) {
    online = value;
    _notify();
  }

  void _clearForm() {
    form = null;
    local = null;
    privateLocal = null;
    kind = null;
    comparedVersion = null;
    confirmed = null;
    startResolution = null;
    endResolution = null;
    _privateExpiry = null;
  }

  void _clearEmployeeRecords() {
    attendance = [];
    leave = [];
    rawEvents = [];
    clockBatches = [];
    clockLineage = [];
    selectedClockBatch = null;
    clockBatchCursor = null;
    clockLineageCursor = null;
    workClaims = [];
    attendanceHistory = [];
    leaveHistory = [];
    selectedAttendance = null;
    selectedLeave = null;
    cursor = null;
    historyCursor = null;
    balance = null;
    balanceGrants = [];
  }

  void _clearVisible() {
    _clearForm();
    _clearEmployeeRecords();
    policies = [];
    policyHistory = [];
    recovery = [];
    leaveRecovery = [];
    selectedPolicy = null;
    selectedPolicyVersion = null;
    employeeId = null;
    employeeName = null;
    assignment = null;
    assignedCalendar = null;
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _timer?.cancel();
    _clearVisible();
    super.dispose();
  }

  bool _denied(Object e) =>
      e is DomainError &&
      {
        'PERMISSION_DENIED',
        'FEATURE_NOT_ENTITLED',
        'AUTHENTICATION_REQUIRED',
      }.contains(e.code);
  void _connected() {
    if (!online || !current) {
      throw const DomainError(
        code: 'OFFLINE',
        message: 'Connect with current workforce access.',
      );
    }
  }

  Future<void> _run(Future<void> Function() work) async {
    if (!current || busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      await work();
    } catch (e) {
      if (_denied(e)) {
        accessDenied = true;
        _clearVisible();
      }
      if (!_disposed) {
        error = e is DomainError
            ? e.message
            : e is FormatException
            ? e.message
            : 'Workforce is unavailable. Encrypted recovery is retained.';
      }
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> checkAccess() async {
    if (!current || busy) return;
    _expirePrivate();
    if (!online ||
        (employeeId == null && viewCapability != 'people.leave.view')) {
      return;
    }
    try {
      await repository.authorize(scope, employeeId, viewCapability);
    } catch (e) {
      if (_denied(e)) {
        accessDenied = true;
        _clearVisible();
        error = 'Workforce access changed.';
        _notify();
      }
    }
  }

  bool _expirePrivate() {
    if (_privateExpiry == null || _privateExpiry!.isAfter(clock())) {
      return false;
    }
    _clearForm();
    message = 'Private leave text expired. Reconcile its minimal receipt.';
    _notify();
    return true;
  }

  Future<void> initialize() => _run(() async {
    if (online && has('people.leave.view')) await _policies();
    await _recover();
  });
  Future<void> _policies({bool more = false}) async {
    _connected();
    final page = await repository.policies(
      scope,
      after: more ? policyCursor : null,
    );
    if (!current) return;
    policies = [if (more) ...policies, ...page.items];
    policyCursor = page.nextCursor;
  }

  Future<void> morePolicies() => _run(() => _policies(more: true));
  Future<void> _recover({WorkforceCommandKind? more}) async {
    final saved = <WorkforceSavedDraft>[if (more != null) ...recovery];
    for (final entry in drafts.entries) {
      if (more != null && entry.key != more) continue;
      if (!WorkforceCommands.fields[entry.key]!.keys.any(
        (a) => has(workforceCapability(entry.key, a)),
      )) {
        continue;
      }
      final page = await entry.value.page(
        scope,
        after: more == entry.key ? recoveryCursors[entry.key] : null,
      );
      if (!current) return;
      saved.addAll(
        page.items
            .where((d) => has(workforceCapability(entry.key, d.action)))
            .map((d) => WorkforceSavedDraft(entry.key, d)),
      );
      recoveryCursors[entry.key] = page.nextCursor;
    }
    if (!current) return;
    recovery = saved;
    if (online && has('people.leave.view')) {
      final rows = await leaveDrafts.recovery(scope);
      if (current) leaveRecovery = rows;
    }
  }

  Future<void> moreRecovery(WorkforceCommandKind kind) =>
      _run(() => _recover(more: kind));
  Future<List<Map<String, Object?>>> employeeChoices(
    String search, {
    String? after,
  }) async {
    _connected();
    if (employees == null || !has('people.employees.view')) return [];
    final row = await employees!.directory(
      scope,
      asOfDate: asOfDate,
      search: search,
      after: after,
    );
    if (!current) return [];
    return (row['items'] as List).map(workforceMap).toList();
  }

  Future<void> _employee(String id) async {
    _connected();
    calendarUuid(id);
    if (employees == null) {
      throw const DomainError(
        code: 'FEATURE_NOT_INSTALLED',
        message: 'Employee directory is unavailable.',
      );
    }
    final employee = EmployeeRecord.fromJson(
      await employees!.detail(scope, id, asOfDate, 'employed'),
    );
    if (!current) return;
    employeeId = id;
    employeeName = '${employee.displayName} · ${employee.code}';
    assignment = null;
    assignedCalendar = null;
    if (organizations == null || !has('people.organization.view')) return;
    String? after;
    var scanned = 0;
    do {
      final state = await organizations!.employee(
        scope,
        id,
        CivilDate.parse(asOfDate),
        after: after,
      );
      if (!current) return;
      assignment ??= state.current;
      after = state.assignments.nextCursor;
      scanned += state.assignments.items.length;
      if (scanned >= 2000 && after != null) {
        throw const DomainError(
          code: 'PAGE_LIMIT',
          message: 'Organization history exceeds its bounded scan.',
        );
      }
    } while (assignment == null && after != null);
    if (assignment == null ||
        calendars == null ||
        !has('people.calendars.view')) {
      return;
    }
    after = null;
    scanned = 0;
    do {
      final page = await calendars!.directory(
        scope,
        asOfDate: asOfDate,
        after: after,
      );
      if (!current) return;
      final match = page.page.items
          .where((r) => r.coverage?.id == assignment!.calendarVersionId)
          .firstOrNull;
      if (match != null) {
        final detail = await calendars!.detail(
          scope,
          match.calendar.id,
          assignment!.calendarVersionId,
        );
        if (current) assignedCalendar = detail;
        return;
      }
      after = page.page.nextCursor;
      scanned += page.page.items.length;
      if (scanned >= 2000 && after != null) {
        throw const DomainError(
          code: 'PAGE_LIMIT',
          message: 'Calendar directory exceeds its bounded scan.',
        );
      }
    } while (after != null);
  }

  Future<void> selectEmployee(String id) => _run(() async {
    if (!await canLeave()) return;
    if (!current) return;
    _clearForm();
    _clearEmployeeRecords();
    employeeId = null;
    employeeName = null;
    assignment = null;
    assignedCalendar = null;
    await _employee(id);
    if (!current) return;
    await _refresh();
  });
  Future<void> filterDate(String date) => _run(() async {
    CivilDate.parse(date);
    if (!await canLeave()) return;
    if (!current) return;
    asOfDate = date;
    _clearForm();
    _clearEmployeeRecords();
    assignment = null;
    assignedCalendar = null;
    selectedPolicy = null;
    selectedPolicyVersion = null;
    policyHistory = [];
    if (employeeId != null) await _employee(employeeId!);
    if (!current) return;
    await _refresh();
  });
  Future<void> changeView(WorkforceView next) => _run(() async {
    if (!views.contains(next) || !await canLeave()) return;
    _clearForm();
    view = next;
    cursor = null;
    historyCursor = null;
    await _refresh();
  });
  Future<void> _refresh({bool more = false}) async {
    _connected();
    if (view == WorkforceView.policies) {
      await _policies(more: more);
      return;
    }
    final id = employeeId;
    if (id == null) return;
    switch (view) {
      case WorkforceView.attendance:
        final page = await repository.attendance(
          scope,
          id,
          after: more ? cursor : null,
        );
        if (current) {
          attendance = [if (more) ...attendance, ...page.items];
          cursor = page.nextCursor;
        }
      case WorkforceView.leave:
        final page = await repository.leaveRequests(
          scope,
          id,
          after: more ? cursor : null,
        );
        if (current) {
          leave = [if (more) ...leave, ...page.items];
          cursor = page.nextCursor;
        }
      case WorkforceView.rawEvents:
        final page = await repository.rawEvents(
          scope,
          id,
          after: more ? cursor : null,
        );
        if (current) {
          rawEvents = [if (more) ...rawEvents, ...page.items];
          cursor = page.nextCursor;
        }
        if (!more) {
          final batches = await repository.clockBatches(scope, id);
          if (!current) return;
          clockBatches = batches.items;
          clockBatchCursor = batches.nextCursor;
          selectedClockBatch = null;
          clockLineage = [];
          clockLineageCursor = null;
        }
      case WorkforceView.workClaims:
        final page = await repository.workClaims(
          scope,
          id,
          after: more ? cursor : null,
        );
        if (current) {
          workClaims = [if (more) ...workClaims, ...page.items];
          cursor = page.nextCursor;
        }
      case WorkforceView.policies:
        break;
    }
  }

  Future<void> refresh({bool more = false}) => _run(() => _refresh(more: more));
  Future<void> moreClockBatches() => _run(() async {
    _connected();
    if (employeeId == null || clockBatchCursor == null) return;
    final page = await repository.clockBatches(
      scope,
      employeeId!,
      after: clockBatchCursor,
    );
    if (!current) return;
    clockBatches = [...clockBatches, ...page.items];
    clockBatchCursor = page.nextCursor;
  });
  Future<void> openClockBatch(String id, {bool more = false}) => _run(() async {
    _connected();
    if (employeeId == null) return;
    final detail = await repository.clockBatchDetail(
      scope,
      employeeId!,
      id,
      after: more ? clockLineageCursor ?? 0 : 0,
    );
    if (!current) return;
    selectedClockBatch = detail.batch;
    clockLineage = [if (more) ...clockLineage, ...detail.rows];
    clockLineageCursor = detail.nextPosition;
  });
  Future<void> selectPolicy(LeavePolicy policy) => _run(() async {
    _connected();
    selectedPolicy = policy;
    selectedPolicyVersion = null;
    policyHistory = [];
    balance = null;
    balanceGrants = [];
    String? after;
    var scanned = 0;
    do {
      final page = await repository.policyVersions(
        scope,
        policy.id,
        after: after,
      );
      if (!current) return;
      policyHistory = [...policyHistory, ...page.items];
      final matches = page.items.where(
        (v) => v.covers(CivilDate.parse(asOfDate)),
      );
      if (matches.isNotEmpty) {
        if (selectedPolicyVersion != null || matches.length != 1) {
          throw const FormatException(
            'Multiple leave policy versions cover this date.',
          );
        }
        selectedPolicyVersion = matches.single;
      }
      after = page.nextCursor;
      scanned += page.items.length;
      if (scanned >= 2000 && after != null) {
        throw const DomainError(
          code: 'PAGE_LIMIT',
          message: 'Policy history exceeds its bounded scan.',
        );
      }
    } while (after != null);
    if (employeeId != null) {
      final value = await repository.leaveBalance(
        scope,
        employeeId!,
        policy.id,
        CivilDate.parse(asOfDate),
      );
      if (current) {
        balance = value;
        balanceGrants = value.grants;
      }
    }
  });
  Future<void> openAttendance(String id, {bool more = false}) => _run(() async {
    _connected();
    final detail = await repository.attendanceDetail(
      scope,
      id,
      after: more ? historyCursor : null,
    );
    if (!current) return;
    if (detail.record.employeeId != employeeId) {
      throw const FormatException('Selected employee changed.');
    }
    selectedAttendance = detail.record;
    attendanceHistory = [
      if (more) ...attendanceHistory,
      ...detail.history.items,
    ];
    historyCursor = detail.history.nextCursor;
  });
  Future<void> openLeave(String id, {bool more = false}) => _run(() async {
    _connected();
    if (!more) {
      selectedLeave = null;
      leaveHistory = [];
      historyCursor = null;
    }
    // Balance and grants must belong to the request whose policy is being read.
    balance = null;
    balanceGrants = [];
    final detail = await repository.leaveDetail(
      scope,
      id,
      after: more ? historyCursor : null,
    );
    if (!current) return;
    if (detail.record.employeeId != employeeId) {
      throw const FormatException('Selected employee changed.');
    }
    selectedLeave = detail.record;
    leaveHistory = [if (more) ...leaveHistory, ...detail.history.items];
    historyCursor = detail.history.nextCursor;
    final value = await repository.leaveBalance(
      scope,
      employeeId!,
      detail.record.policyId,
      CivilDate.parse(asOfDate),
    );
    if (current) {
      balance = value;
      balanceGrants = value.grants;
    }
  });
  Future<void> moreBalance() => _run(() async {
    _connected();
    final currentBalance = balance;
    if (employeeId == null || currentBalance?.nextCursor == null) return;
    final value = await repository.leaveBalance(
      scope,
      employeeId!,
      currentBalance!.policyId,
      CivilDate.parse(asOfDate),
      after: currentBalance.nextCursor,
    );
    if (!current) return;
    if (value.accountVersion != currentBalance.accountVersion) {
      balance = null;
      balanceGrants = [];
      throw const DomainError(
        code: 'VERSION_CONFLICT',
        message: 'The balance changed while paging. Reload the policy balance.',
      );
    }
    balance = value;
    balanceGrants = [...balanceGrants, ...value.grants];
  });
  Map<String, Object?> _new(String action) => {
    'action': action,
    'id': _uuid.v4(),
    if (employeeId != null) 'employee_id': employeeId,
    'reason': '',
  };
  Future<void> begin(WorkforceCommandKind nextKind, String action) =>
      _run(() async {
        if (!has(workforceCapability(nextKind, action))) {
          throw const DomainError(
            code: 'PERMISSION_DENIED',
            message: 'This workforce action is unavailable.',
          );
        }
        if (!await canLeave()) return;
        _clearForm();
        kind = nextKind;
        expectedVersion = 0;
        final payload = _new(action);
        if (nextKind == WorkforceCommandKind.leavePolicy) {
          payload.remove('employee_id');
          payload.addAll({
            'version_id': _uuid.v4(),
            'code': '',
            'name': '',
            'start_date': asOfDate,
            'end_date_exclusive': CivilDate.parse(asOfDate).utc
                .add(const Duration(days: 365))
                .toIso8601String()
                .substring(0, 10),
            'unit': 'hours',
            'day_seconds': 28800,
            'accrual_frequency': 'monthly',
            'accrual_seconds': 28800,
            'carry_cap_seconds': 0,
            'expiry_days': 365,
            'eligible_types': ['permanent'],
            'allow_unpaid': false,
          });
        } else if (nextKind == WorkforceCommandKind.leaveGrant) {
          if (employeeId == null ||
              selectedPolicyVersion == null ||
              balance == null) {
            throw const FormatException(
              'Select an employee and a dated policy balance first.',
            );
          }
          expectedVersion = balance!.accountVersion;
          payload.addAll({
            'policy_version_id': selectedPolicyVersion!.id,
            if (action == 'accrue')
              'period_start': '${asOfDate.substring(0, 7)}-01',
            if (action == 'adjust') ...{
              'effective_date': asOfDate,
              'source_key': '',
              'seconds': 3600,
            },
            if (action == 'carry') 'boundary_date': asOfDate,
          });
        } else if (action == 'raw_import_batch') {
          if (employeeId == null) {
            throw const FormatException('Choose an employee.');
          }
          payload.remove('reason');
          payload.addAll({
            'source_system': 'Synthetic clock import',
            'records': <Object?>[],
            'manifest_digest': '',
          });
        } else if (action == 'raw_import') {
          if (employeeId == null) {
            throw const FormatException('Choose an employee.');
          }
          payload.remove('reason');
          payload.addAll({
            'source_system': 'Synthetic clock import',
            'source_key': '',
            'observed_utc': '',
            'checksum': '',
          });
        } else {
          if (!canCreate) {
            throw const FormatException(
              'Configure a dated employee organization and published calendar first.',
            );
          }
          if (nextKind == WorkforceCommandKind.leaveRequest &&
              selectedPolicyVersion == null) {
            throw const FormatException(
              'Choose a leave policy covering this date.',
            );
          }
          final day = CivilDate.parse(asOfDate);
          final slots = assignedCalendar!.version.pattern.weeklyIntervals.where(
            (slot) => slot.dayOfWeek == day.utc.weekday,
          );
          if (slots.isEmpty) {
            throw const FormatException(
              'No working slot is published for this date.',
            );
          }
          final slot = slots.first;
          String wall(int minute, int dayOffset) => day.utc
              .add(Duration(days: dayOffset, minutes: minute))
              .toIso8601String()
              .substring(0, 19);
          payload.addAll({
            'calendar_version_id': assignment!.calendarVersionId,
            'start_local': wall(slot.startMinute, 0),
            'end_local': wall(slot.endMinute, slot.endDayOffset),
            if (nextKind == WorkforceCommandKind.attendance)
              'breaks': <Object?>[],
            if (nextKind == WorkforceCommandKind.leaveRequest)
              'policy_version_id': selectedPolicyVersion!.id,
          });
        }
        form = payload;
        if (nextKind == WorkforceCommandKind.leaveRequest) {
          _privateExpiry = clock().add(const Duration(hours: 24));
        }
      });
  Future<void> transition(WorkforceCommandKind nextKind, String action) => _run(
    () async {
      if (!has(workforceCapability(nextKind, action))) {
        throw const DomainError(
          code: 'PERMISSION_DENIED',
          message: 'This decision is unavailable.',
        );
      }
      if (!await canLeave()) return;
      _clearForm();
      kind = nextKind;
      final id = nextKind == WorkforceCommandKind.attendance
          ? selectedAttendance?.id
          : selectedLeave?.id;
      final version = nextKind == WorkforceCommandKind.attendance
          ? selectedAttendance?.version
          : selectedLeave?.version;
      if (id == null || version == null || employeeId == null) {
        throw const FormatException('Open the current record first.');
      }
      expectedVersion = version;
      form = {
        'action': action,
        'id': id,
        'employee_id': employeeId,
        'reason': '',
        if (nextKind == WorkforceCommandKind.leaveRequest &&
            {'approve', 'cancel'}.contains(action))
          'balance_version': balance?.accountVersion,
      };
      if (nextKind == WorkforceCommandKind.attendance && action == 'correct') {
        final revision = selectedAttendance!.revision;
        form = {
          ...form!,
          'calendar_version_id': revision.calendarVersionId,
          'start_local': revision.startLocal,
          'end_local': revision.endLocal,
          'start_offset_seconds': revision.startOffsetSeconds,
          'end_offset_seconds': revision.endOffsetSeconds,
          'breaks': jsonDecode(jsonEncode(revision.breaks)),
        };
      }
      if (nextKind == WorkforceCommandKind.leaveRequest) {
        _privateExpiry = clock().add(const Duration(hours: 24));
      }
    },
  );
  Future<void> publishPolicy() => _run(() async {
    _connected();
    if (!has('people.leave.policy.manage') || selectedPolicy == null) {
      throw const FormatException('Select a policy with revision permission.');
    }
    if (!await canLeave()) return;
    _clearForm();
    kind = WorkforceCommandKind.leavePolicy;
    final policy = selectedPolicy!, prior = policy.latest;
    expectedVersion = policy.version;
    form = {
      'action': 'publish',
      'id': policy.id,
      'version_id': _uuid.v4(),
      'start_date': prior.endExclusive.value,
      'end_date_exclusive': prior.endExclusive.utc
          .add(const Duration(days: 365))
          .toIso8601String()
          .substring(0, 10),
      'unit': prior.unit,
      'day_seconds': prior.daySeconds,
      'accrual_frequency': prior.accrualFrequency,
      'accrual_seconds': prior.accrualSeconds,
      'carry_cap_seconds': prior.carryCapSeconds,
      'expiry_days': prior.expiryDays,
      'eligible_types': [...prior.eligibleTypes],
      'allow_unpaid': prior.allowUnpaid,
      'reason': '',
    };
  });
  void setField(String key, Object? value) {
    if (_expirePrivate() || locked || form == null) return;
    form = {...form!, key: value};
    if (form!['action'] == 'raw_import_batch' && key == 'source_system') {
      form!['records'] = <Object?>[];
      form!['manifest_digest'] = '';
    }
    if (form!['action'] == 'raw_import' &&
        {'source_system', 'source_key', 'observed_utc'}.contains(key)) {
      form!['checksum'] = '';
    }
    if (key == 'start_local') {
      startResolution = null;
      form!.remove('start_offset_seconds');
    }
    if (key == 'end_local') {
      endResolution = null;
      form!.remove('end_offset_seconds');
    }
    _notify();
  }

  Future<void> checksumRawEvent() => _run(() async {
    if (kind != WorkforceCommandKind.attendance ||
        form?['action'] != 'raw_import' ||
        pending != null) {
      return;
    }
    final snapshot = [
      scope.tenantId,
      scope.legalEntityId,
      scope.branchId,
      form!['employee_id'],
      workforceText(form!['source_system'], 80),
      workforceText(form!['source_key'], 160),
      parseWorkUtc(form!['observed_utc'] as String).toIso8601String(),
    ];
    final hash = await Sha256().hash(utf8.encode(jsonEncode(snapshot)));
    if (current) {
      form = {
        ...form!,
        'checksum': hash.bytes
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join(),
      };
    }
  });
  Future<void> chooseClockFile() => _run(() async {
    if (pending != null ||
        conflict ||
        confirmed != null ||
        kind != WorkforceCommandKind.attendance ||
        form?['action'] != 'raw_import_batch') {
      return;
    }
    final employee = form!['employee_id'] as String;
    final source = clockSourceText(form!['source_system'], 80);
    await repository.authorize(scope, employee, 'people.attendance.import');
    if (!current) return;
    final csv = await clockFiles.chooseCsv();
    if (csv == null || !current) return;
    final batch = await prepareClockBatch(scope, employee, source, csv);
    await repository.authorize(scope, employee, 'people.attendance.import');
    if (!current) return;
    // Preserve the editor aggregate ID and exact event IDs until submission/retry.
    form = {...batch, 'id': form!['id']};
    message =
        '${(batch['records'] as List).length} raw clock events ready for review. No payable time was created.';
  });

  Future<void> resolveTimes() => _run(() async {
    _connected();
    final version = assignedCalendar?.version;
    final resolver = calendars;
    if (version == null ||
        resolver is! CalendarInstantResolver ||
        form == null) {
      throw const FormatException('A published assigned calendar is required.');
    }
    final start = workforceLocalTime(form!['start_local']),
        end = workforceLocalTime(form!['end_local']);
    if (start.second != 0 || end.second != 0) {
      throw const FormatException('The time picker uses whole minutes.');
    }
    final a = await (resolver as CalendarInstantResolver).localCandidates(
      scope,
      version,
      CivilDate.parse(form!['start_local'].toString().substring(0, 10)),
      start.hour * 60 + start.minute,
    );
    final b = await (resolver as CalendarInstantResolver).localCandidates(
      scope,
      version,
      CivilDate.parse(form!['end_local'].toString().substring(0, 10)),
      end.hour * 60 + end.minute,
    );
    if (!current) return;
    startResolution = a;
    endResolution = b;
    if (a.candidates.length == 1) {
      form = {
        ...form!,
        'start_offset_seconds': a.candidates.single.offsetSeconds,
      };
    }
    if (b.candidates.length == 1) {
      form = {
        ...form!,
        'end_offset_seconds': b.candidates.single.offsetSeconds,
      };
    }
  });
  Future<void> saveLocal() => _run(_save);
  Future<void> _save({bool compared = false}) async {
    if (_expirePrivate()) return;
    if (form == null || kind == null || pending != null || confirmed != null) {
      return;
    }
    final id = form!['id'] as String, action = form!['action'] as String;
    if (kind == WorkforceCommandKind.leaveRequest) {
      await leaveDrafts.save(
        scope,
        form!['employee_id'] as String,
        id,
        action,
        form!,
        expectedVersion,
        compared: compared,
      );
      privateLocal = await leaveDrafts.load(
        scope,
        form!['employee_id'] as String,
        id,
      );
      _privateExpiry = privateLocal?.expiresAt;
    } else {
      await drafts[kind]!.save(
        scope,
        id,
        action,
        form!,
        expectedVersion,
        resolveConflict: compared,
      );
      local = await drafts[kind]!.load(scope, id);
    }
    if (current) message = 'Encrypted draft saved.';
  }

  Future<bool> canLeave() async {
    try {
      await _save();
      return true;
    } catch (e) {
      if (current) {
        error = e is DomainError
            ? e.message
            : 'Save or resolve the workforce draft before leaving.';
      }
      _notify();
      return false;
    }
  }

  Future<void> submit() => _run(() async {
    if (_expirePrivate()) {
      throw const DomainError(
        code: 'PRIVATE_DRAFT_EXPIRED',
        message: 'The private text expired. Reconcile its minimal receipt.',
      );
    }
    _connected();
    if (form == null || kind == null || confirmed != null) return;
    final activeKind = kind!,
        id = form!['id'] as String,
        action = form!['action'] as String;
    if (!has(workforceCapability(activeKind, action))) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Current action permission is required.',
      );
    }
    final employee = form!['employee_id'] as String?;
    final request = activeKind == WorkforceCommandKind.leaveRequest
        ? await leaveDrafts.prepare(
            scope,
            employee!,
            id,
            action,
            form!,
            expectedVersion,
          )
        : await drafts[activeKind]!.prepare(
            scope,
            id,
            action,
            form!,
            expectedVersion,
          );
    if (activeKind == WorkforceCommandKind.leaveRequest) {
      privateLocal = await leaveDrafts.load(scope, employee!, id);
    } else {
      local = await drafts[activeKind]!.load(scope, id);
    }
    try {
      final result = await repository.execute(activeKind, request.envelope);
      if (!current) return;
      confirmed = result;
      message = 'Command confirmed. Refreshing the workspace…';
      if (activeKind == WorkforceCommandKind.leaveRequest) {
        await leaveDrafts.complete(
          scope,
          employee!,
          id,
          request.envelope.commandId,
        );
      } else {
        await drafts[activeKind]!.complete(
          scope,
          id,
          request.envelope.commandId,
        );
      }
      if (!current) return;
      form = null;
      local = null;
      privateLocal = null;
      _privateExpiry = null;
      try {
        await _refresh();
        await _recover();
      } catch (e) {
        if (_denied(e)) rethrow;
        if (current) message = 'Command confirmed. The optional refresh is unavailable; reload when connected.';
      }
    } on DomainError catch (e) {
      if (confirmed == null) {
        try {
          if (activeKind == WorkforceCommandKind.leaveRequest) {
            await leaveDrafts.failure(
              scope,
              employee!,
              id,
              request.envelope.commandId,
              e,
            );
            privateLocal = await leaveDrafts.load(scope, employee, id);
          } else {
            await drafts[activeKind]!.recordFailure(
              scope,
              id,
              request.envelope.commandId,
              e,
            );
            local = await drafts[activeKind]!.load(scope, id);
          }
        } catch (_) {}
      }
      rethrow;
    }
  });
  Future<void> resume(WorkforceSavedDraft saved) => _run(() async {
    if (!await canLeave()) return;
    _clearForm();
    if (!has(workforceCapability(saved.kind, saved.draft.action))) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Recovery access changed.',
      );
    }
    final draft = await drafts[saved.kind]!.load(
      scope,
      saved.draft.aggregateId,
    );
    if (!current || draft == null) return;
    kind = saved.kind;
    local = draft;
    form = workforceMap(
      jsonDecode(jsonEncode(draft.pending?.envelope.payload ?? draft.form)),
    );
    expectedVersion = draft.version;
    if (form!['employee_id'] != null) {
      await _recoveryEmployee(form!['employee_id'] as String);
    }
  });
  Future<void> resumeLeave(SensitiveLeaveRecovery saved) => _run(() async {
    _connected();
    if (!await canLeave()) return;
    _clearForm();
    if (saved.expired) {
      final resolved = await leaveDrafts.reconcileExpired(
        scope,
        saved.employeeId,
        saved.id,
        repository,
      );
      if (current) message = resolved ? 'Expired request outcome reconciled.' : 'No confirmed outcome is available. Keep this recovery entry for reconciliation.';
      await _recover();
      return;
    }
    final draft = await leaveDrafts.load(scope, saved.employeeId, saved.id);
    if (!current || draft == null) return;
    kind = WorkforceCommandKind.leaveRequest;
    privateLocal = draft;
    form = draft.pending?.envelope.payload ?? draft.form;
    expectedVersion = draft.version;
    _privateExpiry = draft.expiresAt;
    await _recoveryEmployee(saved.employeeId);
  });
  Future<void> _recoveryEmployee(String id) async {
    if (employeeId != id) {
      employeeName = null;
      assignment = null;
      assignedCalendar = null;
    }
    employeeId = id;
    if (employees != null && has('people.employees.view')) await _employee(id);
  }

  Future<void> compareConflict() => _run(() async {
    _connected();
    if (!conflict || form == null || kind == null) return;
    final id = form!['id'] as String;
    if (kind == WorkforceCommandKind.attendance) {
      final detail = await repository.attendanceDetail(scope, id);
      if (current) {
        selectedAttendance = detail.record;
        comparedVersion = detail.record.version;
      }
    } else if (kind == WorkforceCommandKind.leaveRequest) {
      final detail = await repository.leaveDetail(scope, id);
      if (current) {
        selectedLeave = detail.record;
        comparedVersion = detail.record.version;
      }
    } else if (kind == WorkforceCommandKind.leaveGrant && employeeId != null) {
      final policy = await repository.policyForVersion(
        scope,
        form!['policy_version_id'] as String,
      );
      if (!current) return;
      selectedPolicy = policy;
      final value = await repository.leaveBalance(
        scope,
        employeeId!,
        policy.id,
        CivilDate.parse(asOfDate),
      );
      if (current) {
        balance = value;
        balanceGrants = value.grants;
        comparedVersion = value.accountVersion;
      }
    } else if (kind == WorkforceCommandKind.leavePolicy) {
      String? after;
      var scanned = 0;
      do {
        final page = await repository.policies(scope, after: after);
        if (!current) return;
        final match = page.items.where((row) => row.id == id).firstOrNull;
        if (match != null) {
          selectedPolicy = match;
          comparedVersion = match.version;
          return;
        }
        after = page.nextCursor;
        scanned += page.items.length;
        if (scanned >= 2000) {
          throw const FormatException(
            'Policy comparison exceeds its bounded scan.',
          );
        }
      } while (after != null);
    }
  });
  Future<void> replaceConflict() => _run(() async {
    if (!conflict || comparedVersion == null) return;
    expectedVersion = comparedVersion!;
    await _save(compared: true);
    comparedVersion = null;
  });
  Future<void> discard() => _run(() async {
    if (form == null || kind == null) return;
    final id = form!['id'] as String;
    if (kind == WorkforceCommandKind.leaveRequest) {
      await leaveDrafts.discard(scope, form!['employee_id'] as String, id);
    } else {
      await drafts[kind]!.discard(scope, id);
    }
    if (current) _clearForm();
    await _recover();
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_domain/jentra_projects.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_projects_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';

const projectActions = {
  'create',
  'plan',
  'approve_plan',
  'reject_plan',
  'progress',
  'close',
  'waive',
  'time_create',
  'time_correct',
  'time_submit',
  'time_approve',
  'time_reject',
  'time_cancel',
};
const projectDefiniteFailures = {
  'VERSION_CONFLICT',
  'VALIDATION_ERROR',
  'STATE_CONFLICT',
  'IDENTITY_EXISTS',
  'PROJECT_TASK_CYCLE',
  'WORK_INTERVAL_CONFLICT',
  'PROJECT_RESOURCE_CAPACITY_CONFLICT',
  'PAYROLL_INPUT_SEALED',
  'IDEMPOTENCY_MISMATCH',
};
ScopedCommandDraftStore projectDrafts(
  EncryptedDraftRepository encrypted,
  String action,
) => ScopedCommandDraftStore(
  encrypted,
  entityType: 'projects.command.$action',
  fields: ProjectCommands.fields,
  validate: (a, p) {
    if (p['action'] != a) {
      throw const FormatException('Project draft action changed.');
    }
    ProjectCommands.validate(p, p['currency_code'] as String? ?? 'XXX', 6);
  },
  definiteFailures: projectDefiniteFailures,
);
final projectsRepositoryProvider = Provider<ProjectRepository?>((ref) => null);
final projectsControllerProvider = Provider.autoDispose<ProjectsController?>((
  ref,
) {
  final scope = ref.watch(activeTenantContextProvider),
      caps = ref.watch(businessCapabilitiesProvider),
      repository = ref.watch(projectsRepositoryProvider);
  if (scope == null ||
      !scope.hasOperationalScope ||
      repository == null ||
      caps.isLoading ||
      caps.hasError ||
      !(caps.value?.contains('projects.view') ?? false)) {
    return null;
  }
  final encrypted = ref.watch(encryptedDraftRepositoryProvider);
  final controller = ProjectsController(
    scope: scope,
    repository: repository,
    drafts: {for (final a in projectActions) a: projectDrafts(encrypted, a)},
    permissions: caps.value!,
    online:
        ref.read(connectivityStateProvider).value == ConnectivityState.online,
  );
  ref.listen(
    connectivityStateProvider,
    (_, v) => controller.setOnline(v.value == ConnectivityState.online),
  );
  ref.onDispose(controller.dispose);
  unawaited(controller.initialize());
  return controller;
});

final class ProjectSavedDraft {
  const ProjectSavedDraft(this.action, this.draft);
  final String action;
  final ScopedCommandDraft draft;
}

final class ProjectPlanReview {
  const ProjectPlanReview(
    this.projectVersion,
    this.plan,
    this.tasks,
    this.resources,
    this.budget,
    this.rates,
  );
  final int projectVersion;
  final ProjectPlan plan;
  final List<ProjectTask> tasks;
  final List<ProjectResource> resources;
  final ProjectBudget budget;
  final List<ProjectResourceCost> rates;
}

final class ProjectsController extends ChangeNotifier {
  ProjectsController({
    required this.scope,
    required this.repository,
    required this.drafts,
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
  final ProjectRepository repository;
  final Map<String, ScopedCommandDraftStore> drafts;
  final Set<String> permissions;
  static const _uuid = Uuid();
  Timer? _timer;
  bool online,
      busy = false,
      denied = false,
      _disposed = false,
      _sending = false;
  int _epoch = 0;
  ProjectProviderState? providers;
  List<ProjectRecord> records = [];
  List<ProjectSavedDraft> recovery = [];
  String? cursor, error, message;
  ProjectRecord? selected;
  ProjectSection section = ProjectSection.plans;
  List<ProjectRow> rows = [];
  String? next;
  String? parentId;
  Map<String, Object?>? form, confirmed;
  ScopedCommandDraft? local;
  ProjectDetail? comparison;
  ProjectPlanReview? planReview;
  int expectedVersion = 0;
  final labels = <String, String>{};
  final recoveryCursors = <String, String?>{};
  bool get current => !_disposed && !denied;
  bool has(String c) => permissions.contains(c);
  String? get action => form?['action'] as String?;
  ScopedPendingCommand? get pending => local?.pending;
  bool get conflict => local?.errorCode == 'VERSION_CONFLICT';
  bool get locked =>
      busy || !current || pending != null || conflict || confirmed != null;
  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void setOnline(bool v) {
    if (online == v) {
      return;
    }
    _epoch++;
    online = v;
    _notify();
  }

  void _clearForm() {
    _epoch++;
    form = null;
    local = null;
    confirmed = null;
    comparison = null;
    planReview = null;
    expectedVersion = 0;
    labels.clear();
  }

  void _deny(DomainError cause) {
    denied = true;
    _clearForm();
    records = [];
    rows = [];
    recovery = [];
    selected = null;
    providers = null;
    cursor = null;
    next = null;
    parentId = null;
    recoveryCursors.clear();
    error = cause.code == 'FEATURE_NOT_ENTITLED'
        ? 'Projects is not enabled for this business. Ask your administrator to review module availability.'
        : 'Project access changed. Select an authorized scope.';
    message = null;
    _notify();
  }

  void _connected() {
    if (!online) {
      throw const DomainError(
        code: 'OFFLINE',
        message: 'Connect before checking or sending project commands.',
      );
    }
  }

  bool _revoked(DomainError e) => {
    'PERMISSION_DENIED',
    'AUTHENTICATION_REQUIRED',
    'FEATURE_NOT_ENTITLED',
    'MFA_REQUIRED',
    'ACCESS_DENIED',
  }.contains(e.code);
  Future<void> _access(String cap) async {
    final epoch = _epoch;
    _connected();
    if (!has(cap)) {
      throw const DomainError(
        code: 'ACTION_NOT_PERMITTED',
        message: 'This project action needs its current capability.',
      );
    }
    try {
      final state = await repository.authorize(scope, cap);
      if (!current || epoch != _epoch || !online) {
        throw const DomainError(
          code: 'ACCESS_RECHECK_REQUIRED',
          message: 'Connection changed. Refresh current project authority.',
        );
      }
      if (current) {
        providers = state;
      }
    } on DomainError catch (e) {
      if (!current || epoch != _epoch || !online) {
        throw const DomainError(
          code: 'ACCESS_RECHECK_REQUIRED',
          message: 'Connection changed. Refresh current project authority.',
        );
      }
      if (_revoked(e) && current) {
        _deny(e);
      }
      rethrow;
    }
  }

  Future<void> _actionAccess(String a) async {
    await _access(ProjectCommands.capability(a));
    if (!current) {
      return;
    }
    if (a == 'plan') {
      await _access('projects.cost.manage');
    }
    if ({'approve_plan', 'reject_plan'}.contains(a)) {
      await _access('projects.cost.view');
    }
  }

  Future<void> _run(Future<void> Function() f) async {
    if (busy || !current) {
      return;
    }
    busy = true;
    error = null;
    _notify();
    try {
      await f();
    } on DomainError catch (e) {
      if (_revoked(e)) {
        _deny(e);
      } else if (current) {
        error = e.message;
      }
    } catch (_) {
      if (current) {
        error = 'The project source or form could not be verified. Check its named inputs and scoped history.';
      }
    } finally {
      if (!_disposed) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> checkAccess() async {
    if (!current || busy || !online) {
      return;
    }
    try {
      await _access('projects.view');
      if (section.privateCost) {
        await _access('projects.cost.view');
      }
      if (action != null) {
        await _actionAccess(action!);
      }
      // Recovery pages retain decrypted forms independently of the open editor.
      // Recheck each resident action before keeping its private fields in memory.
      for (final a in recovery.map((d) => d.action).toSet()) {
        await _actionAccess(a);
        if (!current) {
          return;
        }
      }
      if (planReview != null) {
        await _access('projects.cost.view');
      }
    } on DomainError catch (e) {
      if (_revoked(e)) {
        _deny(e);
      }
    } catch (_) {
      /* Failed reads provide no new authority. */
    }
  }

  Future<void> initialize() => _run(() async {
    await _access('projects.view');
    if (current) {
      await _directory();
    }
    if (current) {
      await _recover();
    }
  });
  Future<void> _directory({bool more = false}) async {
    final epoch = _epoch;
    _connected();
    final page = await repository.directory(scope, after: more ? cursor : null);
    if (current && epoch == _epoch && online) {
      records = [if (more) ...records, ...page.rows];
      cursor = page.next;
    }
  }

  Future<void> refresh() => _run(() async {
    await _access('projects.view');
    if (current) {
      await _directory();
    }
  });
  Future<void> more() => _run(() async {
    await _access('projects.view');
    if (current) {
      await _directory(more: true);
    }
  });
  Future<void> _detail(
    String id,
    ProjectSection kind, {
    String? parent,
    bool more = false,
  }) async {
    final epoch = _epoch;
    if (kind.privateCost) {
      await _access('projects.cost.view');
    } else {
      await _access('projects.view');
    }
    if (!current) {
      return;
    }
    final page = await repository.detail(
      scope,
      id,
      kind,
      parentId: parent,
      after: more ? next : null,
    );
    if (current && epoch == _epoch && online) {
      selected = page.project;
      section = kind;
      parentId = parent;
      rows = [if (more) ...rows, ...page.rows];
      next = page.next;
    }
  }

  Future<void> select(String id) => _run(() async {
    if (pending != null || conflict || confirmed != null) {
      throw const DomainError(
        code: 'COMMAND_PENDING',
        message: 'Resolve the original saved request before selecting another project.',
      );
    }
    await _save();
    if (current) {
      _clearForm();
      await _detail(id, ProjectSection.plans);
    }
  });
  Future<void> show(ProjectSection kind, {String? parent}) => _run(() async {
    if (selected != null) {
      await _detail(selected!.id, kind, parent: parent);
    }
  });
  Future<void> moreDetail() => _run(() async {
    if (selected != null) {
      await _detail(selected!.id, section, parent: parentId, more: true);
    }
  });
  Future<ProjectPage<ProjectChoice>> choices(
    String kind, {
    String? after,
  }) async {
    final epoch = _epoch;
    await _access('projects.view');
    final p = await repository.choices(scope, kind, after: after);
    if (!current || epoch != _epoch) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Project scope or form changed.',
      );
    }
    return p;
  }

  Future<ProjectLocalResolution> resolve(
    CalendarCoverage version,
    String local,
  ) async {
    final epoch = _epoch;
    await _access('projects.view');
    final l = workforceLocalTime(local);
    final result = await repository.localCandidates(
      scope,
      version,
      CivilDate.parse(local.substring(0, 10)),
      l.hour * 60 + l.minute,
      second: l.second,
    );
    if (!current || epoch != _epoch) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Project scope or form changed.',
      );
    }
    return result;
  }

  Future<ProjectPage<ProjectAttendanceClaim>> claims(
    String employee, {
    String? after,
  }) async {
    final epoch = _epoch;
    await _access('projects.time.manage');
    final p = await repository.attendanceClaims(scope, employee, after: after);
    if (!current || epoch != _epoch) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Project scope or form changed.',
      );
    }
    return p;
  }

  Future<void> begin(
    String a, {
    ProjectPlan? plan,
    ProjectTask? task,
    ProjectResource? resource,
    ProjectTime? time,
    ProjectUnit? unit,
  }) => _run(() async {
    if (pending != null || conflict || confirmed != null) {
      throw const DomainError(
        code: 'COMMAND_PENDING',
        message:
            'Resolve the current saved request before starting another form.',
      );
    }
    await _save();
    await _actionAccess(a);
    if (!current) {
      return;
    }
    final r = selected;
    final payload = <String, Object?>{
      'action': a,
      'id': a == 'create' || a == 'time_create'
          ? _uuid.v4()
          : a.startsWith('time_')
          ? time?.id
          : r?.id,
      'reason': '',
    };
    int version = a == 'create' || a == 'time_create'
        ? 0
        : a.startsWith('time_')
        ? time?.version ?? -1
        : r?.version ?? -1;
    if (a != 'create' && r == null || version < 0) {
      throw const FormatException('Select the current project or time source.');
    }
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    switch (a) {
      case 'create':
        payload.addAll({
          'code': '',
          'name': '',
          'customer_id': null,
          'manager_id': null,
          'currency_code': providers!.currency,
          'start_date': today,
          'end_date_exclusive': CivilDate.parse(today).utc
              .add(const Duration(days: 1))
              .toIso8601String()
              .substring(0, 10),
        });
      case 'plan':
        payload.addAll({
          'plan_id': _uuid.v4(),
          'terms': '',
          'budget': '0',
          'tasks': <Object?>[],
          'resources': <Object?>[],
        });
      case 'approve_plan':
      case 'reject_plan':
        if (plan == null || plan.status != 'pending') {
          throw const FormatException('Select the exact pending plan.');
        }
        payload.addAll({'plan_id': plan.id, 'digest': plan.digest});
      case 'progress':
        if (task == null) {
          throw const FormatException('Select the current task.');
        }
        payload.addAll({
          'task_id': task.id,
          'progress': task.basis.progressBasisPoints,
        });
      case 'waive':
        if (unit == null || unit.status != 'available') {
          throw const FormatException(
            'Select an available whole billing unit.',
          );
        }
        payload['unit_id'] = unit.id;
      case 'time_create':
        if (resource == null || !resource.active) {
          throw const FormatException(
            'Select an approved named resource reservation.',
          );
        }
        payload.addAll({
          'project_id': r!.id,
          'employee_id': resource.employeeId,
          'resource_slot_id': resource.id,
          'start_local': resource.startLocal,
          'end_local': resource.endLocal,
          'start_offset_seconds': resource.startOffset,
          'end_offset_seconds': resource.endOffset,
          'breaks': <Object?>[],
          'attendance_claim_id': null,
        });
      case 'time_correct':
        if (time == null || !{'draft', 'rejected'}.contains(time.status)) {
          throw const FormatException(
            'Select an editable unconsumed time revision.',
          );
        }
        payload.addAll({
          'project_id': r!.id,
          'employee_id': time.employeeId,
          'resource_slot_id': time.resourceId,
          'start_local': time.startLocal,
          'end_local': time.endLocal,
          'start_offset_seconds': time.startOffset,
          'end_offset_seconds': time.endOffset,
          'breaks': time.work.breaks
              .map(
                (b) => {
                  'start_utc': _utc(b.startUtc),
                  'end_utc': _utc(b.endUtc),
                },
              )
              .toList(),
          'attendance_claim_id': time.attendanceClaimId,
        });
      case 'time_submit':
      case 'time_approve':
      case 'time_reject':
      case 'time_cancel':
        if (time == null) {
          throw const FormatException('Select the original time revision.');
        }
        payload.addAll({'project_id': r!.id, 'employee_id': time.employeeId});
      case 'close':
        break;
      default:
        throw const FormatException('Project action is unsupported.');
    }
    ProjectPlanReview? review;
    if (plan != null && {'approve_plan', 'reject_plan'}.contains(a)) {
      review = await _planReview(r!, plan, reject: a == 'reject_plan');
      if (!current) {
        return;
      }
    }
    _clearForm();
    planReview = review;
    form = payload;
    expectedVersion = version;
    if (r != null) {
      labels[r.id] = r.name;
    }
    if (resource != null) {
      labels[resource.id] =
          '${resource.employeeName}: ${resource.startLocal} – ${resource.endLocal}';
    }
    if (plan != null) {
      labels[plan.id] = 'Plan revision ${plan.version}';
    }
    if (task != null) {
      labels[task.id] = task.name;
    }
    if (time != null) {
      labels[time.employeeId] = time.employeeName;
    }
  });
  static String _utc(DateTime v) =>
      v.toIso8601String().replaceFirst('.000Z', 'Z');
  void edit(String key, Object? value) {
    if (form == null ||
        locked ||
        !ProjectCommands.fields(action!).contains(key) ||
        {
          'action',
          'id',
          'project_id',
          'plan_id',
          'employee_id',
          'digest',
          'unit_id',
          'task_id',
          'resource_slot_id',
          'currency_code',
        }.contains(key)) {
      return;
    }
    form = {...form!, key: value};
    _notify();
  }

  void choose(String key, ProjectChoice? choice) {
    if (form == null ||
        locked ||
        !{'manager_id', 'customer_id'}.contains(key) ||
        choice != null &&
            choice.kind != (key == 'manager_id' ? 'employees' : 'customers')) {
      return;
    }
    form = {...form!, key: choice?.id};
    if (choice != null) {
      labels[choice.id] = choice.name;
    }
    _notify();
  }

  void chooseClaim(ProjectAttendanceClaim? claim) {
    if (form == null ||
        locked ||
        !{'time_create', 'time_correct'}.contains(action) ||
        claim != null && claim.employeeId != form!['employee_id']) {
      return;
    }
    form = {...form!, 'attendance_claim_id': claim?.id};
    if (claim != null) {
      labels[claim.id] =
          'Attendance ${_utc(claim.span.startUtc)} – ${_utc(claim.span.endUtc)}';
    }
    _notify();
  }

  void chooseResource(ProjectResource resource) {
    if (locked ||
        !{'time_create', 'time_correct'}.contains(action) ||
        selected == null ||
        !resource.active ||
        resource.employeeId != form!['employee_id'] ||
        resource.planId != selected!.planId) {
      return;
    }
    form = {
      ...form!,
      'resource_slot_id': resource.id,
      'start_local': resource.startLocal,
      'end_local': resource.endLocal,
      'start_offset_seconds': resource.startOffset,
      'end_offset_seconds': resource.endOffset,
      'breaks': <Object?>[],
      'attendance_claim_id': null,
    };
    labels[resource.id] =
        '${resource.employeeName}: ${resource.startLocal} – ${resource.endLocal}';
    _notify();
  }

  void chooseTimeOffsets(int start, int end) {
    if (locked || !{'time_create', 'time_correct'}.contains(action)) {
      return;
    }
    form = {...form!, 'start_offset_seconds': start, 'end_offset_seconds': end};
    _notify();
  }

  void addBreak(String startUtc, String endUtc) {
    if (locked || !{'time_create', 'time_correct'}.contains(action)) {
      return;
    }
    final breaks = (form!['breaks'] as List).map(projectMap).toList();
    if (breaks.length >= 16) {
      throw const FormatException('Break limit reached.');
    }
    WorkSpan(workforceInstant(startUtc), workforceInstant(endUtc));
    breaks.add({'start_utc': startUtc, 'end_utc': endUtc});
    form = {...form!, 'breaks': breaks};
    _notify();
  }

  void removeBreak(int index) {
    if (locked || !{'time_create', 'time_correct'}.contains(action)) {
      return;
    }
    final breaks = (form!['breaks'] as List).toList()..removeAt(index);
    form = {...form!, 'breaks': breaks};
    _notify();
  }

  Future<ProjectDetail> readDetail(
    String project,
    ProjectSection kind, {
    String? parent,
    String? after,
  }) async {
    final epoch = _epoch;
    await _access(kind.privateCost ? 'projects.cost.view' : 'projects.view');
    final value = await repository.detail(
      scope,
      project,
      kind,
      parentId: parent,
      after: after,
    );
    if (!current || epoch != _epoch) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Project scope or form changed.',
      );
    }
    return value;
  }

  void addTask(
    String name,
    String start,
    String end, {
    required ProjectChoice owner,
    Iterable<String> dependencies = const [],
  }) {
    if (locked || action != 'plan') {
      return;
    }
    final tasks = (form!['tasks'] as List).map(projectMap).toList();
    if (tasks.length >= 200) {
      throw const FormatException('Task limit reached.');
    }
    projectText(name, 160);
    CivilDate.parse(start);
    CivilDate.parse(end);
    if (owner.kind != 'employees') {
      throw const FormatException('Select a scoped employee as task owner.');
    }
    tasks.add({
      'id': _uuid.v4(),
      'name': name,
      'owner_id': owner.id,
      'start_date': start,
      'end_date_exclusive': end,
      'planned_seconds': 0,
      'dependencies': dependencies.toList(),
    });
    form = {...form!, 'tasks': tasks};
    labels[owner.id] = owner.name;
    _notify();
  }

  void removeTask(String id) {
    if (locked || action != 'plan') {
      return;
    }
    final tasks = (form!['tasks'] as List).map(projectMap).toList();
    if (tasks.any((t) => (t['dependencies'] as List).contains(id))) {
      throw const FormatException('Remove dependent edges before this task.');
    }
    tasks.removeWhere((t) => t['id'] == id);
    final resources = (form!['resources'] as List)
        .map(projectMap)
        .where((s) => s['task_id'] != id)
        .toList();
    form = {...form!, 'tasks': tasks, 'resources': resources};
    _notify();
  }

  void addResource(
    String task,
    ProjectChoice employee,
    ProjectChoice calendar,
    String start,
    String end,
    int startOffset,
    int endOffset,
    String billRate,
    String costRate,
  ) {
    if (locked || action != 'plan') {
      return;
    }
    if (employee.kind != 'employees' || calendar.coverage == null) {
      throw const FormatException('Select named employee and calendar.');
    }
    final slots = (form!['resources'] as List).map(projectMap).toList(),
        tasks = (form!['tasks'] as List).map(projectMap).toList();
    if (slots.length >= 366 || !tasks.any((t) => t['id'] == task)) {
      throw const FormatException(
        'Select an existing task within the resource bound.',
      );
    }
    final seconds = WorkSpan(
      workforceLocalTime(start).subtract(Duration(seconds: startOffset)),
      workforceLocalTime(end).subtract(Duration(seconds: endOffset)),
    ).seconds;
    projectAmount(billRate, selected!.currency);
    projectAmount(costRate, selected!.currency);
    final id = _uuid.v4();
    slots.add({
      'id': id,
      'task_id': task,
      'employee_id': employee.id,
      'calendar_version_id': calendar.id,
      'start_local': start,
      'end_local': end,
      'start_offset_seconds': startOffset,
      'end_offset_seconds': endOffset,
      'bill_rate': billRate,
      'cost_rate': costRate,
    });
    for (final t in tasks) {
      if (t['id'] == task) {
        t['planned_seconds'] = (t['planned_seconds'] as int) + seconds;
      }
    }
    form = {...form!, 'tasks': tasks, 'resources': slots};
    labels[id] = employee.name;
    labels[calendar.id] = calendar.name;
    _notify();
  }

  void removeResource(String id) {
    if (locked || action != 'plan') {
      return;
    }
    final slots = (form!['resources'] as List).map(projectMap).toList(),
        tasks = (form!['tasks'] as List).map(projectMap).toList();
    final removed = slots.firstWhere((s) => s['id'] == id);
    final seconds = workforceLocalTime(removed['end_local'])
        .subtract(Duration(seconds: removed['end_offset_seconds'] as int))
        .difference(
          workforceLocalTime(
            removed['start_local'],
          ).subtract(Duration(seconds: removed['start_offset_seconds'] as int)),
        )
        .inSeconds;
    slots.removeWhere((s) => s['id'] == id);
    for (final t in tasks) {
      if (t['id'] == removed['task_id']) {
        t['planned_seconds'] = (t['planned_seconds'] as int) - seconds;
      }
    }
    form = {...form!, 'tasks': tasks, 'resources': slots};
    _notify();
  }

  Future<void> _recover({String? action, bool more = false}) async {
    final epoch = _epoch;
    for (final a in action == null ? projectActions : {action}) {
      if (!has(ProjectCommands.capability(a)) ||
          a == 'plan' && !has('projects.cost.manage') ||
          {'approve_plan', 'reject_plan'}.contains(a) &&
              !has('projects.cost.view')) {
        continue;
      }
      await _actionAccess(a);
      if (!current || epoch != _epoch) {
        return;
      }
      final page = await drafts[a]!.page(
        scope,
        after: more ? recoveryCursors[a] : null,
      );
      if (!current || epoch != _epoch) {
        return;
      }
      final items = <ProjectSavedDraft>[];
      for (final d in page.items) {
        final sealed = d.pending;
        if (sealed != null &&
            await ProjectCommandAcknowledgements(drafts[a]!).contains(sealed)) {
          try {
            await drafts[a]!.complete(
              scope,
              d.aggregateId,
              sealed.envelope.commandId,
            );
          } catch (_) {
            items.add(ProjectSavedDraft(a, d));
            if (current && epoch == _epoch) {
              message = 'The original request is confirmed. Its encrypted cleanup still needs reconciliation.';
            }
            continue;
          }
          if (!current || epoch != _epoch) return;
          message = 'A confirmed original project request was reconciled without sending it again.';
        } else {
          items.add(ProjectSavedDraft(a, d));
        }
      }
      if (!current || epoch != _epoch) return;
      recovery = [...recovery.where((d) => d.action != a || more), ...items];
      recoveryCursors[a] = page.nextCursor;
    }
  }

  Future<void> moreRecovery(String a) =>
      _run(() => _recover(action: a, more: true));
  Future<void> _save() async {
    if (form == null || pending != null || conflict || confirmed != null) {
      return;
    }
    final a = action!, id = form!['id'] as String;
    await _actionAccess(a);
    if (!current) {
      return;
    }
    await drafts[a]!.save(scope, id, a, form!, expectedVersion);
    if (!current) {
      return;
    }
    local = await drafts[a]!.load(scope, id);
    if (current && local != null) {
      _cache(a, local!);
    }
  }

  void _cache(String a, ScopedCommandDraft d) {
    recovery = [
      ...recovery.where(
        (v) => v.action != a || v.draft.aggregateId != d.aggregateId,
      ),
      ProjectSavedDraft(a, d),
    ];
  }

  Future<void> save() => _run(_save);
  Future<void> resume(ProjectSavedDraft saved) => _run(() async {
    if (confirmed != null ||
        (pending != null &&
            (saved.action != action ||
                saved.draft.aggregateId != form!['id']))) {
      throw const DomainError(
        code: 'COMMAND_PENDING',
        message: 'Resolve the current original request before opening another saved form.',
      );
    }
    await _save();
    await _actionAccess(saved.action);
    if (!current) {
      return;
    }
    final value = await drafts[saved.action]!.load(
      scope,
      saved.draft.aggregateId,
    );
    if (!current || value == null) {
      return;
    }
    _clearForm();
    form = projectMap(
      jsonDecode(jsonEncode(value.pending?.envelope.payload ?? value.form)),
    );
    local = value;
    expectedVersion = value.version;
    selected = null;
    rows = [];
    next = null;
    parentId = null;
    final id = saved.action.startsWith('time_')
        ? form!['project_id'] as String
        : saved.draft.aggregateId;
    if (saved.action != 'create') {
      try {
        await _detail(id, ProjectSection.plans);
      } on DomainError catch (e) {
        if (_revoked(e)) {
          _deny(e);
        } else if (current) {
          message = 'The exact saved request remains ready for reconciliation. Its optional project view is unavailable.';
        }
      } catch (_) {
        if (current) {
          message = 'The exact saved request remains ready for reconciliation. Its optional project view is unavailable.';
        }
      }
    }
    if (current &&
        pending == null &&
        !conflict &&
        {'approve_plan', 'reject_plan'}.contains(saved.action) &&
        selected != null) {
      final page = await repository.detail(
        scope,
        id,
        ProjectSection.plans,
        parentId: form!['plan_id'] as String,
      );
      final plan = page.rows.whereType<ProjectPlan>().single;
      if (plan.digest != form!['digest'] ||
          plan.status != 'pending' ||
          saved.action == 'approve_plan' && plan.version != expectedVersion ||
          page.project.version != expectedVersion) {
        throw const FormatException(
          'The saved plan decision is stale. Compare the original source.',
        );
      }
      planReview = await _planReview(
        page.project,
        plan,
        reject: saved.action == 'reject_plan',
      );
    }
  });
  Map<String, Object?> _verify(
    Map<String, Object?> result,
    ScopedPendingCommand sealed,
  ) {
    calendarFields(result, {
      'request_id',
      'command_id',
      'correlation_id',
      'entity',
      'warnings',
    });
    projectIdentity(result['request_id']);
    projectIdentity(result['correlation_id']);
    final e = projectMap(result['entity']);
    projectScope(e, scope);
    final c = sealed.envelope, a = sealed.action;
    calendarFields(
      e,
      a.startsWith('time_')
          ? {
              'id',
              'tenant_id',
              'legal_entity_id',
              'branch_id',
              'project_id',
              'employee_id',
              'version',
              'status',
              'revision_id',
            }
          : {
              'id',
              'tenant_id',
              'legal_entity_id',
              'branch_id',
              'version',
              'status',
              'current_plan_id',
            },
    );
    if (result['command_id'] != c.commandId ||
        e['id'] != c.payload['id'] ||
        e['version'] != c.expectedEntityVersion! + 1 ||
        result['warnings'] is! List ||
        (result['warnings'] as List).isNotEmpty) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Confirmation does not match the exact project request.',
        retryable: true,
      );
    }
    if (a.startsWith('time_')) {
      projectIdentity(e['revision_id']);
      if (e['project_id'] != c.payload['project_id'] ||
          e['employee_id'] != c.payload['employee_id'] ||
          e['status'] !=
              switch (a) {
                'time_create' || 'time_correct' => 'draft',
                'time_submit' => 'submitted',
                'time_approve' => 'approved',
                'time_reject' => 'rejected',
                'time_cancel' => 'cancelled',
                _ => null,
              }) {
        throw const FormatException('Project time confirmation changed.');
      }
    } else {
      projectOptionalIdentity(e['current_plan_id']);
      if (e['status'] != (a == 'close' ? 'closed' : 'open') ||
          a == 'create' && e['current_plan_id'] != null ||
          a == 'approve_plan' && e['current_plan_id'] != c.payload['plan_id']) {
        throw const FormatException('Project confirmation transition changed.');
      }
    }
    return e;
  }

  Future<void> _confirmed(
    Map<String, Object?> result,
    ScopedPendingCommand sealed,
    int epoch,
  ) async {
    final e = _verify(result, sealed);
    if (current && epoch == _epoch) {
      confirmed = e;
      message = 'Confirmed. The original project request succeeded.';
      _notify();
    }
    try {
      await ProjectCommandAcknowledgements(drafts[sealed.action]!)
          .save(sealed, e);
    } catch (_) {
      if (current && epoch == _epoch) {
        message = 'Confirmed. Saving the encrypted confirmation failed. Keep the original request and reconcile its receipt before issuing another request.';
      }
      return;
    }
    try {
      await drafts[sealed.action]!.complete(
        scope,
        sealed.envelope.payload['id'] as String,
        sealed.envelope.commandId,
      );
      if (!current || epoch != _epoch) {
        return;
      }
      local = null;
      recovery.removeWhere(
        (d) => d.action == sealed.action && d.draft.aggregateId == e['id'],
      );
    } catch (_) {
      if (current && epoch == _epoch) {
        message = 'Confirmed. Encrypted cleanup needs reconciliation; keep the original receipt and do not issue another request.';
      }
      return;
    }
    try {
      await _directory();
      if (current) {
        await _recover();
      }
    } on DomainError catch (e) {
      if (_revoked(e)) {
        _deny(e);
      } else if (current) {
        message = 'Confirmed. Refresh the project view when the service is available.';
      }
    } catch (_) {
      if (current) {
        message = 'Confirmed. Refresh the project view when the service is available.';
      }
    }
  }

  Future<void> send() => _run(() async {
    final epoch = _epoch;
    if (form == null || conflict || confirmed != null) {
      return;
    }
    final a = action!, id = form!['id'] as String;
    await _actionAccess(a);
    if (!current) {
      return;
    }
    final currency =
            selected?.currency ?? form!['currency_code'] as String? ?? 'XXX',
        precision = selected?.precision ?? 6;
    if (pending == null) {
      if ({'approve_plan', 'reject_plan'}.contains(a) &&
          (planReview == null ||
              planReview!.plan.id != form!['plan_id'] ||
              planReview!.plan.digest != form!['digest'] ||
              planReview!.projectVersion != expectedVersion ||
              a == 'approve_plan' &&
                  planReview!.plan.version != expectedVersion)) {
        throw const DomainError(
          code: 'REVIEW_REQUIRED',
          message:
              'Open and review the complete immutable plan before deciding.',
        );
      }
      ProjectCommands.validate(form!, currency, precision);
    }
    final sealed = await drafts[a]!.prepare(
      scope,
      id,
      a,
      form!,
      expectedVersion,
    );
    if (!current || !online || epoch != _epoch) {
      return;
    }
    local = await drafts[a]!.load(scope, id);
    if (!current || !online || epoch != _epoch) {
      return;
    }
    if (local != null) {
      _cache(a, local!);
    }
    if (await ProjectCommandAcknowledgements(drafts[a]!).contains(sealed)) {
      await drafts[a]!.complete(scope, id, sealed.envelope.commandId);
      if (current && epoch == _epoch) {
        local = null;
        _clearForm();
        message = 'The original project request was already confirmed. No request was sent.';
      }
      return;
    }
    if (!current || !online || epoch != _epoch) return;
    _sending = true;
    _notify();
    try {
      final response = await repository.command(
        sealed.envelope,
        currency,
        precision,
      );
      await _confirmed(response, sealed, epoch);
    } on DomainError catch (e) {
      await drafts[a]!.recordFailure(scope, id, sealed.envelope.commandId, e);
      if (!current) {
        return;
      }
      local = await drafts[a]!.load(scope, id);
      if (current && local != null) {
        _cache(a, local!);
      }
      if (_revoked(e)) {
        _deny(e);
      } else if (current) {
        error = e.message;
      }
    } catch (_) {
      const e = DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'The result is uncertain. Reconcile the exact encrypted project request.',
        retryable: true,
      );
      await drafts[a]!.recordFailure(scope, id, sealed.envelope.commandId, e);
      if (current) {
        local = await drafts[a]!.load(scope, id);
        if (current && local != null) {
          _cache(a, local!);
          error = e.message;
        }
      }
    } finally {
      _sending = false;
    }
  });
  Future<void> reconcile() => _run(() async {
    final epoch = _epoch;
    final sealed = pending;
    if (sealed == null || confirmed != null) {
      return;
    }
    await _actionAccess(sealed.action);
    if (!current) {
      return;
    }
    final receipt = await repository.ownReceipt(
      scope,
      sealed.envelope.idempotencyKey,
      sealed.action,
    );
    if (receipt == null) {
      if (current && epoch == _epoch) {
        message = 'No matching receipt was found. Retry only the exact encrypted request.';
      }
      return;
    }
    if (receipt['command_id'] != sealed.envelope.commandId ||
        receipt['idempotency_key'] != sealed.envelope.idempotencyKey) {
      throw const DomainError(
        code: 'COMMAND_PENDING',
        message: 'The receipt belongs to another request.',
      );
    }
    await _confirmed(projectMap(receipt['response']), sealed, epoch);
  });
  Future<void> retryConfirmedCleanup() => _run(() async {
    final sealed = pending;
    if (confirmed == null || sealed == null) {
      return;
    }
    await _actionAccess(sealed.action);
    if (!current) {
      return;
    }
    await drafts[sealed.action]!.complete(
      scope,
      form!['id'] as String,
      sealed.envelope.commandId,
    );
    if (!current) {
      return;
    }
    local = null;
    recovery.removeWhere(
      (d) =>
          d.action == sealed.action && d.draft.aggregateId == confirmed!['id'],
    );
    message = 'Confirmed. The original encrypted request was cleared.';
  });
  Future<void> compare() => _run(() async {
    if (!conflict || form == null) {
      return;
    }
    await _actionAccess(action!);
    if (!current) {
      return;
    }
    final id = action!.startsWith('time_')
        ? form!['project_id'] as String
        : form!['id'] as String;
    final value = await repository.detail(
      scope,
      id,
      action!.startsWith('time_') ? ProjectSection.time : ProjectSection.plans,
      parentId: action!.startsWith('time_')
          ? form!['id'] as String
          : {'approve_plan', 'reject_plan'}.contains(action)
          ? form!['plan_id'] as String
          : null,
    );
    if (current) {
      comparison = value;
    }
  });
  Future<void> adoptComparison() => _run(() async {
    if (!conflict || comparison == null || form == null) {
      return;
    }
    final a = action!, id = form!['id'] as String;
    await _actionAccess(a);
    if (!current) {
      return;
    }
    final version = a.startsWith('time_')
        ? comparison!.rows
              .whereType<ProjectTime>()
              .firstWhere((t) => t.id == id)
              .version
        : comparison!.project.version;
    ProjectPlanReview? reviewed;
    if ({'approve_plan', 'reject_plan'}.contains(a)) {
      final plan = comparison!.rows.whereType<ProjectPlan>().singleWhere(
        (p) => p.id == form!['plan_id'] && p.digest == form!['digest'],
      );
      reviewed = await _planReview(
        comparison!.project,
        plan,
        reject: a == 'reject_plan',
      );
      if (!current) return;
    }
    await drafts[a]!.save(scope, id, a, form!, version, resolveConflict: true);
    if (current) {
      expectedVersion = version;
      if (reviewed != null) planReview = reviewed;
      local = await drafts[a]!.load(scope, id);
      comparison = null;
      if (current && local != null) {
        _cache(a, local!);
      }
    }
  });
  Future<void> discard() => _run(() async {
    if (form == null || pending != null || confirmed != null) {
      return;
    }
    await _actionAccess(action!);
    if (!current) {
      return;
    }
    final a = action!, id = form!['id'] as String;
    await drafts[a]!.discard(scope, id);
    if (current) {
      recovery.removeWhere((d) => d.action == a && d.draft.aggregateId == id);
      _clearForm();
    }
  });
  Future<void> dismissConfirmed() => _run(() async {
    if (confirmed == null || pending != null) {
      return;
    }
    _clearForm();
  });
  Future<bool> canLeave() async {
    if (busy || _sending) {
      return false;
    }
    try {
      await _save();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<T>> _all<T extends ProjectRow>(
    String project,
    ProjectSection kind,
    String plan,
    int version,
    int limit,
  ) async {
    final values = <T>[];
    String? after;
    do {
      final page = await repository.detail(
        scope,
        project,
        kind,
        parentId: plan,
        after: after,
      );
      if (!current) {
        throw const DomainError(
          code: 'PERMISSION_DENIED',
          message: 'Project access changed.',
        );
      }
      if (page.project.version != version) {
        throw const DomainError(
          code: 'VERSION_CONFLICT',
          message: 'The project changed while loading the plan review.',
        );
      }
      values.addAll(page.rows.cast<T>());
      if (values.length > limit ||
          values.map((x) => x.id).toSet().length != values.length) {
        throw const FormatException(
          'Project review exceeds its bound or repeats a source.',
        );
      }
      after = page.next;
    } while (after != null);
    return List.unmodifiable(values);
  }

  Future<ProjectPlanReview> _planReview(
    ProjectRecord project,
    ProjectPlan plan, {
    bool reject = false,
  }) async {
    await _access('projects.cost.view');
    if (!current) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Project cost access changed.',
      );
    }
    if (plan.status != 'pending' ||
        !reject && project.version != plan.version) {
      throw const FormatException('The original pending plan is stale.');
    }
    final tasks = await _all<ProjectTask>(
          project.id,
          ProjectSection.tasks,
          plan.id,
          project.version,
          200,
        ),
        resources = await _all<ProjectResource>(
          project.id,
          ProjectSection.resources,
          plan.id,
          project.version,
          366,
        ),
        budget = await _all<ProjectBudget>(
          project.id,
          ProjectSection.cost,
          plan.id,
          project.version,
          1,
        ),
        rates = await _all<ProjectResourceCost>(
          project.id,
          ProjectSection.resourceCost,
          plan.id,
          project.version,
          366,
        );
    ProjectTaskGraph(project.id, tasks.map((t) => t.basis));
    if (budget.length != 1 ||
        rates.length != resources.length ||
        resources.any((s) => !rates.any((r) => r.id == s.id)) ||
        tasks.any(
          (t) =>
              resources
                  .where((s) => s.taskId == t.id)
                  .fold<int>(0, (n, s) => n + s.plannedSeconds) !=
              t.basis.plannedSeconds,
        )) {
      throw const FormatException(
        'The immutable plan review does not conserve its resources.',
      );
    }
    return ProjectPlanReview(
      project.version,
      plan,
      tasks,
      resources,
      budget.single,
      rates,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _disposed = true;
    _epoch++;
    form = null;
    local = null;
    confirmed = null;
    comparison = null;
    planReview = null;
    selected = null;
    rows = [];
    records = [];
    recovery = [];
    labels.clear();
    recoveryCursors.clear();
    providers = null;
    super.dispose();
  }
}

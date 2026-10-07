import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_projects.dart';
import 'package:jentra_domain/jentra_milestones.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_milestones_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';

final milestoneRepositoryProvider = Provider<MilestoneRepository?>(
  (ref) => null,
);
const milestoneDefiniteFailures = {
  'VERSION_CONFLICT',
  'VALIDATION_ERROR',
  'STATE_CONFLICT',
  'IDENTITY_EXISTS',
  'MILESTONE_BILLING_IMPACT_REQUIRED',
};
ScopedCommandDraftStore milestoneDraftStore(
  EncryptedDraftRepository r,
  String a,
) => ScopedCommandDraftStore(
  r,
  entityType: 'projects.milestone.command.$a',
  fields: MilestoneCommands.fields,
  validate: MilestoneCommands.validate,
  definiteFailures: milestoneDefiniteFailures,
);
final milestoneControllerProvider = Provider.autoDispose
    .family<MilestonesController?, String>((ref, project) {
      final scope = ref.watch(activeTenantContextProvider),
          caps = ref.watch(businessCapabilitiesProvider),
          repo = ref.watch(milestoneRepositoryProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          repo == null ||
          caps.isLoading ||
          caps.hasError ||
          !(caps.value?.contains('projects.view') ?? false)) {
        return null;
      }
      final encrypted = ref.watch(encryptedDraftRepositoryProvider),
          c = MilestonesController(
            scope: scope,
            projectId: project,
            repository: repo,
            drafts: {
              for (final a in milestoneActions)
                a: milestoneDraftStore(encrypted, a),
            },
            permissions: caps.value!,
            online:
                ref.read(connectivityStateProvider).value ==
                ConnectivityState.online,
          );
      ref.listen(
        connectivityStateProvider,
        (_, v) => c.setOnline(v.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

final class MilestoneSavedDraft {
  const MilestoneSavedDraft(this.action, this.draft);
  final String action;
  final ScopedCommandDraft draft;
}

final class MilestonesController extends ChangeNotifier {
  MilestonesController({
    required this.scope,
    required this.projectId,
    required this.repository,
    required this.drafts,
    required Set<String> permissions,
    required this.online,
    bool monitor = true,
  }) : permissions = Set.unmodifiable(permissions) {
    projectIdentity(projectId);
    if (monitor) {
      _timer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(checkAccess()),
      );
    }
  }
  final TenantContext scope;
  final String projectId;
  final MilestoneRepository repository;
  final Map<String, ScopedCommandDraftStore> drafts;
  final Set<String> permissions;
  Timer? _timer;
  bool online,
      busy = false,
      denied = false,
      _disposed = false,
      _sending = false,
      confirmed = false;
  int _epoch = 0, _formEpoch = 0, expectedVersion = 0;
  ProjectRecord? project;
  List<MilestoneRecord> records = [];
  String? cursor, error, message;
  MilestoneDetail? selected, comparison;
  Map<String, Object?>? form;
  ScopedCommandDraft? local;
  List<MilestoneSavedDraft> recovery = [];
  final recoveryCursors = <String, String?>{};
  final labels = <String, String>{};
  int get accessEpoch => _epoch;
  int get formEpoch => _formEpoch;
  bool get current => !_disposed && !denied;
  String? get action => form?['action'] as String?;
  ScopedPendingCommand? get pending => local?.pending;
  bool get conflicted => local?.errorCode == 'VERSION_CONFLICT';
  bool get locked =>
      busy || !current || pending != null || conflicted || confirmed;
  bool has(String cap) => permissions.contains(cap);
  bool _live(int n) => current && online && n == _epoch;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _clear() {
    project = null;
    records = [];
    selected = null;
    comparison = null;
    form = null;
    local = null;
    confirmed = false;
    recovery = [];
    recoveryCursors.clear();
    labels.clear();
    cursor = null;
  }

  void _deny() {
    _epoch++;
    _formEpoch++;
    denied = true;
    _clear();
    error = 'Current project access is required. Select an authorized scope.';
    _notify();
  }

  void _failure(Object e) {
    if (e is DomainError &&
        {
          'AUTHENTICATION_REQUIRED',
          'PERMISSION_DENIED',
          'ACCESS_DENIED',
          'MFA_REQUIRED',
          'FEATURE_NOT_ENTITLED',
        }.contains(e.code)) {
      _deny();
      return;
    }
    error = e is DomainError
        ? e.message
        : e is FormatException
        ? 'Check exact milestone terms, amount and dates.'
        : 'Milestones are unavailable. Retry the scoped read.';
    _notify();
  }

  void setOnline(bool value) {
    if (value == online) return;
    _epoch++;
    _formEpoch++;
    online = value;
    _clear();
    error = value ? null : 'Reconnect to review or send milestones.';
    _notify();
    if (value) unawaited(initialize());
  }

  Future<void> checkAccess() async {
    if (!current || !online) return;
    final n = _epoch;
    try {
      await repository.authorize(scope, 'projects.view');
      for (final a in {?action, ...recovery.map((r) => r.action)}) {
        if (!_live(n)) return;
        await repository.authorize(scope, MilestoneCommands.capability(a));
      }
    } catch (e) {
      if (_live(n)) _failure(e);
    }
  }

  Future<void> initialize() async {
    await refresh();
    if (current && online) await loadRecovery();
  }

  Future<void> refresh({bool more = false}) async {
    if (!current || !online || busy || more && cursor == null) return;
    final n = _epoch, after = more ? cursor : null;
    busy = true;
    _notify();
    try {
      await repository.authorize(scope, 'projects.view');
      if (!_live(n)) return;
      final context = await repository.projects.detail(
        scope,
        projectId,
        ProjectSection.tasks,
      );
      if (!_live(n)) return;
      final page = await repository.list(scope, projectId, after: after);
      if (!_live(n)) return;
      project = context.project;
      records = more ? [...records, ...page.rows] : page.rows;
      cursor = page.next;
      error = null;
    } catch (e) {
      if (_live(n)) _failure(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> select(
    MilestoneRecord row, {
    String kind = 'events',
    bool more = false,
  }) async {
    if (!current || !online || busy) return;
    final entry = _epoch;
    if (!more && (!await canLeave() || !_live(entry))) return;
    final n = _epoch;
    busy = true;
    _notify();
    try {
      await repository.authorize(scope, 'projects.view');
      if (!_live(n)) return;
      final d = await repository.detail(
        scope,
        projectId,
        row.id,
        kind: kind,
        after: more ? selected?.next : null,
      );
      if (!_live(n)) return;
      selected = more && selected?.record.id == row.id && selected?.kind == kind
          ? MilestoneDetail(d.record, kind, [
              ...selected!.rows,
              ...d.rows,
            ], d.next)
          : d;
      if (!more) {
        _formEpoch++;
        form = null;
        local = null;
        comparison = null;
        confirmed = false;
        labels.clear();
      }
    } catch (e) {
      if (_live(n)) _failure(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> begin(String a, {MilestoneRecord? target}) async {
    if (!current ||
        !online ||
        busy ||
        pending != null ||
        !has(MilestoneCommands.capability(a))) {
      return false;
    }
    final entry = _epoch;
    if (!await canLeave() || !_live(entry)) return false;
    final n = _epoch, f = ++_formEpoch;
    try {
      await repository.authorize(scope, MilestoneCommands.capability(a));
      if (!_live(n) || f != _formEpoch) return false;
      final context = await repository.projects.detail(
        scope,
        projectId,
        ProjectSection.tasks,
      );
      if (!_live(n) || f != _formEpoch) return false;
      project = context.project;
      if (target == null) {
        if (a != 'create' ||
            project!.planId == null ||
            project!.customerId == null) {
          throw const DomainError(
            code: 'STATE_CONFLICT',
            message: 'An open billable project and approved plan are required.',
          );
        }
        form = {
          'action': a,
          'id': const Uuid().v4(),
          'project_id': projectId,
          'plan_id': project!.planId,
          'task_id': null,
          'owner_id': null,
          'name': '',
          'due_date': project!.start.value,
          'amount': '0',
          'commercial_terms': '',
          'payment_terms': '',
          'payment_due_days': 30,
          'evidence_reference': '',
          'reason': '',
        };
        expectedVersion = 0;
      } else {
        form = target.form(a);
        expectedVersion = target.version;
        labels['task_id'] = target.taskName;
        labels['owner_id'] = target.ownerName;
        if (a == 'correct' && target.planId != project!.planId) {
          if (project!.planId == null) {
            throw const DomainError(
              code: 'STATE_CONFLICT',
              message: 'Approve a current project plan before correcting milestone terms.',
            );
          }
          form = {
            ...form!,
            'plan_id': project!.planId,
            'task_id': null,
            'owner_id': null,
          };
          labels.clear();
        }
      }
      local = null;
      comparison = null;
      confirmed = false;
      error = null;
      _notify();
      return true;
    } catch (e) {
      if (_live(n) && f == _formEpoch) _failure(e);
      return false;
    }
  }

  void edit(String k, Object? value) {
    if (locked ||
        form == null ||
        !MilestoneCommands.fields(action!).contains(k) ||
        {
          'action',
          'id',
          'project_id',
          'plan_id',
          'task_id',
          'owner_id',
          'digest',
        }.contains(k)) {
      return;
    }
    form = {...form!, k: value};
    error = null;
    _notify();
  }

  Future<ProjectPage<ProjectTask>> tasks({String? after}) async {
    final n = _epoch, f = _formEpoch, a = action;
    if (a == null || !_live(n)) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Current milestone access is required.',
      );
    }
    try {
      await repository.authorize(scope, MilestoneCommands.capability(a));
      if (!_live(n) || f != _formEpoch) {
        throw const DomainError(
          code: 'STATE_CONFLICT',
          message: 'The milestone form changed.',
        );
      }
      final p = await repository.projects.detail(
        scope,
        projectId,
        ProjectSection.tasks,
        parentId: form!['plan_id'] as String?,
        after: after,
      );
      if (!_live(n) ||
          f != _formEpoch ||
          p.project.planId != form!['plan_id']) {
        throw const DomainError(
          code: 'STATE_CONFLICT',
          message: 'The approved plan changed. Reopen the milestone form.',
        );
      }
      return ProjectPage(p.rows.cast<ProjectTask>(), p.next);
    } catch (e) {
      if (_live(n) && f == _formEpoch) _failure(e);
      rethrow;
    }
  }

  Future<ProjectPage<ProjectChoice>> owners({String? after}) async {
    final n = _epoch, f = _formEpoch, a = action;
    if (a == null || !_live(n)) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Current milestone access is required.',
      );
    }
    try {
      await repository.authorize(scope, MilestoneCommands.capability(a));
      if (!_live(n) || f != _formEpoch) {
        throw const DomainError(
          code: 'STATE_CONFLICT',
          message: 'The milestone form changed.',
        );
      }
      final page = await repository.projects.choices(
        scope,
        'employees',
        after: after,
      );
      if (!_live(n) || f != _formEpoch) {
        throw const DomainError(
          code: 'STATE_CONFLICT',
          message: 'The milestone form changed.',
        );
      }
      return page;
    } catch (e) {
      if (_live(n) && f == _formEpoch) _failure(e);
      rethrow;
    }
  }

  void chooseTask(ProjectTask task, int n, int f) {
    if (locked ||
        !_live(n) ||
        f != _formEpoch ||
        task.planId != form?['plan_id']) {
      return;
    }
    form = {
      ...form!,
      'task_id': task.id,
      'owner_id': task.basis.ownerId,
      'due_date': task.basis.start.value,
    };
    labels['task_id'] = task.name;
    labels['owner_id'] = task.ownerName;
    _notify();
  }

  void chooseOwner(ProjectChoice owner, int n, int f) {
    if (locked || !_live(n) || f != _formEpoch || owner.kind != 'employees') {
      return;
    }
    form = {...form!, 'owner_id': owner.id};
    labels['owner_id'] = owner.name;
    _notify();
  }

  Future<void> save() async {
    if (form == null ||
        !current ||
        !online ||
        pending != null ||
        conflicted ||
        confirmed) {
      return;
    }
    final n = _epoch,
        f = _formEpoch,
        a = action!,
        id = form!['id'] as String,
        p = milestoneMap(jsonDecode(jsonEncode(form))),
        v = expectedVersion;
    try {
      await repository.authorize(scope, MilestoneCommands.capability(a));
      if (!_live(n) || f != _formEpoch) return;
      await drafts[a]!.save(scope, id, a, p, v);
      final row = await drafts[a]!.load(scope, id);
      if (_live(n) && f == _formEpoch) {
        local = row;
        message = 'Encrypted milestone draft saved.';
        _notify();
      }
    } catch (e) {
      if (_live(n) && f == _formEpoch) _failure(e);
      rethrow;
    }
  }

  Future<bool> canLeave() async {
    if (busy || _sending) return false;
    final n = _epoch;
    try {
      await save();
      return _live(n);
    } catch (e) {
      if (_live(n)) _failure(e);
      return false;
    }
  }

  Future<void> loadRecovery({String? a}) async {
    if (!current || !online) return;
    final n = _epoch;
    try {
      await repository.authorize(scope, 'projects.view');
      if (!_live(n)) return;
      final found = <MilestoneSavedDraft>[];
      for (final action in a == null ? milestoneActions : {a}) {
        if (!has(MilestoneCommands.capability(action))) continue;
        await repository.authorize(scope, MilestoneCommands.capability(action));
        if (!_live(n)) return;
        final page = await drafts[action]!.page(
          scope,
          after: a == null ? null : recoveryCursors[action],
        );
        if (!_live(n)) return;
        found.addAll(
          page.items
              .where((x) => x.form['project_id'] == projectId)
              .map((x) => MilestoneSavedDraft(action, x)),
        );
        recoveryCursors[action] = page.nextCursor;
      }
      if (_live(n)) {
        recovery = a == null ? found : [...recovery, ...found];
        _notify();
      }
    } catch (e) {
      if (_live(n)) _failure(e);
    }
  }

  Future<void> resume(MilestoneSavedDraft saved) async {
    if (!current || busy) return;
    final entry = _epoch;
    if (!await canLeave() || !_live(entry)) return;
    final n = _epoch, f = ++_formEpoch;
    try {
      await repository.authorize(
        scope,
        MilestoneCommands.capability(saved.action),
      );
      if (!_live(n) || f != _formEpoch) return;
      final row = await drafts[saved.action]!.load(
        scope,
        saved.draft.aggregateId,
      );
      if (!_live(n) || f != _formEpoch || row == null) return;
      if (row.form['project_id'] != projectId) {
        throw const DomainError(
          code: 'DRAFT_SCOPE_MISMATCH',
          message: 'This draft belongs to another project.',
        );
      }
      form = milestoneMap(jsonDecode(jsonEncode(row.form)));
      local = row;
      expectedVersion = row.version;
      confirmed = false;
      comparison = null;
      labels.clear();
      error = null;
      _notify();
    } catch (e) {
      if (_live(n) && f == _formEpoch) _failure(e);
    }
  }

  Future<void> _complete(ScopedPendingCommand r) async {
    await drafts[r.action]!.complete(
      scope,
      r.envelope.payload['id'] as String,
      r.envelope.commandId,
    );
  }

  Future<void> send() async {
    if (locked || !online || form == null) return;
    busy = true;
    _sending = true;
    _notify();
    final n = _epoch, f = _formEpoch, a = action!, id = form!['id'] as String;
    ScopedPendingCommand? request;
    try {
      await repository.authorize(scope, MilestoneCommands.capability(a));
      if (!_live(n) || f != _formEpoch) return;
      if ({'create', 'correct'}.contains(a)) {
        milestoneAmount(form!['amount'], project!.currency, project!.precision);
      }
      request = await drafts[a]!.prepare(scope, id, a, form!, expectedVersion);
      if (!_live(n) || f != _formEpoch) return;
      local = await drafts[a]!.load(scope, id);
      if (!_live(n) || f != _formEpoch) return;
      final result = milestoneReceipt(
        await repository.execute(request.envelope),
        scope,
        projectId,
        request: request.envelope,
      );
      if (_live(n) && f == _formEpoch) {
        confirmed = true;
        message = 'Milestone confirmed. Invoice and payment remain separate.';
        _notify();
      }
      await MilestoneCommandAcknowledgements(drafts[a]!).save(request, result);
      if (_live(n) && f == _formEpoch) {
        confirmed = true;
        message = 'Milestone confirmed. Invoice and payment remain separate.';
        _notify();
      }
      try {
        await _complete(request);
        if (_live(n) && f == _formEpoch) local = null;
      } catch (e) {
        if (_live(n) && f == _formEpoch) {
          message =
              'Milestone confirmed; encrypted recovery cleanup needs retry.';
        }
      }
    } catch (e) {
      if (!_live(n) || f != _formEpoch) return;
      final safe = e is DomainError
          ? e
          : DomainError(
              code: request == null ? 'VALIDATION_ERROR' : 'UNCERTAIN_RESULT',
              message: request == null ? 'Check the exact milestone form.' : 'The result is uncertain. Reconcile the exact saved request.',
              retryable: request != null,
            );
      if (request != null) {
        try {
          await drafts[a]!.recordFailure(
            scope,
            id,
            request.envelope.commandId,
            safe,
          );
          final row = await drafts[a]!.load(scope, id);
          if (_live(n) && f == _formEpoch) local = row;
        } catch (storage) {
          if (_live(n) && f == _formEpoch) _failure(storage);
          return;
        }
      }
      if (_live(n) && f == _formEpoch) {
        if (confirmed && safe.code == 'LOCAL_STORAGE_FULL') {
          message = 'Milestone confirmed. Saving the encrypted confirmation failed; reconcile the original request after restoring local storage.';
        }
        _failure(safe);
      }
    } finally {
      busy = false;
      _sending = false;
      _notify();
    }
    if (_live(n)) await refresh();
  }

  Future<void> retryOriginal() async {
    final request = pending;
    if (request == null || busy || !current || !online || confirmed) return;
    busy = true;
    _sending = true;
    _notify();
    final n = _epoch, f = _formEpoch;
    try {
      await repository.authorize(
        scope,
        MilestoneCommands.capability(request.action),
      );
      if (!_live(n) || f != _formEpoch) return;
      if (!await MilestoneCommandAcknowledgements(drafts[request.action]!)
          .contains(request)) {
        if (!_live(n) || f != _formEpoch) return;
        final result = milestoneReceipt(
          await repository.execute(request.envelope),
          scope,
          projectId,
          request: request.envelope,
        );
        if (_live(n) && f == _formEpoch) {
          confirmed = true;
          message = 'Original milestone change confirmed.';
          _notify();
        }
        await MilestoneCommandAcknowledgements(drafts[request.action]!)
            .save(request, result);
      }
      if (_live(n) && f == _formEpoch) {
        confirmed = true;
        message = 'Original milestone change confirmed.';
        _notify();
      }
      await _complete(request);
      if (_live(n) && f == _formEpoch) local = null;
    } catch (e) {
      if (_live(n) && f == _formEpoch) _failure(e);
    } finally {
      busy = false;
      _sending = false;
      _notify();
    }
  }

  Future<void> reconcile() async {
    final request = pending;
    if (request == null || busy || !current || !online) return;
    busy = true;
    _notify();
    final n = _epoch, f = _formEpoch;
    try {
      await repository.authorize(
        scope,
        MilestoneCommands.capability(request.action),
      );
      if (!_live(n) || f != _formEpoch) return;
      var acknowledged = await MilestoneCommandAcknowledgements(
        drafts[request.action]!,
      ).contains(request);
      if (!acknowledged) {
        if (!_live(n) || f != _formEpoch) return;
        final result = await repository.ownReceipt(
          scope,
          projectId,
          request.action,
          request.envelope.idempotencyKey,
        );
        if (result != null) {
          milestoneReceipt(result, scope, projectId, request: request.envelope);
          if (_live(n) && f == _formEpoch) {
            confirmed = true;
            message = 'Original milestone change confirmed.';
            _notify();
          }
          await MilestoneCommandAcknowledgements(drafts[request.action]!)
              .save(request, result);
          acknowledged = true;
        }
      }
      if (acknowledged) {
        if (_live(n) && f == _formEpoch) {
          confirmed = true;
          message = 'Original milestone change confirmed.';
          _notify();
        }
        await _complete(request);
        if (_live(n) && f == _formEpoch) local = null;
      } else if (_live(n) && f == _formEpoch) {
        message = 'No receipt found. Retry only the original sealed request.';
      }
    } catch (e) {
      if (_live(n) && f == _formEpoch) _failure(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> compare() async {
    if (!current || !online || busy || !conflicted || form == null) return;
    final n = _epoch, f = _formEpoch, a = action!, id = form!['id'] as String;
    try {
      await repository.authorize(scope, MilestoneCommands.capability(a));
      if (!_live(n) || f != _formEpoch) return;
      final d = await repository.detail(
        scope,
        projectId,
        id,
        kind: 'revisions',
      );
      if (_live(n) && f == _formEpoch) {
        comparison = d;
        _notify();
      }
    } catch (e) {
      if (_live(n) && f == _formEpoch) _failure(e);
    }
  }

  Future<void> adoptComparison() async {
    if (comparison == null || !conflicted || pending != null || form == null) {
      return;
    }
    final n = _epoch,
        f = _formEpoch,
        a = action!,
        id = form!['id'] as String,
        v = comparison!.record.version;
    try {
      await repository.authorize(scope, MilestoneCommands.capability(a));
      if (!_live(n) || f != _formEpoch) return;
      final data = {
        ...form!,
        if (!{'create', 'correct'}.contains(a))
          'digest': comparison!.record.digest,
      };
      await drafts[a]!.save(scope, id, a, data, v, resolveConflict: true);
      final row = await drafts[a]!.load(scope, id);
      if (_live(n) && f == _formEpoch) {
        form = data;
        local = row;
        expectedVersion = v;
        comparison = null;
        _notify();
      }
    } catch (e) {
      if (_live(n) && f == _formEpoch) _failure(e);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _formEpoch++;
    _timer?.cancel();
    _clear();
    super.dispose();
  }
}

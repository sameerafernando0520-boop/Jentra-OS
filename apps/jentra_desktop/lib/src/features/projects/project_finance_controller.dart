import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_domain/jentra_projects.dart';
import 'package:jentra_domain/jentra_project_finance.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_project_finance_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';

final projectFinanceRepositoryProvider = Provider<ProjectFinanceRepository?>(
  (ref) => null,
);
const projectFinanceDefiniteFailures = {
  'VERSION_CONFLICT',
  'VALIDATION_ERROR',
  'STATE_CONFLICT',
  'IDENTITY_EXISTS',
  'IDEMPOTENCY_MISMATCH',
  'RESOURCE_NOT_FOUND',
};
ScopedCommandDraftStore projectFinanceDrafts(
  EncryptedDraftRepository repository,
  String action,
) => ScopedCommandDraftStore(
  repository,
  entityType: 'projects.finance.$action',
  fields: projectFinanceFields,
  validate: validateProjectFinanceCommand,
  definiteFailures: projectFinanceDefiniteFailures,
);
final projectFinanceControllerProvider = Provider.autoDispose
    .family<ProjectFinanceController?, (String, String, int)>((ref, key) {
      final scope = ref.watch(activeTenantContextProvider),
          caps = ref.watch(businessCapabilitiesProvider),
          repo = ref.watch(projectFinanceRepositoryProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          repo == null ||
          caps.isLoading ||
          caps.hasError ||
          !((caps.value?.contains('projects.cost.view') ?? false) ||
              (caps.value?.contains('projects.billing.manage') ?? false))) {
        return null;
      }
      final encrypted = ref.watch(encryptedDraftRepositoryProvider);
      final c = ProjectFinanceController(
        scope: scope,
        projectId: key.$1,
        currency: key.$2,
        precision: key.$3,
        repository: repo,
        permissions: caps.value!,
        drafts: {
          for (final a in projectFinanceActions)
            a: projectFinanceDrafts(encrypted, a),
        },
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

final class ProjectFinanceSavedDraft {
  const ProjectFinanceSavedDraft(this.action, this.draft);
  final String action;
  final ScopedCommandDraft draft;
}

final class ProjectFinanceController extends ChangeNotifier {
  ProjectFinanceController({
    required this.scope,
    required this.projectId,
    required this.currency,
    required this.precision,
    required this.repository,
    required Set<String> permissions,
    required this.drafts,
    required this.online,
    bool monitor = true,
  }) : permissions = Set.unmodifiable(permissions) {
    projectIdentity(projectId);
    projectPrecision(precision);
    if (monitor) {
      _timer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(checkAccess()),
      );
    }
  }
  final TenantContext scope;
  final String projectId, currency;
  final int precision;
  final ProjectFinanceRepository repository;
  final Set<String> permissions;
  final Map<String, ScopedCommandDraftStore> drafts;
  static const uuid = Uuid();
  Timer? _timer;
  bool _disposed = false, denied = false, busy = false, online;
  int _epoch = 0;
  ProjectFinanceSection section = ProjectFinanceSection.expenses;
  List<ProjectFinanceRow> rows = [];
  String? next, error, message;
  ProjectMargin? report;
  Map<String, Object?>? form, confirmed;
  ScopedCommandDraft? local;
  ProjectFinanceRow? comparison, review;
  int expectedVersion = 0;
  final labels = <String, String>{};
  List<ProjectFinanceSavedDraft> recovery = [];
  final recoveryCursors = <String, String?>{};
  bool get current => !_disposed && !denied;
  bool has(String cap) => permissions.contains(cap);
  String? get action => form?['action'] as String?;
  ScopedPendingCommand? get pending => local?.pending;
  bool get conflict => local?.errorCode == 'VERSION_CONFLICT';
  bool get locked =>
      busy || !current || pending != null || conflict || confirmed != null;
  String cap(ProjectFinanceSection s) => switch (s) {
    ProjectFinanceSection.billing ||
    ProjectFinanceSection.units => 'projects.billing.manage',
    ProjectFinanceSection.obligations ||
    ProjectFinanceSection.settlements => 'projects.expenses.settle',
    _ => 'projects.cost.view',
  };
  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void setOnline(bool v) {
    online = v;
    _notify();
  }

  bool _revoked(DomainError e) => {
    'PERMISSION_DENIED',
    'AUTHENTICATION_REQUIRED',
    'FEATURE_NOT_ENTITLED',
  }.contains(e.code);
  void _deny() {
    denied = true;
    _epoch++;
    rows = [];
    report = null;
    form = null;
    local = null;
    confirmed = null;
    review = null;
    comparison = null;
    recovery = [];
    labels.clear();
    next = null;
    error = 'Project finance access changed. Select an authorized scope.';
    message = null;
    _notify();
  }

  Future<void> _access(String c) async {
    if (!online) {
      throw const DomainError(
        code: 'OFFLINE',
        message: 'Connect before checking project finance.',
      );
    }
    if (!has(c)) {
      throw const DomainError(
        code: 'ACTION_NOT_PERMITTED',
        message: 'This action requires its project finance capability.',
      );
    }
    try {
      await repository.authorize(scope, c);
    } on DomainError catch (e) {
      if (_revoked(e)) {
        _deny();
      }
      rethrow;
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
        _deny();
      } else if (current) {
        error = e.message;
      }
    } catch (_) {
      if (current) {
        error = 'Check the original amounts, dates and named sources.';
      }
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> initialize() => _run(() async {
    section = has('projects.cost.view')
        ? ProjectFinanceSection.expenses
        : ProjectFinanceSection.billing;
    await _load(section);
    await _recover();
  });
  Future<void> checkAccess() async {
    if (!current || busy || !online) {
      return;
    }
    try {
      await _access(cap(section));
      if (action != null) {
        await _access(projectFinanceCapability(action!));
      }
      if (report != null) {
        await _access('projects.margin.view');
      }
      if (review?.section == ProjectFinanceSection.expenses) {
        await _access('projects.cost.view');
      }
      for (final capability
          in recovery.map((d) => projectFinanceCapability(d.action)).toSet()) {
        await _access(capability);
        if (!current) {
          return;
        }
      }
    } catch (_) {}
  }

  Future<void> _load(ProjectFinanceSection s, {bool more = false}) async {
    await _access(cap(s));
    if (!current) {
      return;
    }
    final epoch = _epoch;
    final page = await repository.detail(
      scope,
      projectId,
      currency,
      s,
      after: more ? next : null,
    );
    if (!current || epoch != _epoch) {
      return;
    }
    section = s;
    rows = [if (more) ...rows, ...page.rows];
    next = page.nextAfter;
  }

  Future<void> load(ProjectFinanceSection s) => _run(() => _load(s));
  Future<void> more() => _run(() => _load(section, more: true));
  Future<void> loadMargin(DateTime asOf, CivilDate date) => _run(() async {
    await _access('projects.margin.view');
    final epoch = _epoch;
    final value = await repository.margin(scope, projectId, asOf, date);
    if (current && epoch == _epoch) {
      report = value;
    }
  });
  Future<ProjectFinancePage<ProjectFinanceChoice>> choices(
    String kind, {
    String? after,
  }) async {
    await _access(
      kind == 'products' || kind == 'output_tax' || kind == 'service_sources'
          ? 'projects.billing.manage'
          : kind == 'banks'
          ? 'projects.expenses.settle'
          : 'projects.cost.view',
    );
    final epoch = _epoch;
    final value = await repository.choices(
      scope,
      kind,
      after: after,
      projectId: projectId,
    );
    if (!current || epoch != _epoch) {
      throw const DomainError(
        code: 'ACCESS_CHANGED',
        message: 'The picker scope changed.',
      );
    }
    return value;
  }

  Future<ProjectFinancePage<ProjectFinanceRow>> unitChoices({
    String? after,
  }) async {
    await _access('projects.billing.manage');
    final epoch = _epoch;
    final value = await repository.detail(
      scope,
      projectId,
      currency,
      ProjectFinanceSection.units,
      after: after,
    );
    if (!current || epoch != _epoch) {
      throw const DomainError(
        code: 'ACCESS_CHANGED',
        message: 'The billing source scope changed.',
      );
    }
    return value;
  }

  Future<ProjectFinanceRow> _currentRow(ProjectFinanceRow row) async {
    await _access(cap(row.section));
    final page = await repository.detail(
      scope,
      projectId,
      currency,
      row.section,
      targetId: row.id,
    );
    if (page.rows.length != 1) {
      throw const DomainError(
        code: 'RESOURCE_NOT_FOUND',
        message: 'This original source is no longer available.',
      );
    }
    return page.rows.single;
  }

  Future<void> begin(String a, {ProjectFinanceRow? row}) => _run(() async {
    if (pending != null || confirmed != null || conflict) {
      throw const DomainError(
        code: 'COMMAND_PENDING',
        message: 'Resolve the original request before opening another form.',
      );
    }
    await _access(projectFinanceCapability(a));
    if (!current) {
      return;
    }
    final source = row == null ? null : await _currentRow(row);
    if (!current) {
      return;
    }
    review = source;
    comparison = null;
    local = null;
    confirmed = null;
    labels.clear();
    expectedVersion = source?.version ?? 0;
    final today = CivilDate.parse(
      DateTime.now().toIso8601String().substring(0, 10),
    ).value;
    final p = <String, Object?>{
      'action': a,
      'id': a == 'settle' ? uuid.v4() : source?.id ?? uuid.v4(),
      'project_id': projectId,
      'reason': '',
    };
    if (a == 'service_source') {
      expectedVersion = 0;
      p.addAll({
        'service_source_id': null,
        'source_version': null,
        'source_digest': null,
      });
    }
    if (a == 'expense_create' || a == 'expense_correct') {
      if (a == 'expense_correct' && source == null) {
        throw const FormatException('Choose the original expense.');
      }
      for (final k in projectFinanceFields(
        a,
      ).difference({'action', 'id', 'project_id', 'reason'})) {
        p[k] = source?.values[k];
      }
      if (source == null) {
        p.addAll({
          'external_reference': '',
          'service_date': today,
          'purpose': '',
          'evidence_reference': '',
          'original_currency': currency,
          'original_precision': precision,
          'net': '0.00',
          'tax': '0.00',
          'gross': '0.00',
          'no_tax_reason': '',
          'billable': false,
          'bill_amount': '0.00',
          'allocations': <Map<String, Object?>>[],
        });
      } else {
        p['allocations'] = (source.values['allocations'] as List).map((v) {
          final r = projectMap(v);
          return {'task_id': r['task_id'], 'weight': r['weight']};
        }).toList();
      }
    }
    if (a == 'expense_approve' || a == 'expense_reject') {
      p['digest'] = source?.values['digest'];
    }
    if (a == 'expense_post' ||
        a == 'expense_reverse' ||
        a == 'settle' ||
        a == 'settlement_reverse') {
      p['posting_date'] = today;
    }
    if (a == 'settle') {
      if (source?.section != ProjectFinanceSection.obligations) {
        throw const FormatException('Choose an original obligation.');
      }
      expectedVersion = 0;
      p.addAll({
        'obligation_id': source!.id,
        'amount': source.values['outstanding'],
        'bank_id': null,
        'bank_version': null,
        'evidence_reference': '',
      });
    }
    if (a == 'billing_prepare') {
      expectedVersion = 0;
      p.addAll({
        'invoice_id': uuid.v4(),
        'document_date': DateTime.now().toUtc().toIso8601String().substring(
          0,
          10,
        ),
        'due_date': today,
        'exchange_rate_id': null,
        'units': <Map<String, Object?>>[],
      });
    } else if (a.startsWith('billing_')) {
      if (source?.section != ProjectFinanceSection.billing) {
        throw const FormatException('Choose an original billing batch.');
      }
      p['invoice_version'] = source!.values['invoice_version'];
      if (a == 'billing_decide') {
        p['decision'] = 'approved';
      }
    }
    form = p;
    message = null;
  });
  void change(String key, Object? value) {
    if (locked ||
        form == null ||
        !projectFinanceFields(action!).contains(key) ||
        {
          'action',
          'id',
          'project_id',
          'digest',
          'invoice_id',
          'invoice_version',
          'obligation_id',
        }.contains(key)) {
      return;
    }
    form = {...form!, key: value};
    _notify();
  }

  void choose(String field, ProjectFinanceChoice value) {
    if (locked) {
      return;
    }
    change(field, value.id);
    labels[value.id] = '${value.code} · ${value.name}';
    if (field == 'tax_definition_id') {
      change('tax_version', value.version);
      change('no_tax_reason', null);
    }
    if (field == 'exchange_rate_id' && action != 'billing_prepare') {
      change('exchange_rate_version', value.version);
    }
    if (field == 'bank_id') {
      change('bank_version', value.version);
    }
    if (field == 'service_source_id') {
      change('source_version', value.values['source_version']);
      change('source_digest', value.values['source_digest']);
    }
    _notify();
  }

  void allocate(String taskId, int weight, String name) {
    if (locked ||
        !(action == 'expense_create' || action == 'expense_correct')) {
      return;
    }
    final list = (form!['allocations'] as List).map(projectMap).toList();
    if (list.length >= 50 ||
        weight <= 0 ||
        list.any((v) => v['task_id'] == taskId)) {
      throw const FormatException(
        'Choose distinct tasks and positive bounded weights.',
      );
    }
    projectIdentity(taskId);
    list.add({'task_id': taskId, 'weight': weight});
    labels[taskId] = name;
    change('allocations', list);
  }

  void removeAllocation(String taskId) {
    if (locked) {
      return;
    }
    change(
      'allocations',
      (form!['allocations'] as List)
          .map(projectMap)
          .where((v) => v['task_id'] != taskId)
          .toList(),
    );
  }

  void bill(
    ProjectFinanceRow unit,
    ProjectFinanceChoice product,
    ProjectFinanceChoice? tax,
    String description,
  ) {
    if (locked || action != 'billing_prepare') {
      return;
    }
    if (unit.section != ProjectFinanceSection.units ||
        unit.status != 'available') {
      throw const FormatException('Choose an available whole source.');
    }
    final list = (form!['units'] as List).map(projectMap).toList();
    if (list.length >= 200 || list.any((v) => v['unit_id'] == unit.id)) {
      throw const FormatException('Choose distinct whole sources.');
    }
    list.add({
      'unit_id': unit.id,
      'source_version': unit.version,
      'source_digest': unit.values['source_digest'],
      'product_id': product.id,
      'product_version': product.version,
      'tax_definition_id': tax?.id,
      'tax_version': tax?.version,
      'description': description,
    });
    labels[unit.id] = unit.title;
    labels[product.id] = product.name;
    change('units', list);
  }

  void removeUnit(String id) {
    if (locked) {
      return;
    }
    change(
      'units',
      (form!['units'] as List)
          .map(projectMap)
          .where((v) => v['unit_id'] != id)
          .toList(),
    );
  }

  Future<void> _recover({String? action, bool more = false}) async {
    for (final a in action == null ? projectFinanceActions : {action}) {
      if (!has(projectFinanceCapability(a))) {
        continue;
      }
      await _access(projectFinanceCapability(a));
      if (!current) {
        return;
      }
      final page = await drafts[a]!.page(
        scope,
        after: more ? recoveryCursors[a] : null,
      );
      if (!current) {
        return;
      }
      recovery = [
        ...recovery.where((d) => d.action != a || more),
        ...page.items
            .where((d) => d.form['project_id'] == projectId)
            .map((d) => ProjectFinanceSavedDraft(a, d)),
      ];
      recoveryCursors[a] = page.nextCursor;
    }
  }

  Future<void> moreRecovery(String a) =>
      _run(() => _recover(action: a, more: true));
  void _cache(String a, ScopedCommandDraft d) {
    recovery = [
      ...recovery.where(
        (v) => v.action != a || v.draft.aggregateId != d.aggregateId,
      ),
      ProjectFinanceSavedDraft(a, d),
    ];
  }

  Future<void> save() => _run(() async {
    if (form == null || pending != null || conflict || confirmed != null) {
      return;
    }
    await _access(projectFinanceCapability(action!));
    if (!current) {
      return;
    }
    await drafts[action]!.save(
      scope,
      form!['id'] as String,
      action!,
      form!,
      expectedVersion,
    );
    if (!current) {
      return;
    }
    local = await drafts[action]!.load(scope, form!['id'] as String);
    if (current && local != null) {
      _cache(action!, local!);
    }
  });
  Future<void> resume(ProjectFinanceSavedDraft d) => _run(() async {
    if (pending != null || confirmed != null) {
      throw const DomainError(
        code: 'COMMAND_PENDING',
        message: 'Resolve the current original request first.',
      );
    }
    await _access(projectFinanceCapability(d.action));
    final value = await drafts[d.action]!.load(scope, d.draft.aggregateId);
    if (!current || value == null) {
      return;
    }
    if (value.form['project_id'] != projectId) {
      throw const FormatException('Draft project changed.');
    }
    form = projectMap(
      jsonDecode(jsonEncode(value.pending?.envelope.payload ?? value.form)),
    );
    local = value;
    expectedVersion = value.version;
    review = null;
    comparison = null;
    confirmed = null;
    labels.clear();
    if (value.pending == null &&
        {'expense_approve', 'expense_reject'}.contains(d.action)) {
      await _access('projects.cost.view');
      final page = await repository.detail(
        scope,
        projectId,
        currency,
        ProjectFinanceSection.expenses,
        targetId: d.draft.aggregateId,
      );
      if (current && page.rows.length == 1) {
        review = page.rows.single;
      }
    }
  });
  Map<String, Object?> verify(Map<String, Object?> r, ScopedPendingCommand p) {
    calendarFields(r, {
      'request_id',
      'command_id',
      'correlation_id',
      'entity',
      'warnings',
    });
    final e = projectMap(r['entity']);
    projectScope(e, scope);
    if (r['command_id'] != p.envelope.commandId ||
        e['id'] != p.envelope.payload['id'] ||
        e['project_id'] != projectId ||
        e['version'] != p.envelope.expectedEntityVersion! + 1 ||
        r['warnings'] is! List ||
        (r['warnings'] as List).isNotEmpty) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Confirmation differs from the original finance request.',
        retryable: true,
      );
    }
    return e;
  }

  Future<void> _confirmed(
    Map<String, Object?> r,
    ScopedPendingCommand p,
  ) async {
    final entity = verify(r, p);
    if (!current) {
      return;
    }
    confirmed = entity;
    message = 'Confirmed. The original finance request succeeded.';
    _notify();
    try {
      await drafts[p.action]!.complete(
        scope,
        p.envelope.payload['id'] as String,
        p.envelope.commandId,
      );
      if (!current) {
        return;
      }
      local = null;
      recovery.removeWhere(
        (d) => d.action == p.action && d.draft.aggregateId == entity['id'],
      );
    } catch (_) {
      if (current) {
        message = 'Confirmed. Retain the original receipt while encrypted cleanup is reconciled.';
      }
      return;
    }
    try {
      await _load(section);
    } catch (_) {
      if (current) {
        message = 'Confirmed. The optional project view is unavailable; refresh it later.';
      }
    }
  }

  Future<void> send() => _run(() async {
    if (form == null || conflict || confirmed != null) {
      return;
    }
    final a = action!, id = form!['id'] as String;
    await _access(projectFinanceCapability(a));
    if (!current) {
      return;
    }
    if (pending == null &&
        {'expense_approve', 'expense_reject'}.contains(a) &&
        (review == null ||
            review!.id != id ||
            review!.version != expectedVersion ||
            review!.values['digest'] != form!['digest'])) {
      throw const DomainError(
        code: 'REVIEW_REQUIRED',
        message: 'Review the complete immutable expense before deciding.',
      );
    }
    final sealed = await drafts[a]!.prepare(
      scope,
      id,
      a,
      form!,
      expectedVersion,
    );
    if (!current) {
      return;
    }
    local = await drafts[a]!.load(scope, id);
    if (!current) {
      return;
    }
    if (local != null) {
      _cache(a, local!);
    }
    try {
      final r = await repository.command(sealed.envelope);
      if (current) {
        await _confirmed(r, sealed);
      }
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
        _deny();
      } else if (current) {
        error = e.message;
      }
    } catch (_) {
      const e = DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Reconcile the exact encrypted finance request.',
        retryable: true,
      );
      await drafts[a]!.recordFailure(scope, id, sealed.envelope.commandId, e);
      if (current) {
        local = await drafts[a]!.load(scope, id);
        if (current && local != null) {
          _cache(a, local!);
        }
        error = e.message;
      }
    }
  });
  Future<void> reconcile() => _run(() async {
    final p = pending;
    if (p == null) {
      return;
    }
    await _access(projectFinanceCapability(p.action));
    if (!current) {
      return;
    }
    final r = await repository.receipt(scope, p.envelope.commandId, p.action);
    if (!current) {
      return;
    }
    if (r == null) {
      message =
          'No original receipt is recorded. Retry this exact sealed request.';
    } else {
      await _confirmed(r, p);
    }
  });
  Future<void> compare() => _run(() async {
    if (!conflict || form == null) {
      return;
    }
    final s = action!.startsWith('billing_')
        ? ProjectFinanceSection.billing
        : action == 'settlement_reverse'
        ? ProjectFinanceSection.settlements
        : ProjectFinanceSection.expenses;
    final p = await repository.detail(
      scope,
      projectId,
      currency,
      s,
      targetId: form!['id'] as String,
    );
    if (current) {
      comparison = p.rows.single;
    }
  });
  Future<void> replace() => _run(() async {
    if (!conflict || comparison == null || pending != null) {
      return;
    }
    await _access(projectFinanceCapability(action!));
    if (!current) {
      return;
    }
    final replacement = {...form!};
    if (action == 'expense_approve' || action == 'expense_reject') {
      replacement['digest'] = comparison!.values['digest'];
    }
    if (action!.startsWith('billing_')) {
      replacement['invoice_version'] = comparison!.values['invoice_version'];
    }
    await drafts[action]!.save(
      scope,
      replacement['id'] as String,
      action!,
      replacement,
      comparison!.version,
      resolveConflict: true,
    );
    if (!current) {
      return;
    }
    form = replacement;
    expectedVersion = comparison!.version;
    local = await drafts[action]!.load(scope, replacement['id'] as String);
    review = comparison;
    comparison = null;
    if (current && local != null) {
      _cache(action!, local!);
    }
  });
  void closeForm() {
    if (pending != null || conflict) {
      return;
    }
    form = null;
    confirmed = null;
    local = null;
    review = null;
    comparison = null;
    labels.clear();
    _epoch++;
    _notify();
  }

  Future<bool> canLeave() async {
    if (!current) {
      return true;
    }
    if (busy || pending != null || conflict) {
      return false;
    }
    if (form == null || confirmed != null) {
      return true;
    }
    await save();
    return current && error == null && local != null;
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _timer?.cancel();
    rows = [];
    report = null;
    form = null;
    local = null;
    confirmed = null;
    review = null;
    comparison = null;
    recovery = [];
    labels.clear();
    super.dispose();
  }
}

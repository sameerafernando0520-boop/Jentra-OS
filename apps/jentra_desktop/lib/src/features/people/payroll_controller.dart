import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_payroll.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_platform/jentra_payroll_platform.dart';
import 'package:jentra_platform/jentra_people_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import 'employee_controller.dart';

enum PayrollView { runs, rules, payslips, self }

final payrollRepositoryProvider = Provider<PayrollRepository?>((ref) => null);
final payrollFilesProvider = Provider<PayrollFiles>(
  (ref) => const NativePayrollFiles(),
);
final payrollControllerProvider = Provider.autoDispose<PayrollController?>((
  ref,
) {
  final scope = ref.watch(activeTenantContextProvider),
      caps = ref.watch(businessCapabilitiesProvider),
      repository = ref.watch(payrollRepositoryProvider);
  if (scope == null ||
      !scope.hasOperationalScope ||
      repository == null ||
      caps.isLoading ||
      caps.hasError ||
      !(caps.value?.contains('people.view') ?? false) ||
      !{
        'people.payroll.view',
        'people.payroll.payslip.view',
        'people.payroll.payslip.self',
      }.any((p) => caps.value!.contains(p))) {
    return null;
  }
  final c = PayrollController(
    scope: scope,
    repository: repository,
    employees: ref.watch(employeeRepositoryProvider),
    files: ref.watch(payrollFilesProvider),
    drafts: SensitivePayrollDraftStore(
      ref.watch(encryptedDraftRepositoryProvider),
      repository.authorize,
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

final class PayrollController extends ChangeNotifier {
  PayrollController({
    required this.scope,
    required this.repository,
    required this.employees,
    required this.files,
    required this.drafts,
    required Set<String> permissions,
    required this.online,
    DateTime Function()? clock,
    bool monitor = true,
  }) : permissions = Set.unmodifiable(permissions),
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
  final PayrollRepository repository;
  final EmployeeRepository? employees;
  final PayrollFiles files;
  final SensitivePayrollDraftStore drafts;
  final Set<String> permissions;
  final DateTime Function() clock;
  static const _uuid = Uuid();
  Timer? _timer;
  bool online,
      busy = false,
      accessDenied = false,
      _disposed = false,
      _sending = false;
  late PayrollView view;
  String? error,
      message,
      cursor,
      calculationCursor,
      obligationCursor,
      settlementCursor,
      historyCursor,
      employeeId,
      employeeName,
      preparedExportId,
      preparedExportDigest;
  List<PayrollRun> runs = [];
  List<PayrollRuleVersion> rules = [];
  List<PayrollEmployeeCalculation> calculations = [];
  List<Map<String, Object?>> obligations = [],
      settlements = [],
      history = [],
      payslips = [],
      assignments = [];
  String? assignmentCursor;
  Map<String, Object?>? frozenSnapshot;
  List<SensitivePayrollRecovery> recovery = [];
  PayrollRun? selectedRun;
  PayrollRuleVersion? selectedRule;
  Map<String, Object?>? settings,
      calculation,
      selectedPayslip,
      form,
      confirmed,
      comparison;
  PayrollCommandKind? kind;
  int expectedVersion = 0;
  SensitivePayrollDraft? local;
  DateTime? _expiry;
  final labels = <String, String>{};
  bool get current => !_disposed && !accessDenied;
  bool has(String cap) => permissions.contains(cap);
  List<PayrollView> get views => [
    if (has('people.payroll.view')) ...[PayrollView.runs, PayrollView.rules],
    if (has('people.payroll.payslip.view')) PayrollView.payslips,
    if (has('people.payroll.payslip.self')) PayrollView.self,
  ];
  String get viewCapability => switch (view) {
    PayrollView.runs || PayrollView.rules => 'people.payroll.view',
    PayrollView.payslips => 'people.payroll.payslip.view',
    PayrollView.self => 'people.payroll.payslip.self',
  };
  bool get conflict => {
    'VERSION_CONFLICT',
    'PAYROLL_INPUTS_CHANGED',
    'PAYROLL_RULES_CHANGED',
  }.contains(local?.errorCode);
  ScopedPendingCommand? get pending => local?.pending;
  bool get locked =>
      busy || !current || pending != null || conflict || confirmed != null;
  String? get action => form?['action'] as String?;
  String get asOf =>
      form?['start_date'] as String? ??
      clock().toIso8601String().substring(0, 10);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void setOnline(bool value) {
    online = value;
    _notify();
  }

  void _clearForm() {
    form = null;
    kind = null;
    local = null;
    confirmed = null;
    comparison = null;
    _expiry = null;
    labels.clear();
  }

  void _clear() {
    _clearForm();
    runs = [];
    rules = [];
    calculations = [];
    obligations = [];
    settlements = [];
    history = [];
    payslips = [];
    assignments = [];
    frozenSnapshot = null;
    recovery = [];
    selectedRun = null;
    selectedRule = null;
    settings = null;
    calculation = null;
    selectedPayslip = null;
    employeeId = null;
    employeeName = null;
    preparedExportId = null;
    preparedExportDigest = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _clear();
    notifyListeners();
    super.dispose();
  }

  bool _denied(Object e) =>
      e is DomainError &&
      {
        'PERMISSION_DENIED',
        'FEATURE_NOT_ENTITLED',
        'AUTHENTICATION_REQUIRED',
        'PAYROLL_MFA_REQUIRED',
      }.contains(e.code);
  void _connected() {
    if (!online || !current) {
      throw const DomainError(
        code: 'OFFLINE',
        message: 'Connect with current payroll access.',
      );
    }
  }

  void _require(String cap) {
    if (!has(cap)) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'This payroll action requires separate permission.',
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
        _clear();
      }
      if (!_disposed) {
        error = e is DomainError
            ? e.message
            : e is FormatException
            ? e.message
            : 'Payroll is unavailable. The encrypted request is retained.';
      }
    } finally {
      _sending = false;
      busy = false;
      _notify();
    }
  }

  Future<void> checkAccess() async {
    if (!current) return;
    if (_expiry != null && !_expiry!.isAfter(clock())) {
      _clearForm();
      message = 'Private payroll fields expired. Reconcile the saved receipt.';
      _notify();
    }
    if (busy || !online) return;
    try {
      for (final cap in {
        viewCapability,
        if (kind != null && action != null)
          PayrollCommands.capability(kind!, action!),
        if (selectedPayslip != null) 'people.payroll.payslip.view',
        if (preparedExportId != null) 'people.payroll.export',
      }) {
        await repository.authorize(scope, cap);
      }
    } catch (e) {
      if (_denied(e)) {
        accessDenied = true;
        _clear();
        error = 'Payroll access changed.';
        _notify();
      }
    }
  }

  Future<void> initialize() => _run(() async {
    await _refresh();
    await _recover();
  });
  Future<void> _recover() async {
    if (!online) return;
    final items = await drafts.recovery(scope);
    if (current) recovery = items;
  }

  Future<void> _refresh({bool more = false}) async {
    _connected();
    switch (view) {
      case PayrollView.runs:
        final page = await repository.runs(scope, after: more ? cursor : null);
        if (current) {
          runs = [if (more) ...runs, ...page.items];
          cursor = page.nextCursor;
        }
        if (!more) {
          final s = await repository.settings(scope);
          if (current) settings = s;
        }
      case PayrollView.rules:
        final page = await repository.rules(scope, after: more ? cursor : null);
        if (current) {
          rules = [if (more) ...rules, ...page.items];
          cursor = page.nextCursor;
        }
        if (!more) {
          final s = await repository.settings(scope);
          if (current) settings = s;
          if (current && employeeId != null) await _assignments();
        }
      case PayrollView.payslips:
        if (employeeId == null) return;
        final page = await repository.payslips(
          scope,
          employeeId!,
          after: more ? cursor : null,
        );
        if (current) {
          payslips = [if (more) ...payslips, ...page.items];
          cursor = page.nextCursor;
        }
      case PayrollView.self:
        final page = await repository.selfPayslips(
          scope,
          after: more ? cursor : null,
        );
        if (current) {
          payslips = [if (more) ...payslips, ...page.items];
          cursor = page.nextCursor;
        }
    }
  }

  Future<void> refresh({bool more = false}) => _run(() => _refresh(more: more));
  Future<void> _assignments({bool more = false}) async {
    final employee = employeeId;
    if (employee == null) return;
    final page = await repository.assignments(
      scope,
      employee,
      after: more ? assignmentCursor : null,
    );
    if (current) {
      assignments = [if (more) ...assignments, ...page.items];
      assignmentCursor = page.nextCursor;
    }
  }

  Future<void> moreAssignments() => _run(() => _assignments(more: true));
  Future<void> changeView(PayrollView next) => _run(() async {
    if (!views.contains(next) || !await canLeave()) return;
    _clearForm();
    view = next;
    cursor = null;
    selectedPayslip = null;
    payslips = [];
    await _refresh();
  });
  Future<List<Map<String, Object?>>> employeeChoices(
    String query, {
    String? after,
  }) async {
    _connected();
    _require('people.employees.view');
    if (employees == null) return [];
    final page = await employees!.directory(
      scope,
      asOfDate: asOf,
      search: query,
      after: after,
    );
    if (!current) return [];
    return (page['items'] as List).map(workforceMap).toList();
  }

  Future<void> selectEmployee(String id, String name) => _run(() async {
    _connected();
    if (!await canLeave()) return;
    if (!current) return;
    calendarUuid(id);
    _clearForm();
    payslips = [];
    assignments = [];
    cursor = null;
    assignmentCursor = null;
    preparedExportId = null;
    preparedExportDigest = null;
    employeeId = id;
    employeeName = name;
    selectedPayslip = null;
    await _refresh();
  });
  void addEmployee(String id, String name) {
    if (locked || action != 'create' || kind != PayrollCommandKind.run) return;
    calendarUuid(id);
    final ids = List<String>.from(form!['employee_ids'] as List);
    if (!ids.contains(id) && ids.length < 200) ids.add(id);
    form = {...form!, 'employee_ids': ids};
    labels[id] = name;
    _notify();
  }

  void removeEmployee(String id) {
    if (locked || action != 'create') return;
    form = {
      ...form!,
      'employee_ids': (form!['employee_ids'] as List)
          .where((v) => v != id)
          .toList(),
    };
    _notify();
  }

  Future<WorkforcePage<Map<String, Object?>>> accountChoices(
    String type, {
    String? after,
  }) async {
    _connected();
    return repository.accounts(scope, type, after: after);
  }

  Future<void> openRun(String id, {bool more = false}) =>
      _run(() => _openRun(id, more: more));
  Future<void> _openRun(String id, {bool more = false}) async {
    _connected();
    final detail = await repository.detail(
      scope,
      id,
      after: more ? calculationCursor : null,
    );
    if (!current) return;
    if (more && selectedRun?.revisionId != detail.run.revisionId) {
      throw const DomainError(
        code: 'VERSION_CONFLICT',
        message: 'The payroll revision changed. Reload the run.',
      );
    }
    selectedRun = detail.run;
    calculations = [if (more) ...calculations, ...detail.calculations.items];
    calculationCursor = detail.calculations.nextCursor;
    if (!more) {
      calculation = null;
      frozenSnapshot = null;
      obligations = [];
      settlements = [];
      history = [];
      final events = await repository.history(scope, id);
      if (!current) return;
      history = events.items;
      historyCursor = events.nextCursor;
      if (has('people.payroll.settle')) {
        final due = await repository.obligations(scope, id);
        if (!current) return;
        obligations = due.items;
        obligationCursor = due.nextCursor;
        final paid = await repository.settlements(scope, id);
        if (!current) return;
        settlements = paid.items;
        settlementCursor = paid.nextCursor;
      }
    }
  }

  Future<void> moreRelated(String type) => _run(() async {
    final id = selectedRun?.id;
    if (id == null) return;
    final page = switch (type) {
      'obligations' => await repository.obligations(
        scope,
        id,
        after: obligationCursor,
      ),
      'settlements' => await repository.settlements(
        scope,
        id,
        after: settlementCursor,
      ),
      _ => await repository.history(scope, id, after: historyCursor),
    };
    if (!current) return;
    if (type == 'obligations') {
      obligations = [...obligations, ...page.items];
      obligationCursor = page.nextCursor;
    } else if (type == 'settlements') {
      settlements = [...settlements, ...page.items];
      settlementCursor = page.nextCursor;
    } else {
      history = [...history, ...page.items];
      historyCursor = page.nextCursor;
    }
  });
  Future<void> openCalculation(
    PayrollEmployeeCalculation row, {
    bool moreLines = false,
    bool moreSources = false,
  }) => _run(() async {
    final run = selectedRun;
    if (run == null) return;
    final prior = calculation;
    final data = await repository.calculation(
      scope,
      row.id,
      run.currency,
      afterCode: moreLines ? (prior?['next_code'] as String?) : null,
      sourceAfter: moreSources ? (prior?['next_source'] as String?) : null,
    );
    if (!current) return;
    if (data['run_id'] != run.id ||
        data['revision_id'] != run.revisionId ||
        data['employee_id'] != row.employeeId ||
        data['input_digest'] != row.digest) {
      throw const FormatException(
        'Payroll calculation does not match the selected revision.',
      );
    }
    calculation = {
      ...data,
      'lines': moreSources
          ? prior!['lines']
          : [
              if (moreLines) ...(prior!['lines'] as List),
              ...(data['lines'] as List),
            ],
      'sources': moreLines
          ? prior!['sources']
          : [
              if (moreSources) ...(prior!['sources'] as List),
              ...(data['sources'] as List),
            ],
      'next_code': moreSources ? prior!['next_code'] : data['next_code'],
      'next_source': moreLines ? prior!['next_source'] : data['next_source'],
    };
    if (!moreLines && !moreSources) frozenSnapshot = null;
  });
  Future<void> openSnapshot(String section, {bool more = false}) =>
      _run(() async {
        final calc = calculation;
        if (calc == null) return;
        final old = frozenSnapshot;
        final data = await repository.snapshot(
          scope,
          calc['id'] as String,
          section,
          after: more && old?['section'] == section
              ? old!['next_position'] as int
              : 0,
        );
        if (!current) return;
        for (final key in [
          'id',
          'run_id',
          'revision_id',
          'employee_id',
          'input_digest',
        ]) {
          if (data[key] != calc[key]) {
            throw const FormatException(
              'Frozen payroll snapshot changed revision.',
            );
          }
        }
        frozenSnapshot = {
          ...data,
          'items': [
            if (more) ...(old!['items'] as List),
            ...(data['items'] as List),
          ],
        };
      });
  Future<void> openPayslip(String id, {bool more = false}) => _run(() async {
    _require('people.payroll.payslip.view');
    final data = await repository.payslip(
      scope,
      id,
      afterCode: more ? (selectedPayslip?['next_code'] as String?) : null,
    );
    if (!current) return;
    selectedPayslip = {
      ...data,
      'lines': [
        if (more) ...(selectedPayslip!['lines'] as List),
        ...(data['lines'] as List),
      ],
    };
  });
  bool canTransition(String action) {
    final r = selectedRun;
    if (r == null ||
        !has(PayrollCommands.capability(PayrollCommandKind.run, action))) {
      return false;
    }
    return switch (action) {
      'prepare' => {
        'draft',
        'prepared',
        'submitted',
        'approved',
      }.contains(r.status),
      'submit' => r.status == 'prepared',
      'approve' =>
        r.status == 'submitted' &&
            r.preparedBy != scope.actorId &&
            r.submittedBy != scope.actorId,
      'post' => r.status == 'approved',
      'reverse' => r.status == 'posted',
      'cancel' => !{'posted', 'reversed', 'cancelled'}.contains(r.status),
      _ => false,
    };
  }

  Future<void> begin(
    PayrollCommandKind next,
    String command, {
    Map<String, Object?>? source,
  }) => _run(() async {
    _connected();
    _require(PayrollCommands.capability(next, command));
    if (!await canLeave()) return;
    final today = clock().toIso8601String().substring(0, 10),
        newId = _uuid.v4();
    _clearForm();
    kind = next;
    expectedVersion = 0;
    switch (next) {
      case PayrollCommandKind.run:
        if (command == 'create') {
          form = {
            'action': command,
            'id': newId,
            'name': 'Synthetic payroll',
            'start_date': today,
            'end_date_exclusive': clock()
                .add(const Duration(days: 1))
                .toIso8601String()
                .substring(0, 10),
            'posting_date': today,
            'employee_ids': <String>[],
            'reason': '',
          };
        } else {
          if (!canTransition(command)) {
            kind = null;
            return;
          }
          final run = selectedRun!;
          expectedVersion = run.version;
          form = {
            'action': command,
            'id': run.id,
            'reason': '',
            if ({'submit', 'approve', 'post', 'reverse'}.contains(command)) ...{
              'revision_id': run.revisionId,
              'digest': run.digest,
            },
          };
        }
      case PayrollCommandKind.configuration:
        if (command == 'settings') {
          expectedVersion = settings?['version'] as int? ?? 0;
          form = {
            'action': command,
            'id': newId,
            'net_account_id': settings?['net_account_id'],
            'reason': '',
          };
        } else if (command == 'assign') {
          final rule = selectedRule;
          if (rule == null) {
            kind = null;
            return;
          }
          form = {
            'action': command,
            'id': newId,
            'employee_id': null,
            'component_id': rule.componentId,
            'start_date': rule.rule.start.value,
            'end_date_exclusive': rule.rule.endExclusive.value,
            'reason': '',
          };
        } else {
          final old = selectedRule;
          final start = old?.rule.endExclusive ?? CivilDate.parse(today);
          expectedVersion = old?.version ?? 0;
          form = {
            'action': command,
            'id': newId,
            'component_id': old?.componentId ?? _uuid.v4(),
            'code': old?.rule.code ?? '',
            'name': old?.name ?? '',
            'classification': switch (old?.rule.classification) {
              PayrollClassification.deduction => 'deduction',
              PayrollClassification.employerCost => 'employer_cost',
              _ => 'earning',
            },
            'start_date': start.value,
            'end_date_exclusive': start.utc
                .add(const Duration(days: 365))
                .toIso8601String()
                .substring(0, 10),
            'basis': switch (old?.rule.basis) {
              PayrollBasis.hourly => 'hourly',
              PayrollBasis.earningsRatio => 'earnings_ratio',
              _ => 'fixed',
            },
            'proration': switch (old?.rule.proration) {
              PayrollProration.eligibleDays => 'eligible_days',
              PayrollProration.paidSeconds => 'paid_seconds',
              _ => 'none',
            },
            'rounding': switch (old?.rule.rounding) {
              PayrollRounding.halfEven => 'half_even',
              PayrollRounding.truncate => 'truncate',
              PayrollRounding.floor => 'floor',
              _ => 'half_away',
            },
            'precision': old?.rule.precision ?? 2,
            'amount': old?.rule.amount.toDecimalString() ?? '0.000000',
            'ratio_numerator': old?.rule.ratioNumerator ?? 1,
            'ratio_denominator': old?.rule.ratioDenominator ?? 1,
            'cap': old?.rule.cap?.toDecimalString(),
            'expense_account_id': old?.expenseAccountId,
            'liability_account_id': old?.liabilityAccountId,
            'reason': '',
          };
        }
      case PayrollCommandKind.settlement:
        final run = selectedRun;
        if (run == null || run.status != 'posted') {
          kind = null;
          return;
        }
        if (command == 'record') {
          form = {
            'action': command,
            'id': newId,
            'run_id': run.id,
            'posting_date': today,
            'bank_id': null,
            'bank_version': null,
            'evidence_reference': '',
            'allocations': <Map<String, Object?>>[],
            'reason': '',
          };
        } else {
          if (source?['status'] != 'recorded') {
            kind = null;
            return;
          }
          expectedVersion = source!['version'] as int;
          form = {
            'action': command,
            'id': source['id'],
            'run_id': run.id,
            'posting_date': today,
            'reason': '',
          };
        }
      case PayrollCommandKind.export:
        if (source == null) {
          kind = null;
          return;
        }
        form = {'action': 'prepare', 'id': newId, 'payslip_id': source['id']};
    }
    _expiry = clock().add(const Duration(hours: 24));
  });
  void selectRule(PayrollRuleVersion? value) {
    if (!busy) {
      selectedRule = value;
      _notify();
    }
  }

  void update(String key, Object? value, {String? label}) {
    if (locked ||
        form == null ||
        PayrollCommands.fields[kind]?[action]?.contains(key) != true ||
        {
          'id',
          'action',
          'revision_id',
          'digest',
          'run_id',
          'component_id',
        }.contains(key)) {
      return;
    }
    form = {...form!, key: value};
    if (key == 'classification') {
      if (value == 'earning') form!['liability_account_id'] = null;
      if (value == 'deduction') form!['expense_account_id'] = null;
    }
    if (key == 'basis') {
      if (value == 'earnings_ratio') {
        form!['amount'] = '0.000000';
      } else {
        form!['ratio_numerator'] = 1;
        form!['ratio_denominator'] = 1;
      }
      if (value != 'fixed') form!['proration'] = 'none';
    }
    if (label != null) labels[key] = label;
    _notify();
  }

  void allocation(String obligationId, String amount) {
    if (locked || kind != PayrollCommandKind.settlement || action != 'record') {
      return;
    }
    final rows = (form!['allocations'] as List)
        .map(workforceMap)
        .where((r) => r['obligation_id'] != obligationId)
        .toList();
    if (amount.isNotEmpty && rows.length < 200) {
      rows.add({'obligation_id': obligationId, 'amount': amount});
    }
    form = {...form!, 'allocations': rows};
    _notify();
  }

  Future<void> _save({bool compared = false}) async {
    if (form == null || kind == null || confirmed != null || pending != null) {
      return;
    }
    final savedKind = kind!,
        savedForm = workforceMap(jsonDecode(jsonEncode(form!))),
        savedAction = action!,
        savedVersion = expectedVersion,
        id = form!['id'] as String;
    await drafts.save(
      scope,
      savedKind,
      id,
      savedAction,
      savedForm,
      savedVersion,
      compared: compared,
    );
    if (!current) return;
    final data = await drafts.load(scope, savedKind, id);
    if (current) {
      local = data;
      _expiry = data?.expiresAt;
      message = 'Encrypted payroll draft saved.';
    }
  }

  Future<void> saveLocal() => _run(() => _save());
  Future<bool> canLeave() async {
    if (_sending) return false;
    if (busy && form == null || _disposed) return !_disposed;
    try {
      await _save();
      return current;
    } catch (_) {
      message = 'Save or resolve the payroll draft before leaving.';
      _notify();
      return false;
    }
  }

  Future<void> submit() => _run(() async {
    _connected();
    if (form == null || kind == null || confirmed != null) return;
    final currentKind = kind!, id = form!['id'] as String;
    if (_expiry != null && !_expiry!.isAfter(clock())) {
      _clearForm();
      throw const DomainError(
        code: 'PRIVATE_DRAFT_EXPIRED',
        message: 'Private payroll fields expired. Reconcile its receipt.',
      );
    }
    _sending = true;
    _require(PayrollCommands.capability(currentKind, action!));
    final sealed =
        pending ??
        await drafts.prepare(
          scope,
          currentKind,
          id,
          action!,
          form!,
          expectedVersion,
        );
    if (!current) return;
    final saved = await drafts.load(scope, currentKind, id);
    if (!current) return;
    local = saved;
    try {
      final result = await repository.execute(currentKind, sealed.envelope);
      if (!current) return;
      // Commit local confirmation before optional list/detail refreshes.
      await drafts.complete(
        scope,
        currentKind,
        id,
        sealed.envelope.commandId,
        result,
      );
      if (!current) return;
      confirmed = result;
      local = null;
      message = 'Payroll command confirmed.';
      if (currentKind == PayrollCommandKind.export) {
        final entity = workforceMap(result['entity']);
        preparedExportId = id;
        preparedExportDigest = entity['content_digest'] as String;
      }
    } on DomainError catch (e) {
      if (current) {
        try {
          await drafts.failure(
            scope,
            currentKind,
            id,
            sealed.envelope.commandId,
            e,
          );
        } catch (_) {
          /* Keep the original seal when authorization or storage is unavailable. */
        }
        if (!_denied(e)) {
          final saved = await drafts.load(scope, currentKind, id);
          if (current) local = saved;
        }
      }
      rethrow;
    }
  });
  Future<void> closeEditor() => _run(() async {
    if (!await canLeave()) return;
    _clearForm();
    await _recover();
    await _refresh();
    if (selectedRun != null && view == PayrollView.runs) {
      await _openRun(selectedRun!.id);
    }
  });
  Future<void> resume(SensitivePayrollRecovery saved) => _run(() async {
    _connected();
    if (!await canLeave()) return;
    _clearForm();
    if (saved.expired) {
      final done = await drafts.reconcileExpired(
        scope,
        saved.kind,
        saved.id,
        repository,
      );
      if (current) message = done ? 'Expired payroll request confirmed.' : 'No confirmed receipt yet. The minimal encrypted receipt is retained.';
      await _recover();
      return;
    }
    final data = await drafts.load(scope, saved.kind, saved.id);
    if (!current || data == null) return;
    local = data;
    kind = data.kind;
    form = data.form;
    expectedVersion = data.version;
    _expiry = data.expiresAt;
    if (has('people.payroll.view') &&
        saved.kind == PayrollCommandKind.run &&
        data.action != 'create') {
      await _openRun(saved.id);
    }
    if (has('people.payroll.view') &&
        saved.kind == PayrollCommandKind.settlement) {
      await _openRun(data.form['run_id'] as String);
    }
  });
  Future<void> compare() => _run(() async {
    _connected();
    if (!conflict || kind == null || form == null) return;
    final id = form!['id'] as String;
    if (kind == PayrollCommandKind.run) {
      final detail = await repository.detail(scope, id);
      if (!current) return;
      comparison = detail.run.toJson();
      selectedRun = detail.run;
    } else if (kind == PayrollCommandKind.configuration) {
      if (action == 'settings') {
        final settings = await repository.settings(scope);
        if (!current) return;
        comparison = settings;
      } else if (action == 'publish') {
        String? after;
        PayrollRuleVersion? latest;
        var count = 0;
        do {
          final page = await repository.rules(scope, after: after);
          if (!current) return;
          for (final r in page.items) {
            if (r.componentId == form!['component_id'] &&
                (latest == null || r.version > latest.version)) {
              latest = r;
            }
          }
          count += page.items.length;
          after = page.nextCursor;
          if (count >= 2000 && after != null) {
            throw const DomainError(
              code: 'PAGE_LIMIT',
              message: 'Payroll rule comparison exceeds its bounded scan.',
            );
          }
        } while (after != null);
        comparison = {
          'version': latest?.version ?? 0,
          'kind': 'rule',
          'name': latest?.name,
        };
      } else {
        comparison = {'version': 0, 'kind': 'assignment'};
      }
    } else if (kind == PayrollCommandKind.settlement) {
      final runId = form!['run_id'] as String;
      String? after;
      Map<String, Object?>? match;
      var count = 0;
      do {
        final page = await repository.settlements(scope, runId, after: after);
        if (!current) return;
        match = page.items.where((r) => r['id'] == id).firstOrNull;
        count += page.items.length;
        after = page.nextCursor;
        if (match != null) break;
        if (count >= 2000 && after != null) {
          throw const DomainError(
            code: 'PAGE_LIMIT',
            message: 'Settlement comparison exceeds its bounded scan.',
          );
        }
      } while (after != null);
      comparison = match;
      if (comparison == null && action == 'record') {
        comparison = {'version': 0, 'kind': 'settlement'};
      }
    }
  });
  Future<void> acceptComparison() => _run(() async {
    if (comparison == null || form == null || kind == null) return;
    final currentVersion = comparison!['version'] as int;
    if (kind == PayrollCommandKind.run) {
      final run = PayrollRun.fromJson(comparison!);
      if (!canTransition(action!)) {
        throw const DomainError(
          code: 'STATE_CONFLICT',
          message: 'Choose an action supported by the current run.',
        );
      }
      if ({'submit', 'approve', 'post', 'reverse'}.contains(action)) {
        form = {...form!, 'revision_id': run.revisionId, 'digest': run.digest};
      }
    }
    expectedVersion = currentVersion;
    await _save(compared: true);
    comparison = null;
  });
  Future<void> discard() => _run(() async {
    if (kind == null || form == null) return;
    await drafts.discard(scope, kind!, form!['id'] as String);
    _clearForm();
    await _recover();
  });
  Future<void> writeExport() => _run(() async {
    _connected();
    _require('people.payroll.export');
    final id = preparedExportId, digest = preparedExportDigest;
    if (id == null || digest == null) return;
    final path = await files.chooseExport();
    if (path == null || !current) return;
    final data = await repository.exportContent(scope, id);
    if (!current) return;
    if (data['content_digest'] != digest) {
      throw const FormatException('The frozen payslip export changed.');
    }
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
    );
    try {
      await repository.authorize(scope, 'people.payroll.export');
      await repository.authorize(scope, 'people.payroll.payslip.view');
      if (!current) return;
      await files.write(path, bytes);
      if (current) message = 'Synthetic payslip saved to your selected file.';
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  });
}

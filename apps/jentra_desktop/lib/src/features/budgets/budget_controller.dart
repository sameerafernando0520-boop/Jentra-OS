import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';

final budgetGatewayProvider = Provider<BudgetGateway?>((ref) => null);

final budgetControllerProvider = Provider.autoDispose<BudgetController?>((ref) {
  final scope = ref.watch(activeTenantContextProvider);
  final gateway = ref.watch(budgetGatewayProvider);
  final access = ref.watch(businessCapabilitiesProvider);
  if (scope == null ||
      !scope.hasOperationalScope ||
      gateway == null ||
      access.isLoading ||
      access.hasError ||
      !(access.value?.contains('finance.view') ?? false)) {
    return null;
  }
  final controller = BudgetController(
    scope: scope,
    gateway: gateway,
    drafts: QuotationDraftStore(ref.watch(encryptedDraftRepositoryProvider)),
    permissions: access.value ?? {},
    online:
        ref.read(connectivityStateProvider).value == ConnectivityState.online,
  );
  ref.listen(
    connectivityStateProvider,
    (_, state) => controller.setOnline(state.value == ConnectivityState.online),
  );
  ref.onDispose(controller.dispose);
  unawaited(controller.initialize());
  return controller;
});

final class BudgetController extends ChangeNotifier {
  BudgetController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.permissions,
    required this.online,
  });

  static const editorSlot = 'budget-version-editor';
  static const varianceSlot = 'budget-variance-editor';
  final TenantContext scope;
  final BudgetGateway gateway;
  final QuotationDraftStore drafts;
  final Set<String> permissions;
  bool online,
      busy = false,
      verified = false,
      denied = false,
      _disposed = false;
  String? error,
      message,
      budgetCursor,
      reportCursor,
      accountCursor,
      periodCursor;
  String? baseCurrency;
  String accountSearch = '';
  String section = 'lines';
  String? budgetLineId;
  int? nextOffset;
  List<Map<String, Object?>> budgets = [],
      reports = [],
      accounts = [],
      periods = [],
      rows = [];
  Map<String, Object?> form = {}, varianceForm = {}, summary = {};
  QuotationLocalDraft? local, varianceLocal;

  bool get canManage => permissions.contains('finance.budgets.manage');
  bool get canApprove => permissions.contains('finance.budgets.approve');
  bool get pending => local?.pending != null;
  bool get variancePending => varianceLocal?.pending != null;
  bool get locked => busy || denied || !verified || pending;
  bool get varianceLocked => busy || denied || !verified || variancePending;
  String get today => DateTime.now().toUtc().toIso8601String().substring(0, 10);
  String? get selectedReportId => summary['id'] as String?;
  Map<String, Object?>? get selectedBudget => budgets
      .where((row) => row['id'] == varianceForm['budget_id'])
      .firstOrNull;

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _clearEvidence() {
    budgets = [];
    reports = [];
    accounts = [];
    periods = [];
    rows = [];
    summary = {};
    budgetCursor = null;
    reportCursor = null;
    accountCursor = null;
    accountSearch = '';
    periodCursor = null;
    nextOffset = null;
    baseCurrency = null;
  }

  void setOnline(bool value) {
    online = value;
    if (!online) {
      verified = false;
      _clearEvidence();
    }
    _emit();
  }

  void _handle(Object failure) {
    if (failure is DomainError && failure.code == 'PERMISSION_DENIED') {
      denied = true;
      verified = false;
      _clearEvidence();
      form = {};
      varianceForm = {};
    }
    error = failure is DomainError
        ? failure.message
        : failure is FormatException
        ? failure.message
        : 'Unable to confirm the result. The sealed request is retained.';
  }

  Future<void> _run(Future<void> Function() work) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    _emit();
    try {
      await work();
    } catch (failure) {
      _handle(failure);
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> initialize() => _run(() async {
    local = await drafts.load(scope, editorSlot);
    varianceLocal = await drafts.load(scope, varianceSlot);
    if (!online) return;
    _clearEvidence();
    await _loadAccounts();
    await _loadPeriods();
    await _loadBudgets();
    await _loadReports();
    if (_disposed) return;
    form = local?.form ?? _newBudget();
    varianceForm = varianceLocal?.form ?? _newVariance();
    verified = true;
    denied = false;
    if (varianceForm['report_id'] is String) {
      await _loadPage(varianceForm['report_id'] as String);
    }
  });

  Map<String, Object?> _newBudget() => {
    'id': const Uuid().v4(),
    'status': 'local',
    'version': 0,
    'period_id': null,
    'budget_year': DateTime.now().toUtc().year,
    'branch_id': scope.branchId,
    'currency_code': baseCurrency,
    'reason': '',
    'lines': <Map<String, Object?>>[],
  };
  Map<String, Object?> _newVariance() => {
    'id': const Uuid().v4(),
    'budget_id': null,
    'as_of': today,
    'status': 'local',
  };

  Future<void> _loadAccounts({bool more = false, String search = ''}) async {
    if (!online) return;
    final requestedSearch = more ? accountSearch : search.trim();
    final result = await gateway.accounts(
      scope,
      after: more ? accountCursor : null,
      search: requestedSearch,
    );
    if (_disposed) return;
    accounts = [
      if (more) ...accounts,
      for (final raw in result['items'] as List)
        (raw as Map).cast<String, Object?>(),
    ];
    accountCursor = result['next_cursor'] as String?;
    accountSearch = requestedSearch;
    baseCurrency = result['base_currency_code'] as String?;
  }

  Future<void> _loadPeriods({bool more = false}) async {
    if (!online) return;
    final result = await gateway.periods(
      scope,
      after: more ? periodCursor : null,
    );
    if (_disposed) return;
    periods = [
      if (more) ...periods,
      for (final raw in result['items'] as List)
        (raw as Map).cast<String, Object?>(),
    ];
    periodCursor = result['next_cursor'] as String?;
  }

  Future<void> _loadBudgets({bool more = false}) async {
    if (!online) return;
    final result = await gateway.budgets(
      scope,
      after: more ? budgetCursor : null,
    );
    if (_disposed) return;
    budgets = [
      if (more) ...budgets,
      for (final raw in result['items'] as List)
        (raw as Map).cast<String, Object?>(),
    ];
    budgetCursor = result['next_cursor'] as String?;
  }

  Future<void> _loadReports({bool more = false}) async {
    if (!online) return;
    final result = await gateway.reports(
      scope,
      after: more ? reportCursor : null,
    );
    if (_disposed) return;
    reports = [
      if (more) ...reports,
      for (final raw in result['items'] as List)
        (raw as Map).cast<String, Object?>(),
    ];
    reportCursor = result['next_cursor'] as String?;
  }

  Future<void> moreAccounts() => _run(() => _loadAccounts(more: true));
  Future<void> searchAccounts(String value) =>
      _run(() => _loadAccounts(search: value));
  Future<void> morePeriods() => _run(() => _loadPeriods(more: true));
  Future<void> moreBudgets() => _run(() => _loadBudgets(more: true));
  Future<void> moreReports() => _run(() => _loadReports(more: true));
  Future<void> refresh() => _run(() async {
    if (!online || denied || !verified) return;
    await _loadBudgets();
    await _loadReports();
    if (selectedReportId != null) await _loadPage(selectedReportId!);
  });

  Future<void> _persistBudget({bool resolveConflict = false}) async {
    await drafts.save(
      scope,
      editorSlot,
      form,
      expectedVersion: form['version'] as int? ?? 0,
      resolveConflict: resolveConflict,
    );
    local = await drafts.load(scope, editorSlot);
  }

  Future<void> _persistVariance() async {
    await drafts.save(scope, varianceSlot, varianceForm, expectedVersion: 0);
    varianceLocal = await drafts.load(scope, varianceSlot);
  }

  Future<void> saveEncrypted() => _run(() async {
    if (pending || variancePending || denied) return;
    await _persistBudget();
    await _persistVariance();
    message = 'Encrypted budget and variance drafts saved.';
  });
  Future<bool> canLeave() async {
    if (busy) return false;
    if (pending || variancePending || denied || !verified) return true;
    await saveEncrypted();
    return error == null;
  }

  Future<void> newBudget() => _run(() async {
    if (pending || !canManage || denied || !verified) return;
    await drafts.discard(scope, editorSlot);
    local = null;
    form = _newBudget();
    message = null;
    await _persistBudget();
  });
  Future<void> openBudget(String id) => _run(() async {
    if (pending || denied || !verified) return;
    final row = budgets.where((value) => value['id'] == id).firstOrNull;
    if (row == null) return;
    await drafts.discard(scope, editorSlot);
    local = null;
    form = {...row, 'branch_id': row['budget_branch_id']};
    await _persistBudget();
  });
  Future<void> revise() => _run(() async {
    if (pending || denied || !canManage || form['status'] != 'approved') return;
    final source = form;
    await drafts.discard(scope, editorSlot);
    local = null;
    form = {
      ...source,
      'id': const Uuid().v4(),
      'source_id': source['id'],
      'status': 'revision',
      'reason': '',
    };
    await _persistBudget();
  });
  void field(String key, Object? value) {
    if (locked ||
        !canManage ||
        !const {'local', 'draft', 'revision'}.contains(form['status']) ||
        !const {
          'period_id',
          'budget_year',
          'branch_id',
          'currency_code',
          'reason',
        }.contains(key)) {
      return;
    }
    form = {...form, key: value};
    _emit();
  }

  void decisionReason(String value) {
    if (locked || !(canManage || canApprove)) return;
    form = {...form, 'reason': value};
    _emit();
  }

  void addLine(String accountId, {bool allowDuplicate = false}) {
    if (locked ||
        !canManage ||
        !const {'local', 'draft', 'revision'}.contains(form['status'])) {
      return;
    }
    final lines = [...form['lines'] as List];
    if (lines.length >= 500 ||
        !allowDuplicate &&
            lines.any((x) => (x as Map)['account_id'] == accountId)) {
      return;
    }
    lines.add({
      'id': const Uuid().v4(),
      'account_id': accountId,
      'amount': '0',
      'cost_centre_id': null,
      'project_id': null,
    });
    form = {...form, 'lines': lines};
    _emit();
  }

  void financialDimension(
    int index,
    String kind,
    Map<String, Object?>? choice,
  ) {
    if (locked ||
        !online ||
        _disposed ||
        !canManage ||
        !{'local', 'draft', 'revision'}.contains(form['status']) ||
        !{'cost_centre', 'project'}.contains(kind)) {
      return;
    }
    if (choice != null &&
        (choice['status'] != 'active' ||
            choice['kind'] != kind ||
            choice['tenant_id'] != scope.tenantId ||
            choice['legal_entity_id'] != scope.legalEntityId ||
            choice['dimension_branch_id'] != null &&
                choice['dimension_branch_id'] != form['branch_id'])) {
      return;
    }
    final lines = [...form['lines'] as List];
    if (index < 0 || index >= lines.length) return;
    final row = (lines[index] as Map).cast<String, Object?>();
    final basis = {...(row['dimension_snapshot'] as Map? ?? {})}..remove(kind);
    if (choice != null) {
      basis[kind] = {
        for (final k in [
          'id',
          'tenant_id',
          'legal_entity_id',
          'kind',
          'version',
          'code',
          'name',
        ])
          k: choice[k],
        'branch_id': choice['dimension_branch_id'],
      };
    }
    lines[index] = {
      ...row,
      '${kind}_id': choice?['id'],
      'dimension_snapshot': basis.isEmpty ? null : basis,
    };
    form = {...form, 'lines': lines};
    _emit();
  }

  void amount(int index, String value) {
    if (locked ||
        !canManage ||
        !const {'local', 'draft', 'revision'}.contains(form['status'])) {
      return;
    }
    final lines = [...form['lines'] as List];
    if (index < 0 || index >= lines.length) return;
    lines[index] = {...lines[index] as Map, 'amount': value.trim()};
    form = {...form, 'lines': lines};
    _emit();
  }

  void removeLine(int index) {
    if (locked ||
        !canManage ||
        !const {'local', 'draft', 'revision'}.contains(form['status'])) {
      return;
    }
    final lines = [...form['lines'] as List];
    if (index < 0 || index >= lines.length) return;
    lines.removeAt(index);
    form = {...form, 'lines': lines};
    _emit();
  }

  void _validateBudget(String action) {
    if (!const {
      'create',
      'save',
      'submit',
      'approve',
      'reject',
      'revise',
    }.contains(action)) {
      throw const FormatException('Unknown budget action.');
    }
    if (form['reason'] is! String ||
        (form['reason'] as String).trim().length < 3 ||
        (form['reason'] as String).length > 1000) {
      throw const FormatException('Give a reason of 3 to 1000 characters.');
    }
    if (action == 'create' || action == 'save') {
      final lines = form['lines'];
      if (lines is! List || lines.isEmpty || lines.length > 500) {
        throw const FormatException('Add 1 to 500 budget accounts.');
      }
      final ids = <String>{};
      final prior = <Map>[];
      for (final raw in lines) {
        final line = raw as Map;
        final value = line['amount'];
        if (line['account_id'] is! String ||
            !ids.add(line['id'] as String) ||
            value is! String ||
            !RegExp(r'^\d+(\.\d{1,6})?$').hasMatch(value) ||
            ExactDecimal.parse(value, scale: 6).isNegative) {
          throw const FormatException(
            'Use valid lines and exact nonnegative amounts.',
          );
        }
        for (final earlier in prior) {
          if (earlier['account_id'] == line['account_id'] &&
              ['cost_centre_id', 'project_id'].every(
                (k) =>
                    earlier[k] == null ||
                    line[k] == null ||
                    earlier[k] == line[k],
              )) {
            throw const FormatException(
              'Budget dimension combinations must not overlap.',
            );
          }
        }
        prior.add(line);
      }
    }
    if (action == 'create') {
      final year = form['budget_year'];
      if (year is! int ||
          year < 2000 ||
          year > 2100 ||
          form['currency_code'] is! String ||
          form['branch_id'] != null && form['branch_id'] != scope.branchId) {
        throw const FormatException(
          'Choose a valid year, currency and branch.',
        );
      }
      final periodId = form['period_id'];
      if (periodId != null &&
          !periods.any(
            (row) =>
                row['id'] == periodId &&
                (row['start_date'] as String).startsWith('$year-'),
          )) {
        throw const FormatException('Choose a period in the budget year.');
      }
    }
  }

  Map<String, Object?> _payload(String action) => {
    'action': action,
    'id': form['id'],
    'reason': (form['reason'] as String).trim(),
    if (action == 'create') ...{
      'period_id': form['period_id'],
      'budget_year': form['budget_year'],
      'branch_id': form['branch_id'],
      'currency_code': form['currency_code'],
    },
    if (action == 'create' || action == 'save') 'lines': form['lines'],
    if (action == 'revise') 'source_id': form['source_id'],
  };

  Future<void> act(String action) => _run(() async {
    if (!online ||
        !verified ||
        denied ||
        !(const {'approve', 'reject'}.contains(action)
            ? canApprove
            : canManage)) {
      return;
    }
    var command = local?.pending;
    if (command == null) {
      _validateBudget(action);
      await _persistBudget();
      command = await drafts.prepare(
        scope,
        editorSlot,
        verb: const {'create', 'save', 'revise'}.contains(action)
            ? 'save'
            : action,
        expectedVersion: form['version'] as int? ?? 0,
        payload: _payload(action),
      );
      local = await drafts.load(scope, editorSlot);
    } else if (command.envelope.payload['action'] != action) {
      return;
    }
    Map<String, Object?> result;
    try {
      result = await gateway.command(command.envelope);
      await drafts.complete(scope, editorSlot, command.envelope.commandId);
    } on DomainError catch (failure) {
      await drafts.recordFailure(
        scope,
        editorSlot,
        failure,
        commandId: command.envelope.commandId,
      );
      local = await drafts.load(scope, editorSlot);
      rethrow;
    }
    if (_disposed) return;
    local = null;
    form = {...result, 'branch_id': result['budget_branch_id']};
    message = 'Budget ${result['status']} at revision ${result['revision']}.';
    try {
      await _persistBudget();
      await _loadBudgets();
    } catch (failure) {
      _handle(failure);
      if (!denied) error = 'Budget confirmed. Refresh its version list.';
    }
  });
  Future<void> retryBudget() =>
      act(local?.pending?.envelope.payload['action'] as String? ?? '');

  void varianceField(String key, String? value) {
    if (varianceLocked ||
        !const {'budget_id', 'as_of'}.contains(key) ||
        varianceForm['status'] == 'generated') {
      return;
    }
    varianceForm = {...varianceForm, key: value};
    _emit();
  }

  Future<void> newVariance() => _run(() async {
    if (variancePending || denied || !verified) return;
    await drafts.discard(scope, varianceSlot);
    varianceLocal = null;
    varianceForm = _newVariance();
    summary = {};
    rows = [];
    section = 'lines';
    budgetLineId = null;
    nextOffset = null;
    await _persistVariance();
  });
  void _validateVariance() {
    final budget = selectedBudget;
    final date = varianceForm['as_of'];
    if (budget == null ||
        budget['status'] != 'approved' ||
        date is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        DateTime.tryParse(date)?.toIso8601String().substring(0, 10) != date ||
        date.compareTo(today) > 0 ||
        !date.startsWith('${budget['budget_year']}-')) {
      throw const FormatException(
        'Choose an approved budget and date within its year.',
      );
    }
    final periodId = budget['period_id'];
    if (periodId != null) {
      final period = periods.where((row) => row['id'] == periodId).firstOrNull;
      if (period != null &&
          (date.compareTo(period['start_date'] as String) < 0 ||
              date.compareTo(period['end_date'] as String) > 0)) {
        throw const FormatException(
          'Variance date must be within the budget period.',
        );
      }
    }
  }

  Future<void> generate() => _run(() async {
    if (!online ||
        !verified ||
        denied ||
        varianceForm['status'] == 'generated') {
      return;
    }
    var command = varianceLocal?.pending;
    if (command == null) {
      _validateVariance();
      await _persistVariance();
      command = await drafts.prepare(
        scope,
        varianceSlot,
        verb: 'accept',
        expectedVersion: 0,
        payload: {
          'id': varianceForm['id'],
          'budget_id': varianceForm['budget_id'],
          'as_of': varianceForm['as_of'],
        },
      );
      varianceLocal = await drafts.load(scope, varianceSlot);
    }
    Map<String, Object?> result;
    try {
      result = await gateway.generate(command.envelope);
      await drafts.complete(scope, varianceSlot, command.envelope.commandId);
    } on DomainError catch (failure) {
      await drafts.recordFailure(
        scope,
        varianceSlot,
        failure,
        commandId: command.envelope.commandId,
      );
      varianceLocal = await drafts.load(scope, varianceSlot);
      rethrow;
    }
    if (_disposed) return;
    varianceLocal = null;
    varianceForm = {
      ...varianceForm,
      'report_id': result['id'],
      'status': 'generated',
    };
    summary = result;
    message = 'Variance saved with frozen posted-journal evidence.';
    try {
      await _persistVariance();
      await _loadPage(result['id'] as String);
      await _loadReports();
    } catch (failure) {
      _handle(failure);
      if (!denied) error = 'Variance confirmed. Refresh to load its evidence.';
    }
  });
  Future<void> retryVariance() => generate();

  Future<void> _loadPage(String id, {bool more = false}) async {
    if (!online) return;
    final result = await gateway.page(
      scope,
      id,
      section,
      offset: more ? nextOffset ?? 0 : 0,
      budgetLineId: budgetLineId,
    );
    if (_disposed) return;
    summary = (result['summary'] as Map).cast<String, Object?>();
    rows = [
      if (more) ...rows,
      for (final raw in result['items'] as List)
        (raw as Map).cast<String, Object?>(),
    ];
    nextOffset = result['next_offset'] as int?;
  }

  Future<void> openReport(String id) => _run(() async {
    if (!online || !verified || denied) return;
    section = 'lines';
    budgetLineId = null;
    rows = [];
    nextOffset = null;
    await _loadPage(id);
  });
  Future<void> chooseSection(String value, {String? lineId}) => _run(() async {
    if (!online ||
        selectedReportId == null ||
        denied ||
        !const {'lines', 'journals'}.contains(value)) {
      return;
    }
    section = value;
    budgetLineId = lineId;
    rows = [];
    nextOffset = null;
    await _loadPage(selectedReportId!);
  });
  Future<void> moreLines() => _run(() async {
    if (!online || nextOffset == null || selectedReportId == null) return;
    await _loadPage(selectedReportId!, more: true);
  });
}

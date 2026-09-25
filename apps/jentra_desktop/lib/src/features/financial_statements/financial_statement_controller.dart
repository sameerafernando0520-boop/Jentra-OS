import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';

final financialStatementGatewayProvider = Provider<FinancialStatementGateway?>(
  (ref) => null,
);
final financialStatementControllerProvider =
    Provider.autoDispose<FinancialStatementController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider);
      final gateway = ref.watch(financialStatementGatewayProvider);
      final access = ref.watch(businessCapabilitiesProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          access.isLoading ||
          access.hasError ||
          !(access.value?.contains('finance.view') ?? false)) {
        return null;
      }
      final controller = FinancialStatementController(
        scope: scope,
        gateway: gateway,
        drafts: QuotationDraftStore(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
      );
      ref.listen(
        connectivityStateProvider,
        (_, state) =>
            controller.setOnline(state.value == ConnectivityState.online),
      );
      ref.onDispose(controller.dispose);
      unawaited(controller.initialize());
      return controller;
    });

final class FinancialStatementController extends ChangeNotifier {
  FinancialStatementController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.online,
  });

  static const slot = 'financial-statement-editor';
  final TenantContext scope;
  final FinancialStatementGateway gateway;
  final QuotationDraftStore drafts;
  bool online;
  bool busy = false, verified = false, denied = false, _disposed = false;
  String? error, message, periodCursor, reportCursor;
  String section = 'accounts';
  String? accountId;
  int? nextOffset;
  Map<String, Object?> form = {}, summary = {};
  List<Map<String, Object?>> periods = [], reports = [], rows = [];
  QuotationLocalDraft? local;

  bool get pending => local?.pending != null;
  bool get locked => busy || denied || pending || form['status'] == 'generated';
  String get today => DateTime.now().toUtc().toIso8601String().substring(0, 10);
  String? get selectedReportId => summary['id'] as String?;
  Map<String, Object?>? get selectedPeriod {
    for (final period in periods) {
      if (period['id'] == form['period_id']) return period;
    }
    return null;
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _clearEvidence() {
    periods = [];
    reports = [];
    rows = [];
    summary = {};
    periodCursor = null;
    reportCursor = null;
    nextOffset = null;
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
      form = {};
      _clearEvidence();
    }
    error = failure is DomainError
        ? failure.message
        : failure is FormatException
        ? failure.message
        : 'Unable to confirm the result. Your sealed request is retained.';
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
    if (form.isNotEmpty && verified && !denied && !pending) await persist();
    local = await drafts.load(scope, slot);
    if (!online) return;
    _clearEvidence();
    await _loadPeriods();
    await _loadReports();
    if (_disposed) return;
    form = local?.form ?? _newForm();
    verified = true;
    denied = false;
    if (form['status'] == 'generated' && form['report_id'] is String) {
      await _loadPage(form['report_id'] as String);
    }
  });

  Map<String, Object?> _newForm() => {
    'id': const Uuid().v4(),
    'kind': 'trial_balance',
    'period_id': periods.isEmpty ? null : periods.first['id'],
    'as_of': periods.isEmpty ? today : periods.first['end_date'],
    'comparative_period_id': null,
    'status': 'local',
  };

  Future<void> _loadPeriods({bool more = false}) async {
    if (!online) return;
    final result = await gateway.periods(
      scope,
      after: more ? periodCursor : null,
    );
    if (_disposed) return;
    periods = [
      if (more) ...periods,
      for (final value in result['items'] as List)
        (value as Map).cast<String, Object?>(),
    ];
    periodCursor = result['next_cursor'] as String?;
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
      for (final value in result['items'] as List)
        (value as Map).cast<String, Object?>(),
    ];
    reportCursor = result['next_cursor'] as String?;
  }

  Future<void> morePeriods() => _run(() => _loadPeriods(more: true));
  Future<void> moreReports() => _run(() => _loadReports(more: true));
  Future<void> refresh() => _run(() async {
    if (!online || !verified || denied) return;
    await _loadPeriods();
    await _loadReports();
    if (selectedReportId != null) await _loadPage(selectedReportId!);
  });

  void field(String name, String? value) {
    if (locked || !verified || denied) return;
    form = {
      ...form,
      name: value,
      if (name == 'period_id')
        'as_of': periods.firstWhere((row) => row['id'] == value)['end_date'],
      if (name == 'period_id') 'comparative_period_id': null,
    };
    _emit();
  }

  Future<void> persist() async {
    await drafts.save(scope, slot, form, expectedVersion: 0);
    local = await drafts.load(scope, slot);
  }

  Future<void> save() => _run(() async {
    if (!denied && !pending && form.isNotEmpty) await persist();
  });

  Future<bool> canLeave() async {
    if (busy) return false;
    if (pending || denied || form.isEmpty) return true;
    await save();
    return error == null;
  }

  Future<void> newReport() => _run(() async {
    if (pending || denied || !verified) return;
    form = _newForm();
    summary = {};
    rows = [];
    section = 'accounts';
    accountId = null;
    nextOffset = null;
    message = null;
    await persist();
  });

  void _validate() {
    final period = selectedPeriod;
    final date = form['as_of'];
    if (period == null ||
        date is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        DateTime.tryParse(date)?.toIso8601String().substring(0, 10) != date ||
        date.compareTo(today) > 0 ||
        date.compareTo(period['start_date'] as String) < 0 ||
        date.compareTo(period['end_date'] as String) > 0) {
      throw const FormatException('Choose a date within the selected period.');
    }
    final comparison = form['comparative_period_id'];
    if (comparison != null &&
        !periods.any(
          (row) =>
              row['id'] == comparison &&
              (row['end_date'] as String).compareTo(
                    period['start_date'] as String,
                  ) <
                  0,
        )) {
      throw const FormatException('Choose an earlier comparative period.');
    }
    if (!const [
      'trial_balance',
      'profit_loss',
      'balance_sheet',
      'cash_flow',
    ].contains(form['kind'])) {
      throw const FormatException('Choose a financial statement.');
    }
  }

  Future<void> generate() => _run(() async {
    if (!online || !verified || denied || form['status'] == 'generated') return;
    var command = local?.pending;
    if (command == null) {
      _validate();
      await persist();
      command = await drafts.prepare(
        scope,
        slot,
        verb: 'accept',
        expectedVersion: 0,
        payload: {
          'id': form['id'],
          'kind': form['kind'],
          'period_id': form['period_id'],
          'as_of': form['as_of'],
          'comparative_period_id': form['comparative_period_id'],
        },
      );
      local = await drafts.load(scope, slot);
    }
    Map<String, Object?> result;
    try {
      result = await gateway.generate(command.envelope);
      await drafts.complete(scope, slot, command.envelope.commandId);
    } on DomainError catch (failure) {
      await drafts.recordFailure(
        scope,
        slot,
        failure,
        commandId: command.envelope.commandId,
      );
      local = await drafts.load(scope, slot);
      rethrow;
    }
    if (_disposed) return;
    local = null;
    form = {...form, 'status': 'generated', 'report_id': result['id']};
    summary = result;
    message = 'Report saved with frozen posted-journal evidence.';
    try {
      await persist();
      await _loadPage(result['id'] as String);
      await _loadReports();
    } catch (failure) {
      _handle(failure);
      if (!denied) error = 'Report confirmed. Refresh to load its evidence.';
    }
  });

  Future<void> retry() => generate();

  Future<void> _loadPage(String id, {bool more = false}) async {
    if (!online) return;
    final result = await gateway.page(
      scope,
      id,
      section,
      offset: more ? nextOffset ?? 0 : 0,
      accountId: accountId,
    );
    if (_disposed) return;
    summary = (result['summary'] as Map).cast<String, Object?>();
    rows = [
      if (more) ...rows,
      for (final value in result['items'] as List)
        (value as Map).cast<String, Object?>(),
    ];
    nextOffset = result['next_offset'] as int?;
  }

  Future<void> open(String id) => _run(() async {
    if (!online || !verified || denied || pending) return;
    section = 'accounts';
    accountId = null;
    rows = [];
    nextOffset = null;
    await _loadPage(id);
  });

  Future<void> chooseSection(String value, {String? account}) => _run(() async {
    if (!online || selectedReportId == null || denied) return;
    if (!const ['accounts', 'journals'].contains(value)) return;
    section = value;
    accountId = account;
    rows = [];
    nextOffset = null;
    await _loadPage(selectedReportId!);
  });

  Future<void> moreLines() => _run(() async {
    if (!online || nextOffset == null || selectedReportId == null) return;
    await _loadPage(selectedReportId!, more: true);
  });
}

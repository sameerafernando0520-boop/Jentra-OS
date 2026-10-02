import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import '../shared/report_wait.dart';

final taxSummaryGatewayProvider = Provider<TaxSummaryGateway?>((ref) => null);

final taxSummaryControllerProvider =
    Provider.autoDispose<TaxSummaryController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider);
      final gateway = ref.watch(taxSummaryGatewayProvider);
      final access = ref.watch(businessCapabilitiesProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          access.isLoading ||
          access.hasError ||
          !(access.value?.contains('finance.view') ?? false)) {
        return null;
      }
      final controller = TaxSummaryController(
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

final class TaxSummaryController extends ChangeNotifier {
  TaxSummaryController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.online,
  });

  static const slot = 'tax-summary-editor';
  final TenantContext scope;
  final TaxSummaryGateway gateway;
  final QuotationDraftStore drafts;
  bool online,
      busy = false,
      verified = false,
      denied = false,
      _disposed = false;
  String? error, message, periodCursor, reportCursor;
  int? nextOffset;
  int? controlNextOffset;
  String controlSection = 'controls';
  String? controlAccountId, controlEvidenceKey;
  Map<String, Object?> form = {}, summary = {};
  List<Map<String, Object?>> periods = [], reports = [], rows = [];
  List<Map<String, Object?>> controlRows = [];
  QuotationLocalDraft? local;
  int _evidenceEpoch = 0;
  final reportWait = ReportWaitState();
  void cancelReportWait() {
    if (!reportWait.cancel()) return;
    _evidenceEpoch++;
    _clearEvidence();
    _emit();
  }

  bool _acceptEvidence(int epoch) =>
      !_disposed && online && epoch == _evidenceEpoch;

  bool get pending => local?.pending != null;
  bool get locked =>
      busy || denied || !verified || pending || form['status'] == 'generated';
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
    _evidenceEpoch++;
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
    controlRows = [];
    controlNextOffset = null;
    controlAccountId = null;
    controlEvidenceKey = null;
    controlSection = 'controls';
  }

  void setOnline(bool value) {
    online = value;
    if (!online) {
      _evidenceEpoch++;
      verified = false;
      _clearEvidence();
    }
    _emit();
  }

  void _handle(Object failure) {
    if (failure is DomainError &&
        const {
          'PERMISSION_DENIED',
          'ACCESS_DENIED',
          'MFA_REQUIRED',
          'AUTHENTICATION_REQUIRED',
        }.contains(failure.code)) {
      _evidenceEpoch++;
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
    final accessEpoch = _evidenceEpoch;
    busy = true;
    error = null;
    _emit();
    try {
      await work();
    } catch (failure) {
      if (_disposed || !online || accessEpoch != _evidenceEpoch) return;
      _handle(failure);
    } finally {
      reportWait.finish();
      busy = false;
      _emit();
    }
  }

  Future<void> initialize() => _run(() async {
    final epoch = _evidenceEpoch;
    local = await drafts.load(scope, slot);
    if (!_acceptEvidence(epoch)) return;
    _clearEvidence();
    await _loadPeriods();
    if (!_acceptEvidence(epoch)) return;
    await _loadReports();
    if (!_acceptEvidence(epoch)) return;
    form = local?.form ?? _newForm();
    verified = true;
    denied = false;
    if (form['status'] == 'generated' && form['report_id'] is String) {
      await _loadPage(form['report_id'] as String);
    }
  });

  Map<String, Object?> _newForm() {
    final period = periods.isEmpty ? null : periods.first;
    final end = period?['end_date'] as String?;
    return {
      'id': const Uuid().v4(),
      'period_id': period?['id'],
      'as_of': end == null || end.compareTo(today) > 0 ? today : end,
      'branch_filter_id': null,
      'status': 'local',
    };
  }

  Future<void> _loadPeriods({bool more = false}) async {
    if (!online) return;
    final epoch = _evidenceEpoch;
    final page = await gateway.periods(
      scope,
      after: more ? periodCursor : null,
    );
    if (!_acceptEvidence(epoch)) return;
    periods = [
      if (more) ...periods,
      for (final row in page['items'] as List)
        (row as Map).cast<String, Object?>(),
    ];
    periodCursor = page['next_cursor'] as String?;
  }

  Future<void> _loadReports({bool more = false}) async {
    if (!online) return;
    final epoch = _evidenceEpoch;
    final page = await gateway.reports(
      scope,
      after: more ? reportCursor : null,
    );
    if (!_acceptEvidence(epoch)) return;
    reports = [
      if (more) ...reports,
      for (final row in page['items'] as List)
        (row as Map).cast<String, Object?>(),
    ];
    reportCursor = page['next_cursor'] as String?;
  }

  Future<void> morePeriods() => _run(() => _loadPeriods(more: true));
  Future<void> moreReports() => _run(() => _loadReports(more: true));
  Future<void> refresh() => _run(() async {
    if (!online || !verified || denied) return;
    final epoch = _evidenceEpoch;
    await _loadPeriods();
    if (!_acceptEvidence(epoch)) return;
    await _loadReports();
    if (!_acceptEvidence(epoch)) return;
    if (selectedReportId != null) await _loadPage(selectedReportId!);
  });

  void field(String name, String? value) {
    if (locked ||
        !const ['period_id', 'as_of', 'branch_filter_id'].contains(name)) {
      return;
    }
    form = {
      ...form,
      name: value,
      if (name == 'period_id')
        'as_of': periods.firstWhere((row) => row['id'] == value)['end_date'],
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
    if (busy) return reportWait.active && reportWait.cancelled;
    if (pending || denied || form.isEmpty) return true;
    await save();
    return error == null;
  }

  Future<void> newReport() => _run(() async {
    if (pending || denied || !verified) return;
    form = _newForm();
    summary = {};
    rows = [];
    nextOffset = null;
    controlRows = [];
    controlNextOffset = null;
    controlAccountId = null;
    controlEvidenceKey = null;
    controlSection = 'controls';
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
        date.compareTo(period['end_date'] as String) > 0 ||
        form['branch_filter_id'] != null &&
            form['branch_filter_id'] != scope.branchId) {
      throw const FormatException(
        'Choose a valid period, as-of date and branch filter.',
      );
    }
  }

  Future<void> generate() => _run(() async {
    if (!online || !verified || denied || form['status'] == 'generated') return;
    reportWait.begin();
    _emit();
    final epoch = _evidenceEpoch;
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
          'period_id': form['period_id'],
          'as_of': form['as_of'],
          'branch_filter_id': form['branch_filter_id'],
        },
      );
      local = await drafts.load(scope, slot);
    }
    if (!_acceptEvidence(epoch) || !verified || denied) return;
    Map<String, Object?> result;
    late Map<String, Object?> confirmedForm;
    try {
      reportWait.generating();
      _emit();
      if (reportWait.cancelled || !_acceptEvidence(epoch)) return;
      result = await gateway.generate(command.envelope);
      confirmedForm = {
        ...command.envelope.payload,
        'status': 'generated',
        'report_id': result['id'],
      };
      await drafts.confirm(
        scope,
        slot,
        command.envelope.commandId,
        form: confirmedForm,
        expectedVersion: 0,
      );
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
    local = await drafts.load(scope, slot);
    if (_disposed) return;
    form = confirmedForm;
    if (!_acceptEvidence(epoch)) return;
    summary = result;
    message = 'Tax review saved with frozen posted-source evidence.';
    try {
      await _loadPage(result['id'] as String);
      if (!_acceptEvidence(epoch)) return;
      await _loadReports();
    } catch (failure) {
      _handle(failure);
      if (!denied) error = 'Report confirmed. Refresh to load its evidence.';
    }
  });

  Future<void> retry() => generate();

  Future<void> _loadPage(String id, {bool more = false}) async {
    if (!online) return;
    if (reportWait.active && reportWait.cancelled) return;
    final epoch = _evidenceEpoch;
    if (!reportWait.active) reportWait.begin();
    reportWait.reading();
    _emit();
    if (reportWait.cancelled || !_acceptEvidence(epoch)) return;
    final page = await gateway.page(
      scope,
      id,
      offset: more ? nextOffset ?? 0 : 0,
    );
    if (!_acceptEvidence(epoch)) return;
    summary = (page['summary'] as Map).cast<String, Object?>();
    rows = [
      if (more) ...rows,
      for (final row in page['items'] as List)
        (row as Map).cast<String, Object?>(),
    ];
    nextOffset = page['next_offset'] as int?;
    if (!more && summary['version'] == 2) {
      controlSection = 'controls';
      controlAccountId = null;
      controlEvidenceKey = null;
      await _loadControls();
    }
  }

  Future<void> _loadControls({bool more = false}) async {
    if (!online || selectedReportId == null || summary['version'] != 2) return;
    final id = selectedReportId!;
    final epoch = _evidenceEpoch;
    final page = await gateway.controls(
      scope,
      id,
      controlSection,
      offset: more ? controlNextOffset ?? 0 : 0,
      accountId: controlAccountId,
      evidenceKey: controlEvidenceKey,
    );
    if (!_acceptEvidence(epoch) || selectedReportId != id) return;
    summary = (page['summary'] as Map).cast<String, Object?>();
    controlRows = [
      if (more) ...controlRows,
      for (final row in page['items'] as List)
        (row as Map).cast<String, Object?>(),
    ];
    controlNextOffset = page['next_offset'] as int?;
  }

  Future<void> controlDrill(
    String section, {
    String? accountId,
    String? evidenceKey,
  }) => _run(() async {
    if (!online || !verified || denied || pending || summary['version'] != 2) {
      return;
    }
    controlSection = section;
    controlAccountId = accountId;
    controlEvidenceKey = evidenceKey;
    controlRows = [];
    controlNextOffset = null;
    await _loadControls();
  });

  Future<void> moreControls() => _run(() async {
    if (!online || controlNextOffset == null || denied) return;
    await _loadControls(more: true);
  });

  Future<void> open(String id) => _run(() async {
    if (!online || !verified || denied || pending) return;
    rows = [];
    controlRows = [];
    controlNextOffset = null;
    nextOffset = null;
    await _loadPage(id);
  });

  Future<void> moreLines() => _run(() async {
    if (!online || nextOffset == null || selectedReportId == null) return;
    await _loadPage(selectedReportId!, more: true);
  });
}

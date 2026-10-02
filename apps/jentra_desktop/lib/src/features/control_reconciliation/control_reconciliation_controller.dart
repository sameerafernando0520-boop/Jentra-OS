import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';

import '../../app_providers.dart';
import '../shared/report_wait.dart';

final controlReconciliationGatewayProvider =
    Provider<ControlReconciliationGateway?>((ref) => null);
final controlReconciliationControllerProvider =
    Provider.autoDispose<ControlReconciliationController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider),
          gateway = ref.watch(controlReconciliationGatewayProvider),
          caps = ref.watch(businessCapabilitiesProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          caps.isLoading ||
          caps.hasError ||
          ![
            'finance.view',
            'finance.controls.reconcile',
          ].every((p) => caps.value?.contains(p) ?? false)) {
        return null;
      }
      final c = ControlReconciliationController(
        scope: scope,
        gateway: gateway,
        drafts: QuotationDraftStore(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        capabilities: caps.value!,
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
      );
      ref.listen(
        connectivityStateProvider,
        (_, s) => c.setOnline(s.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

final class ControlReconciliationController extends ChangeNotifier {
  ControlReconciliationController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.capabilities,
    required this.online,
  });
  final TenantContext scope;
  final ControlReconciliationGateway gateway;
  final QuotationDraftStore drafts;
  final Set<String> capabilities;
  static const slot = 'control-reconciliation-report',
      correctionSlot = 'control-allocation-correction';
  bool online, busy = false, accessDenied = false, _disposed = false;
  bool verified = false;
  int _evidenceEpoch = 0;
  final reportWait = ReportWaitState();
  void cancelReportWait() {
    if (!reportWait.cancel()) return;
    _evidenceEpoch++;
    clearEvidence();
    emit();
  }

  bool _acceptEvidence(int epoch) =>
      !_disposed && online && epoch == _evidenceEpoch;
  String? error, message, cursor, reportCursor, accountId;
  String section = 'accounts';
  Map<String, Object?> form = {}, summary = {}, correction = {};
  List<Map<String, Object?>> reports = [], rows = [];
  QuotationLocalDraft? local, correctionLocal;
  bool get pending =>
      local?.pending != null || correctionLocal?.pending != null;
  bool get locked =>
      busy ||
      accessDenied ||
      !verified ||
      pending ||
      form['status'] == 'generated';
  bool canReverse(String kind) =>
      ['AR', 'AP'].contains(kind) &&
      capabilities.contains(
        kind == 'AR' ? 'finance.receipts.reverse' : 'finance.payments.reverse',
      );
  String get today => DateTime.now().toUtc().toIso8601String().substring(0, 10);
  void emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _evidenceEpoch++;
    _disposed = true;
    super.dispose();
  }

  void setOnline(bool value) {
    online = value;
    if (!online) {
      _evidenceEpoch++;
      verified = false;
      clearEvidence();
    }
    emit();
  }

  void clearEvidence() {
    summary = {};
    rows = [];
    reports = [];
    correction = {};
    cursor = null;
    reportCursor = null;
    accountId = null;
  }

  void deny(Object e) {
    if (e is DomainError &&
        [
          'PERMISSION_DENIED',
          'ACCESS_DENIED',
          'MFA_REQUIRED',
          'AUTHENTICATION_REQUIRED',
        ].contains(e.code)) {
      _evidenceEpoch++;
      accessDenied = true;
      verified = false;
      clearEvidence();
    }
  }

  Future<void> run(Future<void> Function() work) async {
    if (busy || _disposed) return;
    final accessEpoch = _evidenceEpoch;
    busy = true;
    error = null;
    emit();
    try {
      await work();
    } catch (e) {
      if (_disposed || !online || accessEpoch != _evidenceEpoch) return;
      deny(e);
      error = e is DomainError
          ? e.message
          : e is FormatException
          ? e.message
          : 'Unable to complete this action. Saved requests are retained.';
    } finally {
      reportWait.finish();
      busy = false;
      emit();
    }
  }

  Future<void> persist() async {
    await drafts.save(scope, slot, form, expectedVersion: 0);
    local = await drafts.load(scope, slot);
  }

  Future<void> initialize() => run(() async {
    final epoch = _evidenceEpoch;
    // An access refresh must not replace unsaved inputs in an existing editor.
    if (form.isNotEmpty && !accessDenied && !pending) {
      await persist();
      if (correction.isNotEmpty) await persistCorrection();
    }
    local = await drafts.load(scope, slot);
    correctionLocal = await drafts.load(scope, correctionSlot);
    if (_disposed) return;
    form =
        local?.form ??
        {
          'id': const Uuid().v4(),
          'kind': 'AR',
          'as_of': today,
          'status': 'local',
        };
    // Report evidence and source descriptions are only displayed after a fresh permission check.
    if (online) {
      await loadReports();
      if (!_acceptEvidence(epoch)) return;
      verified = true;
      accessDenied = false;
      correction = correctionLocal?.form ?? {};
      if (form['status'] == 'generated' && form['report_id'] is String) {
        await readReport(form['report_id'] as String);
      }
    }
  });
  void field(String key, String value) {
    if (locked) return;
    form = {...form, key: value.trim()};
    emit();
  }

  void correctionField(String key, String value) {
    if (busy || accessDenied || correctionLocal?.pending != null) return;
    correction = {...correction, key: value.trim()};
    emit();
  }

  Future<void> save() => run(() async {
    if (accessDenied) return;
    await persist();
    if (correction.isNotEmpty && correctionLocal?.pending == null) {
      await persistCorrection();
    }
  });
  Future<bool> canLeave() async {
    if (busy) return reportWait.active && reportWait.cancelled;
    if (accessDenied || pending) return true;
    await save();
    return error == null;
  }

  Future<void> loadReports({bool more = false}) async {
    if (!online) return;
    final epoch = _evidenceEpoch;
    final r = await gateway.reports(scope, after: more ? reportCursor : null);
    if (!_acceptEvidence(epoch)) return;
    reports = [
      if (more) ...reports,
      for (final x in r['items'] as List) (x as Map).cast<String, Object?>(),
    ];
    reportCursor = r['next_cursor'] as String?;
  }

  Future<void> refreshReports({bool more = false}) =>
      run(() => loadReports(more: more));
  Future<void> newReport() => run(() async {
    if (pending || accessDenied) return;
    form = {
      'id': const Uuid().v4(),
      'kind': form['kind'] ?? 'AR',
      'as_of': form['as_of'] ?? today,
      'status': 'local',
    };
    summary = {};
    rows = [];
    cursor = null;
    accountId = null;
    section = 'accounts';
    message = null;
    await persist();
  });
  Future<void> generate() => run(() async {
    if (!online ||
        !verified ||
        accessDenied ||
        correctionLocal?.pending != null ||
        form['status'] == 'generated') {
      return;
    }
    reportWait.begin();
    emit();
    final epoch = _evidenceEpoch;
    var command = local?.pending;
    if (command == null) {
      final date = form['as_of'];
      if (date is! String ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
          DateTime.tryParse(date)?.toIso8601String().substring(0, 10) != date) {
        throw const FormatException('Enter a valid posting cutoff date.');
      }
      await persist();
      command = await drafts.prepare(
        scope,
        slot,
        verb: 'accept',
        expectedVersion: 0,
        payload: {'id': form['id'], 'kind': form['kind'], 'as_of': date},
      );
      local = await drafts.load(scope, slot);
    }
    if (!_acceptEvidence(epoch) || !verified || accessDenied) return;
    Map<String, Object?> result;
    late Map<String, Object?> confirmedForm;
    try {
      reportWait.generating();
      emit();
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
    } on DomainError catch (e) {
      await drafts.recordFailure(
        scope,
        slot,
        e,
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
    message = 'Report saved. Its cutoff evidence will not change with later postings.';
    try {
      section = 'accounts';
      accountId = null;
      await readReport(result['id'] as String);
      if (!_acceptEvidence(epoch)) return;
      await loadReports();
    } catch (e) {
      deny(e);
      error =
          'Generation confirmed. Refresh the saved report to load evidence.';
    }
  });
  Future<void> open(Map<String, Object?> r) => run(() async {
    if (!online || !verified || pending || accessDenied) return;
    section = 'accounts';
    accountId = null;
    rows = [];
    cursor = null;
    await readReport(r['id'] as String);
  });
  Future<void> readReport(String id, {bool more = false}) async {
    if (!online || !verified) return;
    if (reportWait.active && reportWait.cancelled) return;
    final epoch = _evidenceEpoch;
    if (!reportWait.active) reportWait.begin();
    reportWait.reading();
    emit();
    if (reportWait.cancelled || !_acceptEvidence(epoch)) return;
    final r = await gateway.page(
      scope,
      id,
      section,
      after: more ? cursor : null,
      accountId: accountId,
    );
    if (!_acceptEvidence(epoch)) return;
    summary = (r['summary'] as Map).cast<String, Object?>();
    rows = [
      if (more) ...rows,
      for (final x in r['items'] as List) (x as Map).cast<String, Object?>(),
    ];
    cursor = r['next_cursor'] as String?;
  }

  Future<void> refreshPage({bool more = false}) => run(() async {
    if (summary.isNotEmpty) {
      await readReport(summary['id'] as String, more: more);
    }
  });
  Future<void> selectSection(String value) => run(() async {
    if (!online || summary.isEmpty) return;
    if (summary['kind'] == 'GRNI' && value == 'allocations') return;
    section = value;
    rows = [];
    cursor = null;
    emit();
    await readReport(summary['id'] as String);
  });
  Future<void> sources(String? value) => run(() async {
    if (!online || summary.isEmpty) return;
    accountId = value;
    section = value == null ? 'accounts' : 'entries';
    rows = [];
    cursor = null;
    emit();
    await readReport(summary['id'] as String);
  });
  Future<void> persistCorrection() async {
    await drafts.save(scope, correctionSlot, correction, expectedVersion: null);
    correctionLocal = await drafts.load(scope, correctionSlot);
  }

  Future<void> chooseAllocation(Map<String, Object?> row) => run(() async {
    final kind = summary['kind'] as String?;
    if (!online ||
        pending ||
        accessDenied ||
        kind == null ||
        !canReverse(kind) ||
        row['reversal'] != null) {
      return;
    }
    correction = {
      'kind': kind,
      'allocation_id': row['id'],
      'source_document_number': row['source_document_number'],
      'target_document_number': row['target_document_number'],
      'posting_date': today,
      'reason': '',
    };
    await persistCorrection();
  });
  Future<void> clearCorrection() => run(() async {
    if (pending || accessDenied) return;
    await drafts.discard(scope, correctionSlot);
    correction = {};
    correctionLocal = null;
  });
  Future<void> reverse() => run(() async {
    if (!online ||
        !verified ||
        accessDenied ||
        local?.pending != null ||
        correction.isEmpty ||
        !canReverse(correction['kind'] as String)) {
      return;
    }
    final epoch = _evidenceEpoch;
    var command = correctionLocal?.pending;
    if (command == null) {
      final reason = (correction['reason'] as String? ?? '').trim(),
          date = correction['posting_date'];
      if (reason.isEmpty ||
          reason.length > 1000 ||
          date is! String ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
          DateTime.tryParse(date)?.toIso8601String().substring(0, 10) != date) {
        throw const FormatException(
          'Enter a valid reversal date and a reason of 1–1000 characters.',
        );
      }
      await persistCorrection();
      command = await drafts.prepare(
        scope,
        correctionSlot,
        verb: 'reject',
        payload: {
          'allocation_id': correction['allocation_id'],
          'posting_date': date,
          'reason': reason,
        },
        expectedVersion: null,
      );
      correctionLocal = await drafts.load(scope, correctionSlot);
    }
    if (!_acceptEvidence(epoch) || !verified || accessDenied) return;
    try {
      await gateway.reverse(correction['kind'] as String, command.envelope);
      await drafts.complete(scope, correctionSlot, command.envelope.commandId);
    } on DomainError catch (e) {
      await drafts.recordFailure(
        scope,
        correctionSlot,
        e,
        commandId: command.envelope.commandId,
      );
      correctionLocal = await drafts.load(scope, correctionSlot);
      rethrow;
    }
    if (_disposed) return;
    correction = {};
    correctionLocal = null;
    message = 'Allocation reversal confirmed. Generate a new report to see reopened items; this saved report remains unchanged.';
  });
}

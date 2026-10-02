import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import '../shared/report_wait.dart';
import 'operational_controller.dart';

const operationalReportPermissions = <String, Set<String>>{
  'customer_statement': {'finance.receivables.view'},
  'supplier_statement': {
    'procurement.bills.view',
    'procurement.bills.manage',
    'procurement.bills.post',
    'finance.payments.manage',
    'finance.payments.post',
    'finance.payments.allocate',
    'finance.payments.reverse',
  },
  'bank_reconciliation': {'finance.view'},
};

final operationalReportControllerProvider = Provider.autoDispose
    .family<OperationalReportController?, String>((ref, kind) {
      final scope = ref.watch(activeTenantContextProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      final gateway = ref.watch(operationalGatewayProvider);
      final allowed = operationalReportPermissions[kind];
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          allowed == null ||
          caps.isLoading ||
          caps.hasError ||
          !(caps.value?.contains('finance.reports.export') ?? false) ||
          !(caps.value?.any(allowed.contains) ?? false)) {
        return null;
      }
      final controller = OperationalReportController(
        scope: scope,
        kind: kind,
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

/// One sealed request per report kind and business scope. An uncertain result
/// is replayed exactly, even if the visible statement selection later changes.
final class OperationalReportController extends ChangeNotifier {
  OperationalReportController({
    required this.scope,
    required this.kind,
    required this.gateway,
    required this.drafts,
    required this.online,
  });

  final TenantContext scope;
  final String kind;
  final OperationalGateway gateway;
  final QuotationDraftStore drafts;
  String get slot => 'operational-report-$kind';
  bool online, busy = false, _disposed = false;
  int _epoch = 0;
  final reportWait = ReportWaitState();
  void cancelReportWait() {
    if (!reportWait.cancel()) return;
    _epoch++;
    summary = {};
    _emit();
  }

  void _finishWait(int epoch) {
    if (_epoch != epoch && !(reportWait.cancelled && _epoch == epoch + 1)) {
      return;
    }
    reportWait.finish();
    if (!_disposed) {
      busy = false;
      _emit();
    }
  }

  QuotationLocalDraft? local;
  Map<String, Object?> summary = {};
  String? error;
  bool get pending => local?.pending != null;
  bool _current(int epoch) => !_disposed && online && epoch == _epoch;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void setOnline(bool value) {
    if (value == online) return;
    online = value;
    if (!value) {
      _epoch++;
      busy = false;
      summary = {};
    }
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    summary = {};
    super.dispose();
  }

  Future<void> initialize() async {
    try {
      local = await drafts.load(scope, slot);
      if (_disposed || !online || pending) return;
      await refresh();
    } catch (_) {
      if (!_disposed) {
        summary = {};
        error = 'The encrypted report request could not be restored.';
        _emit();
      }
    }
  }

  Future<void> refresh() async {
    if (_disposed || !online || busy) return;
    summary = {};
    error = null;
    final reportId = local?.form['report_id'];
    if (reportId is! String) {
      _emit();
      return;
    }
    final epoch = ++_epoch;
    reportWait.begin();
    reportWait.reading();
    busy = true;
    _emit();
    try {
      if (reportWait.cancelled || !_current(epoch)) return;
      final result = await gateway.reportPage(scope, reportId, 'rows');
      if (!_current(epoch)) return;
      final checked = (result['summary'] as Map).cast<String, Object?>();
      if (checked['id'] != reportId || checked['kind'] != kind) {
        throw const FormatException('Saved report identity mismatch.');
      }
      summary = checked;
    } catch (failure) {
      if (!_current(epoch)) return;
      summary = {};
      error = failure is DomainError && failure.code == 'PERMISSION_DENIED'
          ? 'This report is unavailable with your current access.'
          : 'Saved report evidence could not be verified.';
    } finally {
      _finishWait(epoch);
    }
  }

  Future<void> freeze(Map<String, Object?> inputs) async {
    if (_disposed || !online || busy) return;
    if (!pending) {
      try {
        _validate(inputs);
      } on FormatException catch (failure) {
        error = failure.message;
        _emit();
        return;
      }
    }
    final epoch = _epoch;
    reportWait.begin();
    busy = true;
    summary = {};
    error = null;
    _emit();
    try {
      var command = local?.pending;
      if (command == null) {
        final payload = <String, Object?>{
          ...inputs,
          'id': const Uuid().v4(),
          'kind': kind,
        };
        await drafts.save(scope, slot, payload, expectedVersion: 0);
        command = await drafts.prepare(
          scope,
          slot,
          verb: 'accept',
          payload: payload,
          expectedVersion: 0,
        );
        local = await drafts.load(scope, slot);
      }
      if (!_current(epoch)) return;
      reportWait.generating();
      _emit();
      if (reportWait.cancelled || !_current(epoch)) return;
      final receipt = await gateway.generate(command.envelope);
      await drafts.confirm(
        scope,
        slot,
        command.envelope.commandId,
        form: {...command.envelope.payload, 'report_id': receipt['id']},
        expectedVersion: 0,
      );
      if (_disposed) return;
      local = await drafts.load(scope, slot);
      if (!_current(epoch)) return;
      reportWait.reading();
      _emit();
      if (reportWait.cancelled || !_current(epoch)) return;
      final verified = await gateway.reportPage(
        scope,
        receipt['id'] as String,
        'rows',
      );
      if (!_current(epoch)) return;
      final checked = (verified['summary'] as Map).cast<String, Object?>();
      if (checked['id'] != receipt['id'] || checked['kind'] != kind) {
        throw const FormatException('Saved report identity mismatch.');
      }
      summary = checked;
    } on DomainError catch (failure) {
      final command = local?.pending;
      if (command != null) {
        await drafts.recordFailure(
          scope,
          slot,
          failure,
          commandId: command.envelope.commandId,
        );
      }
      if (_disposed) return;
      local = await drafts.load(scope, slot);
      if (!_current(epoch)) return;
      error = failure.message;
    } catch (failure) {
      if (_current(epoch)) {
        error = failure is FormatException ? failure.message : 'The report outcome could not be confirmed. Retry the saved request.';
      }
    } finally {
      _finishWait(epoch);
    }
  }

  void _validate(Map<String, Object?> inputs) {
    final rawDate = inputs['as_of'];
    final date = rawDate is String ? DateTime.tryParse(rawDate) : null;
    if (rawDate is! String ||
        date == null ||
        date.toIso8601String().substring(0, 10) != rawDate ||
        rawDate.compareTo(
              DateTime.now().toUtc().toIso8601String().substring(0, 10),
            ) >
            0) {
      throw const FormatException('Choose a valid report cutoff date.');
    }
    if (kind == 'bank_reconciliation') return;
    if (inputs['party_id'] is! String ||
        !Uuid.isValidUUID(fromString: inputs['party_id'] as String) ||
        inputs['currency_code'] is! String ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(inputs['currency_code'] as String)) {
      throw const FormatException('Choose a party and currency.');
    }
    final buckets = inputs['bucket_days'];
    if (buckets is! List ||
        buckets.isEmpty ||
        buckets.length > 12 ||
        buckets.any((value) => value is! int || value <= 0) ||
        List.generate(
          buckets.length - 1,
          (i) => i,
        ).any((i) => (buckets[i] as int) >= (buckets[i + 1] as int))) {
      throw const FormatException('Choose increasing positive aging days.');
    }
  }
}

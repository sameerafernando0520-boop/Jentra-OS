import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import '../../app_providers.dart';

final closeReviewGatewayProvider = Provider<CloseReviewGateway?>((ref) => null);
final closeReviewControllerProvider =
    Provider.autoDispose<CloseReviewController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider),
          gateway = ref.watch(closeReviewGatewayProvider),
          caps = ref.watch(businessCapabilitiesProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          caps.isLoading ||
          caps.hasError ||
          !CloseReviewController.requiredCapabilities.every(
            (p) => caps.value?.contains(p) ?? false,
          )) {
        return null;
      }
      final c = CloseReviewController(
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
        (_, s) => c.setOnline(s.value == ConnectivityState.online),
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

final class CloseReviewController extends ChangeNotifier {
  CloseReviewController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.online,
  });
  final TenantContext scope;
  final CloseReviewGateway gateway;
  final QuotationDraftStore drafts;
  static const slot = 'close-control-review';
  static const requiredCapabilities = [
    'finance.view',
    'finance.controls.reconcile',
    'inventory.stock.view',
    'inventory.cost.view',
  ];
  bool online,
      busy = false,
      verified = false,
      accessDenied = false,
      _disposed = false;
  int _epoch = 0;
  Map<String, Object?> form = {}, summary = {};
  List<Map<String, Object?>> reports = [], periods = [], rows = [];
  String section = 'controls';
  String? componentKey, cursor, reportCursor, periodCursor, error, message;
  QuotationLocalDraft? local;
  bool get pending => local?.pending != null;
  bool get locked =>
      busy || pending || accessDenied || form['status'] == 'confirmed';
  bool current(int epoch) =>
      !_disposed && online && epoch == _epoch && !accessDenied;
  void emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _epoch++;
    _disposed = true;
    super.dispose();
  }

  void clear() {
    summary = {};
    reports = [];
    periods = [];
    rows = [];
    cursor = null;
    reportCursor = null;
    periodCursor = null;
    componentKey = null;
  }

  void setOnline(bool value) {
    online = value;
    if (!value) {
      _epoch++;
      verified = false;
      clear();
    }
    emit();
  }

  void deny(Object e) {
    if (e is DomainError &&
        [
          'PERMISSION_DENIED',
          'MFA_REQUIRED',
          'AUTHENTICATION_REQUIRED',
        ].contains(e.code)) {
      _epoch++;
      verified = false;
      accessDenied = true;
      clear();
    }
  }

  Future<void> run(Future<void> Function() work) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    emit();
    try {
      await work();
    } catch (e) {
      deny(e);
      error = e is DomainError
          ? e.message
          : e is FormatException
          ? e.message
          : 'Unable to complete this action. Saved requests are retained.';
    } finally {
      busy = false;
      emit();
    }
  }

  Future<void> persist() async {
    await drafts.save(scope, slot, form, expectedVersion: 0);
    local = await drafts.load(scope, slot);
  }

  Future<void> initialize() => run(() async {
    final epoch = _epoch;
    if (form.isNotEmpty && !accessDenied && !pending) await persist();
    local = await drafts.load(scope, slot);
    if (_disposed) return;
    form =
        local?.form ??
        {
          'id': const Uuid().v4(),
          'as_of': DateTime.now().toUtc().toIso8601String().substring(0, 10),
          'status': 'local',
        };
    if (!online) return;
    // Recheck authoritative access before exposing cached identity or evidence.
    final list = await gateway.reports(scope);
    if (_disposed || !online || epoch != _epoch) return;
    accessDenied = false;
    verified = true;
    reports = maps(list);
    reportCursor = list['next_cursor'] as String?;
    await loadPeriods();
    if (!current(epoch)) return;
    if (form['status'] == 'confirmed' && form['report_id'] is String) {
      await read(form['report_id'] as String);
    }
  });
  List<Map<String, Object?>> maps(Map r) => [
    for (final x in r['items'] as List) (x as Map).cast<String, Object?>(),
  ];
  void field(String k, String v) {
    if (locked) return;
    form = {...form, k: v.trim()};
    emit();
  }

  Future<void> save() => run(() async {
    if (!accessDenied && !pending) await persist();
  });
  Future<bool> canLeave() async {
    if (busy) return false;
    if (accessDenied || pending) return true;
    await save();
    return error == null;
  }

  Future<void> loadPeriods({bool more = false}) async {
    if (!online || !verified) return;
    final epoch = _epoch;
    final r = await gateway.periods(scope, after: more ? periodCursor : null);
    if (!current(epoch)) return;
    periods = [if (more) ...periods, ...maps(r)];
    periodCursor = r['next_cursor'] as String?;
  }

  Future<void> morePeriods() => run(() => loadPeriods(more: true));
  Future<void> refreshReports({bool more = false}) => run(() async {
    if (!online || !verified) return;
    final epoch = _epoch;
    final r = await gateway.reports(scope, after: more ? reportCursor : null);
    if (!current(epoch)) return;
    reports = [if (more) ...reports, ...maps(r)];
    reportCursor = r['next_cursor'] as String?;
  });
  Future<void> newReview() => run(() async {
    if (pending || accessDenied) return;
    form = {
      'id': const Uuid().v4(),
      'as_of': form['as_of'],
      'period_id': form['period_id'],
      'status': 'local',
    };
    summary = {};
    rows = [];
    section = 'controls';
    componentKey = null;
    cursor = null;
    message = null;
    await persist();
  });
  Future<void> generate() => run(() async {
    if (!online || !verified || accessDenied || form['status'] == 'confirmed') {
      return;
    }
    final epoch = _epoch;
    var request = local?.pending;
    if (request == null) {
      final date = form['as_of'], period = form['period_id'];
      if (date is! String ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
          DateTime.tryParse(date)?.toIso8601String().substring(0, 10) != date ||
          period is! String ||
          !periods.any(
            (p) =>
                p['id'] == period &&
                date.compareTo(p['start_date'] as String) >= 0 &&
                date.compareTo(p['end_date'] as String) <= 0,
          )) {
        throw const FormatException(
          'Choose a fiscal period and a valid cutoff within it.',
        );
      }
      await persist();
      request = await drafts.prepare(
        scope,
        slot,
        verb: 'accept',
        expectedVersion: 0,
        payload: {'id': form['id'], 'period_id': period, 'as_of': date},
      );
      local = await drafts.load(scope, slot);
    }
    if (!current(epoch) || !verified) return;
    Map<String, Object?> result;
    late Map<String, Object?> confirmed;
    try {
      result = await gateway.generate(request.envelope);
      confirmed = {
        ...request.envelope.payload,
        'status': 'confirmed',
        'report_id': result['id'],
      };
      // Confirmation persists even if offline or disposed after the network result.
      await drafts.confirm(
        scope,
        slot,
        request.envelope.commandId,
        form: confirmed,
        expectedVersion: 0,
      );
    } on DomainError catch (e) {
      await drafts.recordFailure(
        scope,
        slot,
        e,
        commandId: request.envelope.commandId,
      );
      if (!_disposed) local = await drafts.load(scope, slot);
      rethrow;
    }
    if (_disposed) return;
    local = await drafts.load(scope, slot);
    if (_disposed) return;
    form = confirmed;
    if (!current(epoch)) return;
    summary = result;
    section = 'controls';
    componentKey = null;
    cursor = null;
    rows = [];
    message =
        'Review confirmed. Its evidence is frozen; hard close will recheck current ledgers.';
    try {
      await read(result['id'] as String);
    } catch (e) {
      deny(e);
      error = 'Review confirmed. Refresh access to load its saved evidence.';
    }
  });
  Future<void> read(String id, {bool more = false}) async {
    if (!online || !verified || accessDenied) return;
    final epoch = _epoch;
    final r = await gateway.page(
      scope,
      id,
      section,
      after: more ? cursor : null,
      componentKey: componentKey,
    );
    if (!current(epoch)) return;
    summary = (r['summary'] as Map).cast<String, Object?>();
    rows = [if (more) ...rows, ...maps(r)];
    cursor = r['next_cursor'] as String?;
  }

  Future<void> open(Map<String, Object?> r) => run(() async {
    if (pending || !online || !verified || accessDenied) return;
    section = 'controls';
    componentKey = null;
    rows = [];
    cursor = null;
    await read(r['id'] as String);
  });
  Future<void> select(String value, {String? key}) => run(() async {
    if (summary.isEmpty || !online || !verified || accessDenied) return;
    section = value;
    componentKey = key;
    rows = [];
    cursor = null;
    emit();
    await read(summary['id'] as String);
  });
  Future<void> refreshPage({bool more = false}) => run(() async {
    if (summary.isNotEmpty) await read(summary['id'] as String, more: more);
  });
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';

import '../../app_providers.dart';
import '../operations/operational_read_access.dart';

final reservationGatewayProvider = Provider<ReservationGateway?>((ref) => null);
final reservationControllerProvider =
    Provider.autoDispose<ReservationController?>((ref) {
      final scope = ref.watch(activeTenantContextProvider),
          gateway = ref.watch(reservationGatewayProvider);
      final caps = ref.watch(businessCapabilitiesProvider);
      if (scope == null ||
          !scope.hasOperationalScope ||
          gateway == null ||
          caps.isLoading ||
          caps.hasError ||
          !(caps.value?.contains('inventory.reservations.manage') ?? false)) {
        return null;
      }
      final connection = ref.read(connectivityStateProvider);
      final c = ReservationController(
        scope: scope,
        gateway: gateway,
        drafts: QuotationDraftStore(
          ref.watch(encryptedDraftRepositoryProvider),
        ),
        online:
            !connection.isLoading &&
            !connection.hasError &&
            connection.value == ConnectivityState.online,
      );
      ref.listen(
        connectivityStateProvider,
        (_, s) => c.setOnline(
          !s.isLoading && !s.hasError && s.value == ConnectivityState.online,
        ),
      );
      ref.onDispose(c.dispose);
      unawaited(c.initialize());
      return c;
    });

final class ReservationController extends ChangeNotifier
    implements OperationalReadAccess {
  ReservationController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.online,
  });
  final TenantContext scope;
  final ReservationGateway gateway;
  final QuotationDraftStore drafts;
  static const slot = 'reservation-release-editor';
  bool online, busy = false, _disposed = false, accessDenied = false;
  int _epoch = 0;
  @override
  int get readAccessEpoch => _epoch;
  @override
  bool currentRead(int epoch) =>
      !_disposed && online && !accessDenied && epoch == _epoch;
  @override
  void denyReadAccess() {
    if (_disposed) return;
    accessDenied = true;
    _epoch++;
    clearEvidence();
    emit();
  }

  String filter = 'active';
  String? cursor, error, message, coverageStart;
  int? historyCursor;
  String reportInstant = DateTime.now().toUtc().toIso8601String();
  String? reportCursor, loadedReportInstant, reportCoverage;
  List<Map<String, Object?>> reportRows = [];
  Future<void> loadReport({bool more = false}) => run(() async {
    if (!online || accessDenied) return;
    final epoch = _epoch;
    final instant = more ? loadedReportInstant : reportInstant.trim();
    final parsed = instant == null ? null : DateTime.tryParse(instant);
    if (parsed == null ||
        !instant!.endsWith('Z') ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$')
            .hasMatch(instant) ||
        parsed.toUtc().toIso8601String().substring(0, 19) !=
            instant.substring(0, 19)) {
      throw const FormatException(
        'Enter a valid UTC time, for example 2026-09-19T12:00:00Z.',
      );
    }
    final result = await gateway.asOf(
      scope,
      instant,
      after: more ? reportCursor : null,
    );
    if (_disposed || !online || epoch != _epoch) return;
    reportRows = [
      if (more) ...reportRows,
      for (final row in result['items'] as List)
        (row as Map).cast<String, Object?>(),
    ];
    reportCursor = result['next_cursor'] as String?;
    loadedReportInstant = instant;
    reportCoverage = result['coverage_start'] as String?;
  });
  List<Map<String, Object?>> items = [], events = [];
  Map<String, Object?>? form;
  QuotationLocalDraft? local;
  bool get locked =>
      busy || _disposed || accessDenied || local?.pending != null;
  void emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    clearEvidence();
    notifyListeners();
    super.dispose();
  }

  void setOnline(bool value) {
    if (online != value) {
      online = value;
      _epoch++;
      clearEvidence();
    }
    emit();
  }

  void clearEvidence() {
    if (form != null) form = releaseInputs(form!);
    local = inputDraft(local);
    items = [];
    events = [];
    reportRows = [];
    cursor = null;
    historyCursor = null;
    coverageStart = null;
    reportCursor = null;
    loadedReportInstant = null;
    reportCoverage = null;
  }

  static Map<String, Object?> releaseInputs(Map<String, Object?> value) => {
    for (final key in ['id', 'version', 'status', 'reason', 'mode'])
      if (value.containsKey(key)) key: value[key],
  };

  static QuotationLocalDraft? inputDraft(QuotationLocalDraft? value) =>
      value == null
      ? null
      : QuotationLocalDraft(
          form: releaseInputs(value.form),
          expectedVersion: value.expectedVersion,
          localVersion: value.localVersion,
          pending: value.pending,
          errorCode: value.errorCode,
        );

  Future<void> run(Future<void> Function() work) async {
    if (busy || _disposed) return;
    final epoch = _epoch;
    busy = true;
    error = null;
    emit();
    try {
      await work();
    } catch (e) {
      if (_disposed || epoch != _epoch) return;
      if (e is DomainError &&
          const {
            'PERMISSION_DENIED',
            'ACCESS_DENIED',
            'MFA_REQUIRED',
            'AUTHENTICATION_REQUIRED',
          }.contains(e.code)) {
        accessDenied = true;
        _epoch++;
        clearEvidence();
      }
      error = e is DomainError
          ? e.message
          : e is FormatException
          ? e.message
          : 'Unable to complete this action. Saved work is retained.';
    } finally {
      busy = false;
      emit();
    }
  }

  Future<void> initialize() => run(() async {
    local = inputDraft(await drafts.load(scope, slot));
    if (_disposed) return;
    form = local?.form;
    if (online) await _refresh();
  });
  Future<void> _refresh({bool more = false}) async {
    final epoch = _epoch;
    final result = await gateway.queue(
      scope,
      filter: filter,
      after: more ? cursor : null,
    );
    if (_disposed || !online || epoch != _epoch) return;
    items = [
      if (more) ...items,
      for (final row in result['items'] as List)
        (row as Map).cast<String, Object?>(),
    ];
    cursor = result['next_cursor'] as String?;
    accessDenied = false;
  }

  Future<void> refresh({bool more = false, String? selection}) => run(() async {
    if (!online) return;
    if (selection != null && selection != filter) {
      filter = selection;
      items = [];
      cursor = null;
    }
    await _refresh(more: more);
  });
  Future<void> open(Map<String, Object?> row) => run(() async {
    if (!online || form != null || accessDenied) return;
    final current = items
        .where(
          (item) =>
              item['id'] == row['id'] && item['version'] == row['version'],
        )
        .firstOrNull;
    if (current == null) return;
    message = null;
    form = {
      ...current,
      'reason': '',
      'mode': filter == 'expired' || filter == 'retired' ? filter : 'manual',
    };
    events = [];
    historyCursor = null;
    coverageStart = null;
    await _save();
  });
  void update(String key, String value) {
    if (locked ||
        form == null ||
        form!['status'] != 'active' ||
        !['reason', 'mode'].contains(key)) {
      return;
    }
    form = {...form!, key: value};
    emit();
  }

  Future<void> _save() async {
    if (form == null) return;
    final inputs = releaseInputs(form!);
    await drafts.save(
      scope,
      slot,
      inputs,
      expectedVersion: inputs['version'] as int?,
    );
    local = inputDraft(await drafts.load(scope, slot));
  }

  Future<void> save() => run(_save);
  Future<bool> canLeave() async {
    if (busy) return false;
    if (local?.pending != null || form == null) return true;
    await save();
    return error == null;
  }

  Future<void> close() => run(() async {
    if (local?.pending != null) {
      throw const FormatException(
        'Retry the pending release before closing it.',
      );
    }
    await drafts.discard(scope, slot);
    form = null;
    message = null;
    local = null;
    events = [];
    historyCursor = null;
    coverageStart = null;
  });
  Future<void> history({bool more = false}) => run(() async {
    if (!online || accessDenied || form == null) return;
    final epoch = _epoch;
    final result = await gateway.history(
      scope,
      form!['id'] as String,
      beforeVersion: more ? historyCursor : null,
    );
    if (_disposed || !online || epoch != _epoch) return;
    events = [
      if (more) ...events,
      for (final row in result['items'] as List)
        (row as Map).cast<String, Object?>(),
    ];
    coverageStart = result['coverage_start'] as String?;
    historyCursor = result['next_version'] as int?;
  });
  Future<void> release() => run(() async {
    if (!online || accessDenied || form == null) return;
    final epoch = _epoch;
    final inputs = {
      for (final key in ['id', 'version', 'status', 'reason', 'mode'])
        key: form![key],
    };
    var pending = local?.pending;
    if (pending == null) {
      if (form!['status'] != 'active') return;
      final reason = (form!['reason'] as String? ?? '').trim();
      if (reason.length < 3 ||
          reason.length > 1000 ||
          !['manual', 'expired', 'retired'].contains(form!['mode'])) {
        throw const FormatException(
          'Choose a release mode and enter a reason of 3 to 1000 characters.',
        );
      }
      await _save();
      pending = await drafts.prepare(
        scope,
        slot,
        verb: 'cancel',
        payload: {'id': inputs['id'], 'mode': inputs['mode'], 'reason': reason},
        expectedVersion: inputs['version'] as int?,
      );
      local = await drafts.load(scope, slot);
    }
    if (_disposed || !online || accessDenied || epoch != _epoch) return;
    Map<String, Object?> result;
    try {
      result = await gateway.release(pending.envelope);
      await drafts.confirm(
        scope,
        slot,
        pending.envelope.commandId,
        form: {
          ...inputs,
          'status': result['status'],
          'version': result['version'],
        },
        expectedVersion: result['version'] as int?,
      );
    } on DomainError catch (e) {
      await drafts.recordFailure(
        scope,
        slot,
        e,
        commandId: pending.envelope.commandId,
      );
      local = await drafts.load(scope, slot);
      rethrow;
    }
    if (_disposed) return;
    local = null;
    message = 'Reservation release confirmed.';
    if (!online || epoch != _epoch) {
      form = null;
      return;
    }
    form = {...form!, ...result};
    try {
      await _refresh();
    } catch (e) {
      if (_disposed || !online || epoch != _epoch) return;
      if (e is DomainError &&
          const {
            'PERMISSION_DENIED',
            'ACCESS_DENIED',
            'MFA_REQUIRED',
            'AUTHENTICATION_REQUIRED',
          }.contains(e.code)) {
        rethrow;
      }
      error =
          'Release confirmed. Retry the queue refresh to view its evidence.';
    }
  });
}

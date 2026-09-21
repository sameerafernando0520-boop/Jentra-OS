import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import '../../app_providers.dart';

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
      final c = ReservationController(
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

final class ReservationController extends ChangeNotifier {
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
  bool online, busy = false, _disposed = false;
  String filter = 'active';
  String? cursor, error, message, coverageStart;
  int? historyCursor;
  String reportInstant = DateTime.now().toUtc().toIso8601String();
  String? reportCursor, loadedReportInstant, reportCoverage;
  List<Map<String, Object?>> reportRows = [];
  Future<void> loadReport({bool more = false}) => run(() async {
    if (!online) return;
    final instant = more ? loadedReportInstant : reportInstant.trim();
    final parsed = instant == null ? null : DateTime.tryParse(instant);
    if (parsed == null ||
        !instant!.endsWith('Z') ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$',
        ).hasMatch(instant) ||
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
    if (_disposed) return;
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
  bool get locked => busy || _disposed || local?.pending != null;
  void emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void setOnline(bool value) {
    online = value;
    emit();
  }

  Future<void> run(Future<void> Function() work) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    emit();
    try {
      await work();
    } catch (e) {
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
    local = await drafts.load(scope, slot);
    if (_disposed) return;
    form = local?.form;
    if (online) await _refresh();
  });
  Future<void> _refresh({bool more = false}) async {
    final result = await gateway.queue(
      scope,
      filter: filter,
      after: more ? cursor : null,
    );
    if (_disposed) return;
    items = [
      if (more) ...items,
      for (final row in result['items'] as List)
        (row as Map).cast<String, Object?>(),
    ];
    cursor = result['next_cursor'] as String?;
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
    if (form != null) return;
    message = null;
    form = {
      ...row,
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
    await drafts.save(
      scope,
      slot,
      form!,
      expectedVersion: form!['version'] as int?,
    );
    local = await drafts.load(scope, slot);
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
    if (!online || form == null) return;
    final result = await gateway.history(
      scope,
      form!['id'] as String,
      beforeVersion: more ? historyCursor : null,
    );
    if (_disposed) return;
    events = [
      if (more) ...events,
      for (final row in result['items'] as List)
        (row as Map).cast<String, Object?>(),
    ];
    coverageStart = result['coverage_start'] as String?;
    historyCursor = result['next_version'] as int?;
  });
  Future<void> release() => run(() async {
    if (!online || form == null) return;
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
        payload: {'id': form!['id'], 'mode': form!['mode'], 'reason': reason},
        expectedVersion: form!['version'] as int?,
      );
      local = await drafts.load(scope, slot);
    }
    Map<String, Object?> result;
    try {
      result = await gateway.release(pending.envelope);
      await drafts.complete(scope, slot, pending.envelope.commandId);
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
    form = {...form!, ...result};
    local = null;
    message = 'Reservation release confirmed.';
    try {
      await _save();
      await _refresh();
    } catch (_) {
      error = 'Release confirmed. Retry local save or refresh before leaving.';
    }
  });
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';

final periodFxGatewayProvider = Provider<PeriodFxGateway?>((ref) => null);
final periodFxControllerProvider = Provider.autoDispose<PeriodFxController?>((
  ref,
) {
  final scope = ref.watch(activeTenantContextProvider);
  final gateway = ref.watch(periodFxGatewayProvider);
  final caps = ref.watch(businessCapabilitiesProvider);
  if (scope == null ||
      !scope.hasOperationalScope ||
      gateway == null ||
      caps.isLoading ||
      caps.hasError ||
      !(caps.value?.contains('finance.view') ?? false)) {
    return null;
  }
  final controller = PeriodFxController(
    scope: scope,
    gateway: gateway,
    drafts: QuotationDraftStore(ref.watch(encryptedDraftRepositoryProvider)),
    capabilities: caps.value!,
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

final class PeriodFxController extends ChangeNotifier {
  PeriodFxController({
    required this.scope,
    required this.gateway,
    required this.drafts,
    required this.capabilities,
    required this.online,
  });
  static const slot = 'period-fx-editor';
  final TenantContext scope;
  final PeriodFxGateway gateway;
  final QuotationDraftStore drafts;
  final Set<String> capabilities;
  bool online,
      busy = false,
      verified = false,
      denied = false,
      _disposed = false;
  String? error, message;
  int formEpoch = 0;
  Map<String, Object?> form = {};
  QuotationLocalDraft? local;
  final pages = <String, List<Map<String, Object?>>>{};
  final cursors = <String, String?>{};
  List<Map<String, Object?>> detail = [];
  int? detailNext;
  String? detailRunId;

  String? get periodId => form['period_id'] as String?;
  bool get pending => local?.pending != null;
  bool get locked => busy || pending || denied;
  String get today => DateTime.now().toUtc().toIso8601String().substring(0, 10);
  List<Map<String, Object?>> rows(String key) => pages[key] ?? [];
  Map<String, Object?>? get period {
    for (final row in rows('periods')) {
      if (row['id'] == periodId) return row;
    }
    return null;
  }

  bool can(String action) => capabilities.contains(switch (action) {
    'post' || 'reverse' => 'finance.fx.post',
    'soft_lock' || 'hard_lock' => 'finance.period.close',
    'request_reopen' || 'approve_reopen' => 'finance.period.reopen',
    _ => '',
  });

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
    if (!value) {
      verified = false;
      pages.clear();
      detail = [];
    }
    emit();
  }

  void _handle(Object failure) {
    if (failure is DomainError && failure.code == 'PERMISSION_DENIED') {
      denied = true;
      verified = false;
      pages.clear();
      detail = [];
      form = {};
    }
    error = failure is DomainError
        ? failure.message
        : failure is FormatException
        ? failure.message
        : 'Unable to confirm this action. Your sealed request is retained.';
  }

  Future<void> _run(Future<void> Function() work) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    emit();
    try {
      await work();
    } catch (failure) {
      _handle(failure);
    } finally {
      busy = false;
      emit();
    }
  }

  Future<void> initialize() => _run(() async {
    local = await drafts.load(scope, slot);
    if (!online) return;
    await _load('periods');
    verified = true;
    denied = false;
    form = local?.form ?? {'reason': '', 'as_of': today};
    formEpoch++;
    await _load('rates');
    await _load('runs');
    if (periodId != null) {
      await _load('events');
      await _load('reopen_requests');
    }
  });

  Future<void> _load(String resource, {bool more = false}) async {
    if (!online) return;
    final after = more ? cursors[resource] : null;
    final response = switch (resource) {
      'periods' || 'events' || 'reopen_requests' => await gateway.periodOptions(
        scope,
        resource,
        periodId: resource == 'periods' ? null : periodId,
        after: after,
      ),
      _ => await gateway.fxOptions(scope, resource, after: after),
    };
    if (_disposed) return;
    pages[resource] = [
      if (more) ...rows(resource),
      for (final value in response['items'] as List)
        (value as Map).cast<String, Object?>(),
    ];
    cursors[resource] = response['next_cursor'] as String?;
  }

  Future<void> page(String resource) => _run(() => _load(resource, more: true));

  Future<void> _refresh() async {
    await _load('periods');
    await _load('rates');
    await _load('runs');
    if (periodId != null) {
      await _load('events');
      await _load('reopen_requests');
    }
  }

  Future<void> refresh() => _run(() async {
    if (online && verified && !denied) await _refresh();
  });

  Future<void> selectPeriod(String id) => _run(() async {
    if (pending ||
        denied ||
        !verified ||
        !rows('periods').any((row) => row['id'] == id))
      return;
    form = {
      'period_id': id,
      'as_of': rows('periods').firstWhere((row) => row['id'] == id)['end_date'],
      'reason': '',
    };
    formEpoch++;
    await persist();
    await _load('events');
    await _load('reopen_requests');
  });

  void field(String key, String value) {
    if (locked) return;
    form = key == 'currency_code'
        ? {...form, key: value.trim(), 'exchange_rate_id': null}
        : {...form, key: value.trim()};
    emit();
  }

  Future<void> persist() async {
    await drafts.save(
      scope,
      slot,
      form,
      expectedVersion: expectedVersion(form['action'] as String? ?? 'post'),
    );
    local = await drafts.load(scope, slot);
  }

  int expectedVersion(String action) => switch (action) {
    'soft_lock' ||
    'hard_lock' ||
    'request_reopen' ||
    'approve_reopen' => period?['version'] as int? ?? 0,
    'reverse' => 1,
    _ => 0,
  };

  Future<void> save() => _run(() async {
    if (!pending && !denied && form.isNotEmpty) await persist();
  });

  Future<bool> canLeave() async {
    if (busy) return false;
    if (pending || denied || form.isEmpty) return true;
    await save();
    return error == null;
  }

  void _validateDate(Object? value) {
    if (value is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
        DateTime.tryParse(value)?.toIso8601String().substring(0, 10) != value ||
        value.compareTo(today) > 0) {
      throw const FormatException('Enter a valid date no later than today.');
    }
  }

  Future<void> execute(String action, {String? sourceId}) => _run(() async {
    if (!online || !verified || denied || !can(action)) return;
    var pendingCommand = local?.pending;
    if (pendingCommand == null) {
      if (periodId == null || period == null) {
        throw const FormatException('Choose an active fiscal period.');
      }
      final reason = form['reason'] as String? ?? '';
      if (reason.length < 3 || reason.length > 1000) {
        throw const FormatException('Enter a reason of 3 to 1000 characters.');
      }
      final payload = <String, Object?>{
        'action': action,
        'id': const Uuid().v4(),
        'period_id': periodId,
        'reason': reason,
      };
      if (action == 'approve_reopen') {
        if (sourceId == null) {
          throw const FormatException('Choose a reopen request.');
        }
        payload['request_id'] = sourceId;
      } else if (action == 'post' || action == 'reverse') {
        final date = form['as_of'];
        _validateDate(date);
        if ((date as String).compareTo(period!['start_date'] as String) < 0 ||
            date.compareTo(period!['end_date'] as String) > 0) {
          throw const FormatException(
            'Date must be inside the selected period.',
          );
        }
        payload['as_of'] = date;
        if (action == 'reverse') {
          if (sourceId == null) {
            throw const FormatException('Choose an active FX run.');
          }
          payload['run_id'] = sourceId;
        } else {
          final currency = form['currency_code'] as String?;
          final rateId = form['exchange_rate_id'] as String?;
          if (currency == null ||
              rateId == null ||
              !rows('rates').any(
                (row) =>
                    row['id'] == rateId &&
                    row['source_currency_code'] == currency &&
                    row['effective_date'].toString().compareTo(date) <= 0,
              )) {
            throw const FormatException('Choose a valid closing rate.');
          }
          payload['currency_code'] = currency;
          payload['exchange_rate_id'] = rateId;
        }
      }
      form = {...form, 'action': action};
      await persist();
      pendingCommand = await drafts.prepare(
        scope,
        slot,
        verb: 'accept',
        payload: payload,
        expectedVersion: expectedVersion(action),
      );
      local = await drafts.load(scope, slot);
    }
    final command = pendingCommand;
    try {
      final result = action == 'post' || action == 'reverse'
          ? await gateway.revalue(command.envelope)
          : await gateway.govern(command.envelope);
      await drafts.complete(scope, slot, command.envelope.commandId);
      local = null;
      message = result['status'] == 'blocked'
          ? 'Close blocked. Review the recorded exceptions before retrying.'
          : 'Command confirmed. The original evidence remains in history.';
      form = {...form, 'action': null};
      formEpoch++;
      try {
        await persist();
        await _refresh();
      } catch (failure) {
        _handle(failure);
        if (!denied) error = 'Command confirmed. Refresh to load its evidence.';
      }
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
  });

  Future<void> retry() =>
      execute(local?.pending?.envelope.payload['action'] as String? ?? 'post');

  Future<void> resolveConflict() => _run(() async {
    if (!online ||
        !verified ||
        denied ||
        pending ||
        local?.errorCode != 'VERSION_CONFLICT')
      return;
    await _refresh();
    await drafts.save(
      scope,
      slot,
      form,
      expectedVersion: expectedVersion(form['action'] as String? ?? 'post'),
      resolveConflict: true,
    );
    local = await drafts.load(scope, slot);
    message =
        'Current period and rate evidence refreshed. Review before retrying.';
  });

  Future<void> openDetail(String runId) => _run(() async {
    if (!online || !verified || denied) return;
    final page = await gateway.fxDetail(scope, runId);
    detailRunId = runId;
    detail = [
      for (final item in page['items'] as List)
        (item as Map).cast<String, Object?>(),
    ];
    detailNext = page['next_offset'] as int?;
  });

  Future<void> moreDetail() => _run(() async {
    if (detailRunId == null || detailNext == null || !online || denied) return;
    final page = await gateway.fxDetail(
      scope,
      detailRunId!,
      offset: detailNext!,
    );
    detail = [
      ...detail,
      for (final item in page['items'] as List)
        (item as Map).cast<String, Object?>(),
    ];
    detailNext = page['next_offset'] as int?;
  });
}

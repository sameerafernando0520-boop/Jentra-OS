import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_service.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_service_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';

const serviceDefiniteFailures = {
  'VERSION_CONFLICT',
  'VALIDATION_ERROR',
  'STATE_CONFLICT',
  'IDENTITY_EXISTS',
  'WORK_INTERVAL_CONFLICT',
  'PAYROLL_INPUT_SEALED',
  'SERVICE_PARTS_PROVIDER_UNAVAILABLE',
  'SERVICE_BILLING_ADAPTER_UNAVAILABLE',
  'SERVICE_EQUIPMENT_PROVIDER_UNAVAILABLE',
};
ScopedCommandDraftStore serviceDraftStore(
  EncryptedDraftRepository r,
  String action,
) => ScopedCommandDraftStore(
  r,
  entityType: 'service.command.$action',
  fields: ServiceCommands.fields,
  validate: ServiceCommands.validate,
  definiteFailures: serviceDefiniteFailures,
);
final serviceRepositoryProvider = Provider<ServiceRepository?>((ref) => null);
final serviceControllerProvider = Provider.autoDispose<ServiceController?>((
  ref,
) {
  final scope = ref.watch(activeTenantContextProvider),
      caps = ref.watch(businessCapabilitiesProvider),
      repo = ref.watch(serviceRepositoryProvider);
  if (scope == null ||
      !scope.hasOperationalScope ||
      repo == null ||
      caps.isLoading ||
      caps.hasError ||
      !(caps.value?.contains('service.view') ?? false)) {
    return null;
  }
  final encrypted = ref.watch(encryptedDraftRepositoryProvider),
      c = ServiceController(
        scope: scope,
        repository: repo,
        drafts: {
          for (final a in ServiceCommands.extras.keys)
            a: serviceDraftStore(encrypted, a),
        },
        permissions: caps.value!,
        online:
            ref.read(connectivityStateProvider).value ==
            ConnectivityState.online,
      );
  ref.listen(
    connectivityStateProvider,
    (_, x) => c.setOnline(x.value == ConnectivityState.online),
  );
  ref.onDispose(c.dispose);
  unawaited(c.initialize());
  return c;
});

final class ServiceSavedDraft {
  const ServiceSavedDraft(this.action, this.draft);
  final String action;
  final ScopedCommandDraft draft;
}

final class ServiceController extends ChangeNotifier {
  ServiceController({
    required this.scope,
    required this.repository,
    required this.drafts,
    required Set<String> permissions,
    required this.online,
    bool monitor = true,
  }) : permissions = Set.unmodifiable(permissions) {
    if (monitor) {
      _timer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(checkAccess()),
      );
    }
  }
  final TenantContext scope;
  final ServiceRepository repository;
  final Map<String, ScopedCommandDraftStore> drafts;
  final Set<String> permissions;
  static const uuid = Uuid();
  Timer? _timer;
  bool online,
      busy = false,
      denied = false,
      _disposed = false,
      _sending = false;
  int _epoch = 0;
  int _formEpoch = 0;
  ServiceKind kind = ServiceKind.ticket;
  List<ServiceRecord> records = [];
  String? cursor, error, message;
  ServiceAuthority? authority;
  ServiceDetail? selected, comparison;
  Map<String, Object?>? form, confirmed;
  ScopedCommandDraft? local;
  int expectedVersion = 0;
  List<ServiceSavedDraft> recovery = [];
  final labels = <String, String>{};
  final recoveryCursors = <String, String?>{};
  bool get current => !_disposed && !denied;
  int get accessEpoch => _epoch;
  int get formEpoch => _formEpoch;
  bool has(String cap) => permissions.contains(cap);
  String? get action => form?['action'] as String?;
  ScopedPendingCommand? get pending => local?.pending;
  bool get conflicted => local?.errorCode == 'VERSION_CONFLICT';
  bool get locked =>
      busy || !current || pending != null || conflicted || confirmed != null;
  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  bool _live(int epoch) => current && online && epoch == _epoch;
  void _deny() {
    _epoch++;
    _formEpoch++;
    denied = true;
    records = [];
    selected = null;
    comparison = null;
    form = null;
    local = null;
    confirmed = null;
    authority = null;
    labels.clear();
    recovery = [];
    error = 'Current service access is required. Select an authorized scope.';
    _notify();
  }

  void _failure(Object cause) {
    if (cause is DomainError &&
        {
          'AUTHENTICATION_REQUIRED',
          'PERMISSION_DENIED',
          'ACCESS_DENIED',
          'MFA_REQUIRED',
          'FEATURE_NOT_ENTITLED',
        }.contains(cause.code)) {
      _deny();
      return;
    }
    error = cause is DomainError
        ? cause.message
        : cause is FormatException
        ? 'Check the service form and exact evidence.'
        : 'Service is unavailable. Retry the authorized read.';
    _notify();
  }

  void setOnline(bool value) {
    if (online == value) {
      return;
    }
    _epoch++;
    _formEpoch++;
    online = value;
    records = [];
    cursor = null;
    selected = null;
    authority = null;
    comparison = null;
    confirmed = null;
    labels.clear();
    recovery = [];
    form = null;
    local = null;
    error = null;
    message = null;
    _notify();
  }

  Future<void> checkAccess() async {
    if (!current || busy || !online) {
      return;
    }
    final epoch = _epoch;
    try {
      final a = await repository.authorize(scope, 'service.view');
      if (_live(epoch)) {
        authority = a;
      }
    } catch (e) {
      if (_live(epoch)) {
        _failure(e);
      }
    }
  }

  Future<void> initialize() async {
    await refresh();
    if (current) {
      await loadRecovery();
    }
  }

  Future<void> refresh({bool more = false}) async {
    if (!current || busy || !online) {
      return;
    }
    busy = true;
    error = null;
    _notify();
    final epoch = _epoch;
    try {
      final fresh = await repository.authorize(scope, 'service.view');
      if (!_live(epoch)) {
        return;
      }
      authority = fresh;
      final page = await repository.list(
        scope,
        kind,
        after: more ? cursor : null,
      );
      if (_live(epoch)) {
        records = more ? [...records, ...page.items] : page.items;
        cursor = page.nextCursor;
      }
    } catch (e) {
      if (_live(epoch)) {
        _failure(e);
      }
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> selectKind(ServiceKind next) async {
    final epoch = _epoch;
    if (!await canLeave() || !_live(epoch)) {
      return false;
    }
    kind = next;
    selected = null;
    records = [];
    cursor = null;
    await refresh();
    return true;
  }

  Future<void> open(ServiceRecord record, {bool more = false}) async {
    if (!current || busy || !online) {
      return;
    }
    busy = true;
    _notify();
    final epoch = _epoch;
    try {
      final d = await repository.detail(
        scope,
        record.kind,
        record.id,
        after: more ? selected?.nextCursor : null,
      );
      if (_live(epoch)) {
        selected = more && selected != null
            ? ServiceDetail(d.record, [
                ...selected!.events,
                ...d.events,
              ], d.nextCursor)
            : d;
      }
    } catch (e) {
      if (_live(epoch)) {
        _failure(e);
      }
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> loadRecovery({String? moreAction}) async {
    if (!current || !online) {
      return;
    }
    final epoch = _epoch;
    final items = <ServiceSavedDraft>[];
    for (final entry in drafts.entries) {
      final cap = ServiceCommands.capability(entry.key);
      if (!has(cap) || moreAction != null && entry.key != moreAction) {
        continue;
      }
      try {
        await repository.authorize(scope, cap);
        if (!_live(epoch)) {
          return;
        }
        final page = await entry.value.page(
          scope,
          after: moreAction == entry.key ? recoveryCursors[entry.key] : null,
        );
        if (!_live(epoch)) {
          return;
        }
        recoveryCursors[entry.key] = page.nextCursor;
        for (final row in page.items) {
          if (row.pending != null &&
              await ServiceCommandAcknowledgements(entry.value)
                  .contains(row.pending!)) {
            if (!_live(epoch)) {
              return;
            }
            await entry.value.complete(
              scope,
              row.aggregateId,
              row.pending!.envelope.commandId,
            );
          } else {
            items.add(ServiceSavedDraft(entry.key, row));
          }
          if (!_live(epoch)) {
            return;
          }
        }
      } catch (e) {
        if (_live(epoch)) {
          _failure(e);
        }
        return;
      }
    }
    if (_live(epoch)) {
      recovery = moreAction == null ? items : [...recovery, ...items];
      _notify();
    }
  }

  Future<bool> begin(String a, {ServiceRecord? target}) async {
    if (!current ||
        busy ||
        pending != null ||
        !has(ServiceCommands.capability(a))) {
      return false;
    }
    final entryEpoch = _epoch;
    if (!await canLeave() || !_live(entryEpoch)) {
      return false;
    }
    final epoch = _epoch, formEpoch = ++_formEpoch;
    try {
      final fresh = await repository.authorize(
        scope,
        ServiceCommands.capability(a),
      );
      if (!_live(epoch) || formEpoch != _formEpoch) {
        return false;
      }
      authority = fresh;
      final id = target?.id ?? uuid.v4(),
          now = serviceInstant(DateTime.now()),
          today = now.substring(0, 10),
          data = <String, Object?>{'action': a, 'id': id, 'reason': ''};
      final row =
          target?.toJson() ?? selected?.record.toJson() ?? <String, Object?>{};
      switch (a) {
        case 'equipment':
          data.addAll({
            'code': '',
            'name': '',
            'identity': '',
            'kind': 'customer',
            'customer_id': null,
            'provider_id': null,
          });
        case 'coverage':
          data.addAll({
            'equipment_id': row['id'],
            'kind': 'warranty',
            'name': '',
            'start_date': today,
            'end_date_exclusive': today,
            'evidence_reference': '',
          });
        case 'policy':
          data.addAll({
            'name': '',
            'calendar_version_id': null,
            'start_date': today,
            'end_date_exclusive': today,
            'response_seconds': 3600,
            'resolution_seconds': 28800,
            'independent_closure': true,
            'offsets': <Object?>[],
          });
        case 'ticket':
          data.addAll({
            'code': '',
            'name': '',
            'classification': 'repair',
            'customer_id': null,
            'contact_id': null,
            'equipment_id': null,
            'coverage_id': null,
            'policy_id': null,
            'priority': 'normal',
            'owner_id': null,
            'observed_utc': now,
          });
        case 'order':
          data['ticket_id'] = selected?.record.id;
        case 'dispatch':
          data.addAll({
            'employee_id': null,
            'calendar_version_id': null,
            'start_utc': now,
            'end_utc': now,
            'booking_id': uuid.v4(),
          });
        case 'labor':
          data.addAll({
            'order_id': selected?.record.id,
            'employee_id': row['employee_id'],
            'calendar_version_id': null,
            'start_utc': now,
            'end_utc': now,
            'breaks': <Object?>[],
            'claim_id': null,
            'hourly_cost': '0',
            'currency_code': fresh.currency,
            'precision': fresh.precision,
            'billing_kind': 'nonbillable',
            'hourly_billing': '0',
            'billing_reference': 'Synthetic nonbillable work',
          });
        case 'accept' || 'start' || 'pause' || 'resume' || 'evaluate':
          data['observed_utc'] = now;
        case 'reprioritize':
          data.addAll({
            'policy_id': row['policy_id'],
            'priority': row['priority'] ?? 'normal',
            'observed_utc': now,
          });
        case 'complete':
          data.addAll({
            'observed_utc': now,
            'resolution': '',
            'customer_confirmed': false,
            'exception_reason': '',
          });
        case 'plan':
          data.addAll({
            'equipment_id': selected?.record.id,
            'policy_id': null,
            'name': '',
            'basis': 'calendar',
            'interval_units': 30,
            'next_date': today,
            'next_meter': null,
          });
        case 'reading':
          data.addAll({
            'equipment_id': selected?.record.id,
            'kind': 'initial',
            'raw_value': 0,
            'rollover_max': null,
            'observed_utc': now,
          });
        case 'generate':
          data.addAll({
            'ticket_id': uuid.v4(),
            'order_id': uuid.v4(),
            'occurrence_id': uuid.v4(),
            'observed_utc': now,
          });
        case 'defer':
          data['deferred_until'] = today;
      }
      form = data;
      expectedVersion = target?.version ?? 0;
      local = null;
      confirmed = null;
      comparison = null;
      error = null;
      labels.clear();
      _notify();
      return true;
    } catch (e) {
      if (_live(epoch) && formEpoch == _formEpoch) {
        _failure(e);
      }
      return false;
    }
  }

  void edit(String field, Object? value) {
    if (locked ||
        form == null ||
        !ServiceCommands.fields(action!).contains(field) ||
        {
          'id',
          'action',
          'currency_code',
          'precision',
          'booking_id',
          'occurrence_id',
        }.contains(field) ||
        action == 'generate' && {'ticket_id', 'order_id'}.contains(field)) {
      return;
    }
    form = {...form!, field: value};
    if (field == 'customer_id' && action == 'ticket') {
      form!['contact_id'] = null;
      labels.remove('contact_id');
    }
    if (field == 'employee_id' && action == 'labor') {
      form!['claim_id'] = null;
      labels.remove('claim_id');
    }
    if (field == 'basis') {
      form!['next_date'] = value == 'calendar'
          ? serviceInstant(DateTime.now()).substring(0, 10)
          : null;
      form!['next_meter'] = value == 'meter' ? 1 : null;
    }
    if (field == 'billing_kind' && value == 'nonbillable') {
      form!['hourly_billing'] = '0';
    }
    error = null;
    _notify();
  }

  Future<void> choose(String field, ServiceChoice choice) async {
    if (locked) {
      return;
    }
    final epoch = _epoch, formEpoch = _formEpoch;
    if (field == 'equipment_id' && action == 'ticket') {
      try {
        final detail = await repository.detail(
          scope,
          ServiceKind.equipment,
          choice.id,
        );
        if (!_live(epoch) || formEpoch != _formEpoch || locked) {
          return;
        }
        if (detail.record.version != choice.version) {
          throw const DomainError(
            code: 'VERSION_CONFLICT',
            message: 'The equipment changed. Choose its current named source.',
          );
        }
        final equipment = detail.record.toJson();
        if (equipment['kind'] == 'asset') {
          edit('customer_id', null);
          edit('contact_id', null);
          labels['customer_id'] = 'Internal equipment has no customer';
          labels.remove('contact_id');
        } else {
          edit('customer_id', equipment['customer_id']);
          labels['customer_id'] = 'Recorded equipment customer';
        }
      } catch (e) {
        if (_live(epoch) && formEpoch == _formEpoch) _failure(e);
        return;
      }
    }
    edit(field, choice.id);
    labels[field] = choice.name;
    _notify();
  }

  Future<ServicePage<ServiceChoice>> choices(
    String choice, {
    String? after,
  }) async {
    if (!current || !online || form == null) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Current service access is required.',
      );
    }
    final epoch = _epoch,
        formEpoch = _formEpoch,
        a = action!,
        parent =
            form?[choice == 'claim' ? 'employee_id' : 'customer_id'] as String?;
    try {
      await repository.authorize(scope, ServiceCommands.capability(a));
      if (!_live(epoch) || formEpoch != _formEpoch) {
        throw const DomainError(
          code: 'STATE_CONFLICT',
          message: 'The service form changed.',
        );
      }
      ServicePage<ServiceChoice> result;
      if ({
        'customer',
        'contact',
        'employee',
        'calendar',
        'claim',
      }.contains(choice)) {
        result = await repository.choices(
          scope,
          choice,
          after: after,
          parent: parent,
        );
      } else {
        final k = ServiceKind.values.byName(choice),
            page = await repository.list(scope, k, after: after);
        result = ServicePage(
          page.items
              .map(
                (r) => ServiceChoice.fromJson({
                  'id': r.id,
                  'name': r.label,
                  'version': r.version,
                }),
              )
              .toList(),
          page.nextCursor,
        );
      }
      if (!_live(epoch) ||
          formEpoch != _formEpoch ||
          action != a ||
          form?[choice == 'claim' ? 'employee_id' : 'customer_id'] != parent) {
        throw const DomainError(
          code: 'STATE_CONFLICT',
          message: 'The service form changed.',
        );
      }
      return result;
    } catch (e) {
      if (_live(epoch) && formEpoch == _formEpoch) {
        _failure(e);
      }
      rethrow;
    }
  }

  Future<void> save() async {
    if (form == null ||
        pending != null ||
        conflicted ||
        confirmed != null ||
        !current) {
      return;
    }
    final epoch = _epoch,
        formEpoch = _formEpoch,
        a = action!,
        id = form!['id'] as String,
        data = Map<String, Object?>.from(form!),
        version = expectedVersion;
    try {
      await repository.authorize(scope, ServiceCommands.capability(a));
      if (!_live(epoch) || formEpoch != _formEpoch) {
        return;
      }
      await drafts[a]!.save(scope, id, a, data, version);
      if (_live(epoch) && formEpoch == _formEpoch) {
        final row = await drafts[a]!.load(scope, id);
        if (_live(epoch) && formEpoch == _formEpoch) {
          local = row;
        }
      }
    } catch (e) {
      if (_live(epoch) && formEpoch == _formEpoch) {
        _failure(e);
      }
      rethrow;
    }
  }

  Future<bool> canLeave() async {
    if (busy || _sending) {
      return false;
    }
    final epoch = _epoch;
    if (form != null && pending == null && !conflicted && confirmed == null) {
      try {
        await save();
      } catch (e) {
        if (_live(epoch)) {
          _failure(e);
        }
        return false;
      }
    }
    return _live(epoch);
  }

  Map<String, Object?> _confirm(
    Map<String, Object?> result,
    ScopedPendingCommand request,
  ) {
    final c = request.envelope, r = serviceMap(result['entity']);
    if (result['command_id'] != c.commandId ||
        r['id'] != c.payload['id'] ||
        r['kind'] != ServiceCommands.kind(request.action).name ||
        r['version'] != (c.expectedEntityVersion ?? 0) + 1) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'The confirmation does not match the original request.',
        retryable: true,
      );
    }
    serviceScope(r, scope);
    return result;
  }

  Future<void> send() async {
    if (!current ||
        busy ||
        !online ||
        form == null ||
        conflicted ||
        confirmed != null) {
      return;
    }
    busy = true;
    _sending = true;
    error = null;
    _notify();
    final epoch = _epoch, a = action!, id = form!['id'] as String;
    ScopedPendingCommand? request;
    try {
      await repository.authorize(scope, ServiceCommands.capability(a));
      if (!_live(epoch)) {
        return;
      }
      request =
          pending ??
          await drafts[a]!.prepare(scope, id, a, form!, expectedVersion);
      if (!_live(epoch)) {
        return;
      }
      final prepared = await drafts[a]!.load(scope, id);
      if (!_live(epoch)) {
        return;
      }
      local = prepared;
      final result = _confirm(
        await repository.execute(a, request.envelope),
        request,
      );
      if (_live(epoch)) {
        confirmed = result;
        message =
            'Service change confirmed. Invoice and payment remain separate.';
        _notify();
      }
      await ServiceCommandAcknowledgements(drafts[a]!).save(request, result);
      if (!_live(epoch)) {
        await drafts[a]!.complete(scope, id, request.envelope.commandId);
        return;
      }
      confirmed = result;
      message =
          'Service change confirmed. Invoice and payment remain separate.';
      _notify();
      try {
        await drafts[a]!.complete(scope, id, request.envelope.commandId);
        if (_live(epoch)) {
          local = null;
        }
      } catch (_) {
        if (_live(epoch)) {
          message =
              'Service change confirmed; local recovery cleanup needs retry.';
        }
      }
    } catch (e) {
      if (!_live(epoch)) {
        return;
      }
      final safe = e is DomainError
          ? e
          : DomainError(
              code: request == null ? 'VALIDATION_ERROR' : 'UNCERTAIN_RESULT',
              message: request == null ? 'Check the service form.' : 'The result is uncertain. Reconcile the exact original request.',
              retryable: request != null,
            );
      if (request != null) {
        try {
          await drafts[a]!.recordFailure(
            scope,
            id,
            request.envelope.commandId,
            safe,
          );
        } catch (storage) {
          if (_live(epoch)) {
            _failure(storage);
          }
          return;
        }
        if (_live(epoch)) {
          final row = await drafts[a]!.load(scope, id);
          if (_live(epoch)) {
            local = row;
          }
        }
      }
      if (_live(epoch)) {
        if (confirmed != null && safe.code == 'LOCAL_STORAGE_FULL') {
          message = 'Service change confirmed. Saving the encrypted confirmation failed; reconcile the original request after restoring local storage.';
        }
        _failure(safe);
      }
    } finally {
      busy = false;
      _sending = false;
      _notify();
    }
    if (current) {
      await refresh();
    }
  }

  Future<void> resume(ServiceSavedDraft saved) async {
    if (!current || busy || !await canLeave()) {
      return;
    }
    final epoch = _epoch, formEpoch = ++_formEpoch;
    try {
      await repository.authorize(
        scope,
        ServiceCommands.capability(saved.action),
      );
      if (!_live(epoch) || formEpoch != _formEpoch) {
        return;
      }
      final row = await drafts[saved.action]!.load(
        scope,
        saved.draft.aggregateId,
      );
      if (row == null || !_live(epoch) || formEpoch != _formEpoch) {
        return;
      }
      form = serviceMap(jsonDecode(jsonEncode(row.form)));
      local = row;
      expectedVersion = row.version;
      confirmed = null;
      comparison = null;
      error = null;
      _notify();
    } catch (e) {
      if (_live(epoch) && formEpoch == _formEpoch) {
        _failure(e);
      }
    }
  }

  Future<void> reconcile() async {
    final request = pending;
    if (request == null || busy || !current || !online) {
      return;
    }
    busy = true;
    _notify();
    final epoch = _epoch, a = action!, id = form!['id'] as String;
    try {
      final raw = await repository.ownReceipt(
        scope,
        a,
        request.envelope.idempotencyKey,
      );
      if (raw == null) {
        if (_live(epoch)) {
          message = 'No confirmed receipt is available. Retry only the original sealed request.';
        }
      } else {
        final result = _confirm(raw, request);
        if (_live(epoch)) {
          confirmed = result;
          message = 'Original service change confirmed.';
          _notify();
        }
        await ServiceCommandAcknowledgements(drafts[a]!).save(request, result);
        if (!_live(epoch)) {
          await drafts[a]!.complete(scope, id, request.envelope.commandId);
          return;
        }
        confirmed = result;
        message = 'Original service change confirmed.';
        _notify();
        await drafts[a]!.complete(scope, id, request.envelope.commandId);
        if (_live(epoch)) {
          local = null;
        }
      }
    } catch (e) {
      if (_live(epoch)) {
        _failure(e);
      }
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> compare() async {
    if (!current || !online || !conflicted || busy || form == null) {
      return;
    }
    final epoch = _epoch,
        formEpoch = _formEpoch,
        a = action!,
        id = form!['id'] as String;
    try {
      await repository.authorize(scope, ServiceCommands.capability(a));
      if (!_live(epoch) || formEpoch != _formEpoch) {
        return;
      }
      final d = await repository.detail(scope, ServiceCommands.kind(a), id);
      if (_live(epoch) && formEpoch == _formEpoch) {
        comparison = d;
        _notify();
      }
    } catch (e) {
      if (_live(epoch) && formEpoch == _formEpoch) {
        _failure(e);
      }
    }
  }

  Future<void> adoptComparison() async {
    if (comparison == null || !conflicted || pending != null) {
      return;
    }
    final epoch = _epoch,
        formEpoch = _formEpoch,
        a = action!,
        id = form!['id'] as String,
        data = Map<String, Object?>.from(form!),
        version = comparison!.record.version;
    await repository.authorize(scope, ServiceCommands.capability(action!));
    if (!_live(epoch) || formEpoch != _formEpoch) {
      return;
    }
    await drafts[a]!.save(scope, id, a, data, version, resolveConflict: true);
    final row = await drafts[a]!.load(scope, id);
    if (!_live(epoch) || formEpoch != _formEpoch) {
      return;
    }
    expectedVersion = version;
    local = row;
    comparison = null;
    _notify();
  }

  Future<void> discard() async {
    if (pending != null || busy) {
      return;
    }
    if (form != null && local != null) {
      await drafts[action!]!.discard(scope, form!['id'] as String);
    }
    form = null;
    _formEpoch++;
    local = null;
    confirmed = null;
    comparison = null;
    error = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _timer?.cancel();
    records = [];
    selected = null;
    form = null;
    local = null;
    confirmed = null;
    labels.clear();
    authority = null;
    comparison = null;
    recovery = [];
    super.dispose();
  }
}

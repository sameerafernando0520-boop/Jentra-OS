import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_platform/jentra_people_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';

final employeeRepositoryProvider = Provider<EmployeeRepository?>((ref) => null);

final employeeControllerProvider = Provider.autoDispose<EmployeeController?>((
  ref,
) {
  final scope = ref.watch(activeTenantContextProvider);
  final repository = ref.watch(employeeRepositoryProvider);
  final caps = ref.watch(businessCapabilitiesProvider);
  if (scope == null ||
      !scope.hasOperationalScope ||
      repository == null ||
      caps.isLoading ||
      caps.hasError ||
      !{
        'people.view',
        'people.employees.view',
      }.every((permission) => caps.value?.contains(permission) ?? false)) {
    return null;
  }
  final controller = EmployeeController(
    scope: scope,
    repository: repository,
    drafts: EmployeeDraftStore(ref.watch(encryptedDraftRepositoryProvider)),
    permissions: caps.value!,
    online:
        ref.read(connectivityStateProvider).value == ConnectivityState.online,
  );
  ref.listen(connectivityStateProvider, (_, value) {
    controller.setOnline(value.value == ConnectivityState.online);
  });
  ref.onDispose(controller.dispose);
  unawaited(controller.initialize());
  return controller;
});

final class EmployeeController extends ChangeNotifier {
  EmployeeController({
    required this.scope,
    required this.repository,
    required this.drafts,
    required this.permissions,
    required this.online,
  });
  static const slot = 'employee-editor';
  static const _uuid = Uuid();
  final TenantContext scope;
  final EmployeeRepository repository;
  final EmployeeDraftStore drafts;
  final Set<String> permissions;
  bool online;
  bool busy = false, accessDenied = false, _disposed = false;
  String? error, message, cursor;
  String status = 'employed', search = '';
  String asOfDate = '';
  List<Map<String, Object?>> items = [];
  List<Map<String, Object?>> events = [];
  List<Map<String, Object?>> branches = [];
  Map<String, Object?>? selected, form;
  EmployeeDraft? local;

  bool get canCreate => permissions.contains('people.employees.manage');
  bool get canManageEmployment =>
      permissions.contains('people.employment.manage');
  bool get canReadHistory =>
      permissions.contains('people.employees.history.view');
  bool get locked =>
      _disposed || busy || accessDenied || local?.pending != null;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _denied(Object error) =>
      error is DomainError &&
      {
        'PERMISSION_DENIED',
        'FEATURE_NOT_ENTITLED',
        'AUTHENTICATION_REQUIRED',
      }.contains(error.code);

  void _clearVisible() {
    items = [];
    selected = null;
    events = [];
    branches = [];
    form = null;
    cursor = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _clearVisible();
    local = null;
    super.dispose();
  }

  void setOnline(bool value) {
    online = value;
    _notify();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_disposed || busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      await action();
    } catch (cause) {
      if (_disposed) return;
      if (_denied(cause)) {
        accessDenied = true;
        _clearVisible();
      }
      error = cause is DomainError
          ? cause.message
          : cause is FormatException
          ? cause.message
          : 'Unable to load employees. Encrypted work is retained.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> initialize() => _run(() async {
    final saved = await drafts.load(scope, slot);
    if (_disposed) return;
    local = saved;
    form = local?.form;
    if (online) await _refresh();
  });

  Future<void> _refresh({bool more = false}) async {
    final response = await repository.directory(
      scope,
      asOfDate: asOfDate.isEmpty ? null : asOfDate,
      status: status,
      search: search,
      after: more ? cursor : null,
    );
    if (_disposed) return;
    asOfDate = CivilDate.parse(response['as_of'] as String).value;
    items = [
      if (more) ...items,
      for (final raw in response['items'] as List)
        Map<String, Object?>.from(raw as Map),
    ];
    cursor = response['next_cursor'] as String?;
    accessDenied = false;
  }

  Future<void> refresh({bool more = false}) => _run(() async {
    if (online) await _refresh(more: more);
  });

  Future<void> filter({
    String? nextStatus,
    String? nextDate,
    String? nextSearch,
  }) => _run(() async {
    if (nextStatus != null) status = nextStatus;
    if (nextDate != null) asOfDate = CivilDate.parse(nextDate).value;
    if (nextSearch != null) search = nextSearch.trim();
    selected = null;
    events = [];
    if (online) await _refresh();
  });

  Future<void> open(String id) => _run(() async {
    selected = null;
    events = [];
    final detail = await repository.detail(scope, id, asOfDate, status);
    if (_disposed) return;
    selected = detail;
    events = [];
    if (canReadHistory) {
      final result = await repository.history(scope, id);
      if (_disposed) return;
      events = [
        for (final raw in result['items'] as List)
          Map<String, Object?>.from(raw as Map),
      ];
    }
  });

  Future<void> loadBranches() => _run(() async {
    if (!canManageEmployment || !online) return;
    final result = await repository.branches(scope);
    if (_disposed) return;
    branches = [
      for (final raw in result['items'] as List)
        Map<String, Object?>.from(raw as Map),
    ];
  });

  void beginCreate() {
    if (!canCreate || locked) return;
    form = {
      'action': 'create',
      'version': 0,
      'id': _uuid.v4(),
      'code': '',
      'display_name': '',
      'work_email': '',
      'start_date': asOfDate,
      'job_title': '',
      'employment_type': 'permanent',
    };
    _notify();
  }

  void beginAction(String action, {String? eventId}) {
    if (selected == null ||
        locked ||
        (action == 'identity' && !canCreate) ||
        (action != 'identity' && !canManageEmployment)) {
      return;
    }
    final assignments = (selected!['assignments'] as List).cast<Map>();
    final current = assignments
        .where((a) => a['end_date_exclusive'] == null)
        .firstOrNull;
    form = switch (action) {
      'identity' => {
        'action': action,
        'id': selected!['id'],
        'version': selected!['version'],
        'display_name': selected!['display_name'],
        'work_email': selected!['work_email'] ?? '',
        'reason': '',
      },
      'assignment' => {
        'action': action,
        'id': selected!['id'],
        'version': selected!['version'],
        'effective_date': CivilDate.parse(asOfDate).next.value,
        'destination_branch_id': scope.branchId,
        'job_title': current?['job_title'] ?? '',
        'employment_type': current?['employment_type'] ?? 'permanent',
        'reason': '',
      },
      'end' => {
        'action': action,
        'id': selected!['id'],
        'version': selected!['version'],
        'spell_id': current?['spell_id'] ?? '',
        'end_date_exclusive': CivilDate.parse(asOfDate).next.value,
        'reason': '',
      },
      'rehire' => {
        'action': action,
        'id': selected!['id'],
        'version': selected!['version'],
        'start_date': CivilDate.parse(asOfDate).next.value,
        'job_title': '',
        'employment_type': 'permanent',
        'reason': '',
      },
      'correct' => {
        'action': action,
        'id': selected!['id'],
        'version': selected!['version'],
        'event_id': eventId ?? '',
        'correction_action': 'cancel',
        'reason': '',
      },
      _ => throw const FormatException('Unknown employee action.'),
    };
    _notify();
  }

  void edit(String key, Object? value) {
    if (form == null || locked) return;
    form = {...form!, key: value};
    _notify();
  }

  Future<void> saveLocal() => _run(() async {
    if (form == null || local?.pending != null) return;
    await drafts.save(scope, slot, form!, version: form!['version'] as int);
    if (_disposed) return;
    final saved = await drafts.load(scope, slot);
    if (_disposed) return;
    local = saved;
    message = 'Encrypted employee draft saved.';
  });

  Future<void> discard() => _run(() async {
    await drafts.discard(scope, slot);
    if (_disposed) return;
    form = null;
    local = null;
  });

  Future<bool> canLeave() async {
    if (local?.pending != null) return false;
    if (form != null) {
      try {
        await drafts.save(scope, slot, form!, version: form!['version'] as int);
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  Future<void> submit() => _run(() async {
    if (!online || accessDenied) {
      throw const DomainError(
        code: 'OFFLINE',
        message: 'Connect before saving employment.',
      );
    }
    final pending = local?.pending;
    if (form == null && pending == null) return;
    late EmployeePendingCommand command;
    if (pending != null) {
      command = pending;
    } else {
      final action = form!['action'] as String;
      final version = form!['version'] as int;
      final payload = <String, Object?>{
        for (final entry in form!.entries)
          if (entry.key != 'action' && entry.key != 'version')
            entry.key: entry.value,
      };
      validateEmployeePayload(action, payload);
      await drafts.save(scope, slot, form!, version: version);
      if (_disposed) return;
      command = await drafts.prepare(
        scope,
        slot,
        action: action,
        payload: payload,
        version: version,
      );
      if (_disposed) return;
      final saved = await drafts.load(scope, slot);
      if (_disposed) return;
      local = saved;
    }
    Map<String, Object?> confirmed;
    try {
      confirmed = await repository.execute(command.action, command.envelope);
      // A later scope must reconcile this exact receipt before local cleanup.
      if (_disposed) return;
      await drafts.complete(scope, slot, command.envelope.commandId);
    } on DomainError catch (cause) {
      await drafts.recordFailure(
        scope,
        slot,
        cause,
        commandId: command.envelope.commandId,
      );
      if (_disposed) return;
      final saved = await drafts.load(scope, slot);
      if (_disposed) return;
      local = saved;
      rethrow;
    }
    if (_disposed) return;
    selected = confirmed;
    form = null;
    local = null;
    message = 'Employee action confirmed.';
    try {
      await _refresh();
      if (_disposed) return;
      if (canReadHistory) {
        final result = await repository.history(
          scope,
          confirmed['id'] as String,
        );
        if (_disposed) return;
        events = [
          for (final raw in result['items'] as List)
            Map<String, Object?>.from(raw as Map),
        ];
      }
    } catch (cause) {
      if (_disposed) return;
      if (_denied(cause)) {
        accessDenied = true;
        _clearVisible();
        error = (cause as DomainError).message;
      } else {
        error = 'Action confirmed. Refresh the employee directory when ready.';
      }
    }
  });
}

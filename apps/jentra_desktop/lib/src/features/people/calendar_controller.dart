import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_platform/jentra_people_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';

final calendarRepositoryProvider = Provider<WorkCalendarRepository?>(
  (ref) => null,
);
final calendarControllerProvider = Provider.autoDispose<CalendarController?>((
  ref,
) {
  final scope = ref.watch(activeTenantContextProvider);
  final repository = ref.watch(calendarRepositoryProvider);
  final caps = ref.watch(businessCapabilitiesProvider);
  if (scope == null ||
      !scope.hasOperationalScope ||
      repository == null ||
      caps.isLoading ||
      caps.hasError ||
      !{
        'people.view',
        'people.calendars.view',
      }.every((p) => caps.value?.contains(p) ?? false)) {
    return null;
  }
  final controller = CalendarController(
    scope: scope,
    repository: repository,
    drafts: CalendarDraftStore(ref.watch(encryptedDraftRepositoryProvider)),
    permissions: caps.value!,
    online:
        ref.read(connectivityStateProvider).value == ConnectivityState.online,
  );
  ref.listen(
    connectivityStateProvider,
    (_, value) => controller.setOnline(value.value == ConnectivityState.online),
  );
  ref.onDispose(controller.dispose);
  unawaited(controller.initialize());
  return controller;
});

final class CalendarController extends ChangeNotifier {
  CalendarController({
    required this.scope,
    required this.repository,
    required this.drafts,
    required Set<String> permissions,
    required this.online,
  }) : permissions = Set.unmodifiable(permissions);
  static const slot = 'calendar-editor';
  static const _uuid = Uuid();
  final TenantContext scope;
  final WorkCalendarRepository repository;
  final CalendarDraftStore drafts;
  final Set<String> permissions;
  bool online, busy = false, accessDenied = false, _disposed = false;
  String asOfDate = '', search = '';
  String? error, message, cursor, versionCursor, historyCursor;
  List<CalendarDirectoryEntry> items = [];
  List<CalendarVersionSummary> versions = [];
  List<CalendarHistoryEvent> events = [];
  WorkCalendarIdentity? selected;
  CalendarVersionDetail? detail;
  Map<String, Object?>? form;
  CalendarDraft? local;
  bool get canManage => permissions.contains('people.calendars.manage');
  bool get locked =>
      busy ||
      accessDenied ||
      local?.pending != null ||
      local?.errorCode == 'VERSION_CONFLICT';
  bool get canStart => canManage && !locked && form == null;
  bool get conflict => local?.errorCode == 'VERSION_CONFLICT';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    items = [];
    versions = [];
    events = [];
    selected = null;
    detail = null;
    form = null;
    local = null;
    super.dispose();
  }

  void setOnline(bool value) {
    online = value;
    _notify();
  }

  void _deny() {
    accessDenied = true;
    items = [];
    versions = [];
    events = [];
    selected = null;
    detail = null;
    form = null;
    local = null;
    cursor = null;
    versionCursor = null;
    historyCursor = null;
  }

  bool _isDenied(Object cause) =>
      cause is DomainError &&
      {
        'PERMISSION_DENIED',
        'FEATURE_NOT_ENTITLED',
        'AUTHENTICATION_REQUIRED',
      }.contains(cause.code);
  Future<void> _run(Future<void> Function() work) async {
    if (_disposed || busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      await work();
    } catch (cause) {
      if (_isDenied(cause)) _deny();
      error = cause is DomainError
          ? cause.message
          : cause is FormatException
          ? cause.message
          : 'Unable to load calendars. Saved encrypted work is retained.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> _restore() async {
    if (!canManage || _disposed) return;
    local = await drafts.load(scope, slot);
    if (!_disposed) form = local?.form;
  }

  Future<void> initialize() => _run(() async {
    if (online) await _refresh();
    if (!accessDenied) await _restore();
  });
  Future<void> _refresh({bool more = false}) async {
    if (!online) {
      throw const DomainError(
        code: 'OFFLINE',
        message: 'Connect to load published calendars.',
      );
    }
    final page = await repository.directory(
      scope,
      asOfDate: asOfDate.isEmpty ? null : asOfDate,
      search: search,
      after: more ? cursor : null,
    );
    if (_disposed) return;
    asOfDate = page.asOf.value;
    items = [
      ...(more ? items : <CalendarDirectoryEntry>[]),
      ...page.page.items,
    ];
    cursor = page.page.nextCursor;
    accessDenied = false;
  }

  Future<void> refresh({bool more = false}) => _run(() async {
    final denied = accessDenied;
    await _refresh(more: more);
    if (denied) await _restore();
  });
  Future<void> filter({required String date, required String query}) =>
      _run(() async {
        CivilDate.parse(date);
        if (query.trim().length > 160) {
          throw const FormatException('Search is limited to 160 characters.');
        }
        asOfDate = date;
        search = query.trim();
        selected = null;
        detail = null;
        versions = [];
        events = [];
        versionCursor = null;
        historyCursor = null;
        await _refresh();
      });
  Future<void> open(CalendarDirectoryEntry entry) => _run(() async {
    if (!online) return;
    selected = null;
    detail = null;
    versions = [];
    events = [];
    versionCursor = null;
    historyCursor = null;
    final page = await repository.versions(scope, entry.calendar.id);
    final history = await repository.history(scope, entry.calendar.id);
    final versionId = entry.coverage?.id ?? page.items.firstOrNull?.coverage.id;
    final loaded = versionId == null
        ? null
        : await repository.detail(scope, entry.calendar.id, versionId);
    if (_disposed) return;
    selected = loaded?.calendar ?? entry.calendar;
    detail = loaded?.version;
    versions = page.items;
    versionCursor = page.nextCursor;
    events = history.items;
    historyCursor = history.nextCursor;
  });
  Future<void> selectVersion(String id) => _run(() async {
    if (!online || selected == null) return;
    final result = await repository.detail(scope, selected!.id, id);
    if (!_disposed) {
      selected = result.calendar;
      detail = result.version;
    }
  });
  Future<void> moreVersions() => _run(() async {
    if (!online || selected == null || versionCursor == null) return;
    final page = await repository.versions(
      scope,
      selected!.id,
      after: versionCursor,
    );
    if (!_disposed) {
      versions = [...versions, ...page.items];
      versionCursor = page.nextCursor;
    }
  });
  Future<void> moreHistory() => _run(() async {
    if (!online || selected == null || historyCursor == null) return;
    final page = await repository.history(
      scope,
      selected!.id,
      after: historyCursor,
    );
    if (!_disposed) {
      events = [...events, ...page.items];
      historyCursor = page.nextCursor;
    }
  });

  static String clock(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
  static int _minute(Object? value) {
    if (value is! String ||
        !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value)) {
      throw const FormatException(
        'Use a local time in HH:MM, from 00:00 to 23:59.',
      );
    }
    return int.parse(value.substring(0, 2)) * 60 +
        int.parse(value.substring(3));
  }

  Map<String, Object?> _interval(WeeklyWorkInterval value) => {
    'day_of_week': value.dayOfWeek,
    'start_time': clock(value.startMinute),
    'end_time': clock(value.endMinute),
    'end_day_offset': value.endDayOffset,
  };
  void beginCreate() {
    if (!canStart) return;
    final start = asOfDate.isEmpty ? '' : asOfDate;
    form = {
      'action': 'create',
      'version': 0,
      'id': _uuid.v4(),
      'code': '',
      'name': '',
      'version_id': _uuid.v4(),
      'start_date': start,
      'end_date_exclusive': '',
      'timezone': '',
      'weekly_intervals': <Object?>[
        for (var day = 1; day <= 5; day++)
          {
            'day_of_week': day,
            'start_time': '09:00',
            'end_time': '17:00',
            'end_day_offset': 0,
          },
      ],
      'date_overrides': <Object?>[],
      'reason': '',
    };
    message = null;
    _notify();
  }

  void beginAction(String action) {
    if (!canStart ||
        selected == null ||
        !{'rename', 'publish'}.contains(action)) {
      return;
    }
    if (action == 'rename') {
      form = {
        'action': action,
        'version': selected!.version,
        'id': selected!.id,
        'name': selected!.name,
        'reason': '',
      };
    } else {
      form = {
        'action': action,
        'version': selected!.version,
        'id': selected!.id,
        'version_id': _uuid.v4(),
        'start_date': '',
        'end_date_exclusive': '',
        'timezone': detail?.summary.coverage.timezone ?? '',
        'weekly_intervals': <Object?>[
          for (final value
              in detail?.pattern.weeklyIntervals ?? <WeeklyWorkInterval>[])
            _interval(value),
        ],
        'date_overrides': <Object?>[],
        'reason': '',
      };
    }
    message = null;
    _notify();
  }

  void edit(String key, Object? value) {
    if (form == null || locked || !canManage) return;
    form = {...form!, key: value};
    _notify();
  }

  void editRow(String key, int index, String field, Object? value) {
    if (form == null || locked) return;
    final rows = (form![key] as List)
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList();
    rows[index] = {...rows[index], field: value};
    edit(key, rows);
  }

  void addRow(String key) {
    if (form == null || locked) return;
    final rows = List<Object?>.from(form![key] as List);
    if (rows.length >= (key == 'weekly_intervals' ? 56 : 366)) return;
    rows.add(
      key == 'weekly_intervals'
          ? {
              'day_of_week': 1,
              'start_time': '09:00',
              'end_time': '17:00',
              'end_day_offset': 0,
            }
          : {'date': '', 'is_working_day': false, 'reason': ''},
    );
    edit(key, rows);
  }

  void removeRow(String key, int index) {
    if (form == null || locked) return;
    final rows = List<Object?>.from(form![key] as List)..removeAt(index);
    edit(key, rows);
  }

  Map<String, Object?> _payload() {
    final payload = {
      for (final entry in form!.entries)
        if (!{'action', 'version'}.contains(entry.key)) entry.key: entry.value,
    };
    if (payload['weekly_intervals'] != null) {
      payload['weekly_intervals'] = [
        for (final raw in payload['weekly_intervals'] as List)
          {
            'day_of_week': (raw as Map)['day_of_week'],
            'start_minute': _minute(raw['start_time']),
            'end_minute': _minute(raw['end_time']),
            'end_day_offset': raw['end_day_offset'],
          },
      ];
    }
    return payload;
  }

  Future<void> saveLocal() => _run(() async {
    if (!canManage ||
        accessDenied ||
        form == null ||
        local?.pending != null ||
        conflict) {
      return;
    }
    await drafts.save(scope, slot, form!, version: form!['version'] as int);
    await _restore();
    message = 'Encrypted calendar draft saved.';
  });
  Future<void> discard() => _run(() async {
    if (accessDenied || !canManage) return;
    await drafts.discard(scope, slot);
    form = null;
    local = null;
    message = null;
  });
  Future<bool> canLeave() async {
    if (accessDenied || local?.pending != null || conflict) return true;
    if (busy) return false;
    if (form != null && canManage) {
      try {
        await drafts.save(scope, slot, form!, version: form!['version'] as int);
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  /// Explicit comparison is required before retaining edits against a newer aggregate.
  Future<void> compareConflict() => _run(() async {
    if (!online || !conflict || form == null || form!['action'] == 'create') {
      return;
    }
    final id = form!['id'] as String;
    final page = await repository.versions(scope, id);
    if (page.items.isEmpty) {
      throw const FormatException(
        'This calendar has no available version to compare.',
      );
    }
    final current = await repository.detail(
      scope,
      id,
      page.items.first.coverage.id,
    );
    if (_disposed) return;
    selected = current.calendar;
    detail = current.version;
    versions = page.items;
    versionCursor = page.nextCursor;
    message = 'Current calendar loaded for comparison. Replace the stale draft explicitly to retain your edits.';
  });
  Future<void> replaceConflict() => _run(() async {
    if (!canManage ||
        !conflict ||
        selected == null ||
        form == null ||
        selected!.id != form!['id']) {
      return;
    }
    if (selected!.version <= (form!['version'] as int)) {
      throw const FormatException('Compare a newer calendar version first.');
    }
    form = {...form!, 'version': selected!.version};
    await drafts.save(
      scope,
      slot,
      form!,
      version: selected!.version,
      resolveConflict: true,
    );
    await _restore();
    message = 'Draft retained against the compared calendar. Review the dates before confirming.';
  });
  Future<void> submit() => _run(() async {
    if (!online || accessDenied || !canManage) {
      throw const DomainError(
        code: 'OFFLINE',
        message: 'Connect with calendar management access before confirming.',
      );
    }
    final pending = local?.pending;
    if (pending == null && form == null) return;
    late CalendarPendingCommand command;
    if (pending != null) {
      command = pending;
    } else {
      if (conflict) {
        throw const DomainError(
          code: 'VERSION_CONFLICT',
          message: 'Compare and replace the stale draft first.',
        );
      }
      final action = form!['action'] as String;
      final payload = _payload();
      validateCalendarPayload(action, payload);
      await drafts.save(scope, slot, form!, version: form!['version'] as int);
      command = await drafts.prepare(
        scope,
        slot,
        action: action,
        payload: payload,
        version: form!['version'] as int,
      );
      await _restore();
    }
    late CalendarConfirmation confirmed;
    try {
      confirmed = await repository.execute(command.action, command.envelope);
    } catch (cause) {
      final failure = cause is DomainError
          ? cause
          : const DomainError(
              code: 'UNCERTAIN_RESULT',
              message:
                  'The result is uncertain. Retry the original saved request.',
              retryable: true,
            );
      await drafts.recordFailure(
        scope,
        slot,
        failure,
        commandId: command.envelope.commandId,
      );
      await _restore();
      throw failure;
    }
    // Preserve verified confirmation even when optional reads or local cleanup fail.
    if (_disposed) return;
    selected = confirmed.calendar;
    detail = null;
    versions = [];
    events = [];
    versionCursor = null;
    historyCursor = null;
    message = 'Calendar action confirmed.';
    try {
      await drafts.complete(scope, slot, command.envelope.commandId);
    } catch (_) {
      error = 'Action confirmed. Retry the stored request to finish local recovery.';
      return;
    }
    form = null;
    local = null;
    try {
      await _refresh();
      final page = await repository.versions(scope, confirmed.calendar.id);
      versions = page.items;
      versionCursor = page.nextCursor;
      if (confirmed.publishedVersionId != null) {
        detail = (await repository.detail(
          scope,
          confirmed.calendar.id,
          confirmed.publishedVersionId!,
        )).version;
      }
      final history = await repository.history(scope, confirmed.calendar.id);
      events = history.items;
      historyCursor = history.nextCursor;
    } catch (cause) {
      if (_isDenied(cause)) {
        _deny();
        error = (cause as DomainError).message;
      } else {
        error =
            'Action confirmed. Refresh published calendar details when ready.';
      }
    }
  });
}

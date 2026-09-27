import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_people.dart';

import '../../app_providers.dart';
import 'calendar_controller.dart';
import 'calendar_resolution_dialog.dart';

class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(businessCapabilitiesProvider);
    if (caps.isLoading) return const Center(child: CircularProgressIndicator());
    if (caps.hasError) {
      return Center(
        child: TextButton(
          onPressed: () => ref.invalidate(businessCapabilitiesProvider),
          child: const Text('Retry calendar access check'),
        ),
      );
    }
    final controller = ref.watch(calendarControllerProvider);
    if (controller == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Choose an entity and branch with calendar permission.'),
        ),
      );
    }
    return CalendarWorkspace(key: ValueKey(controller), controller: controller);
  }
}

class CalendarWorkspace extends StatefulWidget {
  const CalendarWorkspace({required this.controller, super.key});
  final CalendarController controller;
  @override
  State<CalendarWorkspace> createState() => _CalendarWorkspaceState();
}

class _CalendarWorkspaceState extends State<CalendarWorkspace> {
  late final search = TextEditingController(text: widget.controller.search);
  late final date = TextEditingController(text: widget.controller.asOfDate);
  bool dateSynced = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    _sync();
  }

  void _sync() {
    if (!dateSynced && widget.controller.asOfDate.isNotEmpty) {
      date.text = widget.controller.asOfDate;
      dateSynced = true;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    search.dispose();
    date.dispose();
    super.dispose();
  }

  Future<void> _edit([String? action]) async {
    final c = widget.controller;
    if (action == 'create') {
      c.beginCreate();
    } else if (action != null) {
      c.beginAction(action);
    }
    if (c.form == null || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CalendarEditor(controller: c),
    );
  }

  Widget _card(Widget child) => Card(
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );
  Widget _button(String text, VoidCallback? action) =>
      OutlinedButton(onPressed: action, child: Text(text));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      if (c.accessDenied) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 40),
                const SizedBox(height: 16),
                Text(
                  c.error ?? 'Calendar access changed.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                _button(
                  'Retry calendar access',
                  c.online && !c.busy ? () => c.refresh() : null,
                ),
              ],
            ),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            JentraSectionHeader(
              title: 'Work calendars',
              description:
                  'Published local working hours and dated exceptions for the selected entity.',
              trailing: JentraStatusBadge(
                label: c.online ? 'Connected' : 'Offline drafts',
                tone: c.online
                    ? JentraStatusTone.success
                    : JentraStatusTone.info,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 310,
                  child: TextField(
                    controller: search,
                    maxLength: 160,
                    decoration: const InputDecoration(
                      labelText: 'Search',
                      hintText: 'Code or name',
                      counterText: '',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (_) =>
                        c.filter(date: date.text, query: search.text),
                  ),
                ),
                SizedBox(
                  width: 250,
                  child: TextField(
                    controller: date,
                    decoration: const InputDecoration(
                      labelText: 'As of date',
                      hintText: 'YYYY-MM-DD',
                    ),
                    onSubmitted: (_) =>
                        c.filter(date: date.text, query: search.text),
                  ),
                ),
                _button(
                  'Apply filters',
                  c.busy || !c.online
                      ? null
                      : () => c.filter(date: date.text, query: search.text),
                ),
                _button(
                  'Refresh',
                  c.busy || !c.online ? null : () => c.refresh(),
                ),
                if (c.canManage)
                  FilledButton.icon(
                    onPressed: c.canStart ? () => _edit('create') : null,
                    icon: const Icon(Icons.add),
                    label: const Text('New calendar'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Entity calendars • Rules shown for ${c.asOfDate.isEmpty ? 'the current entity date' : c.asOfDate}',
            ),
            if (c.busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  c.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (c.message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(c.message!),
              ),
            if (c.local?.pending != null)
              _card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Calendar request awaiting confirmation',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Its saved dates and working hours are locked until the original request is confirmed.',
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: c.online && !c.busy ? c.submit : null,
                      child: const Text('Retry original request'),
                    ),
                  ],
                ),
              ),
            if (c.form != null && c.local?.pending == null)
              _card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.conflict
                          ? 'Saved draft needs comparison'
                          : 'Calendar draft available',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (c.conflict)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'The calendar changed after this draft was saved. Review the current calendar before keeping your edits.',
                        ),
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _button(
                          'Resume draft',
                          c.busy || c.conflict ? null : () => _edit(),
                        ),
                        if (c.conflict)
                          _button(
                            'Compare current calendar',
                            c.busy || !c.online ? null : c.compareConflict,
                          ),
                        if (c.conflict && c.selected != null)
                          _button(
                            'Keep edits after comparison',
                            c.busy ? null : c.replaceConflict,
                          ),
                        _button('Discard draft', c.busy ? null : c.discard),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            if (c.items.isEmpty && !c.busy && c.error == null)
              _card(
                Text(
                  c.online
                      ? 'No calendars match this entity and search.'
                      : 'Connect to browse published calendars. Your encrypted draft can be edited offline.',
                ),
              ),
            LayoutBuilder(
              builder: (context, constraints) {
                final register = _register(context, c);
                final detail = c.selected == null
                    ? <Widget>[
                        _card(
                          const Text(
                            'Open a calendar to browse published working hours, versions and history.',
                          ),
                        ),
                      ]
                    : _details(context, c);
                if (constraints.maxWidth >= 1200 &&
                    MediaQuery.textScalerOf(context).scale(14) <= 21) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: register,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        flex: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: c.selected == null
                              ? detail
                              : detail.skip(1).toList(),
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [...register, ...detail],
                );
              },
            ),
          ],
        ),
      );
    },
  );

  List<Widget> _register(BuildContext context, CalendarController c) => [
    for (final entry in c.items)
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${entry.calendar.code} · ${entry.calendar.name}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              entry.coverage == null
                  ? 'No published rules cover ${c.asOfDate}.'
                  : '${entry.coverage!.timezone} · ${entry.coverage!.start} to ${entry.coverage!.endExclusive} (end excluded)',
            ),
            const SizedBox(height: 12),
            _button(
              c.selected?.id == entry.calendar.id
                  ? 'Reload calendar'
                  : 'Open calendar',
              c.busy || !c.online ? null : () => c.open(entry),
            ),
          ],
        ),
      ),
    if (c.cursor != null)
      _button(
        'Load more calendars',
        c.busy || !c.online ? null : () => c.refresh(more: true),
      ),
  ];

  List<Widget> _details(BuildContext context, CalendarController c) {
    final version = c.detail;
    return [
      const SizedBox(height: 20),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c.selected!.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '${c.selected!.code} · Calendar revision ${c.selected!.version}',
            ),
            const SizedBox(height: 12),
            if (c.canManage)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _button(
                    'Publish new version',
                    c.canStart ? () => _edit('publish') : null,
                  ),
                  _button(
                    'Rename calendar',
                    c.canStart ? () => _edit('rename') : null,
                  ),
                ],
              ),
            if (version != null) ...[
              const SizedBox(height: 18),
              Text(
                '${version.summary.coverage.start} to ${version.summary.coverage.endExclusive} (end excluded)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('Local times · ${version.summary.coverage.timezone}'),
              if (c.repository case final CalendarInstantResolver resolver)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _button(
                    'Resolve local time',
                    c.busy || !c.online
                        ? null
                        : () => showDialog<void>(
                            context: context,
                            builder: (_) => Consumer(
                              builder: (context, ref, _) {
                                final current = ref.watch(
                                  calendarControllerProvider,
                                );
                                return CalendarResolutionDialog(
                                  resolver: resolver,
                                  scope: c.scope,
                                  version: version,
                                  isCurrent: () =>
                                      identical(current, c) &&
                                      !c.accessDenied &&
                                      c.detail?.summary.coverage.id ==
                                          version.summary.coverage.id,
                                );
                              },
                            ),
                          ),
                  ),
                ),
              if (c.asOfDate.isNotEmpty &&
                  !version.summary.coverage.contains(
                    CivilDate.parse(c.asOfDate),
                  ))
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'This published version is outside the selected date.',
                  ),
                ),
              const SizedBox(height: 14),
              const Text(
                'Weekly working hours',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              if (version.pattern.weeklyIntervals.isEmpty)
                const Text('No regular working hours.'),
              for (final interval in version.pattern.weeklyIntervals)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${_days[interval.dayOfWeek - 1]} · ${CalendarController.clock(interval.startMinute)}–${CalendarController.clock(interval.endMinute)}${interval.endDayOffset == 1 ? ' next day' : ''}',
                  ),
                ),
              const SizedBox(height: 18),
              const Text(
                'Dated exceptions',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              if (version.pattern.overrides.isEmpty)
                const Text('No dated exceptions.'),
              for (final override in version.pattern.overrides)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${override.date} · ${override.isWorkingDay ? 'Regular hours' : 'Nonworking day'} · ${override.reason}',
                  ),
                ),
              const SizedBox(height: 18),
              Text(
                'Published ${version.summary.publishedAt.toIso8601String()} by ${version.summary.publishedBy}',
              ),
            ],
          ],
        ),
      ),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Published versions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final item in c.versions)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _button(
                  '${item.coverage.start} → ${item.coverage.endExclusive} · ${item.coverage.timezone}',
                  c.busy || !c.online
                      ? null
                      : () => c.selectVersion(item.coverage.id),
                ),
              ),
            if (c.versionCursor != null)
              _button('Load more versions', c.busy ? null : c.moreVersions),
          ],
        ),
      ),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Calendar history',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (c.events.isEmpty) const Text('No history available.'),
            for (final event in c.events)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${event.action == 'rename' ? 'Renamed' : 'Version published'} · Revision ${event.after.calendar.version}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(event.reason),
                    if (event.effectiveDate != null)
                      Text('Effective ${event.effectiveDate}'),
                    Text(
                      '${event.recordedAt.toIso8601String()} · ${event.actorId}',
                    ),
                  ],
                ),
              ),
            if (c.historyCursor != null)
              _button('Load more history', c.busy ? null : c.moreHistory),
          ],
        ),
      ),
    ];
  }
}

const _days = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

class CalendarEditor extends StatefulWidget {
  const CalendarEditor({required this.controller, super.key});
  final CalendarController controller;
  @override
  State<CalendarEditor> createState() => _CalendarEditorState();
}

class _CalendarEditorState extends State<CalendarEditor> {
  final fields = <String, TextEditingController>{};
  final retiredFields = <TextEditingController>[];
  final scroll = ScrollController();
  @override
  void dispose() {
    for (final value in fields.values) {
      value.dispose();
    }
    for (final value in retiredFields) {
      value.dispose();
    }
    scroll.dispose();
    super.dispose();
  }

  TextEditingController _field(String key, Object? value) => fields.putIfAbsent(
    key,
    () => TextEditingController(text: value?.toString() ?? ''),
  );
  Widget _text(
    String key,
    String label, {
    String? hint,
    int? max,
    double width = 320,
  }) {
    final c = widget.controller;
    return SizedBox(
      width: width,
      child: TextField(
        controller: _field(key, c.form![key]),
        enabled: !c.locked,
        maxLength: max,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          counterText: '',
        ),
        onChanged: (value) => c.edit(key, value),
      ),
    );
  }

  Widget _rowText(
    String list,
    int index,
    String key,
    String label, {
    double width = 190,
  }) {
    final c = widget.controller;
    final row = (c.form![list] as List)[index] as Map;
    return SizedBox(
      width: width,
      child: TextField(
        controller: _field('$list:$index:$key', row[key]),
        enabled: !c.locked,
        decoration: InputDecoration(labelText: label),
        onChanged: (value) => c.editRow(list, index, key, value),
      ),
    );
  }

  void _remove(String list, int index) {
    // Recreate the shifted row controls rather than displaying another row's text.
    final keys = fields.keys.where((key) => key.startsWith('$list:')).toList();
    for (final key in keys) {
      retiredFields.add(fields.remove(key)!);
    }
    widget.controller.removeRow(list, index);
  }

  Future<void> _submit() async {
    await widget.controller.submit();
    if (!mounted) return;
    if (widget.controller.form == null ||
        widget.controller.accessDenied ||
        widget.controller.local?.pending != null) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      if (c.accessDenied || c.form == null) {
        return AlertDialog(
          title: const Text('Calendar access changed'),
          content: Text(c.error ?? 'Reopen the calendar workspace.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      }
      final action = c.form!['action'] as String;
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(switch (action) {
                  'create' => 'New work calendar',
                  'publish' => 'Publish calendar version',
                  _ => 'Rename calendar',
                }, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                Flexible(
                  child: Scrollbar(
                    controller: scroll,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: scroll,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            action == 'rename'
                                ? 'The calendar code and published working hours remain fixed.'
                                : 'Published rules are immutable. The end date is the first day these rules no longer apply.',
                          ),
                          if (action == 'publish')
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'Choose future dates that do not overlap an existing published version.',
                              ),
                            ),
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final width = constraints.maxWidth < 650
                                  ? constraints.maxWidth
                                  : (constraints.maxWidth - 16) / 2;
                              return Wrap(
                                spacing: 16,
                                runSpacing: 16,
                                children: [
                                  if (action == 'create')
                                    _text(
                                      'code',
                                      'Calendar code',
                                      max: 32,
                                      width: width,
                                    ),
                                  if (action != 'publish')
                                    _text(
                                      'name',
                                      'Calendar name',
                                      max: 160,
                                      width: width,
                                    ),
                                  if (action != 'rename') ...[
                                    _text(
                                      'start_date',
                                      'Start date',
                                      hint: 'YYYY-MM-DD',
                                      width: width,
                                    ),
                                    _text(
                                      'end_date_exclusive',
                                      'End date (excluded)',
                                      hint: 'YYYY-MM-DD',
                                      width: width,
                                    ),
                                    _text(
                                      'timezone',
                                      'IANA time zone',
                                      hint: 'Asia/Colombo',
                                      max: 100,
                                      width: width,
                                    ),
                                  ],
                                  _text(
                                    'reason',
                                    'Reason',
                                    max: 1000,
                                    width: width,
                                  ),
                                ],
                              );
                            },
                          ),
                          if (action != 'rename') ...[
                            const SizedBox(height: 24),
                            const Text(
                              'Weekly local working hours',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Use HH:MM. Choose “Next day” for an overnight interval.',
                            ),
                            for (
                              var index = 0;
                              index <
                                  (c.form!['weekly_intervals'] as List).length;
                              index++
                            )
                              _weeklyRow(index),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed:
                                  c.locked ||
                                      (c.form!['weekly_intervals'] as List)
                                              .length >=
                                          56
                                  ? null
                                  : () => c.addRow('weekly_intervals'),
                              child: const Text('Add working interval'),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Dated exceptions',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'A nonworking day closes the entire local date. A working exception uses configured regular hours.',
                            ),
                            for (
                              var index = 0;
                              index <
                                  (c.form!['date_overrides'] as List).length;
                              index++
                            )
                              _overrideRow(index),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed:
                                  c.locked ||
                                      (c.form!['date_overrides'] as List)
                                              .length >=
                                          366
                                  ? null
                                  : () => c.addRow('date_overrides'),
                              child: const Text('Add dated exception'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (c.error != null) ...[
                  Text(
                    c.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    TextButton(
                      onPressed: c.busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                    OutlinedButton(
                      onPressed: c.locked ? null : c.saveLocal,
                      child: const Text('Save encrypted draft'),
                    ),
                    FilledButton(
                      onPressed: c.locked || !c.online ? null : _submit,
                      child: Text(
                        c.busy
                            ? 'Saving…'
                            : action == 'rename'
                            ? 'Confirm rename'
                            : 'Publish rules',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _weeklyRow(int index) {
    final c = widget.controller;
    final row = (c.form!['weekly_intervals'] as List)[index] as Map;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 235,
            child: DropdownButtonFormField<int>(
              key: ValueKey('weekday:$index:${row['day_of_week']}'),
              initialValue: row['day_of_week'] as int,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Weekday'),
              items: [
                for (var day = 1; day <= 7; day++)
                  DropdownMenuItem(value: day, child: Text(_days[day - 1])),
              ],
              onChanged: c.locked
                  ? null
                  : (value) {
                      if (value != null) {
                        c.editRow(
                          'weekly_intervals',
                          index,
                          'day_of_week',
                          value,
                        );
                      }
                    },
            ),
          ),
          _rowText('weekly_intervals', index, 'start_time', 'Start time'),
          _rowText('weekly_intervals', index, 'end_time', 'End time'),
          SizedBox(
            width: 235,
            child: DropdownButtonFormField<int>(
              key: ValueKey('offset:$index:${row['end_day_offset']}'),
              initialValue: row['end_day_offset'] as int,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Ends on'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Same day')),
                DropdownMenuItem(value: 1, child: Text('Next day')),
              ],
              onChanged: c.locked
                  ? null
                  : (value) {
                      if (value != null) {
                        c.editRow(
                          'weekly_intervals',
                          index,
                          'end_day_offset',
                          value,
                        );
                      }
                    },
            ),
          ),
          IconButton(
            tooltip: 'Remove working interval ${index + 1}',
            onPressed: c.locked
                ? null
                : () => _remove('weekly_intervals', index),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  Widget _overrideRow(int index) {
    final c = widget.controller;
    final row = (c.form!['date_overrides'] as List)[index] as Map;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _rowText(
            'date_overrides',
            index,
            'date',
            'Date (YYYY-MM-DD)',
            width: 280,
          ),
          SizedBox(
            width: 280,
            child: DropdownButtonFormField<bool>(
              key: ValueKey('override:$index:${row['is_working_day']}'),
              initialValue: row['is_working_day'] as bool,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Day type'),
              items: const [
                DropdownMenuItem(value: false, child: Text('Nonworking')),
                DropdownMenuItem(value: true, child: Text('Regular hours')),
              ],
              onChanged: c.locked
                  ? null
                  : (value) {
                      if (value != null) {
                        c.editRow(
                          'date_overrides',
                          index,
                          'is_working_day',
                          value,
                        );
                      }
                    },
            ),
          ),
          _rowText(
            'date_overrides',
            index,
            'reason',
            'Exception reason',
            width: 300,
          ),
          IconButton(
            tooltip: 'Remove exception ${index + 1}',
            onPressed: c.locked ? null : () => _remove('date_overrides', index),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

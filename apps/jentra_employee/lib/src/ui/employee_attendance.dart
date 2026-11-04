import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/employee_gateway.dart';
import '../data/employee_self_service.dart';
import '../data/employee_workplace_time.dart';
import '../employee_self_service_controller.dart';
import '../l10n/employee_strings.dart';
import 'employee_components.dart';
import 'employee_service_common.dart';
import 'employee_surfaces.dart';

class EmployeeAttendanceBody extends StatefulWidget {
  const EmployeeAttendanceBody({required this.controller, super.key});
  final EmployeeSelfServiceController controller;
  @override
  State<EmployeeAttendanceBody> createState() => _EmployeeAttendanceBodyState();
}

class _EmployeeAttendanceBodyState extends State<EmployeeAttendanceBody> {
  EmployeeSelfServiceController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _reload();
        c.restorePending();
      }
    });
  }

  Future<void> _reload() async {
    await c.load(EmployeeService.attendance);
    await c.load(EmployeeService.attendanceRequests);
  }

  Future<void> _request([EmployeeServiceRecord? entry]) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            EmployeeAttendanceRequestScreen(controller: c, entry: entry),
      ),
    );
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final s = EmployeeStrings.of(context);
      return EmployeePageBody(
        onRefresh: _reload,
        children: [
          EmployeeHeading(s('attendanceTitle'), large: true),
          Text(s('attendanceCopy')),
          EmployeeServiceFeedback(controller: c),
          FilledButton.icon(
            onPressed: c.actionBusy || c.pending != null
                ? null
                : () => _request(),
            icon: const Icon(Icons.add_task_outlined),
            label: Text(s('attendanceCapture')),
          ),
          EmployeeServiceListState(
            controller: c,
            service: EmployeeService.attendance,
          ),
          for (final row
              in c.pages[EmployeeService.attendance]?.items ??
                  <EmployeeServiceRecord>[])
            EmployeeSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${serviceDate(selfMap(row.values['revision'])['start_local'], s, time: true)} – ${serviceDate(selfMap(row.values['revision'])['end_local'], s, time: true)}',
                  ),
                  const SizedBox(height: 8),
                  EmployeeStatus(s(row.text('status', max: 80))),
                  TextButton(
                    onPressed: c.actionBusy || c.pending != null
                        ? null
                        : () => _request(row),
                    child: Text(s('attendanceCorrection')),
                  ),
                ],
              ),
            ),
          EmployeeServiceMore(
            controller: c,
            service: EmployeeService.attendance,
          ),
          EmployeeHeading(s('attendanceRequests')),
          EmployeeServiceListState(
            controller: c,
            service: EmployeeService.attendanceRequests,
          ),
          for (final row
              in c.pages[EmployeeService.attendanceRequests]?.items ??
                  <EmployeeServiceRecord>[])
            EmployeeSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EmployeeStatus(
                    s(row.text('status', max: 80)),
                    warning: row.values['status'] == 'pending_evidence',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    serviceDate(
                      row.values['observed_at'],
                      s,
                      time: true,
                      zone: c.currentIdentity()?.workspace.timeZone,
                    ),
                  ),
                  Text(row.text('reason', max: 1000)),
                  if (row.values['resolution'] != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      s('requestDecision'),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Text(
                      selfText(
                        selfMap(row.values['resolution'])['reason'],
                        max: 1000,
                      ),
                    ),
                    Text(
                      serviceDate(
                        selfMap(row.values['resolution'])['recorded_at'],
                        s,
                        time: true,
                        zone: c.currentIdentity()?.workspace.timeZone,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          EmployeeServiceMore(
            controller: c,
            service: EmployeeService.attendanceRequests,
          ),
        ],
      );
    },
  );
}

class EmployeeAttendanceRequestScreen extends StatefulWidget {
  const EmployeeAttendanceRequestScreen({
    required this.controller,
    this.entry,
    super.key,
  });
  final EmployeeSelfServiceController controller;
  final EmployeeServiceRecord? entry;
  @override
  State<EmployeeAttendanceRequestScreen> createState() =>
      _EmployeeAttendanceRequestScreenState();
}

class _EmployeeAttendanceRequestScreenState
    extends State<EmployeeAttendanceRequestScreen> {
  final _reason = TextEditingController();
  final _form = GlobalKey<FormState>();
  DateTime _observed = DateTime.now();
  EmployeeFailure? _error;
  EmployeeSelfServiceController get c => widget.controller;
  DateTime get _workplaceNow => employeeWorkplaceTime(
    DateTime.now(),
    c.currentIdentity()?.workspace.timeZone ?? 'UTC',
  );
  @override
  void initState() {
    super.initState();
    final now = _workplaceNow;
    _observed = DateTime(now.year, now.month, now.day, now.hour, now.minute);
  }

  @override
  void dispose() {
    _reason.clear();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    try {
      final identity = c.currentIdentity();
      if (identity == null) return;
      final observed = employeeWorkplaceInstant(
        _observed,
        identity.workspace.timeZone,
      );
      final sent = await c.submit('employee_self_attendance_request', {
        'p_request_id': const Uuid().v4(),
        'p_payload': {
          'action': widget.entry == null ? 'capture' : 'correction',
          'observed_at': observed.utc.toIso8601String(),
          'reason': _reason.text.trim(),
          if (widget.entry != null) ...{
            'entry_id': widget.entry!.id,
            'expected_version': widget.entry!.version,
          },
        },
      });
      if (mounted && sent) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) setState(() => _error = employeeFailure(error));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final s = EmployeeStrings.of(context);
      return Scaffold(
        appBar: AppBar(
          title: Text(
            s(
              widget.entry == null
                  ? 'attendanceCapture'
                  : 'attendanceCorrection',
            ),
          ),
        ),
        body: EmployeePageBody(
          children: [
            Text(s('attendanceCopy')),
            Text(
              '${s('requestZone')}: ${c.currentIdentity()?.workspace.timeZone ?? ''}',
            ),
            EmployeeServiceFeedback(controller: c),
            if (_error != null)
              EmployeeMessage(
                title: employeeServiceFailure(_error!, s),
                error: true,
              ),
            Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: c.actionBusy
                        ? null
                        : () async {
                            final value = await pickEmployeeWallTime(
                              context,
                              _observed,
                              firstDate: _workplaceNow.subtract(
                                const Duration(days: 31),
                              ),
                              lastDate: _workplaceNow,
                            );
                            if (mounted && value != null) {
                              setState(() => _observed = value);
                            }
                          },
                    icon: const Icon(Icons.schedule),
                    label: Text(
                      '${s('observedAt')}: ${serviceDate(_observed.toIso8601String(), s, time: true)}',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _reason,
                    enabled: !c.actionBusy,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 1000,
                    decoration: InputDecoration(labelText: s('requestReason')),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? s('requestInvalid')
                        : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: c.actionBusy || c.pending != null
                        ? null
                        : _submit,
                    child: Text(s('requestSend')),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

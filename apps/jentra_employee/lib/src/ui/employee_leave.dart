import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/employee_gateway.dart';
import '../data/employee_self_service.dart';
import '../data/employee_workplace_time.dart';
import '../employee_controller.dart';
import '../employee_self_service_controller.dart';
import '../l10n/employee_strings.dart';
import 'employee_components.dart';
import 'employee_service_common.dart';
import 'employee_surfaces.dart';

class EmployeeLeaveBody extends StatefulWidget {
  const EmployeeLeaveBody({
    required this.employee,
    required this.onDraft,
    super.key,
  });
  final EmployeeController employee;
  final VoidCallback onDraft;
  @override
  State<EmployeeLeaveBody> createState() => _EmployeeLeaveBodyState();
}

class _EmployeeLeaveBodyState extends State<EmployeeLeaveBody> {
  EmployeeSelfServiceController get c => widget.employee.selfService;
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
    await c.load(EmployeeService.leaveRequests);
    await c.load(EmployeeService.leavePolicies);
  }

  Future<void> _request() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EmployeeLeaveRequestScreen(
          controller: c,
          draft: widget.employee.leaveDraft,
        ),
      ),
    );
    if (mounted) await _reload();
  }

  Future<void> _intent(EmployeeServiceRecord row) async {
    final s = EmployeeStrings.of(context);
    final reason = TextEditingController();
    final cancel = row.values['status'] == 'approved';
    final answer = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s(cancel ? 'leaveCancelRequest' : 'leaveWithdraw')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (cancel) Text(s('leaveCancelCopy')),
              TextField(
                controller: reason,
                maxLength: 1000,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(labelText: s('requestReason')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s('cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (reason.text.trim().isNotEmpty) {
                Navigator.pop(context, reason.text.trim());
              }
            },
            child: Text(s('requestSend')),
          ),
        ],
      ),
    );
    reason.clear();
    reason.dispose();
    if (!mounted || answer == null) return;
    await c.submit('employee_self_leave_intent', {
      'p_request_id': row.id,
      'p_action': cancel ? 'cancel_request' : 'withdraw',
      'p_expected_version': row.version,
      'p_reason': answer,
    });
    if (mounted) await c.load(EmployeeService.leaveRequests);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final s = EmployeeStrings.of(context);
      final policies =
          c.pages[EmployeeService.leavePolicies]?.items ??
          <EmployeeServiceRecord>[];
      return EmployeePageBody(
        onRefresh: _reload,
        children: [
          EmployeeHeading(s('leaveHistory'), large: true),
          Text(s('leaveApprovalCopy')),
          EmployeeServiceFeedback(controller: c),
          FilledButton.icon(
            key: const Key('employee-submit-leave'),
            onPressed: c.actionBusy || c.pending != null || policies.isEmpty
                ? null
                : _request,
            icon: const Icon(Icons.event_available_outlined),
            label: Text(s('leaveSubmit')),
          ),
          EmployeeServiceListState(
            controller: c,
            service: EmployeeService.leavePolicies,
          ),
          EmployeeServiceMore(
            controller: c,
            service: EmployeeService.leavePolicies,
          ),
          EmployeeServiceListState(
            controller: c,
            service: EmployeeService.leaveRequests,
          ),
          for (final row
              in c.pages[EmployeeService.leaveRequests]?.items ??
                  <EmployeeServiceRecord>[])
            EmployeeSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EmployeeStatus(s(row.text('status', max: 80))),
                  const SizedBox(height: 12),
                  Text(
                    '${serviceDate(row.values['start_local'], s, time: true)} – ${serviceDate(row.values['end_local'], s, time: true)}',
                  ),
                  Text(
                    '${(row.integer('charge_seconds') / 3600).toStringAsFixed(2)} ${s('hoursUnit')}',
                  ),
                  if (row.optionalText('reason', max: 1000) != null)
                    Text(row.text('reason', max: 1000)),
                  if (row.values['cancellation_request'] != null) ...[
                    const SizedBox(height: 12),
                    EmployeeStatus(
                      s(
                        selfText(
                          selfMap(row.values['cancellation_request'])['status'],
                          max: 80,
                        ),
                      ),
                    ),
                    if (selfMap(
                          row.values['cancellation_request'],
                        )['resolution'] !=
                        null)
                      Text(
                        selfText(
                          selfMap(
                            selfMap(
                              row.values['cancellation_request'],
                            )['resolution'],
                          )['reason'],
                          max: 1000,
                        ),
                      ),
                  ],
                  if ({
                    'created',
                    'submitted',
                    'approved',
                  }.contains(row.values['status']))
                    OutlinedButton(
                      onPressed:
                          c.actionBusy ||
                              c.pending != null ||
                              (row.values['cancellation_request'] is Map &&
                                  selfMap(
                                        row.values['cancellation_request'],
                                      )['status'] ==
                                      'cancellation_requested')
                          ? null
                          : () => _intent(row),
                      child: Text(
                        s(
                          row.values['status'] == 'approved'
                              ? 'leaveCancelRequest'
                              : 'leaveWithdraw',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          EmployeeServiceMore(
            controller: c,
            service: EmployeeService.leaveRequests,
          ),
          EmployeeActionTile(
            title: s(
              widget.employee.leaveDraft == null ? 'createDraft' : 'editDraft',
            ),
            subtitle: s('notSubmitted'),
            icon: Icons.edit_note_outlined,
            onTap: widget.onDraft,
          ),
          Text(s('draftExpires')),
        ],
      );
    },
  );
}

class EmployeeLeaveRequestScreen extends StatefulWidget {
  const EmployeeLeaveRequestScreen({
    required this.controller,
    this.draft,
    super.key,
  });
  final EmployeeSelfServiceController controller;
  final EmployeeLeaveDraft? draft;
  @override
  State<EmployeeLeaveRequestScreen> createState() =>
      _EmployeeLeaveRequestScreenState();
}

class _EmployeeLeaveRequestScreenState
    extends State<EmployeeLeaveRequestScreen> {
  final _form = GlobalKey<FormState>();
  late final _reason = TextEditingController(text: widget.draft?.reason ?? '');
  late DateTime _start = widget.draft?.startDate ?? _initialStart();
  late DateTime _end = widget.draft == null
      ? DateTime(_start.year, _start.month, _start.day, 17)
      : DateTime(
          widget.draft!.endDate.year,
          widget.draft!.endDate.month,
          widget.draft!.endDate.day + 1,
        );
  String? _policyId;
  EmployeeFailure? _error;
  bool _balanceBusy = false;
  EmployeeSelfServiceController get c => widget.controller;
  DateTime _initialStart() {
    final now = employeeWorkplaceTime(
      DateTime.now(),
      c.currentIdentity()?.workspace.timeZone ?? 'UTC',
    );
    return DateTime(now.year, now.month, now.day + 1, 9);
  }

  List<EmployeeServiceRecord> get policies =>
      c.pages[EmployeeService.leavePolicies]?.items ?? [];
  EmployeeServiceRecord? get policy {
    for (final value in policies) {
      if (value.id == _policyId) return value;
    }
    return null;
  }

  String get _asOf =>
      '${_start.year.toString().padLeft(4, '0')}-${_start.month.toString().padLeft(2, '0')}-${_start.day.toString().padLeft(2, '0')}';
  @override
  void initState() {
    super.initState();
    _policyId = policies.firstOrNull?.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _balance();
    });
  }

  @override
  void dispose() {
    _reason.clear();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _balance() async {
    final id = _policyId;
    if (id == null) return;
    setState(() => _balanceBusy = true);
    await c.loadBalance(id, _asOf);
    if (mounted) setState(() => _balanceBusy = false);
  }

  Future<void> _date(bool start) async {
    final result = await pickEmployeeWallTime(context, start ? _start : _end);
    if (result == null || !mounted) return;
    setState(() {
      if (start) {
        _start = result;
      } else {
        _end = result;
      }
      _error = null;
    });
    await _balance();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() ||
        policy == null ||
        !_end.isAfter(_start) ||
        _end.difference(_start) > const Duration(days: 366)) {
      setState(
        () => _error = const EmployeeFailure(
          'VALIDATION_ERROR',
          'Check the date range.',
        ),
      );
      return;
    }
    try {
      final selected = policy!;
      final first = employeeWorkplaceInstant(
        _start,
        selected.text('timezone', max: 100),
      );
      final last = employeeWorkplaceInstant(
        _end,
        selected.text('timezone', max: 100),
      );
      // Obtain a current account version immediately before sealing the request.
      setState(() => _balanceBusy = true);
      final balance = await c.loadBalance(selected.id, _asOf);
      if (!mounted || balance == null) return;
      final sent = await c.submit('employee_self_leave_submit', {
        'p_request_id': const Uuid().v4(),
        'p_expected_balance_version': balance.version,
        'p_payload': {
          'policy_version_id': selected.text('policy_version_id', max: 36),
          'calendar_version_id': selected.text('calendar_version_id', max: 36),
          'start_local': first.local,
          'end_local': last.local,
          'start_offset_seconds': first.offsetSeconds,
          'end_offset_seconds': last.offsetSeconds,
          'reason': _reason.text.trim(),
        },
      });
      if (mounted && sent) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) setState(() => _error = employeeFailure(error));
    } finally {
      if (mounted) setState(() => _balanceBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final s = EmployeeStrings.of(context);
      final selected = policy;
      final balance = c.balances[_policyId];
      return Scaffold(
        appBar: AppBar(title: Text(s('leaveSubmit'))),
        body: EmployeePageBody(
          children: [
            Text(s('leaveApprovalCopy')),
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
                  DropdownButtonFormField<String>(
                    initialValue: _policyId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: s('leavePolicy')),
                    items: [
                      for (final value in policies)
                        DropdownMenuItem(
                          value: value.id,
                          child: Text(value.text('name', max: 160)),
                        ),
                    ],
                    onChanged: c.actionBusy || _balanceBusy
                        ? null
                        : (value) {
                            setState(() => _policyId = value);
                            _balance();
                          },
                    validator: (value) =>
                        value == null ? s('requestInvalid') : null,
                  ),
                  const SizedBox(height: 16),
                  if (selected != null)
                    Text(
                      '${s('requestZone')}: ${selected.text('timezone', max: 100)}',
                    ),
                  if (_balanceBusy) const LinearProgressIndicator(),
                  if (balance != null) ...[
                    Text(
                      '${s('leaveBalance')}: ${(balance.availableSeconds / 3600).toStringAsFixed(2)} ${s('hoursUnit')}',
                    ),
                    Text(
                      '${s('leaveReserved')}: ${(balance.reservedSeconds / 3600).toStringAsFixed(2)} ${s('hoursUnit')}',
                    ),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: c.actionBusy || _balanceBusy
                        ? null
                        : () => _date(true),
                    child: Text(
                      '${s('requestStart')}: ${serviceDate(_start.toIso8601String(), s, time: true)}',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: c.actionBusy || _balanceBusy
                        ? null
                        : () => _date(false),
                    child: Text(
                      '${s('requestEnd')}: ${serviceDate(_end.toIso8601String(), s, time: true)}',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _reason,
                    enabled: !c.actionBusy && !_balanceBusy,
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
                    onPressed:
                        c.actionBusy ||
                            _balanceBusy ||
                            c.pending != null ||
                            selected == null
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

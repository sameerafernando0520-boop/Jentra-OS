import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/employee_gateway.dart';
import '../employee_controller.dart';
import '../l10n/employee_strings.dart';
import 'employee_components.dart';

class EmployeeLeaveDraftScreen extends StatefulWidget {
  const EmployeeLeaveDraftScreen({
    required this.onSave,
    this.initialDraft,
    this.initialDate,
    this.controller,
    super.key,
  });
  final EmployeeLeaveDraft? initialDraft;
  final DateTime? initialDate;
  final EmployeeController? controller;
  final Future<bool> Function(EmployeeLeaveDraft draft) onSave;
  @override
  State<EmployeeLeaveDraftScreen> createState() =>
      _EmployeeLeaveDraftScreenState();
}

class _EmployeeLeaveDraftScreenState extends State<EmployeeLeaveDraftScreen> {
  final _form = GlobalKey<FormState>();
  late final _type = TextEditingController(
    text: widget.initialDraft?.leaveType ?? '',
  );
  late final _reason = TextEditingController(
    text: widget.initialDraft?.reason ?? '',
  );
  late DateTime _start = _calendar(
    widget.initialDraft?.startDate ?? widget.initialDate ?? DateTime.now(),
  );
  late DateTime _end = _calendar(
    widget.initialDraft?.endDate ?? widget.initialDate ?? DateTime.now(),
  );
  bool _dirty = false, _saving = false, _allowExit = false, _saved = false;
  String? _error;
  bool _expired = false;
  late final int? _routeVersion;
  @override
  void initState() {
    super.initState();
    _routeVersion = widget.controller?.privateRouteVersion;
    widget.controller?.addListener(_leaseChanged);
  }

  void _leaseChanged() {
    if (_expired || !mounted) return;
    final c = widget.controller;
    if (c != null &&
        (c.privateRouteVersion != _routeVersion ||
            c.phase != EmployeePhase.ready)) {
      _expired = true;
      _type.clear();
      _reason.clear();
      // The app's owner key destroys this route on the same rebuild. Until
      // disposal, callbacks are fail-closed and the text is already blank.
      setState(() {});
    }
  }

  DateTime _calendar(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  @override
  void dispose() {
    widget.controller?.removeListener(_leaseChanged);
    _type.clear();
    _type.dispose();
    _reason.clear();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _date({required bool start}) async {
    final result = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (result != null && mounted) {
      setState(() {
        if (start) {
          _start = result;
        } else {
          _end = result;
        }
        _dirty = true;
        _error = null;
        _saved = false;
      });
    }
  }

  Future<void> _save() async {
    if (_expired || _saving || !_form.currentState!.validate()) return;
    final s = EmployeeStrings.of(context);
    final draft = EmployeeLeaveDraft(
      leaveType: _type.text.trim(),
      reason: _reason.text.trim(),
      startDate: _start,
      endDate: _end,
    );
    final a = DateTime.utc(_start.year, _start.month, _start.day);
    final b = DateTime.utc(_end.year, _end.month, _end.day);
    if (b.isBefore(a)) {
      setState(() => _error = s('draftDatesError'));
      return;
    }
    if (b.difference(a).inDays + 1 > 366) {
      setState(() => _error = s('draftLengthError'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    FocusScope.of(context).unfocus();
    try {
      final saved = await widget.onSave(draft);
      if (!mounted) return;
      if (saved) {
        setState(() {
          _dirty = false;
          _allowExit = true;
          _saved = true;
        });
        if (Navigator.canPop(context)) Navigator.pop(context, true);
      } else {
        setState(() => _error = s('draftSaveError'));
      }
    } on Object {
      if (mounted) setState(() => _error = s('draftSaveError'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _back() async {
    if (_saving) return;
    if (!_dirty) {
      Navigator.maybePop(context);
      return;
    }
    final s = EmployeeStrings.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s('discardChanges')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s('keepEditing')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s('discard')),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(() => _allowExit = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.maybePop(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = EmployeeStrings.of(context);
    if (_expired) return const SizedBox.shrink();
    return PopScope(
      canPop: !_saving && (!_dirty || _allowExit),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(s('leaveDraft')),
          leading: Navigator.canPop(context)
              ? IconButton(
                  tooltip: s('back'),
                  onPressed: _back,
                  icon: const Icon(Icons.arrow_back),
                )
              : null,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EmployeeMessage(
                    title: s('notSubmitted'),
                    message: s('leaveCopy'),
                    icon: Icons.edit_note_outlined,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const Key('employee-leave-type'),
                    controller: _type,
                    maxLength: 80,
                    enabled: !_saving,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: s('leaveType'),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      helperText: s('typeHint'),
                      helperMaxLines: 3,
                    ),
                    onChanged: (_) => setState(() {
                      _dirty = true;
                      _saved = false;
                    }),
                    validator: (value) =>
                        value == null ||
                            value.trim().isEmpty ||
                            value.trim().length > 80
                        ? s('draftTypeError')
                        : null,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    key: const Key('employee-leave-start'),
                    onPressed: _saving ? null : () => _date(start: true),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s('startDate')),
                              Text(
                                DateFormat.yMMMd(s.language).format(_start),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    key: const Key('employee-leave-end'),
                    onPressed: _saving ? null : () => _date(start: false),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s('endDate')),
                              Text(
                                DateFormat.yMMMd(s.language).format(_end),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const Key('employee-leave-reason'),
                    controller: _reason,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 1000,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: s('reason'),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                    onChanged: (_) => setState(() {
                      _dirty = true;
                      _saved = false;
                    }),
                    validator: (value) =>
                        value == null ||
                            value.trim().isEmpty ||
                            value.trim().length > 1000
                        ? s('draftReasonError')
                        : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    EmployeeMessage(title: _error!, error: true),
                  ],
                  if (_saved) ...[
                    const SizedBox(height: 16),
                    EmployeeStatus(
                      s('localDraft'),
                      warning: true,
                      icon: Icons.save_outlined,
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('employee-save-draft'),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(s('saveDraft')),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    s('draftExpires'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

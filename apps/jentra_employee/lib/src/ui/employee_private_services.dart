import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/employee_self_service.dart';
import '../employee_self_service_controller.dart';
import '../l10n/employee_strings.dart';
import 'employee_components.dart';
import 'employee_service_common.dart';
import 'employee_surfaces.dart';

class EmployeePrivateServiceScreen extends StatelessWidget {
  const EmployeePrivateServiceScreen({
    required this.controller,
    required this.service,
    super.key,
  });
  final EmployeeSelfServiceController controller;
  final EmployeeService service;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(EmployeeStrings.of(context)(employeeServiceTitle(service))),
    ),
    body: EmployeePrivateServiceBody(controller: controller, service: service),
  );
}

class EmployeePrivateServiceBody extends StatefulWidget {
  const EmployeePrivateServiceBody({
    required this.controller,
    required this.service,
    super.key,
  });
  final EmployeeSelfServiceController controller;
  final EmployeeService service;
  @override
  State<EmployeePrivateServiceBody> createState() =>
      _EmployeePrivateServiceBodyState();
}

class _EmployeePrivateServiceBodyState
    extends State<EmployeePrivateServiceBody> {
  EmployeeSelfServiceController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        c.load(widget.service);
        c.restorePending();
      }
    });
  }

  Future<void> _open(EmployeeServiceRecord row) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EmployeePrivateDetailScreen(
          controller: c,
          service: widget.service,
          id: row.id,
        ),
      ),
    );
    if (mounted) await c.load(widget.service);
  }

  Future<void> _case() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EmployeeCaseComposeScreen(controller: c),
      ),
    );
    if (mounted) await c.load(EmployeeService.cases);
  }

  Future<void> _save(EmployeeServiceRecord row) async {
    final s = EmployeeStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s('documentSave')),
        content: Text(s('documentSaveCopy')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s('documentSave')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await c.saveDocument(row);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final s = EmployeeStrings.of(context);
      final service = widget.service;
      return EmployeePageBody(
        onRefresh: () => c.load(service),
        children: [
          EmployeeHeading(s(employeeServiceTitle(service)), large: true),
          if (service == EmployeeService.payslips)
            EmployeeMessage(title: s('paySynthetic'), warning: true),
          if (service == EmployeeService.documents) Text(s('documentsCopy')),
          EmployeeServiceFeedback(controller: c),
          if (service == EmployeeService.cases)
            FilledButton.icon(
              onPressed: c.actionBusy || c.pending != null ? null : _case,
              icon: const Icon(Icons.add_comment_outlined),
              label: Text(s('caseCreate')),
            ),
          EmployeeServiceListState(controller: c, service: service),
          for (final row
              in c.pages[service]?.items ?? <EmployeeServiceRecord>[])
            switch (service) {
              EmployeeService.cases => EmployeeActionTile(
                key: Key('employee-case-${row.id}'),
                title: row.text('subject', max: 160),
                subtitle: s(row.text('status', max: 80)),
                icon: Icons.forum_outlined,
                onTap: () => _open(row),
              ),
              EmployeeService.payslips => EmployeeActionTile(
                key: Key('employee-payslip-${row.id}'),
                title:
                    '${serviceDate(row.values['start_date'], s)} – ${serviceDate(row.values['end_date_exclusive'], s)}',
                subtitle:
                    '${s('payNet')}: ${row.values['net']} ${row.text('currency_code', max: 3)}',
                icon: Icons.receipt_long_outlined,
                onTap: () => _open(row),
              ),
              EmployeeService.documents => EmployeeSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EmployeeHeading(row.text('label', max: 160)),
                    const SizedBox(height: 8),
                    Text(
                      '${row.text('mime', max: 100)} · ${(row.integer('byte_size') / 1024).toStringAsFixed(1)} KB',
                    ),
                    Text(serviceDate(row.values['published_at'], s)),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: c.actionBusy || c.exportBusy
                          ? null
                          : () => _save(row),
                      icon: const Icon(Icons.save_alt),
                      label: Text(s('documentSave')),
                    ),
                  ],
                ),
              ),
              _ => const SizedBox.shrink(),
            },
          EmployeeServiceMore(controller: c, service: service),
        ],
      );
    },
  );
}

class EmployeePrivateDetailScreen extends StatefulWidget {
  const EmployeePrivateDetailScreen({
    required this.controller,
    required this.service,
    required this.id,
    super.key,
  });
  final EmployeeSelfServiceController controller;
  final EmployeeService service;
  final String id;
  @override
  State<EmployeePrivateDetailScreen> createState() =>
      _EmployeePrivateDetailScreenState();
}

class _EmployeePrivateDetailScreenState
    extends State<EmployeePrivateDetailScreen> {
  final _reply = TextEditingController();
  bool _loading = true;
  EmployeeSelfServiceController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await c.loadDetail(widget.service, widget.id);
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _reply.clear();
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send(EmployeeServiceRecord row) async {
    if (_reply.text.trim().isEmpty || _reply.text.length > 4000) return;
    final confirmed = await c.submit('employee_case_command', {
      'p_action': 'reply',
      'p_payload': {
        'id': row.id,
        'expected_version': row.version,
        'body': _reply.text.trim(),
      },
    });
    if (!mounted) return;
    if (confirmed) _reply.clear();
    await _load();
  }

  Future<void> _question(EmployeeServiceRecord row) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EmployeeCaseComposeScreen(controller: c, payslip: row),
      ),
    );
  }

  List<Widget> _case(EmployeeServiceRecord row, EmployeeStrings s) => [
    EmployeeHeading(row.text('subject', max: 160), large: true),
    EmployeeStatus(s(row.text('status', max: 80))),
    Text(
      row.values['owner_user_id'] == null ? s('caseNoOwner') : s('caseOwner'),
    ),
    EmployeeHeading(s('caseMessages')),
    for (final value in row.values['messages']! as List)
      EmployeeSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s(
                selfMap(value)['author_kind'] == 'employee'
                    ? 'caseEmployee'
                    : 'caseHr',
              ),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Text(serviceDate(selfMap(value)['created_at'], s, time: true)),
            const SizedBox(height: 8),
            Text(selfText(selfMap(value)['body'], max: 4000)),
          ],
        ),
      ),
    if (!{'closed', 'resolved'}.contains(row.values['status'])) ...[
      TextField(
        key: const Key('employee-case-reply'),
        controller: _reply,
        enabled: !c.actionBusy,
        minLines: 3,
        maxLines: 8,
        maxLength: 4000,
        decoration: InputDecoration(labelText: s('caseMessage')),
      ),
      FilledButton(
        onPressed: c.actionBusy || c.pending != null ? null : () => _send(row),
        child: Text(s('caseReply')),
      ),
    ] else
      Text(s('caseClosed')),
    EmployeeHeading(s('caseHistory')),
    for (final value in row.values['history']! as List)
      Text(
        '${serviceDate(selfMap(value)['created_at'], s, time: true)} · ${s(selfText(selfMap(value)['status'], max: 80))}',
      ),
  ];
  List<Widget> _payslip(EmployeeServiceRecord row, EmployeeStrings s) => [
    EmployeeMessage(title: s('paySynthetic'), warning: true),
    EmployeeHeading(
      '${serviceDate(row.values['start_date'], s)} – ${serviceDate(row.values['end_date_exclusive'], s)}',
      large: true,
    ),
    Text(
      '${s('payIssued')}: ${serviceDate(row.values['issued_at'], s, time: true)}',
    ),
    EmployeeSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final field in const [
            ('gross', 'payGross'),
            ('deductions', 'payDeductions'),
            ('net', 'payNet'),
            ('employer_cost', 'payEmployer'),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '${s(field.$2)}: ${row.values[field.$1]} ${row.text('currency_code', max: 3)}',
              ),
            ),
        ],
      ),
    ),
    EmployeeHeading(s('payComponents')),
    for (final line in row.values['lines']! as List)
      EmployeeSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(selfText(selfMap(line)['code'], max: 80)),
            Text(
              '${selfMap(line)['amount']} ${row.text('currency_code', max: 3)}',
            ),
          ],
        ),
      ),
    Text('${s('payRevision')}: ${row.values['payslip_revision_id']}'),
    OutlinedButton.icon(
      onPressed: c.actionBusy || c.pending != null
          ? null
          : () => _question(row),
      icon: const Icon(Icons.contact_support_outlined),
      label: Text(s('payQuestion')),
    ),
  ];
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final s = EmployeeStrings.of(context);
      final row = _loading ? null : c.detailFor(widget.service, widget.id);
      return Scaffold(
        appBar: AppBar(title: Text(s(employeeServiceTitle(widget.service)))),
        body: EmployeePageBody(
          onRefresh: _load,
          children: [
            EmployeeServiceFeedback(controller: c),
            if (_loading) const LinearProgressIndicator(),
            if (!_loading && row == null && c.actionError == null)
              EmployeeMessage(title: s('serviceEmpty')),
            if (row != null)
              ...(widget.service == EmployeeService.cases
                  ? _case(row, s)
                  : _payslip(row, s)),
          ],
        ),
      );
    },
  );
}

class EmployeeCaseComposeScreen extends StatefulWidget {
  const EmployeeCaseComposeScreen({
    required this.controller,
    this.payslip,
    super.key,
  });
  final EmployeeSelfServiceController controller;
  final EmployeeServiceRecord? payslip;
  @override
  State<EmployeeCaseComposeScreen> createState() =>
      _EmployeeCaseComposeScreenState();
}

class _EmployeeCaseComposeScreenState extends State<EmployeeCaseComposeScreen> {
  final _form = GlobalKey<FormState>();
  final _subject = TextEditingController(), _body = TextEditingController();
  EmployeeSelfServiceController get c => widget.controller;
  @override
  void dispose() {
    _subject.clear();
    _body.clear();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    final payslip = widget.payslip;
    final sent = await c.submit('employee_case_command', {
      'p_action': 'create',
      'p_payload': {
        'id': const Uuid().v4(),
        'category': payslip == null ? 'general' : 'payroll',
        'subject': _subject.text.trim(),
        'body': _body.text.trim(),
        if (payslip != null) ...{
          'payslip_id': payslip.id,
          'payslip_revision_id': payslip.text('payslip_revision_id', max: 36),
        },
      },
    });
    if (sent && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final s = EmployeeStrings.of(context);
      return Scaffold(
        appBar: AppBar(title: Text(s('caseCreate'))),
        body: EmployeePageBody(
          children: [
            EmployeeHeading(
              s(widget.payslip == null ? 'caseGeneral' : 'casePayroll'),
            ),
            if (widget.payslip != null)
              EmployeeMessage(
                title: s('paySynthetic'),
                message:
                    '${s('payRevision')}: ${widget.payslip!.values['payslip_revision_id']}',
                warning: true,
              ),
            EmployeeServiceFeedback(controller: c),
            Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    key: const Key('employee-case-subject'),
                    controller: _subject,
                    enabled: !c.actionBusy,
                    maxLength: 160,
                    decoration: InputDecoration(labelText: s('caseSubject')),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? s('requestInvalid')
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('employee-case-body'),
                    controller: _body,
                    enabled: !c.actionBusy,
                    minLines: 4,
                    maxLines: 10,
                    maxLength: 4000,
                    decoration: InputDecoration(labelText: s('caseMessage')),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? s('requestInvalid')
                        : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: c.actionBusy || c.pending != null ? null : _send,
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

class EmployeeInboxScreen extends StatefulWidget {
  const EmployeeInboxScreen({
    required this.controller,
    required this.onOpenDestination,
    super.key,
  });
  final EmployeeSelfServiceController controller;
  final ValueChanged<String> onOpenDestination;
  @override
  State<EmployeeInboxScreen> createState() => _EmployeeInboxScreenState();
}

class _EmployeeInboxScreenState extends State<EmployeeInboxScreen> {
  EmployeeSelfServiceController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) c.load(EmployeeService.inbox);
    });
  }

  String? _destination(EmployeeServiceRecord row) {
    final source = row.values['source_context'];
    if (source is! Map) return null;
    final destination = source['destination'];
    if (destination is! String ||
        !{
          'attendance',
          'leave',
          'pay',
          'reviews',
          'documents',
          'cases',
        }.contains(destination)) {
      return null;
    }
    // The subject ID is deliberately not trusted as routing authority. The
    // destination fetches its own server-authorized current records afresh.
    return destination;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final s = EmployeeStrings.of(context);
      return Scaffold(
        appBar: AppBar(title: Text(s('inboxTitle'))),
        body: EmployeePageBody(
          onRefresh: () => c.load(EmployeeService.inbox),
          children: [
            Text(s('inboxCopyNew')),
            EmployeeServiceFeedback(controller: c),
            EmployeeServiceListState(
              controller: c,
              service: EmployeeService.inbox,
            ),
            for (final row
                in c.pages[EmployeeService.inbox]?.items ??
                    <EmployeeServiceRecord>[])
              EmployeeSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EmployeeHeading(s('inboxGenericTitle')),
                    const SizedBox(height: 8),
                    Text(s('inboxGenericBody')),
                    Text(serviceDate(row.values['created_at'], s, time: true)),
                    EmployeeStatus(
                      s(
                        row.values['status'] == 'unread'
                            ? 'inboxUnread'
                            : 'inboxRead',
                      ),
                      icon: row.values['status'] == 'unread'
                          ? Icons.mark_email_unread_outlined
                          : Icons.mark_email_read_outlined,
                    ),
                    if (_destination(row) != null)
                      OutlinedButton(
                        onPressed: () =>
                            widget.onOpenDestination(_destination(row)!),
                        child: Text(s('inboxOpen')),
                      ),
                    if (row.values['status'] == 'unread')
                      TextButton(
                        onPressed: c.actionBusy ? null : () => c.markRead(row),
                        child: Text(s('inboxMarkRead')),
                      ),
                  ],
                ),
              ),
            EmployeeServiceMore(controller: c, service: EmployeeService.inbox),
          ],
        ),
      );
    },
  );
}

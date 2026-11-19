import 'package:flutter/material.dart';
import 'package:jentra_domain/jentra_field_sales.dart';

import '../field_sales_controller.dart';
import 'components.dart';

final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

String? _validDate(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  return !_datePattern.hasMatch(text) || parsed == null
      ? 'Use a date such as 2026-11-20, or leave it empty.'
      : null;
}

const _stateLabels = {
  'planned': 'Planned',
  'checked_in': 'Checked in',
  'completed': 'Completed',
  'cancelled': 'Cancelled',
};

/// The rep's live visits: plan, check in, complete or cancel. Location is
/// only added when the rep ticks it at check in or completion.
class FieldVisitsPage extends StatelessWidget {
  const FieldVisitsPage(this.controller, {super.key});
  final FieldSalesController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (!c.visitsAvailable) {
      return const SalesEmpty(
        'Visits are not enabled yet',
        'Your company has not switched on visit recording.',
      );
    }
    final open = c.visits
        .where((v) => v['state'] == 'planned' || v['state'] == 'checked_in')
        .toList();
    final closed =
        c.visits
            .where(
              (v) => v['state'] == 'completed' || v['state'] == 'cancelled',
            )
            .toList()
          ..sort(
            (a, b) => (b['created_at'] as String? ?? '').compareTo(
              a['created_at'] as String? ?? '',
            ),
          );
    final locked = c.busy || c.pendingVisit != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.pendingVisit != null) ...[
          SalesPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle('Check your last visit update'),
                const Text(
                  'Its outcome is still unconfirmed. Check it before recording anything else; it will not be sent again automatically.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton(
                      onPressed: c.busy ? null : () => c.reconcileVisit(),
                      child: const Text('Check visit update'),
                    ),
                    OutlinedButton(
                      onPressed: c.busy
                          ? null
                          : () => c.reconcileVisit(retry: true),
                      child: const Text('Retry visit update'),
                    ),
                    if (c.canDiscardPendingVisit)
                      TextButton(
                        onPressed: c.busy ? null : c.discardVisit,
                        child: const Text('Clear if not received'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: locked || c.customers.isEmpty
                ? null
                : () => _plan(context),
            icon: const Icon(Icons.event_available_outlined),
            label: const Text('Plan a visit'),
          ),
        ),
        const SizedBox(height: 16),
        if (c.visits.isEmpty)
          const SalesEmpty(
            'No visits yet',
            'Plan a visit to one of your assigned customers.',
          ),
        for (final visit in [...open, ...closed])
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SalesPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    visit['customer_name'] as String? ?? 'Assigned customer',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_stateLabels[visit['state']] ?? visit['state']} · ${visit['purpose']}',
                  ),
                  if (visit['planned_for'] != null)
                    Text('Planned for ${visit['planned_for']}'),
                  if (visit['check_in_location'] != null)
                    const Text('Location added at check in'),
                  if (visit['outcome'] != null)
                    Text('Outcome: ${visit['outcome']}'),
                  if (visit['next_action'] != null)
                    Text(
                      'Next: ${visit['next_action']}'
                      '${visit['next_action_due'] == null ? '' : ' by ${visit['next_action_due']}'}',
                    ),
                  if (visit['cancel_reason'] != null)
                    Text('Cancelled: ${visit['cancel_reason']}'),
                  if (visit['state'] == 'planned' ||
                      visit['state'] == 'checked_in') ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        if (visit['state'] == 'planned')
                          FilledButton(
                            onPressed: locked
                                ? null
                                : () => _checkIn(context, visit),
                            child: const Text('Check in'),
                          ),
                        if (visit['state'] == 'checked_in')
                          FilledButton(
                            onPressed: locked
                                ? null
                                : () => _complete(context, visit),
                            child: const Text('Complete visit'),
                          ),
                        OutlinedButton(
                          onPressed: locked
                              ? null
                              : () => _cancel(context, visit),
                          child: const Text('Cancel visit'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _plan(BuildContext context) async {
    final result = await showDialog<(String, String, String?)>(
      context: context,
      builder: (_) => _PlanVisitDialog(controller.customers),
    );
    if (result == null) return;
    await controller.planVisit(
      customerId: result.$1,
      purpose: result.$2,
      plannedFor: result.$3,
    );
  }

  Future<void> _checkIn(BuildContext context, FieldSalesJson visit) async {
    var withLocation = false;
    if (controller.canLocate) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (_) => const _LocationChoiceDialog(),
      );
      if (choice == null) return;
      withLocation = choice;
    }
    await controller.checkInVisit(visit, withLocation: withLocation);
  }

  Future<void> _complete(BuildContext context, FieldSalesJson visit) async {
    final result = await showDialog<_Completion>(
      context: context,
      builder: (_) => _CompleteVisitDialog(canLocate: controller.canLocate),
    );
    if (result == null) return;
    await controller.completeVisit(
      visit,
      outcome: result.outcome,
      nextAction: result.nextAction,
      nextActionDue: result.nextActionDue,
      withLocation: result.withLocation,
    );
  }

  Future<void> _cancel(BuildContext context, FieldSalesJson visit) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _CancelVisitDialog(),
    );
    if (reason == null) return;
    await controller.cancelVisit(visit, reason);
  }
}

class _PlanVisitDialog extends StatefulWidget {
  const _PlanVisitDialog(this.customers);
  final List<FieldSalesJson> customers;
  @override
  State<_PlanVisitDialog> createState() => _PlanVisitDialogState();
}

class _PlanVisitDialogState extends State<_PlanVisitDialog> {
  final _form = GlobalKey<FormState>();
  final _purpose = TextEditingController();
  final _date = TextEditingController();
  String? _customer;

  @override
  void dispose() {
    _purpose.dispose();
    _date.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Plan a visit'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _customer,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Customer'),
              items: [
                for (final c in widget.customers)
                  DropdownMenuItem(
                    value: c['id'] as String,
                    child: Text(
                      c['name'] as String,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _customer = value),
              validator: (value) =>
                  value == null ? 'Choose an assigned customer.' : null,
            ),
            TextFormField(
              controller: _purpose,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Purpose'),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Say why you are visiting.'
                  : null,
            ),
            TextFormField(
              controller: _date,
              decoration: const InputDecoration(
                labelText: 'Planned date (optional)',
                hintText: 'YYYY-MM-DD',
              ),
              validator: _validDate,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Back'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            final date = _date.text.trim();
            Navigator.pop(context, (
              _customer!,
              _purpose.text.trim(),
              date.isEmpty ? null : date,
            ));
          }
        },
        child: const Text('Plan visit'),
      ),
    ],
  );
}

class _LocationChoiceDialog extends StatelessWidget {
  const _LocationChoiceDialog();
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add your location to this check in?'),
    content: const Text(
      'Your position is read once, now, and kept with this visit. It is never tracked between visits.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Check in without location'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Check in with location'),
      ),
    ],
  );
}

final class _Completion {
  const _Completion(
    this.outcome,
    this.nextAction,
    this.nextActionDue,
    this.withLocation,
  );
  final String outcome;
  final String? nextAction, nextActionDue;
  final bool withLocation;
}

class _CompleteVisitDialog extends StatefulWidget {
  const _CompleteVisitDialog({required this.canLocate});
  final bool canLocate;
  @override
  State<_CompleteVisitDialog> createState() => _CompleteVisitDialogState();
}

class _CompleteVisitDialogState extends State<_CompleteVisitDialog> {
  final _form = GlobalKey<FormState>();
  final _outcome = TextEditingController();
  final _next = TextEditingController();
  final _due = TextEditingController();
  bool _withLocation = false;

  @override
  void dispose() {
    _outcome.dispose();
    _next.dispose();
    _due.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Complete this visit'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _outcome,
              maxLength: 2000,
              decoration: const InputDecoration(labelText: 'Outcome'),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Record what came of the visit.'
                  : null,
            ),
            TextFormField(
              controller: _next,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Next action (optional)',
              ),
            ),
            TextFormField(
              controller: _due,
              decoration: const InputDecoration(
                labelText: 'Next action date (optional)',
                hintText: 'YYYY-MM-DD',
              ),
              validator: (value) =>
                  _validDate(value) ??
                  ((value ?? '').trim().isNotEmpty && _next.text.trim().isEmpty
                      ? 'Add the next action for this date.'
                      : null),
            ),
            if (widget.canLocate)
              CheckboxListTile(
                value: _withLocation,
                onChanged: (value) =>
                    setState(() => _withLocation = value ?? false),
                title: const Text('Add my current location'),
                subtitle: const Text('Read once, now. Never tracked.'),
                contentPadding: EdgeInsets.zero,
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Back'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            final due = _due.text.trim();
            Navigator.pop(
              context,
              _Completion(
                _outcome.text.trim(),
                _next.text.trim().isEmpty ? null : _next.text.trim(),
                due.isEmpty ? null : due,
                _withLocation,
              ),
            );
          }
        },
        child: const Text('Complete visit'),
      ),
    ],
  );
}

class _CancelVisitDialog extends StatefulWidget {
  const _CancelVisitDialog();
  @override
  State<_CancelVisitDialog> createState() => _CancelVisitDialogState();
}

class _CancelVisitDialogState extends State<_CancelVisitDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Cancel this visit?'),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _reason,
        maxLength: 500,
        decoration: const InputDecoration(labelText: 'Reason'),
        validator: (value) =>
            (value ?? '').trim().isEmpty ? 'Say why it is cancelled.' : null,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Keep visit'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _reason.text.trim());
          }
        },
        child: const Text('Cancel visit'),
      ),
    ],
  );
}

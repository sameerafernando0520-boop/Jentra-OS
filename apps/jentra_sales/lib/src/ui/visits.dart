import 'package:flutter/material.dart';

import '../models.dart';
import '../sales_controller.dart';
import 'components.dart';
import 'customers.dart';
import 'order_editor.dart';

class SalesVisits extends StatelessWidget {
  const SalesVisits(this.c, {super.key});
  final SalesController c;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PageHeading(
        'Make every visit count.',
        'Plan the conversation. Capture the next step.',
        action: FilledButton.icon(
          onPressed: () => planVisit(context, c),
          icon: const Icon(Icons.add),
          label: const Text('Plan a visit'),
        ),
      ),
      const SalesNotice(
        'Preview visit plan · Notes and visit outcomes stay in this session. No location is recorded and no customer is contacted.',
      ),
      const SizedBox(height: 24),
      SalesPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle('Your agenda · ${c.visits.length} visits'),
            for (final visit in c.visits) VisitRow(c, visit),
            if (c.visits.isEmpty)
              const SalesEmpty(
                'Your agenda is clear',
                'Plan a visit with a customer to get started.',
              ),
          ],
        ),
      ),
    ],
  );
}

class VisitRow extends StatelessWidget {
  const VisitRow(this.c, this.visit, {super.key});
  final SalesController c;
  final SalesVisit visit;
  @override
  Widget build(BuildContext context) {
    final customer = c.customer(visit.customerId);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => openVisit(context, c, visit),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 9),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                visit.time,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    visit.purpose,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Text(
                        customer.area,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (visit.state == 'Completed')
                        const StatusPill('Completed'),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}

Future<void> openVisit(
  BuildContext context,
  SalesController c,
  SalesVisit visit,
) => salesDialog<void>(context, _VisitDetail(c, visit));

class _VisitDetail extends StatefulWidget {
  const _VisitDetail(this.c, this.visit);
  final SalesController c;
  final SalesVisit visit;
  @override
  State<_VisitDetail> createState() => _VisitDetailState();
}

class _VisitDetailState extends State<_VisitDetail> {
  late final _note = TextEditingController(text: widget.visit.note);
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c, visit = widget.visit;
    final customer = c.customer(visit.customerId);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 12, 12),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Visit details',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Close visit',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.name,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text('${visit.time} · ${customer.area}'),
                const SizedBox(height: 20),
                StatusPill(visit.state),
                const SizedBox(height: 24),
                const SectionTitle('Purpose'),
                Text(visit.purpose),
                const SizedBox(height: 24),
                Text(customer.address),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => openCustomer(context, c, customer),
                  icon: const Icon(Icons.person_outline),
                  label: const Text('Customer details'),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _note,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText: 'Visit notes & next steps',
                    hintText: 'What did you discuss? What happens next?',
                  ),
                ),
                const SizedBox(height: 20),
                const SalesNotice(
                  'Preview notes are session-only. No GPS, customer message or business posting is recorded.',
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: () =>
                    openOrderEditor(context, c, customer: customer),
                icon: const Icon(Icons.add),
                label: const Text('New order'),
              ),
              FilledButton.icon(
                onPressed: () {
                  c.recordPreviewVisit(visit, _note.text.trim());
                  Navigator.pop(context);
                  salesToast(
                    context,
                    'Preview visit completed for this session.',
                  );
                },
                icon: const Icon(Icons.check),
                label: const Text('Complete preview visit'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<void> planVisit(BuildContext context, SalesController c) =>
    salesDialog<void>(context, _PlanVisit(c));

class _PlanVisit extends StatefulWidget {
  const _PlanVisit(this.c);
  final SalesController c;
  @override
  State<_PlanVisit> createState() => _PlanVisitState();
}

class _PlanVisitState extends State<_PlanVisit> {
  final _form = GlobalKey<FormState>();
  final _purpose = TextEditingController();
  String? _customer;
  TimeOfDay _time = const TimeOfDay(hour: 15, minute: 0);
  @override
  void dispose() {
    _purpose.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 12, 16),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Plan a preview visit',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Close visit planner',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _customer,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Customer'),
                  items: widget.c.customers
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.name, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _customer = v),
                  validator: (v) => v == null ? 'Select a customer.' : null,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _purpose,
                  maxLength: 240,
                  decoration: const InputDecoration(
                    labelText: 'Purpose of visit',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Add a purpose.' : null,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: _time,
                    );
                    if (t != null && mounted) setState(() => _time = t);
                  },
                  icon: const Icon(Icons.schedule),
                  label: Text('Today at ${_time.format(context)}'),
                ),
                const SizedBox(height: 24),
                const SalesNotice(
                  'This preview plan stays in the current session. No customer notification or location tracking is activated.',
                ),
              ],
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(24),
        child: FilledButton.icon(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            widget.c.addPreviewVisit(
              SalesVisit(
                id: widget.c.newId(),
                customerId: _customer!,
                time:
                    '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
                purpose: _purpose.text.trim(),
                state: 'Scheduled',
              ),
            );
            Navigator.pop(context);
          },
          icon: const Icon(Icons.check),
          label: const Text('Add preview visit'),
        ),
      ),
    ],
  );
}
